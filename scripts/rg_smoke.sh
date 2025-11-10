#!/usr/bin/env bash
set -euo pipefail

echo "==> Ripgrep smoke check"

if ! command -v rg >/dev/null 2>&1; then
  echo "ERROR: ripgrep (rg) not found on PATH" >&2
  exit 127
fi

rg --version
echo

echo "==> Checking JSON support and reproducible defaults"
cmd=(rg --json -n --no-config -S \
  -g '!{.git,node_modules,.venv,dist,build,.next,.cache,coverage}' \
  -- 'README|README.md' .)
echo "+ ${cmd[*]}"
set +e
output="$("${cmd[@]}" 2>/dev/null)"
status=$?
set -e

if [[ $status -gt 1 ]]; then
  echo "ERROR: rg returned error status $status" >&2
  exit $status
fi

matches=$(printf '%s\n' "$output" | grep -c '"type":"match"' || true)
files=$(printf '%s\n' "$output" | jq -r 'select(.type=="summary")|.data.stats.matched' 2>/dev/null || echo "0")
echo "==> JSON lines parsed: matches=$matches, files_with_matches=${files}"
echo "OK: ripgrep smoke check completed"

