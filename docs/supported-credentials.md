# Supported Credentials

All patterns are stored in `config/patterns.json` and loaded at runtime. This document is the canonical reference for every pattern Vault Guard detects out of the box.

---

## Pattern Table

| ID | Service | Pattern Prefix / Regex | Severity | Notes |
|---|---|---|---|---|
| `stripe_live` | Stripe Live Secret Key | `sk_live_[0-9a-zA-Z]{24,}` | critical | Production billing key |
| `stripe_test` | Stripe Test Secret Key | `sk_test_[0-9a-zA-Z]{24,}` | high | Skipped if `allow_test_keys: true` |
| `stripe_restricted` | Stripe Restricted Key | `rk_live_[0-9a-zA-Z]{24,}` | high | Restricted live key |
| `anthropic` | Anthropic API Key | `sk-ant-[a-zA-Z0-9\-_]{20,}` | critical | Claude API access |
| `openrouter` | OpenRouter API Key | `sk-or-v1-[a-zA-Z0-9]{32,}` | critical | OpenRouter unified key |
| `openai` | OpenAI API Key | `sk-[a-zA-Z0-9]{20,}` (non-Anthropic) | critical | GPT API key |
| `openai_proj` | OpenAI Project Key | `sk-proj-[a-zA-Z0-9\-_]{40,}` | critical | Project-scoped OpenAI key |
| `github_pat` | GitHub Personal Access Token | `ghp_[a-zA-Z0-9]{36}` | critical | Full repo/account access |
| `github_oauth` | GitHub OAuth Token | `gho_[a-zA-Z0-9]{36}` | critical | OAuth app token |
| `github_app` | GitHub App Token | `ghs_[a-zA-Z0-9]{36}` | high | GitHub App server token |
| `github_user` | GitHub User-to-Server Token | `ghu_[a-zA-Z0-9]{36}` | high | User-to-server auth |
| `github_refresh` | GitHub Refresh Token | `ghr_[a-zA-Z0-9]{36}` | high | Token refresh credential |
| `gemini` | Google / Gemini API Key | `AIza[0-9A-Za-z\-_]{35}` | critical | Google Cloud + Gemini access |
| `resend` | Resend API Key | `re_[a-zA-Z0-9]{16,}` | high | Email sending API |
| `telnyx` | Telnyx API Key | `KEY[0-9]{16,}` | high | Voice/SMS API key |
| `groq` | Groq API Key | `gsk_[a-zA-Z0-9]{40,}` | critical | Groq LLM inference key |
| `supabase_jwt` | Supabase JWT (service role) | `eyJ[a-zA-Z0-9\-_]{100,}` | critical | Full DB + storage access |
| `supabase_anon` | Supabase Anon Key | `eyJ[a-zA-Z0-9\-_]{50,99}` | medium | Public anon key (lower risk) |
| `aws_access` | AWS Access Key ID | `AKIA[0-9A-Z]{16}` | critical | AWS identity key |
| `aws_secret` | AWS Secret Access Key | 40-char mixed alphanumeric after `aws_secret` context | critical | AWS signing key |
| `twilio_sid` | Twilio Account SID | `AC[a-f0-9]{32}` | high | Twilio account identifier |
| `twilio_token` | Twilio Auth Token | `SK[a-f0-9]{32}` | high | Twilio API token |
| `sendgrid` | SendGrid API Key | `SG\.[a-zA-Z0-9\-_]{22,}\.[a-zA-Z0-9\-_]{43,}` | critical | Email delivery key |
| `mailgun` | Mailgun API Key | `key-[a-f0-9]{32}` | high | Email delivery key |
| `slack_bot` | Slack Bot Token | `xoxb-[0-9\-a-zA-Z]{40,}` | high | Slack bot/workspace token |
| `slack_user` | Slack User Token | `xoxp-[0-9\-a-zA-Z]{40,}` | high | Slack user OAuth token |
| `slack_webhook` | Slack Incoming Webhook | `https://hooks.slack.com/services/T[A-Z0-9]+/B[A-Z0-9]+/` | medium | Webhook URL |
| `vercel` | Vercel API Token | `[a-zA-Z0-9]{24}` (with `VERCEL_TOKEN` context) | high | Deployment token |
| `firebase_admin` | Firebase Admin SDK Key | JSON `"private_key"` field containing `-----BEGIN` | critical | Service account key |
| `digitalocean` | DigitalOcean Token | `dop_v1_[a-f0-9]{64}` | critical | DO API token |
| `heroku` | Heroku API Key | UUID format in `HEROKU_API_KEY` context | high | Heroku deploy token |
| `npm_token` | npm Publish Token | `npm_[a-zA-Z0-9]{36}` | high | Package publish access |
| `pypi_token` | PyPI API Token | `pypi-[a-zA-Z0-9\-_]{80,}` | high | Python package publish |
| `docker_pat` | Docker Hub PAT | 36-char UUID in `DOCKER_TOKEN` / `DOCKERHUB_TOKEN` context | high | Registry push access |
| `jwt_generic` | Generic JWT | `eyJ[a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]+` | medium | Any signed JWT |
| `private_key_pem` | PEM Private Key | `-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----` | critical | Any private key material |

---

## Severity Definitions

| Severity | Description |
|---|---|
| `critical` | Direct account or service compromise if exposed. Always blocked in `block` mode. |
| `high` | Significant access risk. Blocked in `block` mode; warned in `warn` mode. |
| `medium` | Limited or scoped access. Warned in both modes; not blocked. |
| `low` | Informational only (e.g., public IDs). Logged but no user-facing alert. |

---

## Test Keys

Keys matching `sk_test_`, `pk_test_` (Stripe), or similar test-mode prefixes are treated as `high` severity by default. Set `allow_test_keys: true` in `~/.vaultguard.json` to downgrade these to `low` — useful in development environments where test keys are expected.

---

## Adding Custom Patterns

Edit `config/patterns.json` and add an entry:

```json
{
  "id": "myservice_key",
  "name": "MyService API Key",
  "regex": "ms_[a-zA-Z0-9]{32,}",
  "severity": "high"
}
```

No code changes needed. The hooks load this file at runtime, so the new pattern is active immediately after saving.

---

## False Positive Handling

If a pattern fires on something that is not a real credential (e.g., a fake key in a unit test fixture), you have two options:

1. **Exempt a path:** Add the test directory to `exempt_paths` in `~/.vaultguard.json`
2. **Disable a pattern:** Add the pattern `id` to the `disabled_patterns` array in your config

```json
{
  "disabled_patterns": ["stripe_test", "supabase_anon"]
}
```
