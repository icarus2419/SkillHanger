# Security

SkillHanger runs locally, reads existing Claude Code and Codex logins to check plan allowance, and can install third-party skills and plugins you choose.

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Use GitHub's private reporting: **Security → Report a vulnerability** on this repository. Include steps to reproduce and the affected version. You will get a response as soon as possible.

## Scope notes

- Third-party packages in the Skill Library are not audited. Review a package's source before installing it.
- The optional closed-lid helper is privileged and opt-in. See `Resources/ClosedLidSetup.md`.
