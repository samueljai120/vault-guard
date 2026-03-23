#!/usr/bin/env bash
# Claude Code — Smart Credential Vault (UserPromptSubmit hook)
#
# Paste credentials in ANY format — hook auto-detects, stores to Keychain, blocks.
# Exit 2 = block. Exit 0 = allow through.
#
# Project routing is driven by ~/.vaultguard.json config.
# Falls back to "vault-guard" keychain service if config is missing.

set -euo pipefail

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | python3 -c "
import sys, json, re
raw = sys.stdin.read()
try:
    d = json.loads(raw, strict=False)
    print(d.get('prompt','') or d.get('message','') or d.get('content',''))
except:
    # Fallback: scan raw input directly (handles non-JSON or malformed payloads)
    print(raw)
" 2>/dev/null || true)

[ -z "$PROMPT" ] && exit 0

# Write prompt to temp file — avoids shell interpolation issues in heredocs
TMPFILE=$(mktemp /tmp/cls-scanner-XXXXXX.txt)
trap 'rm -f "$TMPFILE"' EXIT
printf '%s' "$PROMPT" > "$TMPFILE"

# ── Smart detection + auto-store ──────────────────────────────────────────────
DETECTIONS=$(python3 - "$TMPFILE" "$HOME/.vaultguard.json" <<'PYEOF'
import re, sys, base64, json, math, os

# ── Load VaultGuard config ────────────────────────────────────────────────────
def load_vaultguard_config(config_path):
    """Load ~/.vaultguard.json; return (projects_list, default_project_id)."""
    try:
        expanded = os.path.expanduser(config_path)
        with open(expanded, 'r') as f:
            cfg = json.load(f)
        return cfg.get('projects', []), cfg.get('default_project', 'vault-guard')
    except Exception:
        return [], 'vault-guard'

def detect_project_from_key(key_name, projects, default_id):
    """Return the project id whose key_prefixes best match key_name."""
    for proj in projects:
        for prefix in proj.get('key_prefixes', []):
            if key_name.startswith(prefix):
                return proj['id']
    return default_id

def get_keychain_service(project_id, projects, default_id):
    """Return keychain_service for a project id."""
    for proj in projects:
        if proj['id'] == project_id:
            return proj.get('keychain_service', project_id)
    # If project_id IS the default, use it directly as the service name
    return project_id

def get_project_dir(project_id, projects):
    """Return expanded dir path for a project id, or empty string."""
    for proj in projects:
        if proj['id'] == project_id:
            return os.path.expanduser(proj.get('dir', ''))
    return ''

with open(sys.argv[1], 'r', errors='replace') as f:
    text = f.read()

config_path = sys.argv[2]
projects, default_id = load_vaultguard_config(config_path)

# ── Credential fingerprint database ──────────────────────────────────────────
# Format: (regex, env_key_name, key_prefix_hint, label)
# key_prefix_hint is the env key name itself — used to route via detect_project_from_key.
FINGERPRINTS = [
    # Stripe
    (r'sk_live_[A-Za-z0-9]{24,}',             'STRIPE_SECRET_KEY',             'STRIPE_SECRET_KEY',             'Stripe live secret key'),
    (r'sk_test_[A-Za-z0-9]{24,}',             'STRIPE_TEST_SECRET_KEY',        'STRIPE_TEST_SECRET_KEY',        'Stripe test secret key'),
    (r'pk_live_[A-Za-z0-9]{24,}',             'STRIPE_PUBLISHABLE_KEY',        'STRIPE_PUBLISHABLE_KEY',        'Stripe live publishable key'),
    (r'pk_test_[A-Za-z0-9]{24,}',             'STRIPE_TEST_PUBLISHABLE_KEY',   'STRIPE_TEST_PUBLISHABLE_KEY',   'Stripe test publishable key'),
    (r'whsec_[A-Za-z0-9+/=]{30,}',            'STRIPE_WEBHOOK_SECRET',         'STRIPE_WEBHOOK_SECRET',         'Stripe webhook secret'),
    (r'rk_live_[A-Za-z0-9]{24,}',             'STRIPE_RESTRICTED_KEY',         'STRIPE_RESTRICTED_KEY',         'Stripe restricted key'),
    # AI providers
    (r'sk-ant-api[0-9]+-[A-Za-z0-9_-]{80,}',  'ANTHROPIC_API_KEY',             'ANTHROPIC_API_KEY',             'Anthropic API key'),
    (r'sk-or-v1-[a-f0-9]{60,}',               'OPENROUTER_API_KEY',            'OPENROUTER_API_KEY',            'OpenRouter API key'),
    (r'sk-proj-[A-Za-z0-9_-]{40,}',           'OPENAI_API_KEY',                'OPENAI_API_KEY',                'OpenAI API key'),
    # GitHub
    (r'ghp_[A-Za-z0-9]{36,}',                 'GITHUB_TOKEN',                  'GITHUB_TOKEN',                  'GitHub personal token'),
    (r'gho_[A-Za-z0-9]{36,}',                 'GITHUB_OAUTH_TOKEN',            'GITHUB_OAUTH_TOKEN',            'GitHub OAuth token'),
    (r'github_pat_[A-Za-z0-9_]{80,}',         'GITHUB_TOKEN',                  'GITHUB_TOKEN',                  'GitHub fine-grained token'),
    # Google
    (r'AIzaSy[A-Za-z0-9_-]{33}',              'GEMINI_API_KEY',                'AIzaSy',                        'Google/Gemini API key'),
    # Comms / Email
    (r're_[A-Za-z0-9]{20,}',                  'RESEND_API_KEY',                'RESEND_API_KEY',                'Resend API key'),
    (r'KEY[0-9A-F]{16,}_[A-Za-z0-9_-]{10,}',  'TELNYX_API_KEY',               'TELNYX_API_KEY',                'Telnyx API key'),
    # Voice AI
    (r'gsk_[A-Za-z0-9]{40,}',                 'GROQ_API_KEY',                  'GROQ_API_KEY',                  'Groq API key'),
    (r'sk_car_[A-Za-z0-9]{20,}',              'CARTESIA_API_KEY',              'CARTESIA_API_KEY',              'Cartesia API key'),
    (r'sk_[A-Za-z0-9]{48,}',                  'ELEVENLABS_API_KEY',            'ELEVENLABS_API_KEY',            'ElevenLabs API key'),
    # Deepgram / hex-based keys
    (r'dg\.[A-Za-z0-9_-]{30,}',               'DEEPGRAM_API_KEY',              'DEEPGRAM_API_KEY',              'Deepgram API key (dg. prefix)'),
]

NON_SECRETS = {
    'true','false','null','none','undefined','development','production',
    'test','local','placeholder','your_key_here','stored-in-keychain',
}

def decode_jwt_role(token):
    try:
        payload = token.split('.')[1]
        payload += '=' * (4 - len(payload) % 4)
        return json.loads(base64.b64decode(payload)).get('role')
    except:
        return None

def shannon_entropy(s):
    if not s: return 0
    freq = {}
    for c in s: freq[c] = freq.get(c, 0) + 1
    return -sum((f/len(s)) * math.log2(f/len(s)) for f in freq.values())

found = {}  # key_name -> (value, project_id, label)

# Step 1: KEY=value format — explicit name, highest priority
kv_re = re.compile(
    r'^\s*(?:export\s+)?([A-Z][A-Z0-9_]{2,})\s*=\s*["\']?([^\s"\'#\n]{8,})["\']?\s*$',
    re.MULTILINE
)
for key, val in kv_re.findall(text):
    val = val.strip().strip('"').strip("'")
    if not val or val.lower() in NON_SECRETS: continue
    if re.match(r'^(https?|postgres(?:ql)?|redis|mysql|mongodb|amqp|smtp|ftp|s3)://', val): continue
    if re.match(r'^\d{1,5}$', val): continue
    if val.startswith('$') or 'keychain' in val.lower(): continue
    project_id = detect_project_from_key(key, projects, default_id)
    found[key] = (val, project_id, f'KEY=value: {key}')

# Step 2: Raw value pattern matching — no KEY= needed
for pattern, key_name, prefix_hint, label in FINGERPRINTS:
    if key_name in found: continue
    m = re.search(pattern, text)
    if m:
        project_id = detect_project_from_key(prefix_hint, projects, default_id)
        found[key_name] = (m.group(0), project_id, label)

# Step 3: Supabase JWTs — decode to name correctly
for m in re.finditer(
    r'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9\.[A-Za-z0-9._-]{60,}', text
):
    token = m.group(0)
    role = decode_jwt_role(token)
    key_name = ('SUPABASE_SERVICE_ROLE_KEY' if role == 'service_role'
                else 'SUPABASE_ANON_KEY')
    if key_name not in found:
        # Detect project from context text
        ctx = text.lower()
        # Try to match against configured project dirs/names
        matched_id = default_id
        for proj in projects:
            proj_dir_lower = proj.get('dir', '').lower()
            proj_name_lower = proj.get('name', '').lower()
            proj_id_lower   = proj.get('id',   '').lower()
            if any(part in ctx for part in [proj_id_lower, proj_name_lower]):
                matched_id = proj['id']
                break
        found[key_name] = (token, matched_id, f'Supabase JWT (role={role})')

# Step 4: High-entropy unknown strings
# Pure hex strings (0-9a-f only) have max entropy 4.0 but cluster around 3.5 in practice.
# Use a lower threshold for hex-only tokens to catch service keys like Deepgram, VOICE_API_SECRET.
if not found:
    candidates = re.findall(
        r'(?:=|:\s*|^|\s)["\']?([A-Za-z0-9+/=_\-\.]{32,})["\']?', text
    )
    SKIP = ['price_','prod_','example','placeholder','localhost','REDACTED','acct_']
    for token in candidates:
        if any(s in token for s in SKIP): continue
        e = shannon_entropy(token)
        is_hex = bool(re.fullmatch(r'[0-9a-f]+', token))
        threshold = 3.4 if is_hex else 3.8
        if e > threshold:
            found['UNKNOWN_SECRET'] = (
                token, default_id,
                f'high-entropy token ({shannon_entropy(token):.1f} bits)'
            )
            break

# Output — emit keychain_service (not raw project id) so bash layer can use it directly
for key_name, (val, project_id, label) in found.items():
    service = get_keychain_service(project_id, projects, default_id)
    proj_dir = get_project_dir(project_id, projects)
    safe = val.replace('\\', '\\\\').replace('|', '\\|')
    print(f"STORE|{key_name}|{safe}|{service}|{label}|{proj_dir}")
PYEOF
)

