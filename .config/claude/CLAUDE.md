# Personal preferences

Global, user-scoped guidance applied to every project. Project-level `AGENTS.md`
files describe individual repos and take precedence where they conflict.

## Communication

- Write in British English (e.g. "colour", "behaviour", "optimise", "licence").
- Be concise and direct; lead with the answer, then the reasoning.

## Working style

- Match the surrounding code's style, naming, and conventions before adding your own.
- Prefer the smallest change that solves the problem; avoid unrelated refactors.
- Don't add comments that just restate the code; explain *why*, not *what*.
- Run the project's existing lint/test scripts before declaring work done.
- Conventional Commits for commit messages (these repos enforce it via commitlint).
- Never commit secrets; keep tokens in environment variables, not files.
