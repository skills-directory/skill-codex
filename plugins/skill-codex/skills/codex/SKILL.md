---
name: codex
description: Use when the user asks to run Codex CLI (codex exec, codex resume) or references OpenAI Codex for code analysis, refactoring, or automated editing
---

# Codex Skill Guide

## Running a Task
1. Ask the user (via `AskUserQuestion`) which model to run (`gpt-5.3-codex` or `gpt-5.2`) AND which reasoning effort to use (`xhigh`, `high`, `medium`, or `low`) in a **single prompt with two questions**.
2. Select the sandbox mode required for the task; default to `--sandbox read-only` unless edits or network access are necessary.
3. Assemble the command with the appropriate options:
   - `-m, --model <MODEL>`
   - `--config model_reasoning_effort="<xhigh|high|medium|low>"`
   - `--sandbox <read-only|workspace-write|danger-full-access>`
   - `--full-auto`
   - `-C, --cd <DIR>`
   - `--skip-git-repo-check`
   - `"your prompt here"` (as final positional argument)
3. Always use --skip-git-repo-check.
4. When continuing a previous session, use `codex exec --skip-git-repo-check resume --last` via stdin. When resuming don't use any configuration flags unless explicitly requested by the user e.g. if he species the model or the reasoning effort when requesting to resume a session. Resume syntax: `echo "your prompt here" | codex exec --skip-git-repo-check resume --last 2>/dev/null`. All flags have to be inserted between exec and resume.
5. **IMPORTANT**: By default, append `2>/dev/null` to all `codex exec` commands to suppress thinking tokens (stderr). Only show stderr if the user explicitly requests to see thinking tokens or if debugging is needed.
6. Run the command, capture stdout/stderr (filtered as appropriate), and summarize the outcome for the user.
7. **After Codex completes**, inform the user: "You can resume this Codex session at any time by saying 'codex resume' or asking me to continue with additional analysis or changes."

### Quick Reference
| Use case | Sandbox mode | Key flags |
| --- | --- | --- |
| Read-only review or analysis | `read-only` | `--sandbox read-only 2>/dev/null` |
| Apply local edits | `workspace-write` | `--sandbox workspace-write --full-auto 2>/dev/null` |
| Permit network or broad access | `danger-full-access` | `--sandbox danger-full-access --full-auto 2>/dev/null` |
| Resume recent session | Inherited from original | `echo "prompt" \| codex exec --skip-git-repo-check resume --last 2>/dev/null` (no flags allowed) |
| Run from another directory | Match task needs | `-C <DIR>` plus other flags `2>/dev/null` |

## Following Up
- After every `codex` command, immediately use `AskUserQuestion` to confirm next steps, collect clarifications, or decide whether to resume with `codex exec resume --last`.
- When resuming, pipe the new prompt via stdin: `echo "new prompt" | codex exec resume --last 2>/dev/null`. The resumed session automatically uses the same model, reasoning effort, and sandbox mode from the original session.
- Restate the chosen model, reasoning effort, and sandbox mode when proposing follow-up actions.

## Critical Evaluation of Codex Output

Codex is powered by OpenAI models with their own knowledge cutoffs and limitations. Treat Codex as a **colleague, not an authority**.

### Guidelines
- **Trust your own knowledge** when confident. If Codex claims something you know is incorrect, push back directly.
- **Research disagreements** using WebSearch or documentation before accepting Codex's claims. Share findings with Codex via resume if needed.
- **Remember knowledge cutoffs** - Codex may not know about recent releases, APIs, or changes that occurred after its training data.
- **Don't defer blindly** - Codex can be wrong. Evaluate its suggestions critically, especially regarding:
  - Model names and capabilities
  - Recent library versions or API changes
  - Best practices that may have evolved

### When Codex is Wrong
1. State your disagreement clearly to the user
2. Provide evidence (your own knowledge, web search, docs)
3. Optionally resume the Codex session to discuss the disagreement. **Identify yourself as Claude** so Codex knows it's a peer AI discussion. Use your actual model name (e.g., the model you are currently running as) instead of a hardcoded name:
   ```bash
   echo "This is Claude (<your current model name>) following up. I disagree with [X] because [evidence]. What's your take on this?" | codex exec --skip-git-repo-check resume --last 2>/dev/null
   ```
4. Frame disagreements as discussions, not corrections - either AI could be wrong
5. Let the user decide how to proceed if there's genuine ambiguity

## Error Handling
- Stop and report failures whenever `codex --version` or a `codex exec` command exits non-zero; request direction before retrying.
- Before you use high-impact flags (`--full-auto`, `--sandbox danger-full-access`, `--skip-git-repo-check`) ask the user for permission using AskUserQuestion unless it was already given.
- When output includes warnings or partial results, summarize them and ask how to adjust using `AskUserQuestion`.
