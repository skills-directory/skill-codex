---
name: tmux
description: Use to spin up a minimal master/workers tmux session and run commands across workers or a specific pane. Shell-only implementation.
---

# Tmux Orchestrator (Minimal)

Essential tmux orchestration via a single shell script. Creates an isolated tmux server, a session with a `master` window and a `workers` window, and provides subcommands to run commands across all workers or a single worker.

## Prerequisites
- tmux installed (`tmux -V`)

## Script
- `./scripts/tmux_orchestrator.sh`
- Uses a dedicated server via `tmux -L <socket>` to avoid interfering with a user’s own tmux.

## Defaults (overridable via env)
- `TMUX_SOCKET=claude`
- `TMUX_SESSION=agents`
- `MASTER_WINDOW=master`
- `WORKERS_WINDOW=workers`
- `WORKERS=4`
- `TMUX_BASE_INDEX=1`, `TMUX_PANE_BASE_INDEX=1` (pane index starts at 1)
- `TMUX_HISTORY_LIMIT=50000` (larger scrollback for agent output)
- `TMUX_REMAIN_ON_EXIT=on` (inspect crashed panes) — set to `failed` if your tmux supports it, to keep only failed panes
- `TMUX_ALLOW_RENAME=off` (keep titles stable)
- `WORKER_LAYOUT=tiled` (future: allow `even-horizontal`, `even-vertical`)

## Subcommands
- `init [N]`: create session with `master` + `N` worker panes (default: `$WORKERS`)
- `attach`: attach to the session
- `run-all CMD`: send CMD to all worker panes (temporarily enables `synchronize-panes`)
- `run-one IDX CMD`: send CMD to a single worker pane by index (0-based)
- `run-master CMD`: send CMD to the master window pane 0
- `status`: list panes in the session
- `kill`: kill the session
- `capture [DIR]`: save the text of each pane to files under `DIR` (default `logs/tmux/<session>/snapshots`)
- `logs-on` / `logs-off`: toggle per-pane logging via `pipe-pane` into `logs/tmux/<session>/pipes/*.log`
  - If `./scripts/tslog.awk` is present, logs are prefixed with UTC timestamps.

## Task Queue (Minimal)
Backed by a filesystem queue under `var/tmux/<session>/tasks`:
- Directories: `queue/`, `running/`, `done/`, `failed/`, `logs/`
- Worker loop: `./scripts/tmux_task_worker.sh <tasks_dir> <worker_id>`
- Enqueue format: key=value lines (`ID=...`, `CMD=...`, `CWD=...`, repeated `ENV=KEY=VAL`)

### Task Commands
- `tasks-init`: initialize task directories
- `tasks-enqueue [opts] -- CMD...`: enqueue a command
  - Options: `-d/--cwd <dir>`, `-i/--id <id>`, `-e/--env KEY=VAL` (repeat)
- `tasks-start`: start worker loops in all worker panes
- `tasks-stop`: send `C-c` to workers to stop loops
- `tasks-list [queue|running|done|failed|all]`: list tasks
- `tasks-tail <id> [--err]`: show last 100 lines from a task’s log
- `tasks-cancel <id>`: cancel a queued or running task
- `tasks-retry <id>`: move a failed task back to `queue/`
- `tasks-paths`: print directories for the current session
- `tasks-health`: show counts and detect stale running tasks (missing PIDs)
- `tasks-clean [--hours N | --keep N]`: prune done/failed/logs by age or keep last N

## Barriers
- `barrier-wait <name>`: wait for a named signal (`tmux wait-for`)
- `barrier-signal <name>`: signal a named barrier (`tmux wait-for -S`)

## Examples
```bash
# Create session with 6 workers and attach
WORKERS=6 ./scripts/tmux_orchestrator.sh init
./scripts/tmux_orchestrator.sh attach

# Broadcast command to all workers
./scripts/tmux_orchestrator.sh run-all "rg --json -n --no-config -S 'TODO|FIXME'"

# Run tests on worker 2 only
./scripts/tmux_orchestrator.sh run-one 2 "pytest -q"

# Run something on master
./scripts/tmux_orchestrator.sh run-master "codex --version"

# Check status and capture output
./scripts/tmux_orchestrator.sh status
./scripts/tmux_orchestrator.sh capture

# Tear down
./scripts/tmux_orchestrator.sh kill

# --- Task Queue ---
./scripts/tmux_orchestrator.sh tasks-init
./scripts/tmux_orchestrator.sh tasks-start

# Enqueue a few tasks
./scripts/tmux_orchestrator.sh tasks-enqueue -- echo "hello from task 1"
./scripts/tmux_orchestrator.sh tasks-enqueue -d src -- rg --json -n --no-config -S TODO
./scripts/tmux_orchestrator.sh tasks-enqueue -e FOO=bar -- bash -lc 'echo $FOO && sleep 1'

# Inspect
./scripts/tmux_orchestrator.sh tasks-list all
./scripts/tmux_orchestrator.sh tasks-tail t169000000000  # example ID

# Stop workers
./scripts/tmux_orchestrator.sh tasks-stop

# Optional per-pane logging
./scripts/tmux_orchestrator.sh logs-on
./scripts/tmux_orchestrator.sh logs-off

# Barriers
./scripts/tmux_orchestrator.sh barrier-wait phase1 &   # in one pane
./scripts/tmux_orchestrator.sh barrier-signal phase1   # in another pane
```

## Safety
- Shell-only; no file modifications except optional capture to `logs/`.
- Isolated tmux server via `-L <socket>`.
- Idempotent `init` (won’t recreate an existing session).

## References
See REFERENCES.md in this directory for authoritative docs and best practices.
