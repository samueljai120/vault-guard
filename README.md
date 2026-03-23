# CLS Vault Guard

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Made by CLS Booking](https://img.shields.io/badge/made%20by-CLS%20Booking-4f46e5.svg)](https://clsbooking.com)
[![Free & Open Source](https://img.shields.io/badge/free-%26%20open--source-22c55e.svg)]()

**CLS Vault Guard** automatically detects and blocks real credentials from being written to files, executed in shell commands, or leaked in Claude Code sessions — before they ever touch disk or leave your machine. Drop it in once; paste credentials freely in any format and let the hooks handle the rest.

---

## How It Works

Vault Guard installs four Claude Code hooks that intercept every action at the points where credentials are most likely to leak:

### 1. `UserPromptSubmit` — Prompt Scanner
Fires before Claude processes your message. Scans the raw prompt text for credential patterns. If a live key is found, the hook blocks the prompt from being sent and prints a warning. You can still send the message after confirming — this acts as a friction gate, not a hard wall.

### 2. `PostToolUse:Bash` — Shell Command Guard
Fires after every `Bash` tool call. Inspects the command string and its stdout/stderr output for leaked keys (e.g., `export STRIPE_KEY=sk_live_...` or keys echoed to terminal). Flags the result so Claude can redact or abort follow-up actions.

### 3. `PostToolUse:Write|Edit` — File Write Interceptor
Fires after every `Write` or `Edit` tool call. Reads the content that was just written or patched and scans it for credential patterns. If a live key is detected it appends a blocking annotation to the tool result and optionally opens the file for immediate redaction.

### 4. `Stop` — Session Audit
Fires at the end of every Claude Code session (when the agent finishes). Performs a final sweep of all files touched during the session and prints a credential-safety summary. Acts as a last-chance audit log — no session ends silently if a key was written.

---

## Supported Credentials

| Service | Pattern Prefix | Example Format |
|---|---|---|
| Stripe Live Secret | `sk_live_` | `sk_live_51...` |
| Stripe Test Secret | `sk_test_` | `sk_test_4e...` |
| Anthropic | `sk-ant-` | `sk-ant-api03-...` |
| OpenRouter | `sk-or-v1-` | `sk-or-v1-...` |
| GitHub Token (classic) | `ghp_` | `ghp_16C7...` |
| GitHub OAuth | `gho_` | `gho_...` |
| GitHub App Token | `ghs_` / `ghu_` | `ghs_...` |
| Google / Gemini API | `AIza` | `AIzaSy...` |
| Resend | `re_` | `re_123abc_...` |
| Telnyx | `KEY01` | `KEY01...` |
| Groq | `gsk_` | `gsk_...` |
| Supabase JWT | `eyJ` (long) | `eyJhbGci...` |
| OpenAI | `sk-` (non-Anthropic) | `sk-proj-...` |
| AWS Access Key | `AKIA` | `AKIAIOSFODNN7...` |
| Twilio | `SK` + 32 hex | `SK...` |

> Patterns are defined in `config/patterns.json` — add your own in 3 lines.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/clsbooking/vault-guard/main/install.sh | bash
```

Or clone and install locally:

```bash
git clone https://github.com/clsbooking/vault-guard.git
cd vault-guard
bash install.sh
```

Restart Claude Code after install (or run `/reload` in the Claude Code terminal).

---

## Configuration

Vault Guard is configured via `~/.vaultguard.json`. A default config is created automatically on first install. You never need to touch it to get full protection — it works out of the box.

### Default config

```json
{
  "version": 1,
  "mode": "block",
  "projects": [
    {
      "name": "default",
      "path": "~",
      "patterns": "all"
    }
  ],
  "notifications": {
    "terminal": true,
    "log_file": "~/.vaultguard.log"
  },
  "allow_test_keys": false,
  "exempt_paths": [
    "~/.ssh/",
    "~/.gnupg/"
  ]
}
```

### Key options

| Key | Type | Default | Description |
|---|---|---|---|
| `mode` | `"block"` \| `"warn"` | `"block"` | `block` halts the action; `warn` logs but allows it |
| `allow_test_keys` | boolean | `false` | Set `true` to allow `sk_test_` and similar test-mode keys |
| `exempt_paths` | array | `[]` | Paths where credential scanning is skipped |
| `patterns` | `"all"` \| array | `"all"` | Limit to specific pattern IDs from `config/patterns.json` |
| `notifications.log_file` | string \| `null` | `~/.vaultguard.log` | Set to `null` to disable file logging |

Full schema documentation: [docs/configuration.md](docs/configuration.md)

---

## Usage

Just paste credentials in any format — inline in a message, in a file you're editing, in a shell command. The hooks handle the rest. You don't need to wrap anything, escape anything, or remember to check.

```
# These are all caught automatically:

export STRIPE_KEY=sk_live_51abc...          ← Bash hook
ANTHROPIC_API_KEY=sk-ant-api03-...          ← Prompt hook
{ "apiKey": "AIzaSy..." }                   ← Write/Edit hook
```

When a credential is detected you'll see:

```
[VaultGuard] BLOCKED — live Stripe key detected in Write output.
File: /Users/you/project/config.ts  Line: 12
Run `vg status` for session audit.
```

---

## CLI Commands

After install, the `vg` command is available in your terminal:

| Command | Description |
|---|---|
| `vg status` | Show credentials detected this session |
| `vg audit <path>` | Scan a file or directory for credentials |
| `vg patterns` | List all active detection patterns |
| `vg config` | Open `~/.vaultguard.json` in your default editor |
| `vg version` | Print installed version |

---

## Uninstall

```bash
bash uninstall.sh
```

Your `~/.vaultguard.json` is preserved. Re-run `install.sh` to reinstall at any time.

---

## Contributing

Pull requests welcome. To add a new credential pattern, edit `config/patterns.json` and submit a PR — no Python changes needed for most patterns.

See [docs/how-it-works.md](docs/how-it-works.md) for a full technical deep-dive.

---

<p align="center">
  Made with care by <a href="https://clsbooking.com"><strong>CLS Booking</strong></a> &mdash; free forever, MIT licensed.
</p>
