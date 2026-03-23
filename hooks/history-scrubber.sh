#!/usr/bin/env bash
# Claude Code — History Scrubber (Stop hook)
#
# Runs when a Claude Code session ends.
# Scans ~/.claude/history.jsonl and redacts any credential values found.
# Keeps the conversation structure intact — only blanks the secret values.

HISTORY="$HOME/.claude/history.jsonl"
BACKUP="$HOME/.claude/history.jsonl.bak"

[ ! -f "$HISTORY" ] && exit 0

# Patterns to redact — replaces matched value with [REDACTED]
PATTERNS=(
    "sk-ant-api[0-9]+-[A-Za-z0-9_-]{20,}"
    "sk-or-v1-[a-f0-9]{20,}"
    "sk_live_[A-Za-z0-9]{20,}"
    "sk_test_[A-Za-z0-9]{20,}"
    "pk_live_[A-Za-z0-9]{20,}"
    "pk_test_[A-Za-z0-9]{20,}"
    "ghp_[A-Za-z0-9]{35,}"
    "gho_[A-Za-z0-9]{35,}"
    "AIzaSy[A-Za-z0-9_-]{33}"
    "re_[A-Za-z0-9]{20,}"
    "sk-proj-[A-Za-z0-9_-]{40,}"
    "whsec_[A-Za-z0-9+/=]{30,}"
    "gsk_[A-Za-z0-9]{40,}"
    "rk_live_[A-Za-z0-9]{24,}"
    "KEY[0-9A-F]{16,}_[A-Za-z0-9_-]{10,}"
    "github_pat_[A-Za-z0-9_]{80,}"
)

# Build combined sed expression
SED_EXPR=""
for pattern in "${PATTERNS[@]}"; do
    SED_EXPR="${SED_EXPR}s|${pattern}|[REDACTED]|g;"
done

# Backup original
cp "$HISTORY" "$BACKUP" 2>/dev/null || true

# Apply redactions
if sed -E "$SED_EXPR" "$HISTORY" > "${HISTORY}.tmp" 2>/dev/null; then
    mv "${HISTORY}.tmp" "$HISTORY"
    # Count redactions made
    REDACTIONS=$(diff "$BACKUP" "$HISTORY" 2>/dev/null | grep -c "REDACTED" || true)
    if [ "$REDACTIONS" -gt 0 ]; then
        echo "[history-scrubber] Redacted $REDACTIONS credential(s) from history.jsonl" >&2
    fi
else
    rm -f "${HISTORY}.tmp"
fi

exit 0
