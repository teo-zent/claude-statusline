#!/bin/bash
input=$(cat)

# === Session-level info (from stdin JSON) ===
MODEL=$(echo "$input" | jq -r '.model.display_name // "?"')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
CWD=$(echo "$input" | jq -r '.workspace.current_dir // "?"')

COST_FMT=$(printf '$%.2f' "$COST")
USED_TOKENS=$((CONTEXT_SIZE * PCT / 100))

# Format token count
fmt_tokens() {
  local n=$1
  if [ "$n" -ge 1000000 ]; then
    awk "BEGIN {printf \"%.1fM\", $n/1000000}"
  elif [ "$n" -ge 1000 ]; then
    awk "BEGIN {printf \"%.1fk\", $n/1000}"
  else
    echo "$n"
  fi
}

TOKENS_FMT=$(fmt_tokens "$USED_TOKENS")
SIZE_FMT=$(fmt_tokens "$CONTEXT_SIZE")

# Color based on context usage
if [ "$PCT" -ge 90 ]; then COLOR='\033[31m'
elif [ "$PCT" -ge 70 ]; then COLOR='\033[33m'
else COLOR='\033[32m'; fi
RST='\033[0m'
DIM='\033[2m'

# Progress bar helper
make_bar() {
  local width=$1 filled=$2 reserve=${3:-0} bar=""
  local empty=$((width - filled - reserve))
  [ "$empty" -lt 0 ] && empty=0
  [ "$filled" -gt 0 ] && printf -v f "%${filled}s" && bar="${f// /█}"
  [ "$reserve" -gt 0 ] && printf -v r "%${reserve}s" && bar="${bar}${r// /▒}"
  [ "$empty" -gt 0 ] && printf -v e "%${empty}s" && bar="${bar}${e// /░}"
  echo "$bar"
}

# Context bar
CTX_BAR=$(make_bar 10 $((PCT * 10 / 100)))

# Shorten directory
SHORT_CWD=$(echo "$CWD" | awk -F/ '{if(NF<=3) print $0; else print "…/"$(NF-1)"/"$NF}')

# === Account-level quota (cached, refresh every 3 min) ===
CACHE_FILE="/tmp/claude_quota_cache.json"
CACHE_MAX_AGE=180  # 3 minutes

QUOTA_STR=""
fetch_quota() {
  local token
  token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('claudeAiOauth',{}).get('accessToken',''))" 2>/dev/null)
  [ -z "$token" ] && return 1

  umask 077
  curl -s --max-time 5 "https://api.anthropic.com/api/oauth/usage" \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" > "$CACHE_FILE" 2>/dev/null
}

# Check cache age and refresh if needed
need_refresh=true
if [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ]; then
  cache_age=$(( $(date +%s) - $(stat -f%m "$CACHE_FILE" 2>/dev/null || echo 0) ))
  [ "$cache_age" -lt "$CACHE_MAX_AGE" ] && need_refresh=false
fi

if $need_refresh; then
  fetch_quota &
  # Use stale cache if available, don't block
fi

