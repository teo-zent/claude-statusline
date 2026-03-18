# claude-statusline

A real-time status line for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows context usage, account quota, and cost — all in your terminal.

```
░░░░░░░░░░ 4% | 40k/1M | $1.53 | Opus 4.6 | 5h ░░░░░░░░░░ 5% (→ 4h 28m) | 7d ██▒▒▒░░░░░ 24% + rsv 29% (→ 3d 7h) | today $65.01 · month $495.23 | ~/my-project
```

## What it shows

| Section | Description | Source |
|---------|-------------|--------|
| `░░░░░░░░░░ 4%` | Context window usage with color-coded progress bar | Session (stdin JSON) |
| `40k/1M` | Tokens used / context window size | Session |
| `$1.53` | Current session cost | Session |
| `Opus 4.6` | Active model | Session |
| `5h ░░░░░░░░░░ 5% (→ 4h 28m)` | 5-hour quota usage + time until reset | Account (OAuth API) |
| `7d ██▒▒▒░░░░░ 24% + rsv 29% (→ 3d 7h)` | 7-day quota + reserve + reset timer | Account (OAuth API) |
| `today $65.01 · month $495.23` | Estimated cost: today / this month | Local JSONL logs |
| `~/my-project` | Current working directory | Session |

### Color coding

The progress bars change color based on usage:

- **Green** — under 70%
- **Yellow** — 70–90%
- **Red** — over 90%

### Quota bars explained

- `██` — actual usage
- `▒▒▒` — reserved (in-flight requests not yet completed)
- `░░░░░` — remaining capacity

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/teo-zent/claude-statusline/main/install.sh | bash
```

Then **restart Claude Code**.

## Requirements

| Requirement | Why | Check |
|-------------|-----|-------|
| **macOS** | Uses `security` (keychain) and BSD `date` | `uname` = Darwin |
| **Claude Code** | The CLI this extends | `claude --version` |
| **jq** | Parses JSON in the status line script | `brew install jq` |
| **python3** | Runs the cost aggregator | Pre-installed on macOS |
| **OAuth login** | Required for 5h/7d quota display | `claude auth` |

> The installer checks all of these and will guide you if anything is missing.

### OAuth setup (for quota display)

If you haven't authenticated Claude Code via OAuth yet:

```bash
claude auth
```

This stores an OAuth token in your macOS Keychain. The status line reads it to fetch your account's 5-hour and 7-day quota usage from the Anthropic API.

**Without OAuth:** Everything works except the 5h/7d quota section, which will show `5h/7d: unavailable`.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/teo-zent/claude-statusline/main/uninstall.sh | bash
```

## How it works

### Architecture

```
Claude Code
    │
    ├─ stdin JSON ──▶ statusline.sh ──▶ terminal status bar
    │                     │
    │                     ├─ OAuth API (cached 3min) ──▶ 5h/7d quota
    │                     └─ cost_aggregator.py (cached 3min) ──▶ today/month cost
    │
    └─ ~/.claude/projects/**/*.jsonl ──▶ cost_aggregator.py
```

### Status line data

Claude Code sends a JSON payload to the status line script via stdin after each assistant response. This includes session cost, context window usage, model info, etc.

### Quota API

The script reads your OAuth token from the macOS Keychain and calls:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <token>
```

This returns your account-level 5-hour and 7-day quota utilization. Results are cached for 3 minutes to avoid rate limits.

### Cost calculation

The cost aggregator scans `~/.claude/projects/**/*.jsonl` session logs and calculates costs using **the same pricing formula as Claude Code itself** (verified from `cli.js` source):

```
cost = input_tokens/1M * inputRate
     + output_tokens/1M * outputRate
     + cache_creation_tokens/1M * cacheWriteRate
     + cache_read_tokens/1M * cacheReadRate
```

Pricing varies by model and context size (>200k tokens triggers higher rates). Streaming duplicate entries are deduplicated. Subagent costs are included.

> **Note:** Cost figures are estimates based on API pricing. Max/Pro subscribers pay a flat subscription fee — these numbers show what the equivalent API usage would cost.

## File structure

```
~/.claude/
├── settings.json              # statusLine config (auto-configured by installer)
└── statusline/
    ├── statusline.sh          # main script (runs after each response)
    └── cost_aggregator.py     # scans JSONL logs for daily/monthly cost
```

Cache files (auto-created in `/tmp/`, cleared on reboot):

```
/tmp/claude_quota_cache.json   # 5h/7d quota (refreshed every 3min)
/tmp/claude_cost_cache.json    # today/month cost (refreshed every 3min)
```

## Troubleshooting

### Status line not showing

1. Make sure `~/.claude/settings.json` contains the `statusLine` config:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline/statusline.sh",
       "padding": 2
     }
   }
   ```
2. Restart Claude Code.

### `5h/7d: unavailable`

- Run `claude auth` to set up OAuth credentials.
- The API may be temporarily rate-limited. It will recover automatically within 3 minutes.

### `5h/7d: loading...`

Normal on first launch. The quota data is fetched in the background and will appear after the next response.

### Cost shows $0.00

The cost aggregator only scans session files modified this month. If you haven't used Claude Code this month yet, it will show $0.

## License

MIT
