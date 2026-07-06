# Template: Refactoring

Use when the user wants refactoring suggestions or a restructure.

Prompt skeleton (fill the `<placeholders>` and pass as the `codex exec` prompt):

> Refactor `<scope>` to achieve `<goal, e.g. readability, performance, simplicity,
> testability>` while preserving observable behavior. Keep changes minimal and follow the
> existing patterns in the codebase. Explain the trade-offs and why the new shape
> is better, and list the tests that should be run to confirm behavior is unchanged.
