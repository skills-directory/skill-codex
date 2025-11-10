---
name: sg
description: Use when the user asks for AST-aware search or safe structural refactors using ast-grep (sg).
---

# AST-Grep Skill Guide

## Overview

This skill uses ast-grep (CLI: `sg`) for structural, AST-aware code search and safe refactoring. It complements text search by matching syntax nodes, enabling precise queries and replacements across languages.

**Tested Versions**: ast-grep 0.19+ (JSON/stream output supported)

## The 7-Step Workflow

### Step 1: Validate Environment

Goals:
- Verify `sg` is installed and detect version.
- Confirm basic commands and JSON output availability.
- Ensure CLI flags reflect current `sg run` syntax (`--globs`, `--lang`, `--no-ignore` family).

Commands:
```bash
command -v sg >/dev/null || { echo "ERROR: ast-grep (sg) not installed"; exit 1; }
sg --version
sg --help | head -n 1
```

Install Hints:
- macOS: `brew install ast-grep` (or `brew tap ast-grep/ast-grep && brew install ast-grep`)
- Debian/Ubuntu: `curl -fsSL https://ast-grep.github.io/install.sh | sh` or use package if available
- Cargo: `cargo install ast-grep`

Exit Conditions:
- Proceed only if `sg` is present; otherwise guide installation and stop.

---

### Step 2: Parse Intent and Defaults

Intent Dimensions:
- Match style: simple pattern (`-p`) vs rule file (`-r rules/*.yml`).
- Languages: explicit `--lang <lang>` or infer by extension.
- Scope and ignores: include globs (`-g`), hidden files, or bypass ignores on request.
- Output: streaming JSON for programmatic parsing; optional preview context.
- Refactoring: structural replace with `--rewrite` or rule `fix:` sections.

Safe Defaults:
- Read-only search unless refactor requested.
- Respect ignores and exclude heavy dirs by default:
  - `--globs '!{.git,node_modules,.venv,dist,build,.next,.cache,coverage}'`
- Stream results as JSON events with file, range, and snippet.

---

### Step 3: Construct the sg Command

Canonical Shapes:
```bash
# Pattern-based search (regex-like but AST-aware per language grammar)
sg run -p '<pattern>' \
  --json=stream -n \
  --globs '!{.git,node_modules,.venv,dist,build,.next,.cache,coverage}' \
  [--lang <lang>] [--hidden] [--no-ignore] [--globs '<glob>'] [--dir <path>]

# Rule-based search
sg run -r rules/ \
  --json=stream -n \
  --globs '!{.git,node_modules,.venv,dist,build,.next,.cache,coverage}' \
  [--lang <lang>] [--hidden] [--no-ignore] [--dir <path>]

# Structural replace (explicit)
sg run -p '<pattern>' --rewrite '<replacement>' --dry-run \
  --json=stream -n [scoping flags...]
```

Notes:
- Prefer `--json=stream` for line-delimited events; fall back to compact JSON if needed.
- Always quote the pattern to avoid shell expansion.
- Use `--dry-run` by default for refactors; require explicit confirmation to apply.
- For complex patterns, encourage rule YAML with `rule:` / `fix:` blocks and tests.
 - Language selection: prefer `--lang <lang>` (e.g., `--lang typescript`, `--lang python`) over file globs when possible.
 - Debugging: `--inspect` prints rule/pattern diagnostics; `--strictness <level>` controls match leniency.

---

### Step 4: Execute and Stream

Approach:
- Execute `sg` and stream JSON events.
- Detect “no matches” as a successful empty result set.
- Impose a soft timeout for giant repos and suggest narrowing scope on timeout.

---

### Step 5: Aggregate Results and Context

Parsing:
- Parse streaming JSON. Match payload typically includes:
  - file path, language, range (start line/col, end line/col), and code snippet.
- Capture captures for named pattern variables if present.

Aggregation:
- Group results by file; sort by line number.
- Provide concise previews: `file:line:column: code…`
- Offer follow-ups: open file at range, show N lines context, export to a rule file.

---

### Step 6: Output Formatting

User Summary:
- Totals: matches and files.
- Top files by match count with snippets.
- “Repro” command emitted for transparency.

Machine-Readable (internal):
```json
{
  \"matches\": [
    {
      \"file\": \"src/app.ts\",
      \"lang\": \"typescript\",
      \"line\": 42,
      \"column\": 7,
      \"endLine\": 42,
      \"endColumn\": 19,
      \"text\": \"console.log(user)\",
      \"captures\": {\"ident\": \"user\"}
    }
  ],
  \"command\": \"sg run -p 'console.log($X)' --json=stream -n\",
  \"stats\": {\"files\": 6, \"matches\": 9}
}
```

---

### Step 7: Error Recovery and Guidance

Common Issues:
- `sg: command not found`: provide install steps.
- Invalid pattern or language: suggest adding `--lang` or using a rule file with explicit `language`.
- Large matches or binary files: scope with `-g 'src/**'` or use file types.

Recovery Strategies:
- Move from simple `-p` to rule YAML for complex matching or rewrites.
- Narrow search with language and globs.
- For refactors, keep `--dry-run`; then apply with confirmation.

---

## Safety & Permissions

- Read-only by default; structural rewrite runs with `--dry-run` unless explicitly confirmed.
- Respects ignores by default; `--hidden/--no-ignore` only when user requests.
- Emits exact command used for transparency and reproducibility.

## Quick Reference

- Pattern: `-p '<pattern>'` (uses language grammar; add `--lang <lang>` when ambiguous).
- Rule directory: `-r rules/` (supports `fix:` for rewrite).
- JSON: `--json=stream` for NDJSON-style events.
- Scope: `--dir <path>`, `--globs '<glob>'`, `--hidden`, `--no-ignore`.
- Dry run: `--dry-run` for safe preview of rewrites.
- Inspect: `--inspect` to see how patterns/rules are interpreted.

## Examples

```bash
# 1) Find console logs in TS/JS
sg run -p 'call_expression(callee: identifier(name: \"console\"))' \
  --json=stream -n --lang javascript --globs 'src/**'

# 2) Rename identifier via rewrite (preview)
sg run -p 'identifier(name: \"foo\")' --rewrite 'bar' \
  --dry-run --json=stream -n --lang typescript

# 3) Use a rule directory with fixes (preview)
sg run -r rules/ --json=stream -n --dir src/ --lang typescript

# 4) Run the built-in example rule (no-console) from this repo
sg run -r plugins/ast-grep-explorer/examples/rules \
  --json=stream -n --dir . --lang typescript \
  --globs '!{.git,node_modules,.venv,dist,build,.next,.cache,coverage}'

# 5) Apply fixes (dangerous): remove --dry-run to write changes
#    Always commit or back up first. Run on a scoped directory and review diff.
sg run -p 'identifier(name: \"foo\")' --rewrite 'bar' \
  --json=stream -n --lang typescript  # note: no --dry-run here
```

## References
See REFERENCES.md in this directory for authoritative docs and best practices.
