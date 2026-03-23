# Security Policy

## Supported Versions

Only the latest commit on `main` is actively maintained.

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Email: samuel@clsbooking.com

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

You will receive a response within 48 hours. If confirmed, a fix will be released within 7 days and you will be credited in the changelog unless you prefer to remain anonymous.

## Known Limitations

- **macOS only** — Keychain storage is macOS-specific. Linux support is not implemented.
- **User-level Keychain access** — any process running as the same macOS user can read stored credentials without a password prompt (once the login keychain is unlocked). Vault Guard does not set per-application ACLs on Keychain entries.
- **PostToolUse cannot block** — the `output-redactor.sh` (Bash) and `auto-store-secrets.sh` (Write/Edit) hooks cannot prevent Claude Code from displaying tool results. They scrub `history.jsonl` after the fact but the credential may have appeared briefly in the UI.
- **Non-Claude AI tools** — hooks only fire inside Claude Code. Codex CLI, Cursor, and other AI tools are not protected.
