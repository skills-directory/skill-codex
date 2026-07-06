# Template: Security Audit

Use for security-focused review (vulnerabilities, insecure defaults, secrets).

Prompt skeleton (fill the `<placeholders>` and pass as the `codex exec` prompt):

> Perform a security audit of `<scope>`, focusing on `<threat focus, e.g. injection,
> auth, secrets, deserialization, SSRF, supply chain, insecure defaults>`. Report
> findings first, ordered by severity (critical → low). Prioritize exploitable risks
> over theoretical ones, cite concrete evidence (`file:line`) for each finding, and
> propose a specific mitigation. Avoid speculative findings and state your confidence
> for each.
