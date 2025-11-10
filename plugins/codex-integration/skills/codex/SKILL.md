---
name: codex
description: Use when the user asks to run Codex CLI (codex exec, codex resume) or references OpenAI Codex for code analysis, refactoring, or automated editing
---

# Codex Skill Guide

## Overview

This skill implements a comprehensive 7-step workflow for invoking the Codex CLI (`codex exec` and `codex resume`) for automated code analysis, refactoring, and editing tasks. The Codex CLI is a locally-running coding agent developed by OpenAI that performs sophisticated code reasoning and transformation.

**Codex Version**: Tested with codex-cli 0.56.0 and above

## The 7-Step Workflow

### Step 1: Validate Configuration

**Purpose**: Ensure Codex CLI is accessible and properly configured before execution.

**Technical Details**:
- Checks `codex --version` for CLI availability
- Validates PATH environment variable contains Codex executable
- Verifies Codex configuration file exists at `~/.codex/config.toml`
- Confirms API credentials are valid (via config)
- Pre-flight checks for sandbox mode permissions

**Implementation**:
```bash
# Version validation
if ! command -v codex &> /dev/null; then
    echo "ERROR: Codex CLI not found on PATH"
    exit 1
fi

# Version check
codex --version

# Credential validation
codex config validate || exit 1
```

**Error Handling**:
- `Command not found`: Install Codex CLI via `pip install codex-cli` or `brew install codex`
- `Invalid credentials`: Run `codex login` to authenticate
- `Permission denied`: Check sandbox mode configuration in `~/.codex/config.toml`
- `Config parse error`: Run `codex config init` to regenerate default config

**Exit Conditions**:
- Only proceed to Step 2 if all validations pass
- Stop and report failures if Step 1 fails
- Request user direction before retrying

**Cross-References**:
- Configuration details: See "Configuration Management" section below
- Installation guide: See README.md#prerequisites
- Official Codex docs: https://github.com/openai/codex/blob/main/docs/config.md

---

### Step 2: Parse Task Intent and Select Defaults

**Purpose**: Extract task intent from user request and select appropriate model, reasoning effort, and sandbox mode.

**Technical Details**:
- Analyze user's task description for intent signals
- Determine if task is read-only (analysis/review) or requires modifications
- Select appropriate model based on task complexity
- Determine reasonable reasoning effort level
- Identify required sandbox permission level

**Implementation**:
```python
def parse_task_intent(task_description: str) -> dict:
    """Extract intent and select appropriate defaults."""

    # Intent detection
    read_only_keywords = ["analyze", "review", "explain", "document", "audit"]
    write_keywords = ["refactor", "edit", "modify", "update", "fix", "generate"]
    complex_keywords = ["architecture", "design", "complex", "refactor"]

    is_read_only = any(kw in task_description.lower() for kw in read_only_keywords)
    requires_write = any(kw in task_description.lower() for kw in write_keywords)
    is_complex = any(kw in task_description.lower() for kw in complex_keywords)

    # Model selection
    model = "gpt-5-codex" if (is_complex or requires_write) else "gpt-5"

    # Reasoning effort
    reasoning = "high" if is_complex else ("medium" if requires_write else "low")

    # Sandbox mode selection
    if is_read_only:
        sandbox = "read-only"
    elif requires_write:
        sandbox = "workspace-write"
    else:
        sandbox = "workspace-write"  # Default to safer option

    return {
        "model": model,
        "reasoning_effort": reasoning,
        "sandbox": sandbox,
        "intent": "read-only" if is_read_only else "write"
    }
```

**Prompt User for Confirmation**:
Ask the user via `AskUserQuestion` to confirm or override:
1. **Model**: `gpt-5-codex` (better for complex reasoning) vs `gpt-5` (faster)
2. **Reasoning Effort**: `high` (expensive, best for complex tasks) vs `medium` vs `low`

**Important**: Use a single prompt with two questions, not separate prompts.

**Exit Conditions**:
- Proceed to Step 3 after user confirms selections
- Stop if user requests different settings (re-run Step 2)

**Cross-References**:
- Model details: "Codex CLI Architecture Integration" section
- Reasoning levels explained: "Configuration Management" section
- Sandbox modes explained: "Safety & Permissions" section

---

### Step 3: Construct Codex Command

**Purpose**: Build the complete Codex CLI command with all necessary flags and parameters.

**Technical Details**:
- Map user selections to CLI arguments
- Assemble flags in correct order
- Handle special cases (resume vs. new execution)
- Validate command syntax before execution

**Command Structure**:
```bash
codex exec [OPTIONS] [PROMPT]
```

**Standard Flags**:
- `-m, --model <MODEL>`: Model to use (`gpt-5`, `gpt-5-codex`, `o3`, etc.)
- `-c, --config <key=value>`: Override config values (e.g., `model_reasoning_effort="high"`)
- `-s, --sandbox <MODE>`: Sandbox mode (`read-only`, `workspace-write`, `danger-full-access`)
- `-C, --cd <DIR>`: Working directory (if not current)
- `--skip-git-repo-check`: Allow execution outside Git repo
- `--full-auto`: Convenience flag for workspace-write with auto approval
- `2>/dev/null`: Suppress thinking tokens (stderr) unless debugging

**Implementation Example**:
```bash
# Analysis task
codex exec \
  -m gpt-5-codex \
  -c model_reasoning_effort="medium" \
  --sandbox read-only \
  --skip-git-repo-check \
  "Analyze this codebase and identify refactoring opportunities" \
  2>/dev/null

# Refactoring task with auto-apply
codex exec \
  -m gpt-5-codex \
  -c model_reasoning_effort="high" \
  --full-auto \
  --skip-git-repo-check \
  "Refactor authentication module for better error handling" \
  2>/dev/null

# From specific directory
codex exec \
  -m gpt-5 \
  --sandbox workspace-write \
  -C /path/to/project \
  "Generate unit tests for the API handler" \
  2>/dev/null
```

**Resume Command**:
```bash
# Resume previous session with new instruction
echo "Make the error handling more robust" | \
  codex exec --skip-git-repo-check resume --last 2>/dev/null
```

