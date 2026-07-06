# Template: Test Generation / Gap Analysis

Use to add tests or assess coverage.

Prompt skeleton (fill the `<placeholders>` and pass as the `codex exec` prompt):

> Assess test coverage for `<scope>` and generate focused, high-quality tests.
> Cover edge cases, error paths, and invariants, and follow the project's existing
> test framework and style. Prioritize high-risk untested behavior and cite it with
> `file:line`; avoid broad, unrelated testing advice. List which behaviors remain
> untested after your additions.
