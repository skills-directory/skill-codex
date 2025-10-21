---
name: codex
description: Use when the user asks to run Codex CLI (codex exec, codex resume) or references OpenAI Codex for code analysis, refactoring, or automated editing
---

# Codex Skill Guide

## Running a Task
1. Ask the user (via `AskUserQuestion`) which model to run: `gpt-5` or `gpt-5-codex`.
2. Ask the user (via `AskUserQuestion`) which reasoning effort to use: `low`, `medium`, or `high`.
3. Select the sandbox mode required for the task; default to `--sandbox read-only` unless edits or network access are necessary.
4. Assemble the command with the appropriate options:
   - `-m, --model <MODEL>`
   - `--config model_reasoning_effort="<low|medium|high>"`
   - `--sandbox <read-only|workspace-write|danger-full-access>`
   - `--full-auto`
   - `-C, --cd <DIR>`
   - `--skip-git-repo-check`
5. Include `codex exec resume --last` when continuing a previous session and reapply every required flag.
6. Run the command, capture stdout/stderr, and summarize the outcome for the user.

### Quick Reference
| Use case | Sandbox mode | Key flags |
| --- | --- | --- |
| Read-only review or analysis | `read-only` | `--sandbox read-only` |
| Apply local edits | `workspace-write` | `--sandbox workspace-write --full-auto` |
| Permit network or broad access | `danger-full-access` | `--sandbox danger-full-access --full-auto` |
| Resume recent session | Match prior task | `codex exec resume --last` plus prior flags |
| Run from another directory | Match task needs | `-C <DIR>` plus other flags |

## Following Up
- After every `codex` command, immediately use `AskUserQuestion` to confirm next steps, collect clarifications, or decide whether to resume with `codex exec resume --last`.
- Restate the chosen model, reasoning effort, and sandbox mode when proposing follow-up actions.

## Error Handling
- Stop and report failures whenever `codex --version` or a `codex exec` command exits non-zero; request direction before retrying.
- Before you use high-impact flags (`--full-auto`, `--sandbox danger-full-access`, `--skip-git-repo-check`) ask the user for permission using AskUserQuestion unless it was already given.
- When output includes warnings or partial results, summarize them and ask how to adjust using `AskUserQuestion`.
