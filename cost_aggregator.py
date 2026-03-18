#!/usr/bin/env python3
"""Aggregate Claude Code session costs from JSONL files.
Uses Claude Code's internal pricing formula (verified from cli.js source).
Outputs JSON to stdout."""

import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timezone

# Claude Code internal pricing (per million tokens, USD)
# Source: cli.js - Jv5/Mv5/BJ6 functions
PRICING = {
    # n98 - Haiku 3.5
    "claude-3-5-haiku": {"input": 0.8, "output": 4, "cache_w": 1, "cache_r": 0.08},
    # r98 - Haiku 4.5
    "claude-haiku-4-5": {"input": 1, "output": 5, "cache_w": 1.25, "cache_r": 0.1},
    # SQ - Sonnet (≤200k)
    "claude-sonnet": {"input": 3, "output": 15, "cache_w": 3.75, "cache_r": 0.3},
    # SY1 - Sonnet (>200k)
    "claude-sonnet-extended": {"input": 6, "output": 22.5, "cache_w": 7.5, "cache_r": 0.6},
    # FO7 - Opus 4, Opus 4.1
    "claude-opus-4-old": {"input": 15, "output": 75, "cache_w": 18.75, "cache_r": 1.5},
    # CI6 - Opus 4.5+ (≤200k)
    "claude-opus": {"input": 5, "output": 25, "cache_w": 6.25, "cache_r": 0.5},
    # dO7 - Opus 4.5+ (>200k)
    "claude-opus-extended": {"input": 10, "output": 37.5, "cache_w": 12.5, "cache_r": 1},
}

def get_pricing(model: str, context_tokens: int) -> dict:
    is_extended = context_tokens > 200000
    if "haiku-4-5" in model or "haiku-4.5" in model:
        return PRICING["claude-haiku-4-5"]
    if "3-5-haiku" in model or "3.5-haiku" in model:
        return PRICING["claude-3-5-haiku"]
    if "sonnet" in model:
        return PRICING["claude-sonnet-extended"] if is_extended else PRICING["claude-sonnet"]
    if "opus-4-1" in model or "opus-4-0" in model or "opus-4-20" in model:
        return PRICING["claude-opus-4-old"]
    if "opus" in model:
        return PRICING["claude-opus-extended"] if is_extended else PRICING["claude-opus"]
    # Default to opus pricing
    return PRICING["claude-opus-extended"] if is_extended else PRICING["claude-opus"]


def calc_cost(entry: dict) -> float:
    ctx = entry["input"] + entry["cache_r"] + entry["cache_w"]
    p = get_pricing(entry["model"], ctx)
    return (
        entry["input"] * p["input"]
        + entry["output"] * p["output"]
        + entry["cache_w"] * p["cache_w"]
        + entry["cache_r"] * p["cache_r"]
    ) / 1_000_000


def scan_session(filepath: str) -> dict:
    """Returns {date_str: cost} for a session file."""
    msg_groups = defaultdict(list)

    try:
        with open(filepath) as f:
            for line in f:
                if '"type":"assistant"' not in line and '"type": "assistant"' not in line:
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                if d.get("type") != "assistant":
                    continue
                msg = d.get("message", {})
                usage = msg.get("usage", {})
                if not usage:
                    continue

                msg_id = msg.get("id", "")
                req_id = d.get("requestId", "")
                key = f"{msg_id}:{req_id}"
                ts = d.get("timestamp", "")

                msg_groups[key].append({
                    "stop_reason": msg.get("stop_reason"),
                    "model": msg.get("model", ""),
                    "input": usage.get("input_tokens", 0),
                    "output": usage.get("output_tokens", 0),
                    "cache_w": usage.get("cache_creation_input_tokens", 0),
                    "cache_r": usage.get("cache_read_input_tokens", 0),
                    "day": ts[:10] if ts else "unknown",
                })
    except Exception:
        return {}

    daily = {}
    for entries in msg_groups.values():
        # Only count final entries (stop_reason is set = response complete)
        finals = [e for e in entries if e["stop_reason"] is not None]
        if not finals:
            finals = [entries[-1]]
        for e in finals:
            cost = calc_cost(e)
            day = e["day"]
            daily[day] = daily.get(day, 0) + cost

    return daily


def main():
    now = datetime.now(timezone.utc)
    today_str = now.strftime("%Y-%m-%d")
    month_prefix = now.strftime("%Y-%m")
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    cutoff_ts = month_start.timestamp()

    base_dirs = [
        os.path.expanduser("~/.claude/projects/"),
        os.path.expanduser("~/.config/claude/projects/"),
    ]

    today_cost = 0.0
    month_cost = 0.0

    for base in base_dirs:
        if not os.path.isdir(base):
            continue
        for root, dirs, files in os.walk(base):
            for fn in files:
                if not fn.endswith(".jsonl"):
                    continue
                fp = os.path.join(root, fn)
                try:
                    if os.path.getmtime(fp) < cutoff_ts:
                        continue
                except Exception:
                    continue
                daily = scan_session(fp)
                for day, cost in daily.items():
                    if day == today_str:
                        today_cost += cost
                    if day.startswith(month_prefix):
                        month_cost += cost

    result = {
        "today_cost_usd": round(today_cost, 2),
        "month_cost_usd": round(month_cost, 2),
        "date": today_str,
        "month": month_prefix,
    }
    json.dump(result, sys.stdout)


if __name__ == "__main__":
    main()
