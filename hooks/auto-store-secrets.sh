#!/usr/bin/env bash
# Claude Code — Auto-Vault on File Write (PostToolUse: Write|Edit)
#
# Fires whenever Claude writes or edits ANY file.
# Detects credentials, stores to Keychain, redacts .env files.
# Project auto-detected from ~/.vaultguard.json.

# --- Parse file path from hook JSON input ---
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read(), strict=False)
    print(d.get('tool_input',{}).get('file_path','') or d.get('tool_input',{}).get('path',''))
except: print('')
" 2>/dev/null || true)

[ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ] && exit 0

# Skip system/build dirs
for skip in node_modules /.git/ /vendor/ /.cache/ /dist/ /__pycache__/; do
    [[ "$FILE_PATH" == *"$skip"* ]] && exit 0
done

# --- Is this a .env file (safe to redact in-place)? ---
IS_ENV_FILE=false
fname=$(basename "$FILE_PATH")
if [[ "$fname" == .env* || "$fname" == *.env || "$fname" == *.env.* ]]; then
    [[ "$fname" != ".envrc" && "$fname" != *.keys && "$fname" != *.template && "$fname" != *.example && "$fname" != *.sample ]] && IS_ENV_FILE=true
fi

# --- Smart credential extraction + project routing via ~/.vaultguard.json ---
TMPFILE=$(mktemp /tmp/cls-autovault-XXXXXX)
trap 'rm -f "$TMPFILE"' EXIT
cp "$FILE_PATH" "$TMPFILE"

DETECTIONS=$(python3 - "$TMPFILE" "$FILE_PATH" "$HOME/.vaultguard.json" <<'PYEOF'
import re, sys, base64, json, os, math

def load_vaultguard_config(config_path):
    try:
        with open(os.path.expanduser(config_path), 'r') as f:
            cfg = json.load(f)
        return cfg.get('projects', []), cfg.get('default_project', 'vault-guard')
    except Exception:
        return [], 'vault-guard'

def detect_project_from_key(key_name, file_path, projects, default_id):
    # 1. Try to match project dir against file path
    for proj in projects:
        proj_dir = os.path.expanduser(proj.get('dir', ''))
        if proj_dir and file_path.startswith(proj_dir):
            return proj['id']
    # 2. Try key prefix match
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

def get_project_dir(project_id, projects):
    for proj in projects:
        if proj['id'] == project_id:
            return os.path.expanduser(proj.get('dir', ''))
    return ''

file_path_in  = sys.argv[1]
orig_file     = sys.argv[2]
config_path   = sys.argv[3]

projects, default_id = load_vaultguard_config(config_path)

try:
    with open(file_path_in, 'r', errors='replace') as f:
        content = f.read()
except:
    sys.exit(0)

FINGERPRINTS = [
    (r'sk_live_[A-Za-z0-9]{24,}',             'STRIPE_SECRET_KEY'),
    (r'sk_test_[A-Za-z0-9]{24,}',             'STRIPE_TEST_SECRET_KEY'),
    (r'pk_live_[A-Za-z0-9]{24,}',             'STRIPE_PUBLISHABLE_KEY'),
    (r'pk_test_[A-Za-z0-9]{24,}',             'STRIPE_TEST_PUBLISHABLE_KEY'),
    (r'whsec_[A-Za-z0-9+/=]{30,}',            'STRIPE_WEBHOOK_SECRET'),
    (r'rk_live_[A-Za-z0-9]{24,}',             'STRIPE_RESTRICTED_KEY'),
    (r'sk-ant-api[0-9]+-[A-Za-z0-9_-]{80,}',  'ANTHROPIC_API_KEY'),
    (r'sk-or-v1-[a-f0-9]{60,}',               'OPENROUTER_API_KEY'),
    (r'sk-proj-[A-Za-z0-9_-]{40,}',           'OPENAI_API_KEY'),
    (r'ghp_[A-Za-z0-9]{36,}',                 'GITHUB_TOKEN'),
    (r'gho_[A-Za-z0-9]{36,}',                 'GITHUB_OAUTH_TOKEN'),
    (r'github_pat_[A-Za-z0-9_]{80,}',         'GITHUB_TOKEN'),
    (r'AIzaSy[A-Za-z0-9_-]{33}',              'GEMINI_API_KEY'),
    (r're_[A-Za-z0-9]{20,}',                  'RESEND_API_KEY'),
    (r'KEY[0-9A-F]{16,}_[A-Za-z0-9_-]{10,}',  'TELNYX_API_KEY'),
    (r'gsk_[A-Za-z0-9]{40,}',                 'GROQ_API_KEY'),
]

NON_SECRETS = {'true','false','null','none','undefined','development','production',
               'test','local','placeholder','your_key_here','stored-in-keychain'}

found = {}

# KEY=value (explicit name wins)
kv = re.compile(r'^\s*(?:export\s+)?([A-Z][A-Z0-9_]{2,})\s*=\s*["\']?([^\s"\'#\n]{8,})["\']?', re.MULTILINE)
for key, val in kv.findall(content):
    val = val.strip().strip('"').strip("'")
    if not val or val.lower() in NON_SECRETS: continue
    if re.match(r'^(https?|postgres(?:ql)?|redis|mysql|mongodb|amqp|smtp|ftp|s3)://', val): continue
    if re.match(r'^\d{1,5}$', val): continue
    if val.startswith('$') or 'keychain' in val.lower(): continue
    project_id = detect_project_from_key(key, orig_file, projects, default_id)
    found[key] = (val, project_id, 'KEY=value')

# Raw patterns
for pattern, key_name in FINGERPRINTS:
    if key_name in found: continue
    m = re.search(pattern, content)
    if m:
        project_id = detect_project_from_key(key_name, orig_file, projects, default_id)
        found[key_name] = (m.group(0), project_id, 'pattern match')

# Supabase JWTs
for m in re.finditer(r'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9\.[A-Za-z0-9._-]{60,}', content):
    token = m.group(0)
    try:
        payload = token.split('.')[1]
        payload += '=' * (4 - len(payload) % 4)
        role = json.loads(base64.b64decode(payload)).get('role', '')
    except:
        role = ''
    key_name = 'SUPABASE_SERVICE_ROLE_KEY' if role == 'service_role' else 'SUPABASE_ANON_KEY'
    if key_name not in found:
        project_id = detect_project_from_key(key_name, orig_file, projects, default_id)
        found[key_name] = (token, project_id, f'Supabase JWT ({role})')

for key_name, (val, project_id, source) in found.items():
    service = get_keychain_service(project_id, projects, default_id)
    proj_dir = get_project_dir(project_id, projects)
    safe = val.replace('\\', '\\\\').replace('|', '\\|')
    print(f"STORE|{key_name}|{safe}|{service}|{source}|{proj_dir}")
PYEOF
)

