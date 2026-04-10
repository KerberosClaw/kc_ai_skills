#!/bin/bash
# run_banini.sh — wrapper for launchd to run banini cron jobs
# Usage: run_banini.sh <job_id> [--weekday-only]

JOB_ID="${1:-banini}"
WEEKDAY_ONLY="${2:-}"

# Skip weekends if --weekday-only
if [ "$WEEKDAY_ONLY" = "--weekday-only" ]; then
    DOW=$(date +%u)  # 1=Mon ... 7=Sun
    if [ "$DOW" -gt 5 ]; then
        exit 0
    fi
fi

PROMPT='Run python3 ~/.claude/skills/banini/scripts/scrape_threads.py banini31 5, parse the JSON output, then perform 反指標 contrarian analysis on the posts following these rules: 買入=可能跌, 停損=可能反彈, 被套=續跌, 看多=可能跌, 看空=可能漲, 買put=可能飆漲. Output a structured report in Traditional Chinese with 提及標的, 連鎖推導, 建議方向, and 冥燈指數. End with 僅供娛樂參考，不構成投資建議.'

exec /Users/otakubear/.claude/skills/skill-cron/scripts/cron_runner.sh "$PROMPT" "$JOB_ID"
