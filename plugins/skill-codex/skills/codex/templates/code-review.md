# Template: Code Review

Use when the user asks to review code, wants a second opinion, or a quality check.

Prompt skeleton (fill the `<placeholders>` and pass as the `codex exec` prompt):

> Act as a rigorous senior reviewer of `<scope>`. Review for correctness,
> regressions, maintainability, and missing tests. Report findings first, ordered
> by severity (critical → low), each with a `file:line` reference and a concrete
> fix. Challenge unclear intent and risky patterns and push back where the design
> seems wrong. Do not invent issues — cite evidence, and say so plainly if the
> code looks fine.
