#!/usr/bin/env bash
# CLS Vault Guard — install.sh
# Idempotent: safe to run multiple times.
# Usage: bash install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_SRC="$REPO_DIR/hooks"
BIN_SRC="$REPO_DIR/bin"
CLAUDE_HOOKS_DIR="$HOME/.claude/hooks"
BIN_DIR="$HOME/bin"
VAULTGUARD_CONFIG="$HOME/.vaultguard.json"
CLAUDE_SETTINGS="$HOME/.claude/settings.local.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

separator() { printf '%s\n' "────────────────────────────────────────"; }

echo ""
echo -e "${BOLD}  CLS Vault Guard — Installer${RESET}"
separator
echo ""

# ── 1. Create ~/.claude/hooks/ ──────────────────────────────────────────────
if [ ! -d "$CLAUDE_HOOKS_DIR" ]; then
  mkdir -p "$CLAUDE_HOOKS_DIR"
  echo -e "${GREEN}  [+] Created $CLAUDE_HOOKS_DIR${RESET}"
else
  echo -e "${CYAN}  [=] $CLAUDE_HOOKS_DIR already exists${RESET}"
fi

# ── 2. Copy hooks ────────────────────────────────────────────────────────────
HOOKS=(credential-scanner.sh auto-store-secrets.sh output-redactor.sh history-scrubber.sh)
for hook in "${HOOKS[@]}"; do
  src="$HOOKS_SRC/$hook"
  if [ -f "$src" ]; then
    cp -f "$src" "$CLAUDE_HOOKS_DIR/"
    chmod +x "$CLAUDE_HOOKS_DIR/$hook"
    echo -e "${GREEN}  [+] Installed hook: $hook${RESET}"
  else
    echo -e "${YELLOW}  [!] Hook not found: $hook — skipping${RESET}"
  fi
done

# ── 3. Create ~/bin/ ─────────────────────────────────────────────────────────
if [ ! -d "$BIN_DIR" ]; then
  mkdir -p "$BIN_DIR"
  echo -e "${GREEN}  [+] Created $BIN_DIR${RESET}"
else
  echo -e "${CYAN}  [=] $BIN_DIR already exists${RESET}"
fi

# ── 4. Install vault-guard CLI ────────────────────────────────────────────────
if [ -f "$BIN_SRC/vault-guard" ]; then
  cp -f "$BIN_SRC/vault-guard" "$BIN_DIR/vault-guard"
  chmod +x "$BIN_DIR/vault-guard"
  # Also add short alias
  ln -sf "$BIN_DIR/vault-guard" "$BIN_DIR/vg" 2>/dev/null || cp -f "$BIN_DIR/vault-guard" "$BIN_DIR/vg"
  chmod +x "$BIN_DIR/vg"
  echo -e "${GREEN}  [+] Installed vault-guard CLI → $BIN_DIR/vault-guard (alias: vg)${RESET}"
fi

# ── 5. Add ~/bin to PATH in ~/.zshrc ─────────────────────────────────────────
ZSHRC="$HOME/.zshrc"
[ ! -f "$ZSHRC" ] && touch "$ZSHRC"
if grep -qF 'HOME/bin' "$ZSHRC"; then
  echo -e "${CYAN}  [=] ~/bin already in PATH ($ZSHRC)${RESET}"
else
  echo "" >> "$ZSHRC"
  echo "# Added by CLS Vault Guard" >> "$ZSHRC"
  echo 'export PATH="$HOME/bin:$PATH"' >> "$ZSHRC"
  echo -e "${GREEN}  [+] Added ~/bin to PATH in $ZSHRC${RESET}"
fi

# ── 6. Create default ~/.vaultguard.json if absent ──────────────────────────
if [ ! -f "$VAULTGUARD_CONFIG" ]; then
  cat > "$VAULTGUARD_CONFIG" <<'EOF'
{
  "version": "1",
  "projects": [
    {
      "id": "my-project",
      "name": "My Project",
      "keychain_service": "my-project",
      "dir": "~/Documents/my-project",
      "key_prefixes": ["OPENAI_", "STRIPE_", "GITHUB_"]
    }
  ],
  "default_project": "my-project"
}
EOF
  echo -e "${GREEN}  [+] Created default config at $VAULTGUARD_CONFIG${RESET}"
  echo -e "${YELLOW}  [!] Edit $VAULTGUARD_CONFIG to add your project(s).${RESET}"
else
  echo -e "${CYAN}  [=] $VAULTGUARD_CONFIG already exists — not overwritten${RESET}"
fi

# ── 7. Patch ~/.claude/settings.local.json to register all 4 hooks ───────────
if [ ! -f "$CLAUDE_SETTINGS" ]; then
  mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
  echo '{}' > "$CLAUDE_SETTINGS"
  echo -e "${GREEN}  [+] Created $CLAUDE_SETTINGS${RESET}"
fi

python3 - "$CLAUDE_SETTINGS" "$CLAUDE_HOOKS_DIR" <<'PYEOF'
import sys, json

settings_path = sys.argv[1]
hooks_dir     = sys.argv[2]

with open(settings_path) as f:
    try:
        settings = json.load(f)
    except json.JSONDecodeError:
        settings = {}

existing = settings.get("hooks", {})

def has_command(hook_list, cmd):
    for entry in hook_list:
        for h in entry.get("hooks", []):
            if h.get("command", "") == cmd:
                return True
    return False

def ensure_hook(event, entry):
    cmds = [h.get("command","") for h in entry.get("hooks",[])]
    for cmd in cmds:
        if not has_command(existing.get(event, []), cmd):
            existing.setdefault(event, []).append(entry)
            return

ensure_hook("UserPromptSubmit", {
    "hooks": [{"type": "command", "command": f"bash {hooks_dir}/credential-scanner.sh"}]
})
ensure_hook("PostToolUse", {
    "matcher": "Bash",
    "hooks": [{"type": "command", "command": f"bash {hooks_dir}/output-redactor.sh"}]
})
ensure_hook("PostToolUse", {
    "matcher": "Write|Edit",
    "hooks": [{"type": "command", "command": f"bash {hooks_dir}/auto-store-secrets.sh"}]
})
ensure_hook("Stop", {
    "hooks": [{"type": "command", "command": f"bash {hooks_dir}/history-scrubber.sh"}]
})

settings["hooks"] = existing

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("  Hooks registered in settings.local.json")
PYEOF

echo -e "${GREEN}  [+] Patched $CLAUDE_SETTINGS with all 4 hooks${RESET}"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Install complete.${RESET}"
echo ""
echo -e "  Hooks installed to : ${CYAN}$CLAUDE_HOOKS_DIR${RESET}"
echo -e "  CLI commands       : ${CYAN}vault-guard${RESET} / ${CYAN}vg${RESET}  (restart shell first)"
echo -e "  Config file        : ${CYAN}$VAULTGUARD_CONFIG${RESET}"
echo -e "  Claude settings    : ${CYAN}$CLAUDE_SETTINGS${RESET}"
echo ""
echo -e "  ${YELLOW}Restart Claude Code to activate hooks.${RESET}"
echo ""
echo -e "  Quick test: ${CYAN}vault-guard test${RESET}"
echo -e "  Check status: ${CYAN}vault-guard status${RESET}"
separator
echo ""
