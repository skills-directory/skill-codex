#!/usr/bin/env bash
set -euo pipefail

# Minimal tmux orchestrator: master + workers flow using only shell.
# Defaults can be overridden via env vars.
SOCKET="${TMUX_SOCKET:-claude}"         # tmux server socket name (isolates from user tmux)
SESSION="${TMUX_SESSION:-agents}"       # session name
MASTER_WINDOW="${MASTER_WINDOW:-master}"
WORKERS_WINDOW="${WORKERS_WINDOW:-workers}"
WORKERS="${WORKERS:-4}"                 # number of worker panes
LOG_DIR="${LOG_DIR:-logs/tmux/${SESSION}}"

tmuxc() { tmux -L "${SOCKET}" "$@"; }

die() { echo "ERROR: $*" >&2; exit 1; }

need_tmux() {
  command -v tmux >/dev/null 2>&1 || die "tmux not found on PATH"
}

usage() {
  cat <<EOF
tmux_orchestrator.sh - minimal master/workers orchestration

Env:
  TMUX_SOCKET=${SOCKET}  TMUX_SESSION=${SESSION}  WORKERS=${WORKERS}
  MASTER_WINDOW=${MASTER_WINDOW}  WORKERS_WINDOW=${WORKERS_WINDOW}

Subcommands:
  init [N]        Create isolated server + session with master and N workers (default: WORKERS)
  attach          Attach to the orchestrator session
  run-all CMD     Run command in all worker panes (synchronize-panes on/off)
  run-one IDX CMD Run command in a single worker pane index (0-based)
  run-master CMD  Run command in master window (pane 0)
  status          Show panes for the session
  kill            Kill the session
  capture [DIR]   Save text of each pane to DIR (default: \$LOG_DIR/snapshots)

Examples:
  WORKERS=6 ./scripts/tmux_orchestrator.sh init
  ./scripts/tmux_orchestrator.sh run-all "echo hello && sleep 1"
  ./scripts/tmux_orchestrator.sh run-one 2 "pytest -q"
  ./scripts/tmux_orchestrator.sh run-master "codex --version"
  ./scripts/tmux_orchestrator.sh attach
EOF
}

exists_session() { tmuxc has-session -t "${SESSION}" 2>/dev/null; }

cmd_init() {
  need_tmux
  local n="${1:-$WORKERS}"
  if ! [[ "$n" =~ ^[0-9]+$ ]] || [[ "$n" -lt 1 ]]; then
    die "Invalid workers count: $n"
  fi
  if exists_session; then
    echo "Session '${SESSION}' already exists on socket '${SOCKET}'. Skipping create."
    return 0
  fi
  # Create session with master window
  tmuxc new-session -d -s "${SESSION}" -n "${MASTER_WINDOW}"
  # Create workers window
  tmuxc new-window -t "${SESSION}:" -n "${WORKERS_WINDOW}"
  # Ensure at least 1 pane exists; split to reach n panes
  local i=1
  while [[ "$i" -lt "$n" ]]; do
    tmuxc split-window -t "${SESSION}:${WORKERS_WINDOW}" -h
    tmuxc select-layout -t "${SESSION}:${WORKERS_WINDOW}" tiled >/dev/null
    i=$((i+1))
  done
  tmuxc select-window -t "${SESSION}:${MASTER_WINDOW}"
  echo "Created session '${SESSION}' with ${n} worker panes on socket '${SOCKET}'."
}

cmd_attach() {
  need_tmux
  exists_session || die "Session '${SESSION}' not found. Run 'init' first."
  exec tmuxc attach -t "${SESSION}"
}

cmd_run_all() {
  need_tmux
  exists_session || die "Session '${SESSION}' not found."
  [[ $# -ge 1 ]] || die "run-all requires a command string"
  local cmd="$*"
  tmuxc setw -t "${SESSION}:${WORKERS_WINDOW}" synchronize-panes on
  tmuxc send-keys -t "${SESSION}:${WORKERS_WINDOW}" "${cmd}" C-m
  tmuxc setw -t "${SESSION}:${WORKERS_WINDOW}" synchronize-panes off
  echo "Sent to all workers: ${cmd}"
}

cmd_run_one() {
  need_tmux
  exists_session || die "Session '${SESSION}' not found."
  [[ $# -ge 2 ]] || die "Usage: run-one IDX CMD"
  local idx="$1"; shift
  [[ "$idx" =~ ^[0-9]+$ ]] || die "IDX must be a non-negative integer"
  local target="${SESSION}:${WORKERS_WINDOW}.${idx}"
  local cmd="$*"
  tmuxc send-keys -t "${target}" "${cmd}" C-m || die "Failed to send to ${target}"
  echo "Sent to ${target}: ${cmd}"
}

cmd_run_master() {
  need_tmux
  exists_session || die "Session '${SESSION}' not found."
  [[ $# -ge 1 ]] || die "run-master requires a command string"
  local cmd="$*"
  tmuxc send-keys -t "${SESSION}:${MASTER_WINDOW}.0" "${cmd}" C-m
  echo "Sent to master: ${cmd}"
}

cmd_status() {
  need_tmux
  exists_session || die "Session '${SESSION}' not found."
  tmuxc list-panes -t "${SESSION}" -F '#{session_name}:#{window_name}.#{pane_index}\t#{pane_id}\tactive=#{pane_active}\t#{pane_title}'
}

cmd_kill() {
  need_tmux
  exists_session || { echo "Session '${SESSION}' not found; nothing to kill."; return 0; }
  tmuxc kill-session -t "${SESSION}"
  echo "Killed session '${SESSION}' on socket '${SOCKET}'."
}

cmd_capture() {
  need_tmux
  exists_session || die "Session '${SESSION}' not found."
  local outdir="${1:-${LOG_DIR}/snapshots}"
  mkdir -p "${outdir}"
  # Iterate panes and capture full scrollback
  while IFS=$'\t' read -r name pane_id _; do
    # sanitize name to filename
    local fname="${name//[:.]/_}_${pane_id//#/}.txt"
    tmuxc capture-pane -t "${pane_id}" -p -S - > "${outdir}/${fname}"
    echo "Captured ${name} (${pane_id}) -> ${outdir}/${fname}"
  done < <(tmuxc list-panes -t "${SESSION}" -F '#{session_name}:#{window_name}.#{pane_index}\t#{pane_id}\t#{pane_active}')
}

main() {
  local sub="${1:-}"; shift || true
  case "${sub}" in
    init)        cmd_init "${@:-}";;
    attach)      cmd_attach;;
    run-all)     cmd_run_all "$@";;
    run-one)     cmd_run_one "$@";;
    run-master)  cmd_run_master "$@";;
    status)      cmd_status;;
    kill)        cmd_kill;;
    capture)     cmd_capture "${1:-}";;
    -h|--help|"") usage; exit 0;;
    *) usage; echo; die "Unknown subcommand: ${sub}";;
  esac
}

main "$@"

