#!/usr/bin/env bash
# Minimal tmux task worker loop.
# Consumes tasks from a filesystem queue and executes them, writing logs and status files.
set -uo pipefail

TASKS_DIR="${1:-}"
WORKER_ID="${2:-0}"
POLL_INTERVAL="${POLL_INTERVAL:-1}"

if [[ -z "$TASKS_DIR" ]]; then
  echo "Usage: tmux_task_worker.sh <tasks_dir> [worker_id]" >&2
  exit 64
fi

mkdir -p "$TASKS_DIR"/{queue,running,done,failed,logs,tmp}
LOCK_FILE="$TASKS_DIR/queue.lock"

have_flock() { command -v flock >/dev/null 2>&1; }

pop_task() {
  # Attempts to atomically move one task from queue/ to running/
  local picked=""
  if have_flock; then
    exec {fd}>"$LOCK_FILE"
    if flock -n "$fd"; then
      shopt -s nullglob
      local files=("$TASKS_DIR"/queue/*.task)
      if ((${#files[@]})); then
        picked="${files[0]}"
        local base; base="$(basename "$picked")"
        mv "$picked" "$TASKS_DIR/running/$base" 2>/dev/null || picked=""
      fi
      flock -u "$fd"
    fi
  else
    # Fallback: best-effort without flock; susceptible to races
    shopt -s nullglob
    local files=("$TASKS_DIR"/queue/*.task)
    if ((${#files[@]})); then
      picked="${files[0]}"
      local base; base="$(basename "$picked")"
      mv "$picked" "$TASKS_DIR/running/$base" 2>/dev/null || picked=""
    fi
  fi
  [[ -n "$picked" ]] && echo "$TASKS_DIR/running/$(basename "$picked")"
  return 0
}

parse_task_file() {
  # Parses simple key=value lines:
  # ID=..., CMD=..., CWD=..., ENV=KEY=VAL (repeatable)
  local f="$1"
  local line key rest
  TASK_ID=""; TASK_CMD=""; TASK_CWD=""; TASK_ENVS=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="${line%%=*}"
    rest="${line#*=}"
    case "$key" in
      ID) TASK_ID="$rest" ;;
      CMD) TASK_CMD="$rest" ;;
      CWD) TASK_CWD="$rest" ;;
      ENV) TASK_ENVS+=("$rest") ;;
    esac
  done < "$f"
}

run_task() {
  local f="$1"
  parse_task_file "$f"
  [[ -n "$TASK_CMD" ]] || { echo "WARN: empty CMD in $f" >&2; return 1; }
  local id="$TASK_ID"
  if [[ -z "$id" ]]; then
    # derive from filename
    id="$(basename "$f" .task)"; id="${id#*_}"; id="${id#*_}"
  fi
  local out="$TASKS_DIR/logs/${id}.out"
  local err="$TASKS_DIR/logs/${id}.err"
  local info="$TASKS_DIR/running/${id}.info"
  : > "$out"; : > "$err"

  {
    echo "id=$id"
    echo "worker=$WORKER_ID"
    echo "start_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host=$(hostname)"
    echo "cmd=$TASK_CMD"
    echo "cwd=${TASK_CWD:-.}"
  } > "$info"

  # Apply envs
  local e
  for e in "${TASK_ENVS[@]:-}"; do
    export "$e"
  done

  # Execute with process substitution to both log and display in pane; record child PID
  local rc=0 child=0
  if [[ -n "$TASK_CWD" ]]; then
    (
      cd "$TASK_CWD" || exit 1
      bash -lc "exec stdbuf -oL -eL ${TASK_CMD}" \
        > >(tee -a "$out") 2> >(tee -a "$err" >&2) &
      child=$!
      echo "pid=$child" >> "$info"
      wait "$child"
      exit $?
    )
    rc=$?
  else
    bash -lc "exec stdbuf -oL -eL ${TASK_CMD}" \
      > >(tee -a "$out") 2> >(tee -a "$err" >&2) &
    child=$!
    echo "pid=$child" >> "$info"
    wait "$child"
    rc=$?
  fi

  echo "exit_code=$rc" >> "$info"
  echo "end_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$info"

  # Move task file and info to done/ or failed/
  local base="$(basename "$f")"
  if [[ $rc -eq 0 ]]; then
    mv "$f" "$TASKS_DIR/done/$base" 2>/dev/null || true
    mv "$info" "$TASKS_DIR/done/${id}.info" 2>/dev/null || true
  else
    mv "$f" "$TASKS_DIR/failed/$base" 2>/dev/null || true
    mv "$info" "$TASKS_DIR/failed/${id}.info" 2>/dev/null || true
  fi
  return "$rc"
}

trap 'echo "Worker $WORKER_ID exiting"; exit 0' INT TERM

echo "Worker $WORKER_ID watching $TASKS_DIR"
while :; do
  task_path="$(pop_task)"
  if [[ -n "${task_path:-}" && -f "$task_path" ]]; then
    run_task "$task_path" || true
  else
    sleep "$POLL_INTERVAL"
  fi
done
