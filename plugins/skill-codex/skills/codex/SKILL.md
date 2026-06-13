---
name: codex
description: Use when the user asks to run Codex CLI (codex exec, codex resume) or references OpenAI Codex for code analysis, refactoring, or automated editing
---

# Codex Skill Guide

## Running a Task
1. Ask the user (via `AskUserQuestion`) which model to run (`gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.3-codex-spark`, or `gpt-5.3-codex`) AND which reasoning effort to use (`xhigh`, `high`, `medium`, or `low`) in a **single prompt with two questions**.
2. Select the sandbox mode required for the task; default to `--sandbox read-only` unless edits or network access are necessary.
3. Pick a unique `TAG` for this Codex session (e.g. `review-1`, `refactor-auth`). All temp files are namespaced by `TAG`, so concurrent Codex sessions never clobber each other's output.
4. Assemble the initial command. **Always include `--json` and `-o <ANSWER_FILE>`:** `--json` streams events to stdout (this is how the session id is captured for collision-free resume), and `-o` writes the clean final agent message to a file. Options:
   - `-m, --model <MODEL>`
   - `--config model_reasoning_effort="<xhigh|high|medium|low>"`
   - `--sandbox <read-only|workspace-write|danger-full-access>`
   - `--full-auto` (only with `workspace-write` / `danger-full-access`)
   - `-C, --cd <DIR>`
   - `--skip-git-repo-check`
   - `--json -o /tmp/codex-$TAG.txt`
   - `"your prompt here"` (as final positional argument)

   Initial-run template:
   ```bash
   codex exec --skip-git-repo-check -m <MODEL> --config model_reasoning_effort="<EFFORT>" \
     --sandbox <MODE> --json -o /tmp/codex-$TAG.txt "PROMPT" \
     </dev/null 2>/dev/null | tee /tmp/codex-$TAG.jsonl >/dev/null

   SID=$(grep -o '"thread_id":"[0-9a-f-]*"' /tmp/codex-$TAG.jsonl | head -1 | sed 's/.*"thread_id":"//;s/"//')
   # clean final answer -> cat /tmp/codex-$TAG.txt        session id for resume -> $SID
   ```
5. Always use `--skip-git-repo-check`.
6. **Resume by explicit session id, never `--last`.** Record `$SID` from the initial run. `--last` resolves to the newest recorded session *scoped to the current cwd*; when two Codex sessions share a cwd (common — several rounds in one repo) both resume the same target and the call hangs. Resuming by id is collision-free, fully parallel-safe, and preserves the session's context across rounds. All flags go **between** `exec` and `resume`; the new prompt is positional. Don't pass model / reasoning effort / sandbox on resume (they are inherited) unless the user explicitly requests it.

   Resume template:
   ```bash
   codex exec --skip-git-repo-check resume "$SID" "NEXT PROMPT" \
     --json -o /tmp/codex-$TAG.txt </dev/null 2>/dev/null | tee /tmp/codex-$TAG.jsonl >/dev/null
   ```
7. **IMPORTANT (stderr)**: By default, append `2>/dev/null` to all `codex exec` commands to suppress thinking tokens (stderr). Only show stderr if the user explicitly requests to see thinking tokens or if debugging is needed.
8. **IMPORTANT (stdin)**: `codex exec` always reads stdin and concatenates it with the positional prompt -- even when the prompt is fully supplied as a positional argument. If stdin is not closed, codex blocks forever. When invoking from a harness (background tasks, hooks, scripts where stdin is not a TTY but also not closed), explicitly redirect stdin: append `</dev/null` to the command, e.g. `codex exec ... "prompt" </dev/null 2>/dev/null`. Symptom of getting this wrong: zero bytes of stdout, zero CPU accumulated, process appears hung indefinitely.
9. Run the command, read the clean answer from `/tmp/codex-$TAG.txt`, and summarize the outcome for the user.
10. **After Codex completes**, inform the user: "You can resume this Codex session at any time (I'll reuse its id) by asking me to continue with additional analysis or changes."

### Quick Reference
| Use case | Sandbox mode | Key flags |
| --- | --- | --- |
| Read-only review or analysis | `read-only` | `--sandbox read-only --json -o /tmp/codex-$TAG.txt "PROMPT" </dev/null 2>/dev/null` |
| Apply local edits | `workspace-write` | `--sandbox workspace-write --full-auto --json -o /tmp/codex-$TAG.txt "PROMPT" </dev/null 2>/dev/null` |
| Permit network or broad access | `danger-full-access` | `--sandbox danger-full-access --full-auto --json -o /tmp/codex-$TAG.txt "PROMPT" </dev/null 2>/dev/null` |
| Resume a specific session | Inherited from original | `codex exec --skip-git-repo-check resume "$SID" "PROMPT" --json -o /tmp/codex-$TAG.txt </dev/null 2>/dev/null` |
| Run from another directory | Match task needs | `-C <DIR>` plus other flags |

> **Never use `resume --last` for ongoing work.** It is cwd-scoped to the single newest session and collides/hangs when sessions run in parallel. Capture and track `$SID` per session instead.

## Execution timeouts

Codex produces **no intermediate output** — it writes the result only at completion. If the process is killed before finishing, the output file is silently empty (no error).

**Preferred approach:** run synchronously — eliminates timeout risk entirely and the conversation waits for the result anyway.

**If running in background**, set the execution timeout based on reasoning effort:

| Reasoning effort | Timeout |
|---|---|
| `low` | 150s |
| `medium` | 300s |
| `high` | 600s |
| `xhigh` | 1200s |

## Following Up
- After every `codex` command, immediately use `AskUserQuestion` to confirm next steps, collect clarifications, or decide whether to resume.
- Resume by the captured `$SID` (see the resume template above), never `--last`. The resumed session automatically uses the same model, reasoning effort, and sandbox mode from the original session.
- Keep one `$SID` and one `$TAG` per logical session. If several Codex sessions are live at once, keep their ids distinct — never resolve them with `--last`.
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
   codex exec --skip-git-repo-check resume "$SID" \
     "This is Claude (<your current model name>) following up. I disagree with [X] because [evidence]. What's your take on this?" \
     --json -o /tmp/codex-$TAG.txt </dev/null 2>/dev/null
   ```
4. Frame disagreements as discussions, not corrections - either AI could be wrong
5. Let the user decide how to proceed if there's genuine ambiguity

## Error Handling
- Stop and report failures whenever `codex --version` or a `codex exec` command exits non-zero; request direction before retrying.
- If `$SID` comes back empty, id capture failed — re-run the exec without `2>/dev/null` (or inspect `/tmp/codex-$TAG.jsonl`) to see the error; do not fall back to `resume --last`.
- Before you use high-impact flags (`--full-auto`, `--sandbox danger-full-access`, `--skip-git-repo-check`) ask the user for permission using AskUserQuestion unless it was already given.
- When output includes warnings or partial results, summarize them and ask how to adjust using `AskUserQuestion`.
