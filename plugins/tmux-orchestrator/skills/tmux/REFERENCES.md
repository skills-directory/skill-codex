# Tmux Orchestrator References

Authoritative docs and widely referenced resources used to shape this skill’s defaults and commands.

## Official Manual
- tmux(1) manual (common mirrors):
  - man7.org: https://man7.org/linux/man-pages/man1/tmux.1.html
  - OpenBSD: https://man.openbsd.org/tmux.1
  - GitHub mirror: https://github.com/tmux/tmux/wiki

## Commands Used
- new-session, new-window, split-window, select-layout (tiled)
- select-pane -T (set pane title)
- set-option (base-index, pane-base-index, history-limit)
- set-window-option (remain-on-exit, allow-rename)
- pipe-pane (per‑pane logging)
- capture-pane -p -S - (full scrollback snapshot)
- synchronize-panes (temporary broadcast)
- wait-for (barriers/rendezvous; optional future enhancement)

See the tmux(1) manual pages above for exact semantics and options.

## Best‑Practice Notes
- Isolate automation via a dedicated server socket (`tmux -L <name>`).
- Prefer 1‑based indices (`base-index`, `pane-base-index`) for operator clarity.
- Increase `history-limit` for agent output review.
- Enable `remain-on-exit` to inspect failures; consider `remain-on-exit=failed` if supported.
- Disable `allow-rename` to keep titles stable when tools write terminal titles.
- Use `select-layout tiled` after splits for predictable worker grids.
- Use `pipe-pane` for continuous logging; `capture-pane` for one‑off snapshots.
- Toggle `synchronize-panes` only during broadcasts to avoid accidental input.