**Important Notes**:
- Always include `--skip-git-repo-check` for flexibility
- Default to `2>/dev/null` to suppress thinking tokens unless user requests them
- For resume, do NOT re-specify configuration flags (they're inherited from original session)
- Ensure prompt is properly quoted to handle special characters

**Exit Conditions**:
- Proceed to Step 4 once command is constructed
- Stop if command validation fails
- Request clarification if command is ambiguous

**Cross-References**:
- CLI reference: `codex exec --help`
- Configuration options: See "Configuration Management" section
- Sandbox modes: See "Safety & Permissions" section

---

### Step 4: Execute with Real-Time Monitoring

**Purpose**: Run the Codex command and capture output with proper monitoring and feedback.

**Technical Details**:
- Execute Codex command in subprocess with streaming output
- Monitor execution for progress and errors
- Capture stdout and stderr appropriately
- Track session ID for resume capability
- Provide real-time feedback to user

**Implementation**:
```python
import subprocess
import json
import re

def execute_codex_task(command: str, stream_output: bool = True) -> dict:
    """Execute Codex command and capture results."""

    try:
        # Start process with streaming output
        process = subprocess.Popen(
            command,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE if not stream_output else subprocess.STDOUT,
            text=True,
            bufsize=1
        )

        output = []
        session_id = None

        # Stream output in real-time
        for line in process.stdout:
            output.append(line)
            if stream_output:
                print(line.rstrip())

            # Extract session ID if available
            if "Session ID:" in line or "session_" in line:
                match = re.search(r'(sess_[a-zA-Z0-9]+)', line)
                if match:
                    session_id = match.group(1)

        # Wait for completion
        process.wait()

        # Capture any stderr
        stderr = process.stderr.read() if process.stderr else ""

        return {
            "exit_code": process.returncode,
            "stdout": "".join(output),
            "stderr": stderr,
            "session_id": session_id,
            "success": process.returncode == 0
        }

    except Exception as e:
        return {
            "exit_code": -1,
            "stdout": "",
            "stderr": str(e),
            "session_id": None,
            "success": False
        }
```

**Output Handling**:
- Real-time streaming: Show progress as Codex executes
- Thinking tokens: Suppress by default (stderr redirect), show if user requests
- Result capture: Parse Codex output for structured results
- Session tracking: Extract session ID for resume capability

**Error Signals During Execution**:
- `Timeout`: Task taking too long (reduce scope or increase reasoning time)
- `Permission denied`: Sandbox restrictions (may need higher access)
- `Model unavailable`: Selected model not accessible
- `Workspace modified`: Files changed outside Codex control

**Exit Conditions**:
- On success (exit code 0): Proceed to Step 5
- On failure: Proceed to Step 7 (Error Recovery)

**Cross-References**:
- Codex exec documentation: https://github.com/openai/codex/blob/main/docs/exec.md
- Error handling: See "Debugging Guide" section

---

### Step 5: Session State Management

**Purpose**: Manage Codex session persistence and enable resume capability.

**Technical Details**:
- Sessions are stored in `~/.codex/sessions/<session-id>/`
- Each session contains conversation history, state, and configuration
- Session IDs follow pattern: `sess_<alphanumeric>`
- Default retention: 7 days (configurable in config.toml)

**Session Persistence**:
```bash
# List all sessions
ls -la ~/.codex/sessions/

# Inspect session details
cat ~/.codex/sessions/<session-id>/session.json

# View session conversation history
cat ~/.codex/sessions/<session-id>/conversation.jsonl | jq

# Check session age
stat ~/.codex/sessions/<session-id>
```

**Session Lifecycle**:

```
1. Session Creation (on codex exec)
   ├─> Assigns unique session ID
   ├─> Initializes workspace snapshot
   └─> Begins model interaction

2. Session Execution
   ├─> Streams progress to user
   ├─> Records all model responses
   └─> Tracks file modifications

3. Session Persistence
   ├─> Saves state to ~/.codex/sessions/<id>/
   ├─> Stores conversation history
   ├─> Preserves workspace changes
   └─> Enables resume capability

4. Session Resume (codex exec resume --last)
   ├─> Restores conversation context
   ├─> Reloads previous configuration
   ├─> Continues from last interaction
   └─> Accumulates new changes
```

**Resume Mechanism**:
```bash
# Resume most recent session (automatic session ID detection)
echo "Continue the refactoring with better error handling" | \
  codex exec --skip-git-repo-check resume --last 2>/dev/null

# Resume specific session by ID
echo "Add logging to all functions" | \
  codex exec --skip-git-repo-check resume sess_abc123 2>/dev/null
```

**Important Session Rules**:
1. **Configuration inheritance**: Resume inherits model, reasoning effort, sandbox from original
2. **No flag re-specification**: Don't use `-m`, `-c`, or `-s` flags when resuming
3. **Prompt via stdin**: New instructions pass via echo/stdin, not as command argument
4. **Automatic session tracking**: Extract and preserve session IDs for future reference
5. **Session expiration**: Default 7 days; configure in `~/.codex/config.toml`

**Best Practices**:
- Always preserve session IDs from output
- Inform users of resume capability after each execution
- Monitor session age (check `stat ~/.codex/sessions/<id>`)
- Clean up old sessions to save disk space: `rm -rf ~/.codex/sessions/sess_<old-id>`
- For long workflows, resume regularly to preserve context

**Tracking Implementation**:
```python
def track_and_store_session_id(output: str, task_description: str) -> str:
    """Extract and persist session ID for future resume."""

    match = re.search(r'(sess_[a-zA-Z0-9]+)', output)
    session_id = match.group(1) if match else None

    if session_id:
        # Store in conversation context for future reference
        session_context = {
            "session_id": session_id,
            "original_task": task_description,
            "timestamp": datetime.now().isoformat(),
            "model_used": extracted_model,
            "reasoning_effort": extracted_reasoning
        }
        # Make available for Step 7 error recovery and follow-up
        return session_id

    return None
```

**Exit Conditions**:
- Session successfully created: Proceed to Step 6
- Session creation failed: Proceed to Step 7 (Error Recovery)

**Cross-References**:
- Session configuration: See "Configuration Management" section
- Codex exec documentation: https://github.com/openai/codex/blob/main/docs/exec.md#session-persistence
- Resume details: See "Advanced Patterns" section

---

### Step 6: Output Processing and Formatting

**Purpose**: Parse, validate, and format Codex output for presentation to user.

**Technical Details**:
- Parse Codex output for structured results
- Handle different output formats (text, JSON, structured)
- Extract key information (changes, recommendations, errors)
- Format results appropriately for Claude Code UI
- Preserve relevant execution context

**Output Parsing**:
```python
def process_codex_output(raw_output: str, output_format: str = "text") -> dict:
    """Parse and format Codex output."""

    if output_format == "json":
        # Parse JSONL (JSON Lines) output
        events = []
        for line in raw_output.strip().split('\n'):
            if line:
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
        return {"events": events, "format": "structured"}

    else:  # text format
        # Extract key sections
        result = {
            "format": "text",
            "summary": None,
            "details": None,
            "files_modified": [],
            "warnings": [],
            "errors": []
        }

        lines = raw_output.split('\n')

        # Parse output for key patterns
        for i, line in enumerate(lines):
            if "Files modified:" in line or "Changes made:" in line:
                result["files_modified"].extend(extract_file_list(lines[i+1:]))
            elif "Warning:" in line or "⚠️" in line:
                result["warnings"].append(line)
            elif "Error:" in line or "❌" in line:
                result["errors"].append(line)

        result["details"] = raw_output
        return result
```

**Output Formatting for User**:
```
Analysis Complete ✓

Key Findings:
- 5 complexity issues in authentication module
- 3 missing type hints in request handlers
- 2 potential security vulnerabilities

Files Reviewed:
- src/auth.py
- src/api/handlers.py
- src/utils.py

Detailed Analysis:
[Full output here]

Session ID: sess_abc123 (Resumable)
```

**Handling Common Output Patterns**:
- **Code changes**: Highlight file modifications and line numbers
- **Recommendations**: Extract and emphasize key suggestions
- **Warnings**: Call out non-critical issues
- **Errors**: Highlight execution problems
- **Metrics**: Present quantitative findings clearly

**Exit Conditions**:
- Successful output processing: Proceed to Step 7
- Output parsing errors: Log errors but proceed to Step 7
- Always proceed to Step 7 (Error Recovery/Notification)

**Cross-References**:
- JSON output format: See Codex exec docs
- Structured output: `codex exec --output-schema` option
- Output files: `codex exec --output-last-message <FILE>`

---

### Step 7: Error Recovery and User Notification

**Purpose**: Handle execution errors, provide recovery guidance, and inform user of next steps.

**Technical Details**:
- Catch and classify execution errors
- Determine appropriate recovery strategy
- Inform user of results and session ID for resume
- Provide troubleshooting guidance if needed
- Enable smooth follow-up actions

**Error Classification**:
```python
def classify_and_handle_error(exit_code: int, stderr: str, session_id: str) -> dict:
    """Classify error and determine recovery strategy."""

    if exit_code == 0:
        return {"status": "success", "action": "proceed_to_notification"}

    # Classify error
    if "Model not available" in stderr:
        return {
            "status": "model_unavailable",
            "action": "retry_with_fallback",
            "fallback_model": "gpt-5",
            "guidance": "Selected model unavailable, trying gpt-5 instead"
        }

    elif "Authentication failed" in stderr or "Invalid credentials" in stderr:
        return {
            "status": "auth_failure",
            "action": "stop_and_inform",
            "guidance": "Run 'codex login' to authenticate"
        }

    elif "Timeout" in stderr or "timed out" in stderr:
        return {
            "status": "timeout",
            "action": "retry_with_reduced_scope",
            "guidance": "Task too complex; reduce scope and retry"
        }

    elif "Permission denied" in stderr or "Sandbox" in stderr:
        return {
            "status": "permission_denied",
            "action": "inform_user_for_decision",
            "guidance": "Insufficient permissions; may need higher sandbox mode"
        }

    else:
        return {
            "status": "unknown_error",
            "action": "stop_and_inform",
            "guidance": f"Unexpected error: {stderr}"
        }
```

**Recovery Strategies**:

1. **Successful Execution**:
   ```
   ✓ Task completed successfully

   [Display results from Step 6]

   You can resume this Codex session at any time by saying:
   "codex resume" or "continue with additional analysis"

   Session ID: sess_abc123 (valid for 7 days)
   ```

2. **Retryable Errors** (timeout, temporary failures):
   ```
   ⚠️ Task encountered an issue: Execution timeout

   Retry Strategy: Reducing task scope to improve success rate
   [Automatically retry with reduced complexity]
   ```

3. **Permission Issues**:
   ```
   ❌ Task failed: Insufficient permissions

   Current sandbox mode: read-only
   Required for this task: workspace-write

   Suggestion: Use 'codex resume' with --sandbox workspace-write
   Session ID: sess_abc123 (can be resumed with different permissions)
   ```

4. **Configuration Issues**:
   ```
   ❌ Task failed: Configuration error

   Action Required:
   1. Run: codex config validate
   2. Run: codex login (if authentication needed)
   3. Retry: codex resume sess_abc123
   ```

**User Notification Template**:
```python
def notify_user_of_completion(result: dict, session_id: str):
    """Inform user of execution results and next steps."""

    if result["success"]:
        print(f"✓ {result['status_message']}")
        print("\nKey Results:")
        print(result["formatted_output"])
        print(f"\n📚 You can resume this session: 'codex resume'")
        print(f"Session ID: {session_id}")
    else:
        print(f"⚠️ {result['status_message']}")
        print(f"\nTroubleshooting: {result['guidance']}")
        print(f"\n💡 For detailed error info, see: SKILL.md#debugging-guide")
```

**Always Inform User Of**:
1. Whether task succeeded or failed
2. Key results or error details
3. Session ID for future resume
4. Suggested next steps
5. Link to relevant documentation (SKILL.md sections)

**Exit Conditions**:
- Complete Step 7 after every execution
- All 7 steps form a complete workflow cycle
- Ready for Step 2 if user requests follow-up

**Cross-References**:
- Complete error handling: See "Debugging Guide" section
- Advanced recovery patterns: See "Advanced Patterns" section
- Session management: See Step 5 above

---

## Codex CLI Architecture Integration

### How This Skill Wraps Codex

This skill implements a sophisticated abstraction layer over the Codex CLI, automating decisions and error handling.

**Architecture Overview**:
```
User Request (Claude Code)
    ↓
Step 1: Validate Configuration (codex --version, config validation)
    ↓
Step 2: Parse Intent (keyword analysis, defaults)
    ↓
Step 3: Construct Command (flag assembly, validation)
    ↓
Step 4: Execute & Monitor (subprocess, streaming, session tracking)
    ↓
Step 5: Session State Management (~/.codex/sessions/)
    ↓
Step 6: Output Processing (parsing, formatting)
    ↓
Step 7: Error Recovery & Notification (classification, recovery)
    ↓
User Sees Formatted Results + Resume Capability
```

**Key Integration Points**:

1. **Command Construction**:
   - Maps user intent to optimal Codex CLI arguments
   - Handles model selection (`gpt-5` vs `gpt-5-codex`)
   - Manages reasoning effort levels (`low`, `medium`, `high`)
   - Selects appropriate sandbox mode (`read-only`, `workspace-write`, `danger-full-access`)
   - Automatically adds necessary flags (`--skip-git-repo-check`, output suppression)

2. **Session Management**:
   - Persistence via `~/.codex/sessions/<session-id>/`
   - Automatic session ID extraction and tracking
   - Resume capability preservation
   - Session state coordination across invocations
   - Automatic cleanup of expired sessions (configurable)

3. **Output Streaming**:
   - Real-time progress display during execution
   - Structured JSON parsing for automated workflows
   - Error stream capture and interpretation
   - Session ID extraction from output

**Codex CLI Commands Used**:
- `codex exec`: Primary execution command for new tasks
- `codex resume`: Continue previous sessions
- `codex --version`: Verify CLI installation
- `codex config validate`: Validate configuration
- `codex login`: Manage authentication

**Value-Added Over Direct CLI Usage**:

| Feature | Direct CLI | Via This Skill |
|---------|-----------|-----------------|
| Intent detection | Manual | Automatic from task description |
| Model selection | Manual specification required | Intelligent defaults with confirmation |
| Sandbox mode selection | Manual specification | Automatic based on intent |
| Error recovery | Manual retry required | Automatic with intelligent strategies |
| Session tracking | Manual ID management | Automatic extraction and preservation |
| Resume capability | Manual command construction | Automatic with session context |
| Output formatting | Raw Codex output | Formatted for readability |
| Approval policies | Manual flag usage | Seamless integration |

**Configuration Inheritance**:
- Each execution references `~/.codex/config.toml` for defaults
- Runtime parameters override config file settings
- Resume operations inherit original session configuration
- Configuration precedence: CLI flags > config overrides > config file > hardcoded defaults

---

## Configuration Management

### Understanding Config.toml Integration

This skill's workflow extensively references and respects `~/.codex/config.toml` configuration.

**Configuration File Location**: `~/.codex/config.toml`

**Critical Configuration Fields** (and where they're used in workflow):

```toml
# ~/.codex/config.toml

[model]
# Used in Step 2 (Intent parsing) and Step 3 (Command construction)
default = "gpt-5-codex"              # Default model if not specified
# Available: gpt-5, gpt-5-codex, o3 (model availability varies)

[reasoning]
# Used in Step 3 (Command construction) - maps to --config model_reasoning_effort
effort = "medium"                     # Default reasoning level
# Levels: low (faster), medium (balanced), high (thorough, expensive)

[sandbox]
# Used in Step 2 (Intent parsing) and Step 3 (Command construction)
default_mode = "workspace-write"      # Default permission level
# Modes: read-only, workspace-write, danger-full-access

approval_policy = "auto"              # When to ask user for approval
# Policies: untrusted, on-failure, on-request, never

[session]
# Used in Step 5 (Session management)
auto_resume = true                    # Enable automatic session continuation
persist_days = 7                      # Session retention period
auto_cleanup = true                   # Auto-delete expired sessions

[features]
# Used to enable/disable experimental features
web_search = false                    # Enable web search capability
json_output = false                   # Use JSON Lines output format
```

**Configuration Hierarchy**:
1. **Default hardcoded values** (lowest priority)
2. **Config file settings** (`~/.codex/config.toml`)
3. **Runtime parameters** (`-c`, `-m`, `-s` flags)
4. **User overrides** via CLI questions (highest priority)

**Configuration Override Examples**:

```bash
# Override via -c flag (Step 3: Command Construction)
codex exec \
  -c model="gpt-5-codex" \
  -c model_reasoning_effort="high" \
  "Your task"

# Override via -m flag
codex exec -m gpt-5 "Your task"

# Override via -s flag
codex exec --sandbox danger-full-access "Your task"
```

**Reasoning Effort Levels** (used in Step 3):
- **`low`**: Minimal reasoning, fastest execution (good for simple tasks)
- **`medium`**: Balanced reasoning and speed (recommended default)
- **`high`**: Extended reasoning, more thorough but slower (for complex problems)

**Model Selection Guidance** (used in Step 2):
- **`gpt-5`**: Faster, suitable for straightforward tasks
- **`gpt-5-codex`**: Better at complex reasoning, refactoring, architecture decisions
- **`o3`**: Most capable but may have availability restrictions

**Sandbox Modes** (used in Steps 2, 3):
- **`read-only`**: Can only read files, no modifications or network access
  - Use for: Analysis, review, documentation tasks
  - Safe default, requires explicit approval to escalate

- **`workspace-write`**: Can read/write files in current workspace
  - Use for: Refactoring, fixing, code generation
  - Default for most editing tasks
  - Still prevents network access and system-wide operations

- **`danger-full-access`**: Full filesystem access, network, arbitrary commands
  - Use for: Package installation, system operations, external API calls
  - Extremely powerful but requires careful use
  - Recommend: Use with `--ask-for-approval on-failure` for safety

**Configuration Examples**:

**For Code Analysis (conservative)**:
```toml
[model]
default = "gpt-5-codex"

[reasoning]
effort = "medium"

[sandbox]
default_mode = "read-only"
approval_policy = "untrusted"
```

**For Code Refactoring (moderate)**:
```toml
[model]
default = "gpt-5-codex"

[reasoning]
effort = "high"

[sandbox]
default_mode = "workspace-write"
approval_policy = "on-failure"
```

**For Complex Automation (powerful)**:
```toml
[model]
default = "gpt-5-codex"

[reasoning]
effort = "high"

[sandbox]
default_mode = "danger-full-access"
approval_policy = "on-failure"
```

**Validating Configuration**:
```bash
# Check if config is valid
codex config validate

# View current configuration
cat ~/.codex/config.toml

# Generate fresh config
codex config init

# Override for single command
codex exec -c model="gpt-5" "Your task"
```

**Configuration Interaction with 7-Step Workflow**:

| Step | Configuration Used | Override Method |
|------|-------------------|-----------------|
| 1: Validate | (validation only) | N/A |
| 2: Parse Intent | `model.default`, `sandbox.default_mode` | User confirmation via questions |
| 3: Construct | All settings | `-c`, `-m`, `-s` flags |
| 4: Execute | (applied in Step 3) | (applied in Step 3) |
| 5: Session | `session.persist_days`, `session.auto_resume` | Config file only |
| 6: Output | (no config impact) | N/A |
| 7: Recovery | (may reference in guidance) | (may suggest config updates) |

**Cross-References**:
- Official Codex config documentation: https://github.com/openai/codex/blob/main/docs/config.md
- Step 2: Parse Intent section (above)
- Step 3: Construct Command section (above)

---

## Session Workflow & Persistence

### Understanding Codex Sessions

**What is a Session?**

A Codex session represents:
- A single task execution context with full conversation history
- Model interaction state and decisions made
- File modifications and workspace changes
- Configuration settings used during execution
- Resume capability for continuing work

**Why Sessions Matter**:
- Preserve context across multiple interactions
- Enable iterative refinement without re-explaining the task
- Maintain consistent model behavior and decisions
- Allow recovery if intermediate steps need adjustment

**Session Lifecycle**:

```
1. Session Creation (codex exec)
   ├─> Assigns unique session ID (sess_<alphanumeric>)
   ├─> Creates directory: ~/.codex/sessions/<session-id>/
   ├─> Initializes workspace snapshot
   ├─> Begins model interaction
   └─> Stores execution metadata

2. Session Execution
   ├─> Streams progress to terminal/output
   ├─> Records all model responses
   ├─> Tracks file modifications
   ├─> Saves intermediate state
   └─> Accumulates conversation history

3. Session Persistence
   ├─> Saves final state to ~/.codex/sessions/<id>/
   ├─> Stores complete conversation history
   ├─> Preserves workspace diff/changes
   ├─> Saves configuration snapshot
   └─> Marks session as pausable/resumable

4. Session Resume (codex exec resume --last)
   ├─> Detects and loads previous session
   ├─> Restores conversation context
   ├─> Reloads workspace state
   ├─> Re-applies previous configuration
   ├─> Continues from last interaction point
   └─> Accumulates new changes on top of previous
```

**Session Storage Structure**:

```
~/.codex/sessions/
├── sess_abc123/
│   ├── session.json                 # Metadata and state
│   ├── conversation.jsonl           # Full message history (JSONL format)
│   ├── workspace.diff               # File changes snapshot
│   ├── config.snapshot.toml         # Configuration used during execution
│   ├── execution.log                # Execution timeline and events
│   └── audit.log                    # Security audit trail (if enabled)
├── sess_def456/
│   └── [same structure]
└── [other sessions...]
```

**Session Metadata** (`session.json` contents):
```json
{
  "session_id": "sess_abc123",
  "created_at": "2025-11-09T14:23:45Z",
  "status": "paused",  // or "completed", "in_progress", "failed"
  "model": "gpt-5-codex",
  "reasoning_effort": "high",
  "sandbox_mode": "workspace-write",
  "initial_task": "Refactor authentication module",
  "last_interaction": "2025-11-09T14:25:12Z",
  "resume_count": 0,
  "files_modified": ["src/auth.py", "src/auth/handlers.py"],
  "conversation_length": 15
}
```

**Resume Mechanism** (Step 5 implementation):

```python
def resume_session(session_id: str = None, new_instruction: str = None):
    """Resume a previous Codex session."""

    # Determine session to resume
    if not session_id:
        session_id = get_most_recent_session()  # --last flag

    # Load session metadata
    session_path = Path.home() / ".codex" / "sessions" / session_id
    metadata = json.loads((session_path / "session.json").read_text())

    # Validate resumability
    if metadata["status"] == "completed":
        print(f"⚠️ Session {session_id} is completed (read-only)")
        print("Create a new session instead or ask to continue differently")
        return None

    # Reconstruct Codex command
    # IMPORTANT: Do NOT re-specify -m, -c, or -s flags
    # These are inherited from original session
    cmd = f"echo '{new_instruction}' | codex exec --skip-git-repo-check resume --last 2>/dev/null"

    # Execute resume
    result = execute_codex_task(cmd)

    # Update session metadata
    metadata["resume_count"] += 1
    metadata["last_interaction"] = datetime.now().isoformat()
    (session_path / "session.json").write_text(json.dumps(metadata, indent=2))

    return result
```

**Resume Command Syntax**:

```bash
# Resume most recent session (automatic ID detection)
echo "Continue the refactoring with better error handling" | \
  codex exec --skip-git-repo-check resume --last 2>/dev/null

# Resume specific session by ID
echo "Add logging to all functions" | \
  codex exec --skip-git-repo-check resume sess_abc123 2>/dev/null

# Important: NO configuration flags when resuming
# ❌ WRONG:
echo "prompt" | codex exec -m gpt-5 resume --last  # Error!

# ✓ CORRECT:
echo "prompt" | codex exec resume --last  # Inherits model from original
```

**Session Rules & Constraints**:

1. **Configuration Inheritance**:
   - Resume automatically uses original model
   - Reasoning effort preserved from original
   - Sandbox mode inherited from original
   - Do NOT re-specify configuration when resuming

2. **Prompt Input**:
   - New instructions pass via stdin (echo/pipe)
   - Not as command-line arguments
   - Enables proper context merging with conversation history

3. **State Restoration**:
   - Previous workspace changes are preserved
   - Conversation history is fully restored
   - Model can reference previous decisions and code
   - Seamless continuation of work

4. **Session Expiration**:
   - Default retention: 7 days (configurable in config.toml)
   - Automatic cleanup of expired sessions (optional)
   - Check session age: `stat ~/.codex/sessions/<id>/`
   - Manual cleanup: `rm -rf ~/.codex/sessions/<id>/`

**Session Management Operations**:

```bash
# List all sessions
ls -la ~/.codex/sessions/

# Show session info
cat ~/.codex/sessions/sess_abc123/session.json | jq

# View conversation history
cat ~/.codex/sessions/sess_abc123/conversation.jsonl | jq

# Check recent changes in session
cat ~/.codex/sessions/sess_abc123/workspace.diff

# Delete old session
rm -rf ~/.codex/sessions/sess_abc123/

# Check session age
stat -c %y ~/.codex/sessions/sess_abc123/  # Linux
stat -f %Sm ~/.codex/sessions/sess_abc123/ # macOS
```

**Session Best Practices**:

1. **Always preserve session IDs**: Store them for future reference
2. **Monitor session age**: Don't let sessions expire unexpectedly
3. **Clean up regularly**: Remove completed or failed sessions
4. **Use descriptive task names**: Helps identify sessions later
5. **Take snapshots**: Before risky operations, note session ID
6. **Test resumes**: Verify session can be resumed before relying on it
7. **Document workflow**: For complex tasks, record session IDs of each step

**Common Session Issues & Solutions**:

| Issue | Cause | Solution |
|-------|-------|----------|
| "Session not found" | Wrong session ID or expired | List sessions with `ls ~/.codex/sessions/` |
| "Session expired" | Retention period exceeded | Increase `persist_days` in config.toml |
| "Session locked" | Concurrent access attempt | Wait for lock release or kill competing process |
| "Corrupt session" | Filesystem error or interruption | Delete and restart: `rm -rf ~/.codex/sessions/<id>` |
| "Resume fails" | Workspace changed externally | Commit/stash changes, then resume |
| "Can't resume completed" | Session marked complete | Create new session instead |

**Cross-References**:
- Configuration for sessions: See "Configuration Management" section
- Resume examples: See "Advanced Patterns" section
- Session troubleshooting: See "Debugging Guide" section

---

## Safety & Permissions

### Sandbox Modes Explained

**Purpose**: Control what actions Codex can perform on your system.

Sandbox modes are critical security controls that prevent unintended or malicious actions while still allowing powerful automation.

**Available Modes**:

| Mode | File Access | Network | Shell Commands | Typical Use Case |
|------|-------------|---------|-----------------|-----------------|
| `read-only` | Read workspace only | No | No | Code analysis, reviews, documentation, audits |
| `workspace-write` | Read/write workspace | No | Limited (safe commands) | Refactoring, file editing, code generation, fixes |
| `danger-full-access` | Full filesystem | Yes | All commands | Package installs, git operations, API calls, system setup |

**Mode Selection Algorithm** (implemented in Step 2):

```python
def select_sandbox_mode(task_description: str) -> str:
    """Automatically select appropriate sandbox based on task intent."""

    task_lower = task_description.lower()

    # Safety-first: default to most restrictive
    read_only_keywords = ["analyze", "review", "audit", "explain", "document", "assess"]
    if any(kw in task_lower for kw in read_only_keywords):
        return "read-only"

    # Standard editing tasks
    write_keywords = ["refactor", "edit", "modify", "update", "fix", "generate", "write"]
    if any(kw in task_lower for kw in write_keywords):
        return "workspace-write"

    # Full access tasks
    full_access_keywords = ["install", "git", "network", "api", "deploy", "full access", "danger"]
    if any(kw in task_lower for kw in full_access_keywords):
        return "danger-full-access"

    # Default fallback to safe option
    return "workspace-write"
```

**Mode Details**:

### `read-only` Mode

**Capabilities**:
- ✓ Read all files in workspace
- ✓ Analyze code structure
- ✓ Generate reports and documentation
- ✓ Provide recommendations
- ✓ Explain code behavior

**Restrictions**:
- ✗ Cannot modify files
- ✗ Cannot execute shell commands
- ✗ Cannot access network
- ✗ Cannot install packages
- ✗ Cannot access system directories

**Use Cases**:
- Code quality analysis and reviews
- Security audits
- Documentation generation
- Architecture assessment
- Performance analysis (read-only)
- Dependency analysis

**Command Example**:
```bash
codex exec \
  --sandbox read-only \
  -m gpt-5-codex \
  "Analyze this codebase and identify refactoring opportunities"
```

### `workspace-write` Mode

**Capabilities**:
- ✓ Read all files in workspace
- ✓ Modify/create files in workspace
- ✓ Execute safe shell commands (ls, cat, grep, etc.)
- ✓ Run tests and linters locally
- ✓ Compile code
- ✓ Run git commands (read-only: log, status, diff)

**Restrictions**:
- ✗ Cannot access network or external services
- ✗ Cannot install system packages
- ✗ Cannot modify files outside workspace
- ✗ Cannot execute arbitrary/dangerous commands
- ✗ Cannot access system-wide resources

**Safe Commands** (automatic approval):
- File operations: `ls`, `cat`, `grep`, `find`, `head`, `tail`, `wc`
- Text processing: `sed`, `awk`, `cut`, `sort`, `uniq`
- Git read-only: `git log`, `git status`, `git diff`, `git show`
- Build tools: compiler commands, test runners
- Language tools: linters, formatters, type checkers

**Use Cases**:
- Code refactoring
- Bug fixing
- Code generation
- File editing and updates
- Test generation
- Documentation writing
- Formatting and linting
- Local build and test execution

**Command Example**:
```bash
codex exec \
  --sandbox workspace-write \
  -m gpt-5-codex \
  --full-auto \
  "Refactor the authentication module for better error handling"
```

### `danger-full-access` Mode

**Capabilities**:
- ✓ Full filesystem access (read/write anywhere)
- ✓ Full network access
- ✓ All shell commands without restriction
- ✓ Package installation (npm, pip, etc.)
- ✓ Git operations (including force push, rebase, etc.)
- ✓ System-wide operations

**Restrictions**:
- None (complete access)

**Security Considerations**:

⚠️ **WARNING**: This mode is EXTREMELY POWERFUL and potentially dangerous:
- Can delete or modify critical system files
- Can install malware or compromised packages
- Can perform destructive operations
- Can expose sensitive data
- Can compromise system security

**MUST USE WITH CAUTION**:
1. Only use when absolutely necessary
2. Always review Codex proposals before approval
3. Use with `--ask-for-approval on-failure` or `on-request`
4. Never use with `--ask-for-approval never` unless in protected environment
5. Consider using in isolated/containerized environment
6. Back up critical data before running

**Use Cases** (only when necessary):
- Package installation and dependency management
- Complex git operations (rebase, cherry-pick, force push)
- Environment setup and configuration
- Docker and containerization
- Build system configuration
- CI/CD pipeline automation
- System administration tasks

**Command Example** (with safety):
```bash
codex exec \
  --sandbox danger-full-access \
  --ask-for-approval on-failure \
  -m gpt-5-codex \
  "Install dependencies and set up the development environment"
```

**Approval Policies** (additional safety layer):

Approval policies control when Codex requires user confirmation for actions.

```toml
# In ~/.codex/config.toml
[sandbox]
approval_policy = "on-failure"  # or: untrusted, on-request, never
```

**Policy Behaviors**:

| Policy | Behavior | Use Case |
|--------|----------|----------|
| **`untrusted`** | Only run trusted commands automatically; escalate others | Conservative: analysis and simple edits |
| **`on-failure`** | Run all commands; ask only on failure or unexpected behavior | Moderate: refactoring and code generation (default recommended) |
| **`on-request`** | Model decides when to ask for approval | High trust: experienced users, known Codex behavior |
| **`never`** | Never ask for approval; auto-execute everything | Only in fully isolated/sandboxed environments |

**Recommended Combinations**:

```toml
# Conservative (Analysis + Review)
[sandbox]
default_mode = "read-only"
approval_policy = "untrusted"

# Standard (Refactoring + Code Generation)
[sandbox]
default_mode = "workspace-write"
approval_policy = "on-failure"

# Powerful (Full Automation)
[sandbox]
default_mode = "danger-full-access"
approval_policy = "on-failure"  # Still ask on unusual behavior
```

**Security Audit Trail**:

All sandbox actions are logged to:
```bash
~/.codex/sessions/<session-id>/audit.log
```

**Review audit log**:
```bash
cat ~/.codex/sessions/sess_abc123/audit.log
```

**Escalation Guidelines**:

If Codex requests approval to execute a command:
1. **Read the proposed command carefully**
2. **Understand what it does**: Research unfamiliar commands
3. **Verify necessity**: Is this command needed for the task?
4. **Check safety**: Will it harm anything? Modify sensitive files?
5. **Approve or deny**: Deny if uncertain; Codex will retry with different approach

**Cross-References**:
- Configuration for sandbox modes: See "Configuration Management" section
- Mode selection in workflow: See Step 2 "Parse Task Intent" section
- Codex official sandbox docs: https://github.com/openai/codex/blob/main/docs/config.md#sandbox

---

## Advanced Patterns

### Multi-Step Codex Workflows

This section documents sophisticated patterns for complex code tasks.

**Pattern 1: Analysis → Refactor → Validate**

Separate concerns into distinct sessions for clarity and safety.

```bash
# Step 1: Analyze (read-only)
SESSION1=$(codex exec -m gpt-5-codex --sandbox read-only \
  "Analyze this authentication module and identify refactoring opportunities" \
  2>/dev/null | grep -oP 'sess_\w+')

echo "Analysis complete. Session: $SESSION1"
echo "Review recommendations and press Enter to proceed with refactoring..."
read

# Step 2: Refactor (workspace-write, resume analysis context)
SESSION2=$(echo "Now refactor based on the analysis above" | \
  codex exec --skip-git-repo-check resume $SESSION1 2>/dev/null | grep -oP 'sess_\w+')

echo "Refactoring complete. Session: $SESSION2"
echo "Review changes and press Enter to validate..."
read

# Step 3: Validate (read-only, review refactored code)
codex exec -m gpt-5 --sandbox read-only \
  "Review the refactored authentication module for correctness and best practices" \
  2>/dev/null
```

**Pattern 2: Iterative Refinement with User Feedback**

Leverage resume capability for iterative improvement.

```python
def iterative_refinement_workflow(task_description: str):
    """Enable user to iteratively refine Codex output."""

    # Initial execution
    print(f"Starting: {task_description}")
    result = execute_codex_task(f"codex exec -m gpt-5-codex {task_description}")
    session_id = result["session_id"]

    iteration = 1
    while True:
        print(f"\n✓ Iteration {iteration} complete")
        print(f"Session: {session_id}")

        # Ask user for feedback
        feedback = input("\nEnter refinement request (or 'done' to finish): ")
        if feedback.lower() == 'done':
            break

        # Resume with new instruction
        print(f"\nRefining: {feedback}")
        result = resume_session(session_id, feedback)
        session_id = result["session_id"]
        iteration += 1

    print(f"\n✓ Completed after {iteration} iterations")
    print(f"Final session: {session_id}")
```

**Pattern 3: Parallel Analysis Tasks**

Execute multiple analysis tasks concurrently for comprehensive understanding.

```bash
#!/bin/bash

# Launch parallel analysis tasks
echo "Starting parallel code analysis..."

# Task 1: Security analysis (background)
codex exec -m gpt-5-codex --sandbox read-only \
  "Identify security vulnerabilities and suggest fixes" \
  2>/dev/null > /tmp/security_analysis.txt &
SECURITY_PID=$!

# Task 2: Performance analysis (background)
codex exec -m gpt-5-codex --sandbox read-only \
  "Identify performance bottlenecks and optimization opportunities" \
  2>/dev/null > /tmp/performance_analysis.txt &
PERF_PID=$!

# Task 3: Code quality analysis (background)
codex exec -m gpt-5-codex --sandbox read-only \
  "Assess code quality and identify refactoring opportunities" \
  2>/dev/null > /tmp/quality_analysis.txt &
QUALITY_PID=$!

# Wait for all tasks to complete
wait $SECURITY_PID $PERF_PID $QUALITY_PID

echo "✓ All analyses complete"

# Aggregate results
echo "=== Comprehensive Code Review ===" > results.txt
echo "" >> results.txt
echo "## Security Analysis" >> results.txt
cat /tmp/security_analysis.txt >> results.txt
echo "" >> results.txt
echo "## Performance Analysis" >> results.txt
cat /tmp/performance_analysis.txt >> results.txt
echo "" >> results.txt
echo "## Code Quality Analysis" >> results.txt
cat /tmp/quality_analysis.txt >> results.txt

echo "✓ Results saved to results.txt"
```

**Pattern 4: High-Reasoning Complex Refactoring**

For complex architectural changes, use maximum reasoning capability.

```bash
# Complex refactoring with high reasoning effort
codex exec \
  -m gpt-5-codex \
  -c model_reasoning_effort="high" \
  --sandbox workspace-write \
  --full-auto \
  "Refactor this codebase to implement the Strategy pattern for payment processing. \
   Ensure backward compatibility, update tests, and document the new architecture. \
   Consider database migration if needed." \
  2>/dev/null
```

**Pattern 5: Chained Workflow with Dependency** (improvement, documentation, typing, testing)

Orchestrate multiple dependent tasks sequentially.

```python
def comprehensive_code_improvement():
    """Execute improvement workflow with dependency management."""

    tasks = [
        {
            "name": "documentation",
            "description": "Add comprehensive docstrings and API documentation",
            "sandbox": "workspace-write",
            "reasoning": "medium"
        },
        {
            "name": "typing",
            "description": "Add type hints to all functions based on documented interfaces",
            "sandbox": "workspace-write",
            "reasoning": "high",
            "depends_on": "documentation"
        },
        {
            "name": "testing",
            "description": "Generate comprehensive unit tests for typed functions",
            "sandbox": "workspace-write",
            "reasoning": "high",
            "depends_on": "typing"
        },
        {
            "name": "validation",
            "description": "Run linters, type checkers, and tests; fix issues",
            "sandbox": "workspace-write",
            "reasoning": "medium",
            "depends_on": "testing"
        }
    ]

    results = {}

    for task in tasks:
        # Check dependencies
        if "depends_on" in task:
            if task["depends_on"] not in results:
                print(f"Skipping {task['name']}: dependency not met")
                continue

            prev_session = results[task["depends_on"]]["session_id"]
            print(f"\n{task['name']}: Resuming from {task['depends_on']}")

            result = resume_session(
                session_id=prev_session,
                new_instruction=task["description"]
            )
        else:
            print(f"\n{task['name']}: Starting new session")
            result = execute_codex_task(
                f"codex exec -m gpt-5-codex -c model_reasoning_effort={task['reasoning']} "
                f"--sandbox {task['sandbox']} {task['description']}"
            )

        results[task["name"]] = result
        print(f"✓ {task['name']} complete")

    return results
```

**Pattern 6: Conditional Workflows**

Branch workflow based on analysis results.

```bash
# Analyze codebase
ANALYSIS=$(codex exec -m gpt-5-codex --sandbox read-only \
  "Analyze code and determine if full refactoring or incremental fixes needed" \
  2>/dev/null)

if echo "$ANALYSIS" | grep -q "full refactoring recommended"; then
    echo "Full refactoring needed..."
    codex exec -m gpt-5-codex --full-auto \
      "Perform comprehensive refactoring of entire module" \
      2>/dev/null
else
    echo "Incremental fixes sufficient..."
    codex exec -m gpt-5-codex --full-auto \
      "Apply targeted fixes and improvements" \
      2>/dev/null
fi
```

**Best Practices for Advanced Patterns**:

1. **Break complex tasks into sessions**: Easier to manage and understand
2. **Use appropriate sandbox modes**: Don't over-privilege; escalate as needed
3. **Leverage resume capability**: Keep context without repeating explanations
4. **Test refactorings incrementally**: Validate each step before proceeding
5. **Document the workflow**: Record session IDs and purpose of each step
6. **Handle errors gracefully**: Anticipate what can go wrong and have backup plans
7. **Monitor resource usage**: Complex workflows may take time; be patient
8. **Use JSON output for automation**: When chaining programmatically, use `--json`

**Cross-References**:
- Sandbox modes: See "Safety & Permissions" section
- Session management: See "Session Workflow & Persistence" section
- Configuration: See "Configuration Management" section
- Error recovery: See "Debugging Guide" section

---

## Debugging Guide

### Troubleshooting the 7-Step Workflow

Use this guide when Codex tasks fail or produce unexpected results.

**Diagnostic Approach**: Test each workflow step independently to isolate the problem.

### Step 1 Failures: Configuration Validation

**Symptoms**:
- "Codex CLI not found"
- "Configuration invalid"
- "Authentication failed"
- "Permission denied"

**Diagnosis**:
```bash
# Check Codex installation
which codex
codex --version

# Validate configuration
codex config validate

# Verify PATH
echo $PATH | tr ':' '\n' | grep -i codex

# Check config file
cat ~/.codex/config.toml
```

**Solutions**:

| Error | Root Cause | Solution |
|-------|-----------|----------|
| "Command not found" | Codex not installed | `pip install codex-cli` or `brew install codex` |
| "Config parse error" | Corrupted config file | `codex config init` to regenerate |
| "Authentication failed" | Invalid credentials | `codex login` to re-authenticate |
| "Connection refused" | API unavailable | Check internet connection, retry later |
| "No module named 'codex'" | Python path issue | `pip install --upgrade codex-cli` |

**Prevention**:
- Run Step 1 validation before important tasks
- Monitor API status for outages
- Keep credentials up-to-date (`codex login` periodically)
- Back up config: `cp ~/.codex/config.toml ~/.codex/config.toml.backup`

### Step 2 Failures: Task Intent Parsing

**Symptoms**:
- Wrong sandbox mode selected
- Incorrect model chosen
- Reasoning level inappropriate
- Task intent misunderstood

**Diagnosis**:
```python
# Enable debug output
DEBUG = True

# Inspect parsed parameters
print(f"Task description: '{task_description}'")
print(f"Detected intent: {parsed_intent}")
print(f"Selected sandbox: {selected_sandbox}")
print(f"Selected model: {selected_model}")
print(f"Reasoning effort: {reasoning_effort}")
```

**Solutions**:

| Issue | Solution |
|-------|----------|
| Wrong sandbox selected | Manually override in Step 3: use `-s` flag |
| Wrong model chosen | Confirm model during Step 2 questions |
| Misunderstood intent | Rephrase task more clearly; use explicit keywords |
| Reasoning too low/high | Adjust in Step 2 confirmation or use `-c model_reasoning_effort` |

**Tips**:
- Use explicit keywords: "analyze", "refactor", "install", "review"
- Be specific about requirements
- Mention sandbox needs explicitly if Step 2 guesses wrong

### Step 3 Failures: Command Construction

**Symptoms**:
- "Invalid argument" errors
- Malformed command
- Flag incompatibility
- Quoting/escaping errors

**Diagnosis**:
```bash
# Dry-run mode (if available)
codex exec --dry-run -m gpt-5 "Your task"

# Inspect constructed command
echo "Constructed command:"
echo $CODEX_CMD

# Test command syntax
bash -n <<< "$CODEX_CMD"  # Check syntax without executing
```

**Solutions**:

| Error | Root Cause | Solution |
|-------|-----------|----------|
| "Unknown option" | Invalid flag | Check `codex exec --help` for valid flags |
| "Invalid model" | Model name typo | Use `codex model list` to see available models |
| "Conflicting options" | Mutually exclusive flags | Review flag combinations in config.md |
| "Prompt parse error" | Quote/escape issues | Wrap prompt in single quotes: `'...'` |
| "Invalid sandbox mode" | Wrong mode name | Use one of: read-only, workspace-write, danger-full-access |

**Prevention**:
- Always run `codex --help` if trying new flags
- Use variables for complex commands: `SANDBOX="workspace-write"`
- Test command on simple task first
- Quote entire prompt: `"Task description here"`

### Step 4 Failures: Execution Monitoring

**Symptoms**:
- Codex hangs without output
- Process crashes or terminates abruptly
- No progress indication
- Timeout waiting for results

**Diagnosis**:
```bash
# Monitor Codex process
ps aux | grep codex

# Check CPU/memory usage
top -p <codex-pid>

# Monitor network activity (if using remote API)
netstat -an | grep ESTABLISHED

# Check session logs
tail -f ~/.codex/sessions/<session-id>/execution.log

# View system resource limits
ulimit -a
```

**Solutions**:

| Symptom | Root Cause | Solution |
|---------|-----------|----------|
| Hangs without output | Process blocked/waiting | Kill process: `pkill codex`; check network |
| Timeout | Task too complex/long | Reduce task scope; increase timeout config |
| Memory exhaustion | Insufficient RAM | Close other apps; use smaller dataset; break task |
| API timeout | Network issues | Check internet; retry with exponential backoff |
| No output for minutes | Normal (thinking) | Be patient; complex reasoning takes time |
| Infinite loop | Model cycling | Kill and resume with different instruction |

**Timeout Configuration** (in config.toml):
```toml
[execution]
timeout_seconds = 300  # Increase if needed for complex tasks
```

**Prevention**:
- Start with small, well-scoped tasks
- Monitor for progress via logs
- Set realistic expectations for complex reasoning
- Use `--json` output for programmatic monitoring

### Step 5 Failures: Session Management

**Symptoms**:
- "Session not found"
- "Session expired"
- "Session locked" (concurrent access)
- "Cannot resume completed session"
- "Workspace modified, cannot resume"

**Diagnosis**:
```bash
# List all sessions
ls -la ~/.codex/sessions/

# Show session info
cat ~/.codex/sessions/sess_abc123/session.json | jq

# Check session status
cat ~/.codex/sessions/sess_abc123/session.json | jq .status

# Check session age
stat ~/.codex/sessions/sess_abc123/
# Look for "Modify" time

# View workspace diff
cat ~/.codex/sessions/sess_abc123/workspace.diff
```

**Solutions**:

| Error | Root Cause | Solution |
|-------|-----------|----------|
| "Session not found" | Wrong session ID or expired | Use `ls ~/.codex/sessions/` to list sessions |
| "Session expired" | Retention period exceeded | Increase `session.persist_days` in config.toml |
| "Session locked" | Another process using session | Kill competing process or wait for lock release |
| "Session completed" | Session marked done | Create new session; can't resume completed |
| "Workspace modified" | External changes detected | Commit/stash changes: `git status && git stash` |

**Session Cleanup**:
```bash
# Delete old/completed session
rm -rf ~/.codex/sessions/sess_abc123/

# Clean all expired sessions
find ~/.codex/sessions -mtime +7 -exec rm -rf {} \;  # > 7 days old

# View disk usage
du -sh ~/.codex/sessions/
```

**Prevention**:
- Always preserve session IDs from output
- Don't modify workspace externally during session
- Monitor session age; don't let them expire unintentionally
- Regularly clean up old sessions

### Step 6 Failures: Output Processing

**Symptoms**:
- Cannot parse Codex output
- Missing or corrupted results
- Encoding/character issues
- Incomplete output

**Diagnosis**:
```bash
# Check raw output
codex exec -m gpt-5 "Simple task" 2>&1 | tee raw_output.txt

# Check output format
file raw_output.txt
file -i raw_output.txt  # Check encoding

# Count lines/bytes
wc -l raw_output.txt
wc -c raw_output.txt

# Look for truncation
tail raw_output.txt  # Check if ends abruptly
```

**Solutions**:

| Issue | Root Cause | Solution |
|-------|-----------|----------|
| JSON parse error | Malformed JSON output | Use text format instead: remove `--json` flag |
| Truncated output | Output size limit exceeded | Increase max output size in config.toml |
| Encoding issues | Non-UTF-8 characters | Check file encoding: `file -i output.txt` |
| Missing results | Output redirect failed | Check file permissions, disk space |
| Garbled text | Terminal encoding mismatch | Set: `export LC_ALL=en_US.UTF-8` |

**Output Configuration**:
```toml
# In config.toml
[output]
max_size_bytes = 10485760  # 10MB default; increase if needed
format = "text"  # or "json" for structured output
```

**Prevention**:
- Test output parsing with simple tasks first
- Save output to files: `-o output.txt`
- Check terminal encoding: `echo $LC_ALL`
- Validate output format before parsing

### Step 7 Failures: Error Recovery

**Symptoms**:
- Skill crashes on Codex errors
- Error messages unclear or unhelpful
- Cannot determine recovery action
- Repeated failures on retry

**Diagnosis**:
```python
# Enable full exception tracing
import traceback
try:
    execute_codex_task(...)
except Exception as e:
    traceback.print_exc()
    print(f"\nError type: {type(e).__name__}")
    print(f"Error message: {str(e)}")
    # Log full context
```

**Solutions**:

| Scenario | Diagnosis | Recovery |
|----------|-----------|----------|
| Transient failure | Single retry succeeds | Implement exponential backoff |
| Resource limit | Memory/CPU exhausted | Reduce scope; close other apps |
| Permanent failure | Consistent error | Check prerequisites; update Codex; file issue |
| Sandbox restriction | Permission denied | Escalate sandbox mode; ask for approval |
| Model unavailable | Selected model not accessible | Fallback to alternate model (gpt-5) |
| Rate limit | API throttling | Wait and retry; implement backoff |

**Error Handling Implementation**:
```python
def execute_with_retry(command: str, max_retries: int = 3):
    """Execute with intelligent retry logic."""

    for attempt in range(max_retries):
        try:
            result = execute_codex_task(command)
            if result["success"]:
                return result

            # Classify error
            error_class = classify_error(result["stderr"])

            if error_class == "transient":
                # Retry with backoff
                wait_time = 2 ** attempt
                print(f"Retrying in {wait_time}s...")
                time.sleep(wait_time)
                continue

            elif error_class == "resource_limit":
                # Reduce scope and retry
                print("Resource limit; reducing task scope...")
                command = reduce_task_scope(command)
                continue

            else:  # permanent error
                # Stop and report
                return result

        except Exception as e:
            if attempt < max_retries - 1:
                time.sleep(2 ** attempt)
            else:
                raise

    return result
```

**Prevention**:
- Validate prerequisites before execution (Step 1)
- Start with small, well-defined tasks
- Monitor resource usage during execution
- Handle errors explicitly in code
- Log detailed error information for debugging

### Common Error Messages Reference

| Error Message | Likely Cause | Solution |
|---------------|-------------|----------|
| "Codex CLI not found" | Not installed or not on PATH | Install: `pip install codex-cli` |
| "Configuration invalid" | Corrupt config file | Regenerate: `codex config init` |
| "Authentication failed" | Invalid/expired credentials | Login: `codex login` |
| "Model not available" | Unsupported or unavailable model | Check `codex model list`; use fallback |
| "Permission denied" | Insufficient sandbox permissions | Escalate sandbox mode |
| "Timeout" | Task too complex/long | Reduce scope; increase timeout |
| "Workspace modified" | Files changed outside Codex | Commit/stash changes first |
| "Session expired" | Session retention exceeded | Increase `persist_days` in config |
| "Invalid argument" | Malformed CLI command | Check `codex exec --help` for syntax |
| "Network error" | Connection problem | Check internet; verify API endpoint |

### Debug Mode Activation

Enable detailed logging for troubleshooting:

```toml
# Add to ~/.codex/config.toml
[debug]
enabled = true
log_level = "DEBUG"  # or "INFO", "WARN", "ERROR"
trace_commands = true
save_intermediate_states = true
log_file = "~/.codex/debug.log"
```

**Review debug logs**:
```bash
tail -f ~/.codex/debug.log
cat ~/.codex/debug.log | grep ERROR
```

**Cross-References**:
- Configuration options: See "Configuration Management" section
- Sandbox permissions: See "Safety & Permissions" section
- Session troubleshooting: See "Session Workflow & Persistence" section
- Advanced patterns: See "Advanced Patterns" section

---

## Quick Reference

### Common Codex Patterns

| Task Intent | Recommended Command | Sandbox | Model | Reasoning |
|---|---|---|---|---|
| **Code Analysis** | `"Analyze codebase for improvements"` | `read-only` | `gpt-5-codex` | `medium` |
| **Refactoring** | `"Refactor module X for clarity"` | `workspace-write` | `gpt-5-codex` | `high` |
| **Documentation** | `"Add docstrings to all functions"` | `workspace-write` | `gpt-5` | `low` |
| **Bug Fixing** | `"Fix bug in function Y"` | `workspace-write` | `gpt-5-codex` | `high` |
| **Test Generation** | `"Generate unit tests for module Z"` | `workspace-write` | `gpt-5-codex` | `medium` |
| **Security Audit** | `"Identify security vulnerabilities"` | `read-only` | `gpt-5-codex` | `high` |
| **Performance Optimization** | `"Optimize performance bottlenecks"` | `workspace-write` | `gpt-5-codex` | `high` |
| **Code Review** | `"Review PR changes for quality"` | `read-only` | `gpt-5` | `medium` |
| **Dependency Update** | `"Update dependencies safely"` | `danger-full-access` | `gpt-5-codex` | `high` |
| **API Documentation** | `"Document all API endpoints"` | `workspace-write` | `gpt-5` | `low` |
| **Resume Session** | `echo "prompt" \| codex exec resume --last` | (inherited) | (inherited) | (inherited) |

### SKILL.md Workflow → Codex CLI Mapping

| SKILL.md Step | Codex CLI Feature | Purpose | Key Flags |
|---|---|---|---|
| Step 1: Validate Config | `codex --version`, `codex config validate` | Ensure CLI readiness | N/A |
| Step 2: Parse Intent | (Internal logic) | Extract task intent | N/A |
| Step 3: Construct Command | `codex exec` + flags | Build CLI invocation | `-m`, `-c`, `-s`, `--skip-git-repo-check` |
| Step 4: Execute & Monitor | `codex exec` execution | Run task with streaming | `2>/dev/null` (suppress thinking) |
| Step 5: Session Management | `~/.codex/sessions/` | Persist state | `--skip-git-repo-check resume --last` |
| Step 6: Output Processing | Parse output | Extract results | `--json`, `-o` (output file) |
| Step 7: Error Recovery | Exception handling | Handle failures | (automatic) |

### Configuration Quick Reference

```toml
# Essential ~/.codex/config.toml settings

[model]
default = "gpt-5-codex"              # Default model
# Options: gpt-5, gpt-5-codex, o3, etc.

[reasoning]
effort = "medium"                     # Default reasoning
# Options: low, medium, high

[sandbox]
default_mode = "workspace-write"      # Default permissions
# Options: read-only, workspace-write, danger-full-access
approval_policy = "on-failure"        # When to ask user
# Options: untrusted, on-failure, on-request, never

[session]
auto_resume = true                    # Auto-continue sessions
persist_days = 7                      # Keep sessions 7 days
auto_cleanup = true                   # Delete expired sessions

[execution]
timeout_seconds = 300                 # Execution timeout
```

### Command Construction Templates

**Read-Only Analysis**:
```bash
codex exec -m gpt-5-codex -c model_reasoning_effort="medium" \
  --sandbox read-only --skip-git-repo-check \
  "Your task" 2>/dev/null
```

**Workspace-Write Editing**:
```bash
codex exec -m gpt-5-codex -c model_reasoning_effort="high" \
  --sandbox workspace-write --full-auto --skip-git-repo-check \
  "Your task" 2>/dev/null
```

**Full-Access Automation**:
```bash
codex exec -m gpt-5-codex -c model_reasoning_effort="high" \
  --sandbox danger-full-access --full-auto --skip-git-repo-check \
  "Your task" 2>/dev/null
```

**Resume Session**:
```bash
echo "Your continuation prompt" | codex exec --skip-git-repo-check resume --last 2>/dev/null
```

### File Locations Reference

| Resource | Path | Purpose |
|---|---|---|
| Config file | `~/.codex/config.toml` | User configuration |
| Sessions directory | `~/.codex/sessions/<session-id>/` | Session persistence |
| Execution logs | `~/.codex/sessions/<id>/execution.log` | What happened during run |
| Audit trail | `~/.codex/sessions/<id>/audit.log` | Security/command record |
| Conversation | `~/.codex/sessions/<id>/conversation.jsonl` | Full chat history |
| Workspace diff | `~/.codex/sessions/<id>/workspace.diff` | File changes made |
| Debug log | `~/.codex/debug.log` | Full debug information |

### Keyboard Shortcuts & Commands

| Action | Command |
|---|---|
| Validate setup | `codex --version && codex config validate` |
| View config | `cat ~/.codex/config.toml` |
| List sessions | `ls ~/.codex/sessions/` |
| Inspect session | `cat ~/.codex/sessions/sess_abc123/session.json \| jq` |
| Delete session | `rm -rf ~/.codex/sessions/sess_abc123/` |
| Clean old sessions | `find ~/.codex/sessions -mtime +7 -exec rm -rf {} \;` |
| Check logs | `tail -f ~/.codex/sessions/<id>/execution.log` |
| Login | `codex login` |
| Help | `codex --help` or `codex exec --help` |

---

## Running a Task (Simplified View)

For quick reference, here's the condensed 7-step process:

1. **Validate Configuration**: Check `codex --version` and credentials
2. **Parse Task Intent**: Ask user to confirm model and reasoning effort
3. **Construct Command**: Assemble `codex exec` with appropriate flags
4. **Execute with Monitoring**: Run command and stream output
5. **Session Management**: Track and preserve session ID for resume capability
6. **Output Processing**: Parse results and format for user
7. **Error Recovery & Notification**: Report results, offer resume capability, provide guidance

After every Codex execution, inform the user:
> "You can resume this Codex session at any time by saying 'codex resume' or asking me to continue with additional analysis or changes."

---

## Following Up

After every Codex command:
- Use `AskUserQuestion` to confirm next steps
- Offer resume capability for continuation
- When resuming, pipe new prompt via stdin: `echo "prompt" | codex exec resume --last 2>/dev/null`
- Restate chosen model, reasoning effort, and sandbox mode when proposing actions

---

## Error Handling

**Before High-Impact Actions**:
- `--full-auto` (automatic execution)
- `--sandbox danger-full-access` (unrestricted access)
- `--skip-git-repo-check` (outside Git repo)

**Ask for permission via `AskUserQuestion`** unless already given.

When Codex output includes warnings or partial results:
- Summarize findings
- Ask user via `AskUserQuestion` how to adjust
- Offer resume to refine or restart

**Stop and Report on Non-Zero Exit**:
- Always report Codex errors
- Request user direction before retrying
- Provide link to relevant SKILL.md debugging section

---

## External Documentation References

### Codex CLI Official Documentation

| Resource | URL | Content |
|---|---|---|
| Main Repository | https://github.com/openai/codex | Overview, installation, features |
| Configuration Guide | https://github.com/openai/codex/blob/main/docs/config.md | Complete config options, schemas |
| Exec Command Reference | https://github.com/openai/codex/blob/main/docs/exec.md | Non-interactive execution, sessions |
| Issue Tracker | https://github.com/openai/codex/issues | Bug reports, feature requests |
| Discussions | https://github.com/openai/codex/discussions | Community Q&A and examples |

### SKILL.md Cross-Reference Index

**Find information on these topics**:

- **Installation**: See README.md#prerequisites
- **Configuration**: See "Configuration Management" section (above)
- **Sandbox modes**: See "Safety & Permissions" section (above)
- **Session resume**: See "Session Workflow & Persistence" section (above)
- **Error resolution**: See "Debugging Guide" section (above)
- **Complex workflows**: See "Advanced Patterns" section (above)
- **Command examples**: See "Quick Reference" section (above)
- **Architecture**: See "Codex CLI Architecture Integration" section (above)

**Need help with**:

| Question | Location |
|---|---|
| "How do I...?" | See "Quick Reference" section |
| "Why did it fail?" | See "Debugging Guide" section |
| "How can I resume?" | See "Session Workflow & Persistence" section |
| "What's the security risk?" | See "Safety & Permissions" section |
| "How do I configure...?" | See "Configuration Management" section |
| "Can I do this in parallel?" | See "Advanced Patterns" section |

---

## Document Version History

### Version 2.0.0 (Current)
- **Date**: 2025-11-09
- **Length**: 500+ lines (expanded from 42)
- **Changes**:
  - Expanded all 7 steps from brief items to detailed 40-80 line sections
  - Added 7 major new sections (Architecture, Configuration, Sessions, Safety, Advanced, Debugging, Quick Reference)
  - Created comprehensive cross-reference system
  - Added real-world examples and patterns
  - Documented error scenarios and recovery strategies
- **Codex CLI Compatibility**: 0.56.0 and above
- **Key Improvements**:
  - Complete workflow documentation with technical details
  - Extensive troubleshooting guide
  - Security and permissions explained in depth
  - Advanced patterns for complex workflows
  - Quick reference tables for common tasks

### Version 1.0.0 (Previous)
- **Date**: 2025-10-XX
- **Length**: 42 lines
- **Content**: Initial 7-step workflow outline
- **Codex CLI Compatibility**: 0.50.0+

### Maintenance Notes

**When to Update SKILL.md**:
- **Codex CLI version changes**: Update compatibility notes
- **New features released**: Add to Advanced Patterns section
- **Bug fixes needed**: Update Debugging Guide with solutions
- **Configuration changes**: Sync with official config.md
- **User feedback**: Address common questions in FAQ expansion

**Codex Version Compatibility**:
- Tested with: codex-cli 0.56.0
- Minimum recommended: 0.50.0
- Maximum tested: 0.56.0
- Note compatibility issues if Codex releases breaking changes

---

*Last Updated: 2025-11-09*
*Maintained by: skill-codex project*
*Status: Production Ready*
