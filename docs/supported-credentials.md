# Supported Credentials

Vault Guard detects credentials using 18 hardcoded fingerprints in the hook scripts, plus Supabase JWT decoding and a Shannon entropy fallback for unknown formats.

---

## Detected Patterns

| Service | Prefix / Pattern | Auto-Named As | Notes |
|---|---|---|---|
| Stripe live secret | `sk_live_` | `STRIPE_SECRET_KEY` | Production billing key |
| Stripe test secret | `sk_test_` | `STRIPE_TEST_SECRET_KEY` | Test mode key |
| Stripe publishable (live) | `pk_live_` | `STRIPE_PUBLISHABLE_KEY` | Client-side key |
| Stripe publishable (test) | `pk_test_` | `STRIPE_TEST_PUBLISHABLE_KEY` | Client-side test key |
| Stripe webhook secret | `whsec_` | `STRIPE_WEBHOOK_SECRET` | Webhook signature verification |
| Stripe restricted key | `rk_live_` | `STRIPE_RESTRICTED_KEY` | Scoped live key |
| Anthropic | `sk-ant-api` | `ANTHROPIC_API_KEY` | Claude API access |
| OpenRouter | `sk-or-v1-` | `OPENROUTER_API_KEY` | OpenRouter unified key |
| OpenAI (project) | `sk-proj-` | `OPENAI_API_KEY` | Project-scoped OpenAI key |
| GitHub PAT (classic) | `ghp_` | `GITHUB_TOKEN` | Full repo/account access |
| GitHub OAuth | `gho_` | `GITHUB_OAUTH_TOKEN` | OAuth app token |
| Google / Gemini | `AIzaSy` | `GEMINI_API_KEY` | Google Cloud + Gemini |
| Resend | `re_` | `RESEND_API_KEY` | Email sending |
| Telnyx | `KEY` + hex | `TELNYX_API_KEY` | Voice/SMS API |
| Groq | `gsk_` | `GROQ_API_KEY` | Groq LLM inference |
| Cartesia | `sk_car_` | `CARTESIA_API_KEY` | Text-to-speech |
| ElevenLabs | `sk_` (48+ chars) | `ELEVENLABS_API_KEY` | Voice synthesis |
| Supabase JWT | `eyJhbGci...` | `SUPABASE_SERVICE_ROLE_KEY` or `SUPABASE_ANON_KEY` | Auto-detected via JWT payload `role` field |

---

## Additional Detection

### KEY=value parsing
Any line matching `KEY_NAME=value` (8+ character value) is detected regardless of whether the service is in the fingerprint list. The key name is preserved as-is.

### Shannon entropy fallback
Strings 32+ characters with high entropy are flagged as `UNKNOWN_SECRET`:
- Pure hex `[0-9a-f]+`: threshold > 3.4 bits/char
- Other strings: threshold > 3.8 bits/char

This catches credentials from services not in the fingerprint list, like Deepgram, custom API keys, and hex tokens.

---

## Not Detected (Known Gaps)

These formats are NOT currently detected by fingerprint and rely on KEY=value context or entropy fallback:

- AWS (`AKIA...` access keys, secret keys)
- Twilio (`AC...` SID, `SK...` token)
- SendGrid (`SG.` keys)
- Slack (`xoxb-`, `xoxp-` tokens)
- Vercel, Firebase, DigitalOcean, Heroku, npm, PyPI tokens
- PEM private keys (multi-line)
- MongoDB/Postgres connection strings

These WILL be caught if pasted as `KEY=value` (e.g., `AWS_SECRET_ACCESS_KEY=...`). They will NOT be caught if pasted as raw values without a key name, unless they have high enough entropy.

---

## Adding Custom Patterns

Edit the `FINGERPRINTS` list inside `~/.claude/hooks/credential-scanner.sh`:

```python
FINGERPRINTS = [
    # ... existing patterns ...
    (r'hf_[A-Za-z0-9]{34,}', 'HUGGINGFACE_TOKEN', 'HUGGINGFACE_TOKEN', 'HuggingFace token'),
]
```

Also update `auto-store-secrets.sh` and `output-redactor.sh` with the same pattern for full coverage.

Note: `config/patterns.json` exists as a reference document listing common credential formats. It is **not read at runtime** by the hooks — patterns are hardcoded in the hook scripts for speed and simplicity.

---

## False Positives

If a pattern fires on something that isn't a real credential, the credential is stored to Keychain harmlessly. You can remove it:

```bash
vault-guard del my-project FAKE_KEY_NAME
```
