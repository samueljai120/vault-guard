# How Vault Guard Works — Technical Deep-Dive

CLS Vault Guard installs four **bash scripts** as Claude Code hooks. Each hook intercepts a specific event in the Claude Code session lifecycle, runs a Python detection pipeline inline, and stores detected credentials to macOS Keychain.

---

## Architecture

```
Claude Code session
       │
       ├── [UserPromptSubmit]    → credential-scanner.sh   (exits 2 to BLOCK)
       │
       ├── [PostToolUse: Bash]   → output-redactor.sh      (exits 0, scrubs history)
       │
       ├── [PostToolUse: Write]  → auto-store-secrets.sh   (exits 0, redacts .env)
       ├── [PostToolUse: Edit]   → auto-store-secrets.sh
       │
       └── [Stop]                → history-scrubber.sh     (exits 0, scrubs history.jsonl)
```

Hooks are bash scripts installed to `~/.claude/hooks/`. Python code runs inline via heredoc (`python3 - args <<'PYEOF' ... PYEOF`) — there are no separate Python files.

---

## Detection pipeline

All four hooks share the same 4-step Python detection logic:

### Step 1 — KEY=value parsing (highest priority)
```python
kv_re = re.compile(
    r'^\s*(?:export\s+)?([A-Z][A-Z0-9_]{2,})\s*=\s*["\']?([^\s"\'#\n]{8,})["\']?\s*$',
    re.MULTILINE
)
```
Catches explicit `KEY=value` and `export KEY=value` syntax. The key name is used directly — no auto-naming needed.

**Filters applied:** skips URL schemes (`postgres://`, `https://`, etc.), short numerics, placeholder values (`your_key_here`, `placeholder`, `stored-in-keychain`), and keys that start with `$`.

### Step 2 — Fingerprint matching
18 hardcoded regex patterns matched against the raw text:
```python
FINGERPRINTS = [
    (r'sk_live_[A-Za-z0-9]{24,}',  'STRIPE_SECRET_KEY',  ...),
    (r'sk-ant-api[0-9]+-...',       'ANTHROPIC_API_KEY',  ...),
    # ... 16 more
]
```
Used when there is no `KEY=` prefix — the key name is auto-assigned from the fingerprint database. Project routing uses the key name prefix against `~/.vaultguard.json`.

### Step 3 — Supabase JWT decode
```python
re.finditer(r'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9\.[A-Za-z0-9._-]{60,}', text)
```
Base64-decodes the JWT payload to read the `role` field. Auto-names as `SUPABASE_SERVICE_ROLE_KEY` or `SUPABASE_ANON_KEY`.

### Step 4 — Shannon entropy fallback
```python
def shannon_entropy(s):
    freq = {}
    for c in s: freq[c] = freq.get(c, 0) + 1
    return -sum((f/len(s)) * math.log2(f/len(s)) for f in freq.values())
```
Only runs if steps 1–3 found nothing. Scans 32+ character tokens. Threshold:
- Pure hex strings `[0-9a-f]+`: entropy > 3.4
- All other strings: entropy > 3.8

Stored as `UNKNOWN_SECRET`.

---

## Project routing

Each credential is routed to a Keychain service via `~/.vaultguard.json`:

```
File path match → key prefix match → default_project
```

1. If the file being written is inside a project's `dir`, that project wins
2. If the key name starts with a project's `key_prefixes` entry, that project wins
3. Otherwise, `default_project` is used

---

## Hook 1: `credential-scanner.sh` (UserPromptSubmit)

**Exit codes:**
- `exit 2` — credential detected → message blocked, never sent to Anthropic
- `exit 0` — no credentials → message passes through normally

**JSON input (Claude Code sends this on stdin):**
```json
{"prompt": "STRIPE_SECRET_KEY=sk_live_51..."}
```

**Multiline messages** arrive with literal newlines inside the JSON string (technically invalid JSON). Fixed with `json.loads(raw, strict=False)`. Falls back to scanning raw stdin if JSON parsing still fails.

After blocking, Claude Code surfaces the box to the user:
```
╔══════════════════════════════════════╗
║  AUTO-VAULT — INTERCEPTED            ║
║  ✓ STRIPE_SECRET_KEY → [my-project]  ║
║  Message blocked.                    ║
╚══════════════════════════════════════╝
```

---

## Hook 2: `output-redactor.sh` (PostToolUse: Bash)

Only processes `Bash` tool calls. Scans the tool response output for credential patterns. Cannot block (PostToolUse exit 2 is not supported by Claude Code for this event) — instead:

1. Stores any found credentials to Keychain
2. Scrubs `~/.claude/history.jsonl` immediately (sed in-place)
3. Logs the event to `~/.claude/credential-leak.log`

---

## Hook 3: `auto-store-secrets.sh` (PostToolUse: Write|Edit)

Fires after Claude writes any file. Scans the written file's content.

For `.env` files (`.env`, `.env.local`, `.env.production`, etc.) — redacts in-place:
```
STRIPE_SECRET_KEY=# stored-in-keychain
```

**Excluded from redaction:** `.env.template`, `.env.example`, `.env.sample`, `.envrc`, `.env.keys`

For code files (`.ts`, `.py`, etc.) — stores but does NOT redact (would break syntax).

---

## Hook 4: `history-scrubber.sh` (Stop)

Runs when the Claude Code session ends. Applies regex redaction to `~/.claude/history.jsonl`:

```bash
for pattern in "${PATTERNS[@]}"; do
    SED_EXPR="${SED_EXPR}s|${pattern}|[REDACTED]|g;"
done
sed -E "$SED_EXPR" "$HISTORY" > "${HISTORY}.tmp" && mv "${HISTORY}.tmp" "$HISTORY"
```

---

## Keychain storage

All credentials are stored to macOS Keychain via:
```bash
security add-generic-password -U -s "$service" -a "$key_name" -w "$value"
```

- `-U` — update if already exists (idempotent)
- `-s "$service"` — the Keychain service name (= project's `keychain_service` field)
- `-a "$key_name"` — the account name (= env variable name)
- `-w "$value"` — the password (= the secret value)

Retrieve at any time:
```bash
security find-generic-password -s "my-project" -a "STRIPE_SECRET_KEY" -w
```

---

## Exit codes (Claude Code hook system)

| Code | Meaning |
|---|---|
| `0` | Hook ran, no blocking action |
| `1` | Hook error (Claude Code logs it) |
| `2` | Block — only works in `UserPromptSubmit` |

Only `credential-scanner.sh` uses exit `2`. All other hooks exit `0`.

---

## Adding credential patterns

Patterns are hardcoded in the Python block inside each hook file. To add a new pattern, edit the `FINGERPRINTS` list in `~/.claude/hooks/credential-scanner.sh`:

```python
FINGERPRINTS = [
    # ... existing patterns ...
    (r'hf_[A-Za-z0-9]{34,}', 'HUGGINGFACE_TOKEN', 'HUGGINGFACE_TOKEN', 'HuggingFace token'),
]
```

Note: `config/patterns.json` exists as a reference/documentation of pattern formats but is not read at runtime by the hooks.