# Parse quota cache
if [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ]; then
  has_error=$(jq -r '.error // empty' "$CACHE_FILE" 2>/dev/null)
  if [ -n "$has_error" ]; then
    QUOTA_STR="${DIM}5h/7d: unavailable${RST}"
  elif true; then
    # 5-hour window
    FIVE_H_PCT=$(jq -r '.five_hour.utilization // empty' "$CACHE_FILE" 2>/dev/null)
    FIVE_H_RESET=$(jq -r '.five_hour.resets_at // empty' "$CACHE_FILE" 2>/dev/null)

    # 7-day window
    SEVEN_D_PCT=$(jq -r '.seven_day.utilization // empty' "$CACHE_FILE" 2>/dev/null)
    SEVEN_D_RESET=$(jq -r '.seven_day.resets_at // empty' "$CACHE_FILE" 2>/dev/null)
    SEVEN_D_RSV=$(jq -r '.iguana_necktie.utilization // empty' "$CACHE_FILE" 2>/dev/null)

    # Format reset time as relative
    fmt_reset() {
      local reset_at=$1
      [ -z "$reset_at" ] && return
      local reset_epoch now_epoch diff_s
      reset_epoch=$(date -juf "%Y-%m-%dT%H:%M:%S" "${reset_at%%.*}" "+%s" 2>/dev/null || date -juf "%Y-%m-%dT%H:%M:%SZ" "${reset_at%%.*}" "+%s" 2>/dev/null)
      [ -z "$reset_epoch" ] && return
      now_epoch=$(date -u +%s)
      diff_s=$((reset_epoch - now_epoch))
      [ "$diff_s" -lt 0 ] && diff_s=0
      local days=$((diff_s / 86400))
      local hours=$(( (diff_s % 86400) / 3600 ))
      local mins=$(( (diff_s % 3600) / 60 ))
      if [ "$days" -gt 0 ]; then
        echo "${days}d ${hours}h"
      elif [ "$hours" -gt 0 ]; then
        echo "${hours}h ${mins}m"
      else
        echo "${mins}m"
      fi
    }

    # Build 5h section
    if [ -n "$FIVE_H_PCT" ]; then
      five_int=${FIVE_H_PCT%.*}
      five_bar=$(make_bar 10 $((five_int * 10 / 100)))
      five_reset=$(fmt_reset "$FIVE_H_RESET")
      if [ "$five_int" -ge 90 ]; then five_color='\033[31m'
      elif [ "$five_int" -ge 70 ]; then five_color='\033[33m'
      else five_color='\033[32m'; fi
      QUOTA_STR="${five_color}5h ${five_bar} ${five_int}%${RST}"
      [ -n "$five_reset" ] && QUOTA_STR="${QUOTA_STR} ${DIM}(→ ${five_reset})${RST}"
    fi

    # Build 7d section
    if [ -n "$SEVEN_D_PCT" ]; then
      seven_int=${SEVEN_D_PCT%.*}
      rsv_int=0
      [ -n "$SEVEN_D_RSV" ] && rsv_int=${SEVEN_D_RSV%.*}
      seven_filled=$((seven_int * 10 / 100))
      rsv_filled=$((rsv_int * 10 / 100))
      seven_bar=$(make_bar 10 "$seven_filled" "$rsv_filled")
      seven_reset=$(fmt_reset "$SEVEN_D_RESET")
      if [ "$seven_int" -ge 90 ]; then seven_color='\033[31m'
      elif [ "$seven_int" -ge 70 ]; then seven_color='\033[33m'
      else seven_color='\033[32m'; fi
      QUOTA_STR="${QUOTA_STR} | ${seven_color}7d ${seven_bar} ${seven_int}%${RST}"
      [ "$rsv_int" -gt 0 ] && QUOTA_STR="${QUOTA_STR} + rsv ${rsv_int}%"
      [ -n "$seven_reset" ] && QUOTA_STR="${QUOTA_STR} ${DIM}(→ ${seven_reset})${RST}"
    fi
  fi
fi

# No cache at all = first run or fetch in progress
if [ -z "$QUOTA_STR" ]; then
  QUOTA_STR="${DIM}5h/7d: loading...${RST}"
fi

# === Daily/Monthly cost (cached, refresh every 3 min) ===
COST_CACHE="/tmp/claude_cost_cache.json"
COST_STR=""
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || readlink "$0" 2>/dev/null || echo "$0")")" && pwd)"

cost_need_refresh=true
if [ -f "$COST_CACHE" ] && [ -s "$COST_CACHE" ]; then
  cost_cache_age=$(( $(date +%s) - $(stat -f%m "$COST_CACHE" 2>/dev/null || echo 0) ))
  [ "$cost_cache_age" -lt "$CACHE_MAX_AGE" ] && cost_need_refresh=false
fi

if $cost_need_refresh; then
  (umask 077; python3 "$SCRIPT_DIR/cost_aggregator.py" > "$COST_CACHE" 2>/dev/null) &
fi

if [ -f "$COST_CACHE" ] && [ -s "$COST_CACHE" ]; then
  TODAY_COST=$(jq -r '.today_cost_usd // empty' "$COST_CACHE" 2>/dev/null)
  MONTH_COST=$(jq -r '.month_cost_usd // empty' "$COST_CACHE" 2>/dev/null)
  if [ -n "$TODAY_COST" ]; then
    COST_STR="today \$${TODAY_COST} · month \$${MONTH_COST}"
  fi
fi

# === Output ===
LINE="${COLOR}${CTX_BAR}${RST} ${PCT}% | ${TOKENS_FMT}/${SIZE_FMT} | ${COST_FMT} | ${MODEL} | ${QUOTA_STR}"
[ -n "$COST_STR" ] && LINE="${LINE} | ${DIM}${COST_STR}${RST}"
LINE="${LINE} | ${SHORT_CWD}"

echo -e "$LINE"
