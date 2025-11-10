#!/usr/bin/env bash
set -euo pipefail

echo "==> ast-grep (sg) smoke check"

if ! command -v sg >/dev/null 2>&1; then
  echo "ERROR: ast-grep (sg) not found on PATH" >&2
  exit 127
fi

sg --version
echo

echo "==> Running a minimal pattern search (no matches is OK)"
cmd=(sg run -p 'identifier(name: \"__smoke_test_identifier__\")' --json=stream -n --dir . \
  --globs '!{.git,node_modules,.venv,dist,build,.next,.cache,coverage}')
echo "+ ${cmd[*]}"
set +e
output="$("${cmd[@]}" 2>/dev/null)"
status=$?
set -e

if [[ $status -gt 1 ]]; then
  echo "ERROR: sg returned error status $status" >&2
  exit $status
fi

matches=$(printf '%s\n' "$output" | grep -c '\"kind\":\"match\"' || true)
echo "==> Stream parsed: matches=$matches"
echo "Tip: scope with --dir <path> and set --lang <language> (e.g., --lang typescript) for precise results."
echo "OK: ast-grep smoke check completed"
