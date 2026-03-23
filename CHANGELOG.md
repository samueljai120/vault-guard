# Changelog

## [Unreleased]

## [1.0.0] — 2026-03-23

### Added
- Four Claude Code hooks: `credential-scanner.sh`, `auto-store-secrets.sh`, `output-redactor.sh`, `history-scrubber.sh`
- 4-step detection pipeline: KEY=value → fingerprint → Supabase JWT → Shannon entropy
- 18 credential fingerprints: Stripe, Anthropic, OpenRouter, OpenAI, GitHub, Google/Gemini, Resend, Telnyx, Groq, Cartesia, ElevenLabs, Deepgram
- Project-scoped Keychain namespaces via `~/.vaultguard.json`
- `vault-guard` CLI: `list`, `get`, `set`, `del`, `import`, `run`, `projects`, `status`, `test`
- `vault-guard import <project> <file>` — bulk-import existing `.env` files to Keychain
- `vault-guard run <project> <cmd>` — inject project secrets into subprocess (no eval, uses `os.execvpe`)
- Idempotent `install.sh` and `uninstall.sh`
- GitHub Actions CI (macOS)
- `SECURITY.md` with known limitations and disclosure process

### Fixed
- Multi-line prompts bypassing scanner — Claude Code sends literal newlines inside JSON strings (invalid JSON); fixed with `json.loads(strict=False)` + raw fallback
- Pure hex keys (entropy ~3.57) missed by 3.8 threshold — separate 3.4 threshold for `[0-9a-f]+` tokens
- `.env.template`, `.env.example`, `.env.sample` incorrectly redacted — fixed exclusion to use glob matching
- `DATABASE_URL` imported by `vault-guard import` — URL scheme filter added
- `vault-guard run` used `eval` with bash-embedded Python strings — shell injection risk; replaced with `os.execvpe` (no shell, no eval)
- `get_service()` printed service name twice — bare `except:` was catching `SystemExit` from Python's `exit()`; fixed with `except Exception:`
- Backup file `history.jsonl.bak` accumulated unredacted history — now deleted at the start of each scrub run
- Uninstall script removed wrong files (`.py` instead of `.sh`)
- `docs/how-it-works.md` described non-existent Python files — rewritten to match actual bash implementation
