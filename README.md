# claude-statusline

A real-time status line for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows context usage, account quota, and cost — all in your terminal.

![screenshot](assets/screenshot.png)

```
██░░░░░░░░ 19% | 190k/1M | $20.11 | Opus 4.6 | 5h ██░░░░░░░░ 21% (→ 2h 22m) | 7d ██░░░░░░░░ 25% (→ 3d 5h) | today $161.87 · month $536.37 | ~/my-project
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/teo-zent/claude-statusline/main/install.sh | bash
```

Then **restart Claude Code** (exit and reopen).

> **Note:** If you already have a `statusLine` config in `~/.claude/settings.json`, the installer will back it up to `settings.json.backup` before replacing it. All other settings (permissions, model, etc.) are preserved.

Works on any terminal — iTerm2, Terminal.app, VS Code, PyCharm, Warp, Alacritty, etc. The status line is rendered by Claude Code itself, so the terminal app doesn't matter.

## What each section means

### Context window — `░░░░░░░░░░ 4% | 40k/1M`

Claude keeps all previous messages in memory while answering. This is the **context window** — think of it as a conversation's battery indicator.

- `4%` = you've used 4% of the available space
- `40k/1M` = ~40,000 tokens used out of 1,000,000 max

**Why this matters:** When context fills up (~90%+), Claude starts compressing older messages and may lose context from earlier in the conversation. Watching this helps you know when to start a fresh session (`/clear`) instead of getting degraded responses.

The progress bar changes color as it fills:
- **Green** — under 70% (plenty of room)
- **Yellow** — 70–90% (getting full, consider starting fresh)
- **Red** — over 90% (context compression likely happening)

### Session cost — `$1.53`

How much this conversation has cost so far in API-equivalent pricing. Reported directly by Claude Code's internal cost tracker.

> For Max/Pro subscribers this is not actual billing — you pay a flat subscription. This shows what the equivalent API usage would cost.

### Model — `Opus 4.6`

Which Claude model is active. Useful for catching accidental model switches (e.g., `/model` changed to Haiku when you expected Opus).

### 5-hour quota — `5h ░░░░░░░░░░ 5% (→ 4h 28m)`

Claude Max/Pro has a **rolling 5-hour usage window**. If you use too much within 5 hours, you'll hit rate limits and get slower responses.

- `5%` = you've used 5% of your 5-hour allowance
- `(→ 4h 28m)` = the current window resets in 4 hours 28 minutes

This is **account-level** — reflects total usage across all your devices and sessions.

### 7-day quota — `7d ██▒▒▒░░░░░ 24% + rsv 29% (→ 3d 7h)`

A rolling **7-day usage cap** for your subscription tier.

- `██` (filled blocks) = actual usage (24%)
- `▒▒▒` (hatched blocks) = reserved — tokens claimed by in-flight requests that haven't completed yet
- `░░░░░` (empty blocks) = remaining capacity
- `+ rsv 29%` = 29% is reserved
- `(→ 3d 7h)` = resets in 3 days 7 hours

Also account-level. When this gets high, you may experience throttling.

### Daily/monthly cost — `today $65.01 · month $495.23`

Estimated cost from this Mac, calculated by scanning local session logs.

- `today` = sessions from today (UTC)
- `month` = sessions from the current calendar month

This is **per-device**, not per-account. Each machine tracks its own session files.

### Working directory — `~/my-project`

The directory Claude Code is operating in. Shows the last two path components to save space.

## Cost estimation methodology

The daily/monthly cost figures are calculated by scanning Claude Code's local session logs (`~/.claude/projects/**/*.jsonl`), using **the exact same pricing formula as Claude Code itself**.

This was verified by reverse-engineering [Claude Code's source](https://www.npmjs.com/package/@anthropic-ai/claude-code) (`cli.js`):

| Model | Input | Output | Cache Write | Cache Read |
|-------|------:|-------:|------------:|-----------:|
| Haiku 3.5 | $0.80/M | $4/M | $1/M | $0.08/M |
| Haiku 4.5 | $1/M | $5/M | $1.25/M | $0.10/M |
| Sonnet (≤200k context) | $3/M | $15/M | $3.75/M | $0.30/M |
| Sonnet (>200k context) | $6/M | $22.50/M | $7.50/M | $0.60/M |
| Opus 4, 4.1 | $15/M | $75/M | $18.75/M | $1.50/M |
| Opus 4.5+ (≤200k context) | $5/M | $25/M | $6.25/M | $0.50/M |
| Opus 4.5+ (>200k context) | $10/M | $37.50/M | $12.50/M | $1/M |

The formula:

```
cost = input_tokens/1M × inputRate
     + output_tokens/1M × outputRate
     + cache_creation_tokens/1M × cacheWriteRate
     + cache_read_tokens/1M × cacheReadRate
```

Key details:
- **Context-aware pricing**: When a single API call's context (`input + cache_read + cache_creation`) exceeds 200k tokens, higher rates apply
- **Streaming deduplication**: Only final responses are counted (partial streaming chunks are excluded)
- **Subagent costs included**: Agent tool spawns are tracked in separate JSONL files and included in totals

Verified accuracy: **<1% deviation** from Claude Code's internal `total_cost_usd` on a test session ($10.35 calculated vs $10.28 reported).

> These are API-equivalent estimates. Max/Pro subscribers pay a flat fee — these numbers help you understand your usage patterns, not your actual bill.

## Requirements

| Requirement | Why | How to get it |
|-------------|-----|---------------|
| **macOS** | Uses Keychain (`security`) and BSD `date`/`stat` | — |
| **Claude Code** | The CLI this extends | `npm install -g @anthropic-ai/claude-code` |
| **jq** | Parses JSON in the status line script | `brew install jq` |
| **python3** | Runs the cost aggregator | Pre-installed on macOS |
| **OAuth login** | Needed for 5h/7d quota display | Run `claude auth` |

> The installer checks all of these and guides you through anything missing.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/teo-zent/claude-statusline/main/uninstall.sh | bash
```

## How it works

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

- **statusline.sh** runs after each Claude response (~300ms debounced)
- **Quota API** calls are cached for 3 minutes and fetched in the background (non-blocking)
- **Cost aggregation** scans session JSONL files, also cached for 3 minutes in the background
- Cache files live in `/tmp/` and are cleared on reboot

## File structure

```
~/.claude/
├── settings.json              # statusLine config (auto-configured)
└── statusline/
    ├── statusline.sh          # main script
    └── cost_aggregator.py     # JSONL log scanner
```

## Troubleshooting

### Status line not showing

1. Check `~/.claude/settings.json` has the config:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline/statusline.sh",
       "padding": 2
     }
   }
   ```
2. Restart Claude Code (fully exit and reopen).

### `5h/7d: unavailable`

- Run `claude auth` to authenticate via OAuth.
- The Anthropic API may be temporarily rate-limited. It auto-recovers within 3 minutes.

### `5h/7d: loading...`

Normal on first launch. Quota data is fetched in the background and appears after the next Claude response.

### Cost shows $0.00

The aggregator only scans files modified this month. If this is your first session of the month, it will show the current session's accumulated cost after the next background refresh.

## License

MIT
