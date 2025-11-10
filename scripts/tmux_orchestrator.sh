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
TASK_ROOT="${TASK_ROOT:-var/tmux/${SESSION}/tasks}"
# Recommended tmux options (overridable)
TMUX_BASE_INDEX="${TMUX_BASE_INDEX:-1}"
TMUX_PANE_BASE_INDEX="${TMUX_PANE_BASE_INDEX:-1}"
TMUX_HISTORY_LIMIT="${TMUX_HISTORY_LIMIT:-50000}"
TMUX_REMAIN_ON_EXIT="${TMUX_REMAIN_ON_EXIT:-on}"
TMUX_ALLOW_RENAME="${TMUX_ALLOW_RENAME:-off}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

Tasks:
  tasks-init              Prepare filesystem queue under \$TASK_ROOT
  tasks-enqueue [opts] -- CMD...
      Options: -d <cwd>  -i <id>  -e KEY=VAL (repeatable)
  tasks-start             Start worker loops in all worker panes
  tasks-stop              Stop worker loops (sends C-c to workers window)
  tasks-list [state]      List tasks (state: queue|running|done|failed|all)
  tasks-tail <id> [--err] Show last 100 lines of task output (or stderr)
  tasks-cancel <id>       Cancel a queued or running task
  tasks-retry <id>        Move failed task back to queue
  tasks-paths             Print task directories for this session
  tasks-health            Show queue counts and stale running tasks

Barriers:
  barrier-wait <name>     Wait for a signal (tmux wait-for)
  barrier-signal <name>   Signal a barrier (tmux wait-for -S)

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
  # Apply recommended server/global options on isolated server
  tmuxc set-option -t "${SESSION}" base-index "${TMUX_BASE_INDEX}"
  tmuxc set-option -t "${SESSION}" pane-base-index "${TMUX_PANE_BASE_INDEX}"
  tmuxc set-option -t "${SESSION}" history-limit "${TMUX_HISTORY_LIMIT}"
  tmuxc set-window-option -t "${SESSION}:" remain-on-exit "${TMUX_REMAIN_ON_EXIT}"
  tmuxc set-window-option -t "${SESSION}:" allow-rename "${TMUX_ALLOW_RENAME}"
  # Create workers window
  tmuxc new-window -t "${SESSION}:" -n "${WORKERS_WINDOW}"
  # Ensure at least 1 pane exists; split to reach n panes
  local i=1
  while [[ "$i" -lt "$n" ]]; do
    tmuxc split-window -t "${SESSION}:${WORKERS_WINDOW}" -h
    tmuxc select-layout -t "${SESSION}:${WORKERS_WINDOW}" tiled >/dev/null
    i=$((i+1))
  done
  # Title each worker pane for clarity
  while IFS=$'\t' read -r idx pane_id; do
    tmuxc select-pane -t "${pane_id}" -T "worker-${idx}"
  done < <(tmuxc list-panes -t "${SESSION}:${WORKERS_WINDOW}" -F '#{pane_index}\t#{pane_id}')

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

# Toggle per-pane logging using pipe-pane
cmd_logs_on() {
  mkdir -p "${LOG_DIR}/pipes"
  while IFS=$'\t' read -r idx pane_id; do
    local log="${LOG_DIR}/pipes/${SESSION}_${WORKERS_WINDOW}_${idx}_${pane_id//#/}.log"
    if [[ -f "${SCRIPT_DIR}/tslog.awk" ]]; then
      tmuxc pipe-pane -t "${pane_id}" -o "awk -f '${SCRIPT_DIR}/tslog.awk' >> '${log}'"
    else
      tmuxc pipe-pane -t "${pane_id}" -o "cat >> '${log}'"
    fi
    echo "Logging ON for pane ${idx} (${pane_id}) -> ${log}"
  done < <(tmuxc list-panes -t "${SESSION}:${WORKERS_WINDOW}" -F '#{pane_index}\t#{pane_id}')
}

cmd_logs_off() {
  while IFS=$'\t' read -r idx pane_id; do
    tmuxc pipe-pane -t "${pane_id}"
    echo "Logging OFF for pane ${idx} (${pane_id})"
  done < <(tmuxc list-panes -t "${SESSION}:${WORKERS_WINDOW}" -F '#{pane_index}\t#{pane_id}')
}

