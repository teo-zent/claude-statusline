#!/usr/bin/env bash
# claude-statusline installer
# Usage: curl -fsSL https://raw.githubusercontent.com/teo-zent/claude-statusline/main/install.sh | bash
set -e

REPO_RAW="https://raw.githubusercontent.com/teo-zent/claude-statusline/main"
INSTALL_DIR="$HOME/.claude/statusline"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; }

# --- Pre-flight checks ---
echo ""
echo "  claude-statusline installer"
echo "  ─────────────────────────────"
echo ""

# macOS check
if [[ "$(uname)" != "Darwin" ]]; then
  err "This tool is macOS only (uses security keychain + BSD date)."
  exit 1
fi

# Claude Code check
if ! command -v claude &>/dev/null; then
  err "Claude Code CLI not found."
  echo "  Install: npm install -g @anthropic-ai/claude-code"
  exit 1
fi
log "Claude Code found: $(claude --version 2>/dev/null || echo 'ok')"

# jq check
if ! command -v jq &>/dev/null; then
  if command -v brew &>/dev/null; then
    warn "jq not found. Installing via Homebrew..."
    brew install jq
  else
    err "jq not found. Install it first: brew install jq"
    exit 1
  fi
fi
log "jq found"

# python3 check
if ! command -v python3 &>/dev/null; then
  err "python3 not found. Install it first: brew install python3"
  exit 1
fi
log "python3 found"

# curl check
if ! command -v curl &>/dev/null; then
  err "curl not found."
  exit 1
fi

# OAuth check
if security find-generic-password -s "Claude Code-credentials" -w &>/dev/null; then
  log "OAuth credentials found in keychain"
else
  warn "OAuth credentials not found in keychain."
  echo "  Run: claude auth"
  echo "  Quota display (5h/7d) won't work without it."
  echo "  Other features will work fine."
  echo ""
fi

# --- Download files ---
log "Downloading files..."
mkdir -p "$INSTALL_DIR"

curl -fsSL "$REPO_RAW/statusline.sh" -o "$INSTALL_DIR/statusline.sh"
curl -fsSL "$REPO_RAW/cost_aggregator.py" -o "$INSTALL_DIR/cost_aggregator.py"

chmod +x "$INSTALL_DIR/statusline.sh"
chmod +x "$INSTALL_DIR/cost_aggregator.py"

log "Files installed to $INSTALL_DIR/"

# --- Configure settings.json ---
SETTINGS="$HOME/.claude/settings.json"
STATUSLINE_CMD="~/.claude/statusline/statusline.sh"

if [ -f "$SETTINGS" ]; then
  if grep -q "statusLine" "$SETTINGS" 2>/dev/null; then
    # Backup existing settings before overwriting statusLine
    cp "$SETTINGS" "${SETTINGS}.backup"
    warn "Existing statusLine config found — backed up to settings.json.backup"
    python3 -c "
import json
with open('$SETTINGS') as f:
    data = json.load(f)
data['statusLine'] = {'type': 'command', 'command': '$STATUSLINE_CMD', 'padding': 2}
with open('$SETTINGS', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" && log "Updated existing statusLine in settings.json"
  else
    # Add statusLine to existing settings
    python3 -c "
import json
with open('$SETTINGS') as f:
    data = json.load(f)
data['statusLine'] = {'type': 'command', 'command': '$STATUSLINE_CMD', 'padding': 2}
with open('$SETTINGS', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" && log "Added statusLine to settings.json"
  fi
else
  # Create new settings.json
  mkdir -p "$(dirname "$SETTINGS")"
  cat > "$SETTINGS" << EOF
{
  "statusLine": {
    "type": "command",
    "command": "$STATUSLINE_CMD",
    "padding": 2
  }
}
EOF
  log "Created settings.json"
fi

# --- Done ---
echo ""
echo "  ─────────────────────────────"
echo -e "  ${GREEN}Installation complete!${NC}"
echo ""
echo "  Restart Claude Code to see the status line."
echo ""
echo -e "  ${DIM}To uninstall: curl -fsSL $REPO_RAW/uninstall.sh | bash${NC}"
echo ""