[ -z "$DETECTIONS" ] && exit 0

# ── Store everything detected ─────────────────────────────────────────────────
STORED=()
FAILED=()

while IFS='|' read -r action key_name value service label proj_dir; do
    [ "$action" != "STORE" ] && continue
    [ -z "$key_name" ] || [ -z "$value" ] && continue

    if security add-generic-password -U -s "$service" -a "$key_name" -w "$value" 2>/dev/null; then
        STORED+=("$key_name → [$service]  ($label)")

        if [ -n "$proj_dir" ] && [ -d "$proj_dir" ]; then
            KEYS_FILE="$proj_dir/.env.keys"
            touch "$KEYS_FILE"
            grep -qx "$key_name" "$KEYS_FILE" 2>/dev/null || echo "$key_name" >> "$KEYS_FILE"
        fi
    else
        FAILED+=("$key_name  [Keychain denied]")
    fi
done <<< "$DETECTIONS"

[ ${#STORED[@]} -eq 0 ] && [ ${#FAILED[@]} -eq 0 ] && exit 0

# ── Print result box ──────────────────────────────────────────────────────────
W=66
div() { printf "╠%${W}s╣\n" | tr ' ' '═'; }
top() { printf "╔%${W}s╗\n" | tr ' ' '═'; }
bot() { printf "╚%${W}s╝\n" | tr ' ' '═'; }
row() { printf "║  %-$((W-2))s║\n" "$1"; }

echo ""
top
row "AUTO-VAULT — INTERCEPTED & STORED TO KEYCHAIN"
div
row ""
if [ ${#STORED[@]} -gt 0 ]; then
    row "✓ Stored:"
    for s in "${STORED[@]}"; do row "  $s"; done
    row ""
fi
if [ ${#FAILED[@]} -gt 0 ]; then
    row "✗ Failed (Keychain denied):"
    for f in "${FAILED[@]}"; do row "  $f"; done
    row ""
fi
div
row "Message blocked — values never reached Anthropic."
row "Now tell Claude: 'Keys are stored. [describe task]'"
bot
echo ""
exit 2
