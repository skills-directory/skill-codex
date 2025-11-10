# Skills Directory Plugins Marketplace

The official Skills Directory marketplace for Claude Code extensions. Currently featuring the Codex Integration plugin for automated code analysis and refactoring.

## Quick Start

### Standard Installation

Run Claude and add the marketplace:

/plugin marketplace add https://github.com/skills-directory/skill-codex

Then install the plugin:

/plugin install codex-integration

### One-Command Installation

Use the [Claude Plugins CLI](https://claude-plugins.dev) to skip the marketplace setup:

npx claude-plugins install @skills-directory/skill-codex/codex-integration

This automatically adds the marketplace and installs the plugin in a single step.

### Local Development Installation

For development and testing:

```bash
git clone https://github.com/skills-directory/skill-codex.git
cd skill-codex
claude
/plugin marketplace add .
/plugin install codex-integration
```

---

# Codex Integration Plugin

A Claude Code plugin that enables automated code analysis, refactoring, and editing workflows using the Codex CLI.

## What Is Codex Integration?

**Transform how you analyze and refactor code using AI-powered automation.**

Traditional code review and refactoring requires manual effort and expertise. The Codex Integration plugin automates these processes by:

- Running comprehensive code analysis with multiple AI models
- Providing systematic refactoring suggestions
- Supporting session resumption for iterative improvements
- Offering configurable reasoning effort levels
- Managing sandbox environments for safe execution

This plugin makes code improvement workflows more efficient and consistent, allowing developers to focus on high-level decisions while AI handles the detailed analysis and refactoring work.

## How It Works

The plugin provides a streamlined workflow for AI-powered code analysis:

### 1\. Model & Configuration Selection

When you request Codex analysis, Claude automatically:
- Asks which model to use (`gpt-5` or `gpt-5-codex`)
- Determines appropriate reasoning effort (`low`, `medium`, or `high`)
- Selects the right sandbox mode for your task

### 2\. Automated Execution

The plugin executes Codex commands with optimal settings:
- Uses `--full-auto` for automated workflows
- Applies `--skip-git-repo-check` for flexibility
- Suppresses thinking tokens by default to reduce context usage
- Captures and summarizes results for easy consumption

### 3\. Session Management

Supports resumable sessions for iterative work:
- Resume previous analysis sessions
- Maintain context across multiple interactions
- Preserve user preferences and configurations

📖 **For complete technical workflow details**, see [SKILL.md - The 7-Step Workflow](./plugins/codex-integration/skills/codex/SKILL.md#the-7-step-workflow)

## Practical Examples

### Example: Repository Analysis

**Request:**
```
Use codex to analyze this repository and suggest improvements
```

**Process:**
1. Claude selects appropriate model and reasoning effort
2. Runs Codex in read-only sandbox mode
3. Analyzes codebase structure and patterns
4. Provides comprehensive improvement suggestions

### Example: Code Refactoring

**Request:**
```
Refactor this function using codex for better performance
```

**Process:**
1. Claude configures workspace-write sandbox mode
2. Executes Codex with high reasoning effort
3. Applies automated refactoring suggestions
4. Validates changes and provides summary

### Example: Session Resumption

**Request:**
```
Continue the codex analysis from before
```

**Process:**
1. Resumes previous session automatically
2. Maintains original model and configuration
3. Continues iterative improvement process

## Configuration Options

### Models
- **gpt-5**: General purpose model, good for most tasks
- **gpt-5-codex**: Specialized for code-related tasks

### Reasoning Effort
- **low**: Quick analysis, faster execution
- **medium**: Balanced analysis and speed
- **high**: Deep analysis, slower but more thorough

### Sandbox Modes
- **read-only**: Analysis and suggestions only
- **workspace-write**: Apply local code changes
- **danger-full-access**: Network access and broader permissions

🔧 **For detailed configuration guidance and advanced options**, see [SKILL.md - Configuration Management](./plugins/codex-integration/skills/codex/SKILL.md#configuration-management)

⚠️ **For sandbox mode security details and safety guidelines**, see [SKILL.md - Safety & Permissions](./plugins/codex-integration/skills/codex/SKILL.md#safety--permissions)

## Key Features

### Thinking Token Management
- Suppresses stderr output by default to optimize context usage
- Allows explicit requests to view thinking tokens for debugging
- Balances transparency with efficiency

### Error Handling
- Validates Codex CLI installation before use
- Provides clear error messages and recovery guidance
- Stops execution safely when issues occur

### Session Persistence
- Maintains context across multiple interactions
- Supports resumable workflows
- Preserves user preferences and configurations

## Why This Makes Development Better

**Traditional development challenges:**
- Manual code review is time-consuming and inconsistent
- Refactoring requires deep expertise and careful execution
- Analysis often misses subtle issues or opportunities

**Codex Integration advantages:**
- Consistent, automated analysis using advanced AI models
- Systematic refactoring with validation
- Scalable workflows that work across team sizes
- Reduced cognitive load on developers
- Faster iteration cycles with resumable sessions

## Prerequisites

- **Codex CLI**: Installed and available on PATH
- **Credentials**: Valid Codex API credentials configured
- **Claude Code**: Plugin support enabled
- **Verification**: Run `codex --version` to confirm installation

## Installation Methods

### Marketplace Installation (Recommended)

```bash
# Add the Skills Directory marketplace
/plugin marketplace add https://github.com/skills-directory/skill-codex

# Install the Codex Integration plugin
/plugin install codex-integration
```

### Direct Repository Installation

```bash
# Clone and install locally
git clone https://github.com/skills-directory/skill-codex.git
cd skill-codex
claude
/plugin marketplace add .
/plugin install codex-integration
```

### Manual Skill Installation (Fallback)

```bash
# Manual installation to user skills directory
git clone https://github.com/skills-directory/skill-codex.git ~/.claude/skills/codex-integration
```

## Usage Guidelines

### Basic Usage
Start with natural language requests:
- "Analyze this codebase with codex"
- "Use codex to refactor this function"
- "Run codex analysis on these files"

### Advanced Configuration
Specify preferences explicitly:
- "Use codex with high reasoning effort to analyze..."
- "Run codex in read-only mode for..."
- "Use gpt-5-codex model for this analysis"

### Session Management
- Resume with: "Continue the codex analysis"
- New sessions automatically use previous settings
- Override settings for specific requests

## Getting Started

1. **Install Prerequisites**
   ```bash
   # Verify Codex CLI
   codex --version
   ```

2. **Install Plugin**
   ```bash
   /plugin marketplace add https://github.com/skills-directory/skill-codex
   /plugin install codex-integration
   ```

3. **Start Using**
   ```
   Use codex to analyze this repository
   ```

4. **Explore Features**
   - Try different reasoning effort levels
   - Experiment with various request types
   - Use session resumption for iterative work

## Technical Details

### Plugin Structure
```
skill-codex/
├── .claude-plugin/marketplace.json    # Marketplace configuration
├── plugins/codex-integration/         # Plugin directory
│   ├── .claude-plugin/plugin.json     # Plugin manifest
│   └── skills/codex/SKILL.md          # Skill implementation (authoritative reference)
├── CLAUDE.md                          # Usage instructions for Claude Code
└── README.md                          # This documentation
```

### Skill Implementation & Documentation

The authoritative technical documentation is in [SKILL.md](./plugins/codex-integration/skills/codex/SKILL.md), which includes:

- **7-Step Workflow**: Detailed breakdown of how the plugin executes Codex tasks
- **Architecture Integration**: How the skill wraps Codex CLI for automation
- **Configuration Management**: Complete guide to config.toml settings and overrides
- **Session Management**: Understanding resumable sessions and persistence
- **Safety & Permissions**: Sandbox modes explained with security guidelines
- **Advanced Patterns**: Multi-step workflows, parallel execution, conditional logic
- **Debugging Guide**: Comprehensive troubleshooting for each workflow step
- **Quick Reference**: Common patterns, command templates, and lookup tables

For API-level details, consult the official Codex documentation:
- [Codex Configuration Guide](https://github.com/openai/codex/blob/main/docs/config.md)
- [Codex Exec Command Reference](https://github.com/openai/codex/blob/main/docs/exec.md)

---

# Ripgrep Explorer Plugin

A Claude Code plugin that enables fast, structured code search using ripgrep (rg) with JSON output and sensible defaults.

## What Is Ripgrep Explorer?

**Blazing‑fast file/code search with structured results.**

This plugin standardizes rg usage so you can quickly locate symbols, TODOs, and patterns across repos while respecting ignores and providing JSON‑parsed results suitable for navigation or follow‑ups.

## How It Works

The skill constructs safe, reproducible rg commands:

### Defaults
- JSON output: `--json -n --color never`
- Smart case: `-S`
- Excludes: `-g '!{.git,node_modules,.venv,dist,build,.next,.cache,coverage}'`

### Common Variants
- Literal search: add `-F`
- Types: `-t py -t js -t ts ...`
- Globs: `-g 'src/**'`, `--iglob '*.test.*'`
- Expand scope: `--hidden`, `--no-ignore`

📖 See [SKILL.md](./plugins/ripgrep-explorer/skills/rg/SKILL.md) for the 7‑step workflow and examples.

## Practical Examples

### Example: Find TODOs
```
Use ripgrep to find TODO|FIXME across the repo
```
Result: Runs `rg --json -n -S -g '!{.git,node_modules,.venv,dist,build}' -- 'TODO|FIXME'` and returns grouped matches.

### Example: Limit to Python files
```
Search 'async|await' only in Python
```
Result: Adds `-t py` and returns structured results with file/line/column.

## Installation

```bash
/plugin marketplace add https://github.com/skills-directory/skill-codex
/plugin install ripgrep-explorer
```

## Prerequisites

- ripgrep installed (`rg --version`)

## Why It Helps

- Faster than naive grep; respects `.gitignore` by default
- JSON Lines enable precise formatting and navigation
- Safe defaults with opt‑in expansion for deep searches
- Reproducible: uses `--no-config` so results aren’t affected by user `RIPGREP_CONFIG_PATH`

## Smoke Test

```bash
bash scripts/rg_smoke.sh
```
Runs a minimal JSON search with reproducible flags and prints a small summary.

---

# AST-Grep Explorer Plugin

An AST-aware code search and refactoring plugin powered by ast-grep (`sg`). It matches syntax nodes instead of plain text and can apply safe structural rewrites with dry-run by default.

## What It Does

- Structural search: query AST patterns across supported languages
- Rule-based scans: run YAML rules with optional `fix:` blocks
- Safe refactors: `--dry-run` previews replacements before applying
- Structured output: streaming JSON for precise navigation

## How It Works

The skill builds `sg run` commands with safe defaults:

### Defaults
- JSON: `--json=stream -n`
- Excludes: `-g '!{.git,node_modules,.venv,dist,build,.next,.cache,coverage}'`
- Read-only unless rewrite is requested; refactors use `--dry-run` unless you confirm apply

### Common Variants
- Pattern search: `sg run -p '<pattern>' [--lang <lang>]`
- Rule directory: `sg run -r rules/`
- Rewrite preview: `sg run -p '<pattern>' --rewrite '<replacement>' --dry-run`
 - Diagnostics: add `--inspect` to debug rule/pattern behavior

📖 See [SKILL.md](./plugins/ast-grep-explorer/skills/sg/SKILL.md) for the 7‑step workflow and examples.

## Practical Examples

### Example: Find console calls in TS/JS
```
Use ast-grep to find console calls in TypeScript and JavaScript
```
Runs `sg run -p 'call_expression(callee: identifier(name: "console"))' --json=stream -n -t ts -t js` and returns grouped, navigable matches.

### Example: Preview a rename refactor
```
Rename identifier 'foo' to 'bar' in TypeScript (preview only)
```
Runs `sg run -p 'identifier(name: "foo")' --rewrite 'bar' --dry-run --json=stream -n -t ts` and shows proposed edits.

## Installation

```bash
/plugin marketplace add https://github.com/skills-directory/skill-codex
/plugin install ast-grep-explorer
```

## Prerequisites

- ast-grep installed (`sg --version`)

## Smoke Test

```bash
bash scripts/sg_smoke.sh
```
Runs a benign structural search; “no matches” is OK and treated as success.

## Example Rule

This repo includes a demo rule:
- `plugins/ast-grep-explorer/examples/rules/no-console.yml`

Preview it against the current workspace:
```bash
sg run -r plugins/ast-grep-explorer/examples/rules --json=stream -n --dir . --lang typescript
```

---

# Tmux Orchestrator Plugin

A minimal tmux orchestration plugin that uses a single shell script to create a master + workers flow for coordinating other agents.

## What It Does
- Creates an isolated tmux server and a session with `master` and `workers`
- Splits `workers` window into N panes
- Runs commands on all workers or a single worker
- Provides attach/status/kill and optional capture of pane text

## Usage

```bash
/plugin marketplace add https://github.com/skills-directory/skill-codex
/plugin install tmux-orchestrator
```

Script:
```bash
# Create with 6 workers, then attach
WORKERS=6 ./scripts/tmux_orchestrator.sh init
./scripts/tmux_orchestrator.sh attach

# Broadcast to all workers
./scripts/tmux_orchestrator.sh run-all "echo hello"

# Target a single worker
./scripts/tmux_orchestrator.sh run-one 2 "pytest -q"

# Master only
./scripts/tmux_orchestrator.sh run-master "codex --version"

# Status, capture, teardown
./scripts/tmux_orchestrator.sh status
./scripts/tmux_orchestrator.sh capture
./scripts/tmux_orchestrator.sh kill
```

## Troubleshooting

### Common Issues

**Codex CLI not found:**
```bash
# Verify installation
which codex
codex --version
```

**Plugin not loading:**
```bash
# Check marketplace
/plugin marketplace list

# Reinstall plugin
/plugin uninstall codex-integration
/plugin install codex-integration
```

**Session issues:**
- Restart Claude Code to clear session state
- Specify model/reasoning explicitly for new sessions

### Debug Mode
Request thinking tokens for troubleshooting:
```
Show me the thinking tokens when running codex analysis
```

🐛 **For comprehensive troubleshooting and error resolution**, see [SKILL.md - Debugging Guide](./plugins/codex-integration/skills/codex/SKILL.md#debugging-guide) which covers:
- Configuration validation errors (Step 1)
- Task intent parsing issues (Step 2)
- Command construction problems (Step 3)
- Execution monitoring failures (Step 4)
- Session management errors (Step 5)
- Output processing issues (Step 6)
- Error recovery strategies (Step 7)

## Contributing

This marketplace follows the Skills Directory contribution guidelines. Plugin submissions welcome!

## About

Official Skills Directory marketplace for Claude Code extensions.

### Resources
[Readme](#skills-directory-plugins-marketplace)
