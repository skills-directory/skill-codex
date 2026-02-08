Leave a star ⭐ if you like it 😘

# Codex Integration for Claude Code

<img width="2288" height="808" alt="skillcodex" src="https://github.com/user-attachments/assets/85336a9f-4680-479e-b3fe-d6a68cadc051" />


## Purpose
Enable Claude Code to invoke the Codex CLI (`codex exec` and session resumes) for automated code analysis, refactoring, and editing workflows.

## Prerequisites
- `codex` CLI installed and available on `PATH`.
- Codex configured with valid credentials and settings.
- Confirm the installation by running `codex --version`; resolve any errors before using the skill.

## Installation

This repository is structured as a [Claude Code Plugin](https://code.claude.com/docs/en/plugins) with a marketplace. You can install it as a **plugin** (recommended) or extract it as a **standalone skill**.

### Option 1: Plugin Installation (Recommended)

Install via Claude Code's plugin system for automatic updates:

```
/plugin marketplace add skills-directory/skill-codex
/plugin install skill-codex@skill-codex
```

### Option 2: Standalone Skill Installation

Extract the skill folder manually:

```
git clone --depth 1 git@github.com:skills-directory/skill-codex.git /tmp/skills-temp && \
mkdir -p ~/.claude/skills && \
cp -r /tmp/skills-temp/plugins/skill-codex/skills/codex ~/.claude/skills/codex && \
rm -rf /tmp/skills-temp
```

## Usage

### Important: Thinking Tokens
This skill captures stderr separately and handles it conditionally: concise summaries on success, full stderr surfaced on failures. If you want raw stderr/thinking output even on successful runs, explicitly ask Claude to show it.

### Example Workflow

**User prompt:**
```
Use codex to analyze this repository and suggest improvements for my claude code skill.
```

**Claude Code response:**
Claude will activate the Codex skill and:
1. Ask for model and reasoning effort only if you did not already specify them.
2. Run preflight checks (`codex --version`, repo context, safety/privacy constraints).
3. Select appropriate sandbox mode (defaults to `read-only` for analysis).
4. Run a command like:
```bash
printf '%s' "Analyze this Claude Code skill repository comprehensively..." | codex exec \
  -m "<chosen-model>" \
  --config model_reasoning_effort="medium" \
  --sandbox read-only \
  --json
```

**Result:**
Claude will summarize the Codex analysis output, highlighting key suggestions and asking if you'd like to continue with follow-up actions.

### Detailed Instructions
See [`plugins/skill-codex/skills/codex/SKILL.md`](plugins/skill-codex/skills/codex/SKILL.md) for complete operational instructions, CLI options, and workflow guidance.

## License

MIT License - see [LICENSE](LICENSE) for details.
