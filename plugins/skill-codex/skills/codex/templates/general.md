# Template: General

Use only when the user wants a structured prompt but no specific template fits.
It is not the default — unmatched requests should normally stay freeform.

Prompt skeleton (fill the `<placeholders>` and pass as the `codex exec` prompt):

> `<the user's task, in full>`. Work in `<scope>`. Be precise, cite file paths and
> line numbers for anything you reference, and explain non-obvious decisions.
> Flag assumptions and anything you are uncertain about instead of guessing.
