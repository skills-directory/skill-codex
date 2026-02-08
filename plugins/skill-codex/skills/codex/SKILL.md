---
name: codex
description: Delegate tasks to OpenAI Codex CLI when the user asks to run `codex`, `codex exec`, or `codex resume`, or asks for Codex-based code analysis, refactoring, code review, automated edits, or follow-up continuation of a previous Codex session.
---

# Codex Skill Guide

## Operating Principles
- Treat Codex as a collaborator, not an authority; validate high-impact claims.
- Prefer least privilege: start with read-only unless the task requires writes or broader access.
- Delegate only user-approved content; ask before sending sensitive/private material externally.

## Preflight Checks
1. Verify CLI availability first: `codex --version`.
2. Determine whether current directory is a Git repo.
3. Use `--skip-git-repo-check` only when needed (outside Git repos) or when the user explicitly asks.
4. If preflight fails, stop and report the failure with exact stderr.

## Workflow
1. Parse user intent:
- New run: `codex exec ...`
- Resume previous session: `codex exec resume ...`
- Repository review: `codex exec review ...`
2. Collect missing runtime inputs only when unspecified:
- Model (`-m`) and reasoning effort (`--config model_reasoning_effort=...`) in one prompt.
3. Select sandbox mode:
- `read-only` for analysis.
- `workspace-write` for local edits.
- `danger-full-access` only with explicit user confirmation.
4. Build command with safe prompt piping:
- Use `printf '%s' "$PROMPT" | codex exec ...` instead of `echo`.
5. Handle stderr conditionally:
- Capture stderr to a temp file.
- If exit code is 0, summarize concise output (optionally omit noisy stderr).
- If exit code is non-zero, surface stderr and stop.
6. Summarize outcome clearly:
- Include model, reasoning effort, sandbox mode, and whether `--skip-git-repo-check` was used.
7. Offer continuation only when useful:
- If work is complete and unambiguous, provide result and mention resume availability.
- Ask a follow-up question only when there is ambiguity, missing input, or multiple viable next steps.

## Command Patterns

### New Execution
```bash
# Build optional args based on context.
# Add --skip-git-repo-check only when needed.
tmp_err="$(mktemp)"
if printf '%s' "$PROMPT" | codex exec \
  -m "$MODEL" \
  --config "model_reasoning_effort=\"$REASONING\"" \
  --sandbox "$SANDBOX" \
  "$SKIP_GIT_FLAG" \
  "$FULL_AUTO_FLAG" \
  "$SEARCH_FLAG" \
  -C "$WORKDIR" \
  2>"$tmp_err"; then
  # Success: summarize stdout; include stderr only if user asked.
  :
else
  # Failure: report stderr verbatim and stop.
  cat "$tmp_err"
fi
rm -f "$tmp_err"
```

### Resume Last Session
```bash
# Resume uses the most recent session in cwd by default.
# If not found in cwd, retry with --all.
tmp_err="$(mktemp)"
if printf '%s' "$PROMPT" | codex exec resume --last 2>"$tmp_err"; then
  :
elif grep -qi "no sessions\|not found\|no previous" "$tmp_err"; then
  if printf '%s' "$PROMPT" | codex exec resume --last --all 2>"$tmp_err"; then
    :
  else
    cat "$tmp_err"
    # Report: no resumable session; ask whether to start a new exec run.
  fi
else
  cat "$tmp_err"
fi
rm -f "$tmp_err"
```

### Structured Output
```bash
# Use when machine-readable output is requested.
printf '%s' "$PROMPT" | codex exec \
  -m "$MODEL" \
  --sandbox "$SANDBOX" \
  --json \
  -o "$LAST_MSG_FILE"
```

### Review Mode
```bash
# Useful for repo diffs and PR-style review workflows.
printf '%s' "$PROMPT" | codex exec review --base "$BASE_BRANCH"
```

## Edge Cases
- No previous session:
  - If `resume --last` fails, explain clearly and ask whether to start a new run.
- CWD mismatch:
  - Retry resume with `--all`; report which session scope succeeded.
- Timeout strategy:
  - If the user sets a timeout, enforce it with the shell timeout utility when available.
  - If timeout tooling is unavailable, monitor and terminate long-running commands manually, then report partial output.
- Privacy guardrail:
  - Before first delegation in a session, confirm external delegation is acceptable when prompts may include secrets, private code, or regulated data.
- Warnings/partial results:
  - Report warnings explicitly and state confidence/limitations.

## Output Quality Requirements
- Always report:
  - Command intent (new run, resume, review)
  - Effective model/reasoning/sandbox
  - Exit status
  - Key findings or edits
- Never hide failures by default; include actionable stderr on error.
- When disagreeing with Codex output, present evidence and let the user decide.

## Quick Reference
| Use case | Recommended mode | Notes |
| --- | --- | --- |
| Read-only analysis | `--sandbox read-only` | Default for audits, exploration, reviews |
| Local edits | `--sandbox workspace-write` + optional `--full-auto` | Use `--full-auto` only when autonomous edits are intended |
| Broad access/network-like workflows | `--sandbox danger-full-access` | Require explicit user confirmation |
| Resume recent thread | `codex exec resume --last` | Retry with `--all` on cwd mismatch |
| Outside Git repo | add `--skip-git-repo-check` | Do not force this flag when inside a repo |
| Machine-readable output | `--json` and `-o <FILE>` | Use for deterministic downstream parsing |

## Closing Pattern
After completion, include:
- A concise result summary.
- Resume hint: "You can resume this Codex session by asking me to run `codex resume` with your next prompt." 
