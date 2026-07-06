# Template: Bug Hunt

Use to root-cause a specific bug or failure.

Prompt skeleton (fill the `<placeholders>` and pass as the `codex exec` prompt):

> Investigate `<symptom>` in `<scope>`. Form explicit hypotheses, inspect the
> relevant code paths, and identify the most likely root cause with evidence
> (`file:line`). Propose the smallest correct fix and list concrete steps to
> verify it. If you cannot confirm the cause, say what additional information or
> reproduction would be needed rather than guessing.
