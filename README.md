# CLS Vault Guard

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Made by CLS Booking](https://img.shields.io/badge/made%20by-CLS%20Booking-4f46e5.svg)](https://clsbooking.com)

**Zero-config credential DLP for Claude Code.**

Paste an API key into Claude Code chat — it gets intercepted, stored to macOS Keychain, and **blocked before reaching Anthropic**. No manual steps. Works with any format.

```
╔══════════════════════════════════════════════════════════════════╗
║  AUTO-VAULT — INTERCEPTED & STORED TO KEYCHAIN                   ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                    ║
║  ✓ Stored:                                                         ║
║    STRIPE_SECRET_KEY → [my-project]  (Stripe live secret key)      ║
║                                                                    ║
╠══════════════════════════════════════════════════════════════════╣
║  Message blocked — values never reached Anthropic.                 ║
║  Now tell Claude: 'Keys are stored. [describe task]'               ║
╚══════════════════════════════════════════════════════════════════╝
```

---

## Install

```bash
git clone https://github.com/samueljai120/vault-guard.git
cd vault-guard
bash install.sh
```

Then **restart Claude Code** to activate hooks.

---

## What it does

Four Claude Code hooks fire automatically on every session:

| Hook | Fires when | Action |
|---|---|---|
| `UserPromptSubmit` | You send any message | Scans for credentials → stores to Keychain → **blocks message** (exit 2) |
| `PostToolUse: Write\|Edit` | Claude writes a file | Scans file content → stores → redacts `.env` files in-place |
| `PostToolUse: Bash` | Claude runs a shell command | Scans bash output → stores → scrubs session history |
| `Stop` | Session ends | Scans `~/.claude/history.jsonl` → redacts any remaining credential values |

---

## Supported formats

All of these are caught automatically — no `KEY=value` wrapper needed for known patterns:

```bash
# Format 1: KEY=value (any key name)
STRIPE_SECRET_KEY=sk_live_51abc...

# Format 2: export syntax
export ANTHROPIC_API_KEY=sk-ant-api03-...

# Format 3: raw value (known prefixes only)
sk_live_51abc...
ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA

# Format 4: Supabase JWTs (auto-named by role)
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

# Format 5: quoted values
RESEND_API_KEY="re_abc123..."

# Format 6: high-entropy unknown strings (fallback)
# Strings with Shannon entropy > 3.8 are flagged as UNKNOWN_SECRET
```

**Unknown keys** (like `TWILIO_AUTH_TOKEN=xxx`) are stored under the key name you provide. Raw values without a `KEY=` prefix are only detected if they match a known pattern.

---

## Supported credential types

| Service | Pattern | Auto-named as |
|---|---|---|
| Stripe live secret | `sk_live_...` | `STRIPE_SECRET_KEY` |
| Stripe test secret | `sk_test_...` | `STRIPE_TEST_SECRET_KEY` |
| Stripe publishable (live) | `pk_live_...` | `STRIPE_PUBLISHABLE_KEY` |
| Stripe webhook | `whsec_...` | `STRIPE_WEBHOOK_SECRET` |
| Stripe restricted | `rk_live_...` | `STRIPE_RESTRICTED_KEY` |
| Anthropic | `sk-ant-api...` | `ANTHROPIC_API_KEY` |
| OpenRouter | `sk-or-v1-...` | `OPENROUTER_API_KEY` |
| OpenAI | `sk-proj-...` | `OPENAI_API_KEY` |
| GitHub token (classic) | `ghp_...` | `GITHUB_TOKEN` |
| GitHub OAuth | `gho_...` | `GITHUB_OAUTH_TOKEN` |
| GitHub fine-grained | `github_pat_...` | `GITHUB_TOKEN` |
| Google / Gemini | `AIzaSy...` | `GEMINI_API_KEY` |
| Resend | `re_...` | `RESEND_API_KEY` |
| Telnyx | `KEY[hex]_...` | `TELNYX_API_KEY` |
| Groq | `gsk_...` | `GROQ_API_KEY` |
| Supabase service role | JWT with `role=service_role` | `SUPABASE_SERVICE_ROLE_KEY` |
| Supabase anon | JWT with `role=anon` | `SUPABASE_ANON_KEY` |
| Unknown high-entropy | Shannon entropy > 3.8 | `UNKNOWN_SECRET` |

---

## Project namespaces (optional)

By default, all credentials go to a single `vault-guard` Keychain service.

To route credentials to separate per-project namespaces, edit `~/.vaultguard.json`:

```json
{
  "version": "1",
  "projects": [
    {
      "id": "my-app",
      "name": "My App",
      "keychain_service": "my-app",
      "dir": "~/Documents/my-app",
      "key_prefixes": ["STRIPE_", "RESEND_", "MY_APP_"]
    },
    {
      "id": "my-other-app",
      "name": "My Other App",
      "keychain_service": "my-other-app",
      "dir": "~/Documents/my-other-app",
      "key_prefixes": ["OPENAI_", "GITHUB_"]
    }
  ],
  "default_project": "my-app"
}
```

Routing priority:
1. **File path** — if Claude writes to a file inside `dir`, that project wins
2. **Key prefix** — if the key name starts with a listed prefix, that project wins
3. **Default** — falls back to `default_project`

---

## CLI

After install, `vault-guard` (alias `vg`) is available:

```bash
vault-guard list                          # list all stored keys across all projects
vault-guard list my-app                   # list keys for one project
vault-guard get my-app STRIPE_SECRET_KEY  # retrieve a value
vault-guard set my-app MY_KEY             # store a value (prompts, input hidden)
vault-guard del my-app OLD_KEY            # delete a key
vault-guard import my-app .env            # bulk-import an existing .env file → Keychain
vault-guard run my-app node server.js     # run a command with project secrets in env
vault-guard projects                      # list configured projects
vault-guard status                        # check hook installation health
vault-guard test                          # run a quick self-test
```

---

## Retrieve credentials at runtime

Use `vault-guard get` in scripts or `.envrc` (with [direnv](https://direnv.net)):

```bash
# .envrc — auto-loads when you cd into the project
export STRIPE_SECRET_KEY=$(vault-guard get my-app STRIPE_SECRET_KEY)
export RESEND_API_KEY=$(vault-guard get my-app RESEND_API_KEY)
```

Or use `security find-generic-password` directly:

```bash
export STRIPE_SECRET_KEY=$(security find-generic-password -s "my-app" -a "STRIPE_SECRET_KEY" -w)
```

---

## Migrating existing `.env` files

If you have credentials already sitting in `.env` files, import them in one command:

```bash
vault-guard import my-app .env
```

This reads every `KEY=value` line, stores each credential to Keychain, and skips URLs, comments, placeholders, and short values.

---

## Running commands with secrets injected

Instead of sourcing `.env` files directly, use `vault-guard run` to inject credentials into a subprocess without exposing them in shell history:

```bash
vault-guard run my-app node server.js
vault-guard run my-app python manage.py migrate
vault-guard run my-app npm run dev
```

Secrets are exported into the child process's environment and do not persist in your shell session.

---

## What is NOT protected

- **Codex CLI and other AI tools** — Claude Code hooks only fire inside Claude Code. For other tools, use `vault-guard run <project> <cmd>` to ensure secrets are injected from Keychain rather than from `.env` files.
- **Raw hex values without `KEY=` prefix** — 32-char hex strings (e.g., `92791e77...`) are caught if their entropy exceeds 3.4 bits/char. Longer hex keys (40+ chars) are caught more reliably. When in doubt, use `KEY=value` format.
- **Non-macOS systems** — storage uses macOS Keychain. Linux users can adapt the hooks to use `secret-tool` (GNOME Keyring) or `pass`.

---

## Uninstall

```bash
bash uninstall.sh
```

Your `~/.vaultguard.json` and Keychain entries are preserved.

---

## How it works (technical)

See [docs/how-it-works.md](docs/how-it-works.md).

Detection pipeline (runs in Python, inside each hook):
1. `KEY=value` regex scan — highest priority, captures explicit key names
2. Fingerprint matching — 18 known credential patterns
3. Supabase JWT decode — base64 payload → role → auto-named
4. Shannon entropy fallback — strings > 3.8 bits flagged as `UNKNOWN_SECRET`

---

## Contributing

To add a new credential pattern: edit `config/patterns.json` and open a PR.

```json
{
  "id": "my_service",
  "label": "My Service API key",
  "pattern": "ms_[A-Za-z0-9]{32,}",
  "key_name": "MY_SERVICE_API_KEY"
}
```

---

<p align="center">
  Made with care by <a href="https://clsbooking.com"><strong>CLS Booking</strong></a> — free forever, MIT licensed.
</p>
