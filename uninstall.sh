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
  "vg_prompt_scan.py"
  "vg_bash_guard.py"
  "vg_write_intercept.py"
  "vg_session_audit.py"
)

REMOVED_HOOKS=0
for hook in "${VG_HOOKS[@]}"; do
  target="$CLAUDE_HOOKS_DIR/$hook"
  if [ -f "$target" ]; then
    rm -f "$target"
    echo -e "${GREEN}  [−] Removed $target${RESET}"
    REMOVED_HOOKS=$((REMOVED_HOOKS + 1))
  fi
done
if [ "$REMOVED_HOOKS" -eq 0 ]; then
  echo -e "${CYAN}  [=] No hook files found to remove${RESET}"
fi

# ── 2. Remove hook entries from ~/.claude/settings.local.json ────────────────
VG_COMMANDS=(
  "python3 ~/.claude/hooks/vg_prompt_scan.py"
  "python3 ~/.claude/hooks/vg_bash_guard.py"
  "python3 ~/.claude/hooks/vg_write_intercept.py"
  "python3 ~/.claude/hooks/vg_session_audit.py"
)

if [ -f "$CLAUDE_SETTINGS" ]; then
  # Build a JSON array of commands to remove
  CMD_LIST_JSON=$(printf '%s\n' "${VG_COMMANDS[@]}" | python3 -c "
import sys, json
cmds = [line.strip() for line in sys.stdin]
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
        filtered_hooks = [
            h for h in entry.get("hooks", [])
            if h.get("command", "") not in remove_cmds
        ]
        if filtered_hooks:
            new_entry = dict(entry)
            new_entry["hooks"] = filtered_hooks
            kept.append(new_entry)
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

# ── 3. Remove bin/vg ─────────────────────────────────────────────────────────
VG_BIN="$BIN_DIR/vg"
if [ -f "$VG_BIN" ]; then
  rm -f "$VG_BIN"
  echo -e "${GREEN}  [−] Removed $VG_BIN${RESET}"
else
  echo -e "${CYAN}  [=] $VG_BIN not found — nothing to remove${RESET}"
fi

# ── 4. Note about config ──────────────────────────────────────────────────────
echo ""
if [ -f "$VAULTGUARD_CONFIG" ]; then
  echo -e "${YELLOW}  [i] $VAULTGUARD_CONFIG was left intact.${RESET}"
  echo -e "      Remove it manually if you no longer need it:"
  echo -e "      rm $VAULTGUARD_CONFIG"
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