# --- Tasks management ---

ensure_tasks_dirs() {
  mkdir -p "${TASK_ROOT}"/{queue,running,done,failed,logs,tmp} || die "cannot create ${TASK_ROOT}"
}

cmd_tasks_init() {
  ensure_tasks_dirs
  echo "Initialized tasks at ${TASK_ROOT}"
}

gen_task_id() {
  local ts rand
  ts="$(date +%s)"
  rand="$(printf '%06d' "$RANDOM")"
  echo "t${ts}${rand}"
}

cmd_tasks_enqueue() {
  ensure_tasks_dirs
  local cwd="" id="" envs=()
  # parse options until --
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--cwd) cwd="$2"; shift 2;;
      -i|--id) id="$2"; shift 2;;
      -e|--env) envs+=("$2"); shift 2;;
      --) shift; break;;
      *) break;;
    esac
  done
  [[ $# -gt 0 ]] || die "tasks-enqueue requires -- CMD..."
  local cmd="$*"
  [[ -n "$id" ]] || id="$(gen_task_id)"
  local ts="$(date +%s)"
  local base="${ts}_$RANDOM_${id}.task"
  local f="${TASK_ROOT}/queue/${base}"
  {
    echo "ID=${id}"
    echo "CMD=${cmd}"
    [[ -n "$cwd" ]] && echo "CWD=${cwd}"
    local e
    for e in "${envs[@]:-}"; do
      echo "ENV=${e}"
    done
  } > "$f"
  echo "Enqueued task ${id}"
}

cmd_tasks_start() {
  ensure_tasks_dirs
  # Start worker loop in each worker pane
  local panes; panes=$(tmuxc list-panes -t "${SESSION}:${WORKERS_WINDOW}" -F '#{pane_index}' 2>/dev/null) || die "workers window not found"
  local idx
  for idx in $panes; do
    tmuxc send-keys -t "${SESSION}:${WORKERS_WINDOW}.${idx}" "scripts/tmux_task_worker.sh '${TASK_ROOT}' ${idx}" C-m
  done
  echo "Started task workers in window '${WORKERS_WINDOW}'."
}

cmd_tasks_stop() {
  # best-effort: send C-c to each worker pane
  local panes; panes=$(tmuxc list-panes -t "${SESSION}:${WORKERS_WINDOW}" -F '#{pane_index}' 2>/dev/null) || die "workers window not found"
  local idx
  for idx in $panes; do
    tmuxc send-keys -t "${SESSION}:${WORKERS_WINDOW}.${idx}" C-c
  done
  echo "Sent C-c to workers."
}

task_glob_for_id() {
  local id="$1" state="$2"
  case "$state" in
    queue|running|done|failed) echo "${TASK_ROOT}/${state}/*_${id}.task" ;;
    *) echo "${TASK_ROOT}"/{queue,running,done,failed}"/*_${id}.task" ;;
  esac
}

find_task_file_by_id() {
  local id="$1"
  local f; f=$(echo $(task_glob_for_id "$id" all) 2>/dev/null | awk '{print $1}')
  [[ -n "${f:-}" && -e "$f" ]] && echo "$f"
}

cmd_tasks_list() {
  ensure_tasks_dirs
  local state="${1:-all}"
  case "$state" in
    all)
      for d in queue running done failed; do
        echo "== $d =="
        ls -1 "${TASK_ROOT}/${d}"/*.task 2>/dev/null | sed 's#.*/##' || true
      done
      ;;
    queue|running|done|failed)
      ls -1 "${TASK_ROOT}/${state}"/*.task 2>/dev/null | sed 's#.*/##' || true
      ;;
    *)
      die "unknown state: $state"
      ;;
  esac
}

