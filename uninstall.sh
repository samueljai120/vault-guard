#!/usr/bin/env bash
# CLS Vault Guard — uninstall.sh
# Removes hooks, bin commands, and hook entries from Claude settings.
# Leaves ~/.vaultguard.json intact (your personal config).
# Usage: bash uninstall.sh

set -euo pipefail

CLAUDE_HOOKS_DIR="$HOME/.claude/hooks"
BIN_DIR="$HOME/bin"
CLAUDE_SETTINGS="$HOME/.claude/settings.local.json"
VAULTGUARD_CONFIG="$HOME/.vaultguard.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

separator() { printf '%s\n' "────────────────────────────────────────"; }

echo ""
echo -e "${BOLD}  CLS Vault Guard — Uninstaller${RESET}"
separator
echo ""

# ── 1. Remove hook files ──────────────────────────────────────────────────────
VG_HOOKS=(
  "credential-scanner.sh"
  "auto-store-secrets.sh"
  "output-redactor.sh"
  "history-scrubber.sh"
)

REMOVED_HOOKS=0
for hook in "${VG_HOOKS[@]}"; do
  target="$CLAUDE_HOOKS_DIR/$hook"
  if [ -f "$target" ]; then
    rm -f "$target"
    echo -e "${GREEN}  [−] Removed $target${RESET}"
    ((REMOVED_HOOKS++)) || true
  fi
done
[ "$REMOVED_HOOKS" -eq 0 ] && echo -e "${CYAN}  [=] No hook files found to remove${RESET}"

# ── 2. Remove hook entries from ~/.claude/settings.local.json ────────────────
VG_COMMANDS=(
  "bash $CLAUDE_HOOKS_DIR/credential-scanner.sh"
  "bash $CLAUDE_HOOKS_DIR/auto-store-secrets.sh"
  "bash $CLAUDE_HOOKS_DIR/output-redactor.sh"
  "bash $CLAUDE_HOOKS_DIR/history-scrubber.sh"
)

if [ -f "$CLAUDE_SETTINGS" ]; then
  CMD_LIST_JSON=$(printf '%s\n' "${VG_COMMANDS[@]}" | python3 -c "
import sys, json
cmds = [line.strip() for line in sys.stdin if line.strip()]
print(json.dumps(cmds))
")
  python3 - "$CLAUDE_SETTINGS" "$CMD_LIST_JSON" <<'PYEOF'
import sys, json

settings_path = sys.argv[1]
remove_cmds = set(json.loads(sys.argv[2]))

with open(settings_path) as f:
    try:
        settings = json.load(f)
    except json.JSONDecodeError:
        settings = {}

hooks = settings.get("hooks", {})

def strip_vg_entries(entry_list):
    kept = []
    for entry in entry_list:
        filtered = [h for h in entry.get("hooks", []) if h.get("command", "") not in remove_cmds]
        if filtered:
            kept.append({**entry, "hooks": filtered})
    return kept

for event in list(hooks.keys()):
    hooks[event] = strip_vg_entries(hooks[event])
    if not hooks[event]:
        del hooks[event]

if hooks:
    settings["hooks"] = hooks
elif "hooks" in settings:
    del settings["hooks"]

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYEOF
  echo -e "${GREEN}  [−] Removed Vault Guard hook entries from $CLAUDE_SETTINGS${RESET}"
else
  echo -e "${CYAN}  [=] $CLAUDE_SETTINGS not found — nothing to patch${RESET}"
fi

# ── 3. Remove bin commands ────────────────────────────────────────────────────
for bin_cmd in vault-guard vg; do
  target="$BIN_DIR/$bin_cmd"
  if [ -f "$target" ] || [ -L "$target" ]; then
    rm -f "$target"
    echo -e "${GREEN}  [−] Removed $target${RESET}"
  fi
done

# ── 4. Note about config ──────────────────────────────────────────────────────
echo ""
if [ -f "$VAULTGUARD_CONFIG" ]; then
  echo -e "${YELLOW}  [i] $VAULTGUARD_CONFIG was left intact.${RESET}"
  echo -e "      Remove manually if no longer needed: rm $VAULTGUARD_CONFIG"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Uninstall complete.${RESET}"
echo ""
echo -e "  Vault Guard hooks and CLI have been removed."
echo -e "  ${YELLOW}Restart Claude Code to deactivate hooks.${RESET}"
separator
echo ""
