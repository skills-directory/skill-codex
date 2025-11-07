# Claude Code Plugin Instructions

This marketplace provides tools for automated code analysis, refactoring, and editing workflows.

## Available Plugins

### codex-integration
**Codex CLI integration for Claude Code**

Enables Claude Code to invoke the Codex CLI (`codex exec` and session resumes) for automated code analysis, refactoring, and editing workflows.

**Key Features:**
- Automated code analysis and refactoring
- Session resume capabilities
- Multiple model support (gpt-5, gpt-5-codex)
- Configurable reasoning effort levels
- Sandbox mode selection for different task types

**When to Use:**
- When users ask to run Codex CLI or reference OpenAI Codex
- For code analysis, refactoring, or automated editing tasks
- When systematic code review and improvement is needed

## Installation

```bash
# Add the marketplace
/plugin marketplace add https://github.com/skills-directory/skill-codex

# Install the plugin
/plugin install codex-integration
```

## Usage Examples

**Basic Code Analysis:**
```
Use codex to analyze this repository and suggest improvements
```

**Code Refactoring:**
```
Run codex to refactor this function for better performance
```

**Resume Previous Session:**
```
Continue with the codex analysis from before
```

## Prerequisites

- `codex` CLI installed and available on PATH
- Codex configured with valid credentials
- Confirm installation: `codex --version`

## Configuration

The plugin supports various sandbox modes:
- `read-only`: For analysis tasks
- `workspace-write`: For applying local edits
- `danger-full-access`: For tasks requiring network or broad access

Model options: `gpt-5`, `gpt-5-codex`
Reasoning effort: `low`, `medium`, `high`