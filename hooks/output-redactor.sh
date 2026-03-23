#!/usr/bin/env bash
# Claude Code — Output Redactor (PostToolUse hook)
#
# Scans Bash tool output for credentials before they're stored in history.
# Auto-stores found credentials to Keychain using ~/.vaultguard.json routing.

INPUT=$(cat)

TOOL=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name', '') or d.get('tool', ''))
except: print('')
" 2>/dev/null || true)

[[ "$TOOL" != "Bash" ]] && exit 0

OUTPUT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    r = d.get('tool_response', {}) or d.get('result', {}) or d.get('output', {})
    if isinstance(r, dict):
        print(r.get('output', '') or r.get('stdout', '') or r.get('content', ''))
    elif isinstance(r, str):
        print(r)
except: print('')
" 2>/dev/null || true)

[ -z "$OUTPUT" ] && exit 0

# ── Pattern check ─────────────────────────────────────────────────────────────
PATTERNS=(
    "sk-ant-api[0-9]+-[A-Za-z0-9_-]{20,}"
    "sk-or-v1-[a-f0-9]{20,}"
    "sk_live_[A-Za-z0-9]{20,}"
    "sk_test_[A-Za-z0-9]{20,}"
    "pk_live_[A-Za-z0-9]{20,}"
    "pk_test_[A-Za-z0-9]{20,}"
    "ghp_[A-Za-z0-9]{36,}"
    "gho_[A-Za-z0-9]{36,}"
    "AIzaSy[A-Za-z0-9_-]{33}"
    "re_[A-Za-z0-9]{20,}"
    "sk-proj-[A-Za-z0-9_-]{40,}"
    "whsec_[A-Za-z0-9+/=]{30,}"
    "KEY[0-9A-F]{16,}_[A-Za-z0-9_-]{10,}"
    "gsk_[A-Za-z0-9]{40,}"
    "rk_live_[A-Za-z0-9]{24,}"
    "github_pat_[A-Za-z0-9_]{80,}"
)

LEAKED=0
for pattern in "${PATTERNS[@]}"; do
    if echo "$OUTPUT" | grep -qE "$pattern" 2>/dev/null; then
        LEAKED=1; break
    fi
done

[ "$LEAKED" -eq 0 ] && exit 0

# ── Store credentials found in output using ~/.vaultguard.json routing ────────
STORED_FROM_OUTPUT=()

TMPFILE=$(mktemp /tmp/cls-output-XXXXXX)
trap 'rm -f "$TMPFILE"' EXIT
printf '%s' "$OUTPUT" > "$TMPFILE"

DETECTIONS=$(python3 - "$TMPFILE" "$HOME/.vaultguard.json" <<'PYEOF'
import re, sys, base64, json, os

def load_vaultguard_config(config_path):
    try:
        with open(os.path.expanduser(config_path), 'r') as f:
            cfg = json.load(f)
        return cfg.get('projects', []), cfg.get('default_project', 'vault-guard')
    except Exception:
        return [], 'vault-guard'

def detect_project_from_key(key_name, projects, default_id):
    for proj in projects:
        for prefix in proj.get('key_prefixes', []):
            if key_name.startswith(prefix):
                return proj['id']
    return default_id

def get_keychain_service(project_id, projects, default_id):
    for proj in projects:
        if proj['id'] == project_id:
            return proj.get('keychain_service', project_id)
    return project_id

with open(sys.argv[1], 'r', errors='replace') as f:
    text = f.read()

projects, default_id = load_vaultguard_config(sys.argv[2])

FINGERPRINTS = [
    (r'sk_live_[A-Za-z0-9]{24,}',             'STRIPE_SECRET_KEY'),
    (r'sk_test_[A-Za-z0-9]{24,}',             'STRIPE_TEST_SECRET_KEY'),
    (r'whsec_[A-Za-z0-9+/=]{30,}',            'STRIPE_WEBHOOK_SECRET'),
    (r'sk-ant-api[0-9]+-[A-Za-z0-9_-]{80,}',  'ANTHROPIC_API_KEY'),
    (r'sk-or-v1-[a-f0-9]{60,}',               'OPENROUTER_API_KEY'),
    (r'sk-proj-[A-Za-z0-9_-]{40,}',           'OPENAI_API_KEY'),
    (r'ghp_[A-Za-z0-9]{36,}',                 'GITHUB_TOKEN'),
    (r'gho_[A-Za-z0-9]{36,}',                 'GITHUB_OAUTH_TOKEN'),
    (r'AIzaSy[A-Za-z0-9_-]{33}',              'GEMINI_API_KEY'),
    (r're_[A-Za-z0-9]{20,}',                  'RESEND_API_KEY'),
    (r'gsk_[A-Za-z0-9]{40,}',                 'GROQ_API_KEY'),
    (r'rk_live_[A-Za-z0-9]{24,}',             'STRIPE_RESTRICTED_KEY'),
]

for pattern, key_name in FINGERPRINTS:
    m = re.search(pattern, text)
    if m:
        project_id = detect_project_from_key(key_name, projects, default_id)
        service = get_keychain_service(project_id, projects, default_id)
        safe = m.group(0).replace('\\', '\\\\').replace('|', '\\|')
        print(f"STORE|{key_name}|{safe}|{service}")
PYEOF
)

while IFS='|' read -r action key_name value service; do
    [ "$action" != "STORE" ] && continue
    if security add-generic-password -U -s "$service" -a "$key_name" -w "$value" 2>/dev/null; then
        STORED_FROM_OUTPUT+=("✓ $key_name → [$service]")
    fi
done <<< "$DETECTIONS"

# ── Scrub history ─────────────────────────────────────────────────────────────
LOG="$HOME/.claude/credential-leak.log"
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] credential in Bash output — auto-stored + history scrubbed" >> "$LOG"

HISTORY="$HOME/.claude/history.jsonl"
if [ -f "$HISTORY" ]; then
    SED_EXPR=""
    for pattern in "${PATTERNS[@]}"; do
        SED_EXPR="${SED_EXPR}s|${pattern}|[REDACTED]|g;"
    done
    sed -E "$SED_EXPR" "$HISTORY" > "${HISTORY}.tmp" 2>/dev/null && mv "${HISTORY}.tmp" "$HISTORY"
fi

echo "" >&2
echo "🔐 Auto-Vault: credential caught in Bash output" >&2
for item in "${STORED_FROM_OUTPUT[@]}"; do echo "   $item" >&2; done
echo "   History scrubbed." >&2
echo "" >&2

exit 0
