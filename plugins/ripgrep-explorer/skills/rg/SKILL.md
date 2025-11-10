---
name: rg
description: Use when the user asks to search code/files with ripgrep (rg), explore repos quickly, or needs structured search results for navigation or follow‑up actions.
---

# Ripgrep Skill Guide

## Overview

This skill wraps ripgrep (rg) to provide fast, structured, and configurable code/file search inside Claude Code sessions. It favors safety and repeatability, outputs machine‑parseable results (JSON Lines), and includes clear defaults with opt‑in expansion.

**Tested Versions**: ripgrep 13+ (JSON mode available since rg 11)

## The 7‑Step Workflow

### Step 1: Validate Environment

Goals:
- Ensure `rg` binary is available and detect version.
- Confirm JSON output support.
- Establish safe default search roots and ignore patterns.

Commands:
```bash
command -v rg >/dev/null || { echo "ERROR: ripgrep not installed"; exit 1; }
rg --version
rg --help | head -n 1
```

Common Install Hints:
- macOS: `brew install ripgrep`
- Debian/Ubuntu: `sudo apt-get install ripgrep`
- Arch: `sudo pacman -S ripgrep`

Exit Conditions:
- Proceed only if `rg` is present; otherwise surface guidance and stop.

---

### Step 2: Parse Intent and Defaults

Intent Dimensions:
- Pattern type: literal (`-F`) vs regex (default).
- Case policy: smart case (`-S`) default; or force `-i`/`-s`.
- Scope: file globs (`-g`), language types (`-t`), include hidden (`--hidden`), bypass ignores (`--no-ignore`).
- Output form: JSON (`--json`) with line/column; optional context (`-n -C <N>`).

Safe Defaults:
- Read‑only search; never modifies files.
- Respect ignores; exclude heavy dirs by default:
  - `-g '!{.git,node_modules,.venv,dist,build,.next,.cache,coverage}'`
- Smart case matching (`-S`) and JSON output (`--json -n --color never`).

Example Default Selection:
```text
- If user says “find TODOs”: regex mode, smart case, default excludes.
- If user says “literal string”: add -F.
- If user says “only Python”: add -t py.
- If user says “search everything incl hidden”: add --hidden; maybe --no-ignore if requested.
```

---

### Step 3: Construct the rg Command

Canonical Shape:
```bash
rg --json -n --color never -S \
  -g '!{.git,node_modules,.venv,dist,build,.next,.cache,coverage}' \
  [--hidden] [--no-ignore] [-F] [--iglob '<glob>'] [-g '<glob>'] \
  [-t js -t ts -t py ...] [-C 2] [--max-columns 300] -- '<pattern>' [<paths...>]
```

Notes:
- Use `--` before pattern to avoid parsing pitfalls.
- Prefer `-g`/`--iglob` over shell globs for portability.
- Add `--max-columns 300` to avoid truncation in long lines.
- For multiline context, keep JSON but rely on subsequent targeted reads for full blocks.

Examples:
```bash
# TODOs across repo, default excludes
rg --json -n -S -g '!{.git,node_modules,.venv,dist,build}' -- 'TODO|FIXME'

# Literal search limited to src, JS/TS only
rg --json -n -F -S -t js -t ts -g 'src/**' -- 'use client'

# Include hidden & bypass ignores
rg --json -n -S --hidden --no-ignore -- '^secret_key\\s*='
```

Exit Conditions:
- If command is ambiguous (missing pattern), stop and ask for a pattern or path hint.

---

### Step 4: Execute and Stream

Approach:
- Run `rg` in a subprocess and stream JSON Lines.
- Enforce a soft timeout for very large repos; suggest narrowing scope on timeout.

Signals to Watch:
- Non‑zero exit status with no stderr often means “no matches” (`rg` uses exit code 1 for no match). Treat as success with empty result set.
- Exit code >1 indicates an error; surface stderr.

---

### Step 5: Aggregate Results and Context

Parsing:
- Consume JSON Lines. Types include: `begin`, `match`, `context`, `end`, `summary`.
- For each `match`, extract `data.path.text`, `data.lines.text`, `data.line_number`, `data.submatches[*].start/end`.

Aggregation:
- Group by file, keep matches ordered by line number.
- Provide compact preview “file:line:column: text”.
- Offer follow‑ups: open file at line, show N lines of surrounding context (`rg -n -C N ...`), or refine by file type/glob.

Navigation Aids:
- Show a short list per file with counts.
- For big result sets, present top 10 files by match count and allow “show more”.

---

### Step 6: Output Formatting

User‑Facing Summary:
- Matches: total, files affected, top files by count.
- Snippets: up to 3 per file unless asked for more.
- Commands Repro: exact `rg` command used to reproduce.

Machine‑Readable Shape (internal):
```json
{
  "matches": [
    {
      "file": "path/to/file.py",
      "line": 123,
      "column": 8,
      "text": "def foo(bar): ...",
      "submatches": [{"start": 7, "end": 10}]
    }
  ],
  "command": "rg --json -n -S ... -- 'pattern'",
  "stats": {"files": 12, "matches": 37}
}
```

---

### Step 7: Error Recovery and Guidance

Common Issues:
- `rg: command not found`: Provide install instructions by OS.
- “Path is too deep / permission denied”: suggest narrowing search root or adding `--hidden --no-ignore` deliberately.
- “Binary file matches”: add `-U` or `--text` if user truly wants to scan binaries.

Recovery Strategies:
- Reduce scope (`-g 'src/**'`, `-t py`).
- Switch to literal (`-F`) if regex fails.
- Increase context with `-C 2` for better previews.

---

## Safety & Permissions

- Read‑only by default; no file modifications.
- Respects VCS ignores and common heavy directories unless overridden.
- For large monorepos, warn about performance and encourage scoping.

## Quick Reference

- Literal vs Regex: `-F` for literal, default is regex.
- Case Policy: `-S` smart, `-i` ignore case, `-s` case‑sensitive.
- Types: `-t <lang>` (repeatable), list with `rg --type-list`.
- Globs: `-g '<glob>'` include; `-g '!<glob>'` exclude; `--iglob` for case‑insensitive.
- JSON: `--json` emits NDJSON events; parse `match` events for results.

## Examples

```bash
# 1) Find TODOs ignoring vendor/outputs
rg --json -n -S -g '!{.git,node_modules,.venv,dist,build,.next}' -- 'TODO|FIXME'

# 2) Search only Python and Rust files
rg --json -n -S -t py -t rust -- 'async|await'

# 3) Literal string in src/ with 2 lines context
rg --json -n -F -C 2 -g 'src/**' -- 'use client'
```
