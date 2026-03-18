#!/usr/bin/env bash
# claude-statusline uninstaller
set -e

GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }

echo ""
echo "  claude-statusline uninstaller"
echo "  ─────────────────────────────"
echo ""

# Remove files
rm -rf "$HOME/.claude/statusline"
log "Removed ~/.claude/statusline/"

# Remove caches
rm -f /tmp/claude_quota_cache.json
rm -f /tmp/claude_cost_cache.json
log "Removed cache files"

# Remove statusLine from settings.json
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ] && grep -q "statusLine" "$SETTINGS" 2>/dev/null; then
  python3 -c "
import json
with open('$SETTINGS') as f:
    data = json.load(f)
data.pop('statusLine', None)
with open('$SETTINGS', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" && log "Removed statusLine from settings.json"
fi

echo ""
echo "  Uninstall complete. Restart Claude Code to apply."
echo ""