[ -z "$DETECTIONS" ] && exit 0

# --- Store + redact ---
STORED=()
KEYS_TO_REDACT=()

while IFS='|' read -r action key_name value service source proj_dir; do
    [ "$action" != "STORE" ] && continue
    [ -z "$key_name" ] || [ -z "$value" ] && continue

    if security add-generic-password -U -s "$service" -a "$key_name" -w "$value" 2>/dev/null; then
        STORED+=("✓ $key_name → [$service]")
        KEYS_TO_REDACT+=("$key_name")

        if [ -n "$proj_dir" ] && [ -d "$proj_dir" ]; then
            touch "$proj_dir/.env.keys"
            grep -qx "$key_name" "$proj_dir/.env.keys" 2>/dev/null || echo "$key_name" >> "$proj_dir/.env.keys"
        fi
    fi
done <<< "$DETECTIONS"

[ ${#STORED[@]} -eq 0 ] && exit 0

# --- Redact .env file in place ---
if [ "$IS_ENV_FILE" = true ]; then
    OUTFILE=$(mktemp)
    while IFS= read -r line || [ -n "$line" ]; do
        key="${line%%=*}"
        key=$(echo "$key" | xargs 2>/dev/null || true)
        if printf '%s\n' "${KEYS_TO_REDACT[@]}" | grep -qx "$key" 2>/dev/null; then
            echo "${key}=# stored-in-keychain"
        else
            echo "$line"
        fi
    done < "$FILE_PATH" > "$OUTFILE"
    mv "$OUTFILE" "$FILE_PATH"
fi

# --- Report ---
echo "" >&2
echo "🔐 Auto-Vault: ${#STORED[@]} credential(s) stored from $(basename "$FILE_PATH")" >&2
for item in "${STORED[@]}"; do echo "   $item" >&2; done
[ "$IS_ENV_FILE" = false ] && echo "   ⚠ Code file — stored but NOT redacted from source" >&2
echo "" >&2

exit 0