cmd_tasks_tail() {
  ensure_tasks_dirs
  [[ $# -ge 1 ]] || die "tasks-tail <id> [--err]"
  local id="$1"; shift || true
  local stream="out"
  [[ "${1:-}" == "--err" ]] && stream="err"
  local log="${TASK_ROOT}/logs/${id}.${stream}"
  [[ -f "$log" ]] || die "log not found: $log"
  tail -n 100 "$log"
}

cmd_tasks_cancel() {
  ensure_tasks_dirs
  [[ $# -ge 1 ]] || die "tasks-cancel <id>"
  local id="$1"
  local f; f="$(find_task_file_by_id "$id")" || true
  [[ -n "${f:-}" ]] || die "task not found: $id"
  case "$f" in
    *"/queue/"*)
      mv "$f" "${TASK_ROOT}/failed/$(basename "$f")"
      echo "Canceled queued task $id"
      ;;
    *"/running/"*)
      # Attempt to kill by reading info
      local info="${TASK_ROOT}/running/${id}.info"
      if [[ -f "$info" ]]; then
        local pid; pid="$(grep '^pid=' "$info" | cut -d= -f2 || true)"
        if [[ -n "$pid" ]]; then
          kill "$pid" 2>/dev/null || true
          sleep 1
          kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
        fi
      fi
      mv "$f" "${TASK_ROOT}/failed/$(basename "$f")"
      echo "Marked running task $id as failed (canceled)"
      ;;
    *)
      echo "Task $id is not cancelable (state: ${f})"
      ;;
  esac
}

cmd_tasks_retry() {
  ensure_tasks_dirs
  [[ $# -ge 1 ]] || die "tasks-retry <id>"
  local id="$1"
  local f; f="$(echo "${TASK_ROOT}/failed/"*"_${id}.task" | awk '{print $1}')" || true
  [[ -n "${f:-}" && -f "$f" ]] || die "failed task not found: $id"
  mv "$f" "${TASK_ROOT}/queue/$(basename "$f")"
  echo "Requeued failed task $id"
}

cmd_tasks_paths() {
  ensure_tasks_dirs
  echo "TASK_ROOT=${TASK_ROOT}"
  for d in queue running done failed logs; do
    echo " - ${d}: ${TASK_ROOT}/${d}"
  done
}

cmd_tasks_health() {
  ensure_tasks_dirs
  local count_queue count_running count_done count_failed
  count_queue=$(ls -1 "${TASK_ROOT}/queue"/*.task 2>/dev/null | wc -l | tr -d ' ')
  count_running=$(ls -1 "${TASK_ROOT}/running"/*.task 2>/dev/null | wc -l | tr -d ' ')
  count_done=$(ls -1 "${TASK_ROOT}/done"/*.task 2>/dev/null | wc -l | tr -d ' ')
  count_failed=$(ls -1 "${TASK_ROOT}/failed"/*.task 2>/dev/null | wc -l | tr -d ' ')
  echo "Queue: ${count_queue} | Running: ${count_running} | Done: ${count_done} | Failed: ${count_failed}"
  local stale=0
  for info in "${TASK_ROOT}/running/"*.info 2>/dev/null; do
    [[ -f "$info" ]] || continue
    local id pid
    id="$(grep '^id=' "$info" | cut -d= -f2 || true)"
    pid="$(grep '^pid=' "$info" | cut -d= -f2 || true)"
    if [[ -n "$pid" ]]; then
      if ! kill -0 "$pid" 2>/dev/null; then
        echo "STALE: running task id=${id} pid=${pid} (no such process)"
        stale=$((stale+1))
      fi
    fi
  done
  echo "Stale running tasks: ${stale}"
}

cmd_barrier_wait() {
  [[ $# -ge 1 ]] || die "barrier-wait <name>"
  tmuxc wait-for "$1"
}

cmd_barrier_signal() {
  [[ $# -ge 1 ]] || die "barrier-signal <name>"
  tmuxc wait-for -S "$1"
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
    logs-on)     cmd_logs_on;;
    logs-off)    cmd_logs_off;;
    tasks-init)  cmd_tasks_init;;
    tasks-enqueue) cmd_tasks_enqueue "$@";;
    tasks-start) cmd_tasks_start;;
    tasks-stop)  cmd_tasks_stop;;
    tasks-list)  cmd_tasks_list "$@";;
    tasks-tail)  cmd_tasks_tail "$@";;
    tasks-cancel) cmd_tasks_cancel "$@";;
    tasks-retry) cmd_tasks_retry "$@";;
    tasks-paths) cmd_tasks_paths;;
    tasks-health) cmd_tasks_health;;
    barrier-wait) cmd_barrier_wait "$@";;
    barrier-signal) cmd_barrier_signal "$@";;
    -h|--help|"") usage; exit 0;;
    *) usage; echo; die "Unknown subcommand: ${sub}";;
  esac
}

main "$@"
