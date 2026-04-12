#!/bin/bash
# Run many experiments to find the fastest weblens configuration
# 2 tasks × 2 runs each = 4 calls per experiment

RUNS=2
TASK1="Go to https://example.com and tell me exactly what text is on the page."
TASK2="Go to https://news.ycombinator.com and tell me the titles of the top 3 stories."

run_experiment() {
  local NAME="$1"
  local PROMPT="$2"
  local T1_TOTAL=0
  local T2_TOTAL=0

  for run in $(seq 1 $RUNS); do
    # Task 1
    START=$(python3 -c "import time; print(time.time())")
    claude --dangerously-skip-permissions -p "$PROMPT $TASK1" --output-format text 2>&1 > /dev/null
    END=$(python3 -c "import time; print(time.time())")
    T=$(python3 -c "print(round($END - $START, 1))")
    T1_TOTAL=$(python3 -c "print($T1_TOTAL + $T)")

    # Task 2
    START=$(python3 -c "import time; print(time.time())")
    claude --dangerously-skip-permissions -p "$PROMPT $TASK2" --output-format text 2>&1 > /dev/null
    END=$(python3 -c "import time; print(time.time())")
    T=$(python3 -c "print(round($END - $START, 1))")
    T2_TOTAL=$(python3 -c "print($T2_TOTAL + $T)")
  done

  T1_AVG=$(python3 -c "print(round($T1_TOTAL / $RUNS, 1))")
  T2_AVG=$(python3 -c "print(round($T2_TOTAL / $RUNS, 1))")
  OVERALL=$(python3 -c "print(round(($T1_TOTAL + $T2_TOTAL) / ($RUNS * 2), 1))")

  echo "$NAME | $T1_AVG | $T2_AVG | $OVERALL" | tee -a experiment_results.txt
}

# Pre-warm daemon
weblens stop 2>/dev/null; pkill -f "bun.*daemon" 2>/dev/null; rm -f ~/.weblens/daemon.json; sleep 1
weblens --headless https://example.com > /dev/null 2>&1
echo "Daemon warm. Starting experiments..."
echo ""
echo "Experiment | example.com | HN | avg" | tee experiment_results.txt
echo "--- | --- | --- | ---" | tee -a experiment_results.txt

# === PROMPT EXPERIMENTS ===

# E1: Current v5 (plain text, weblens <url>)
run_experiment "E1_plaintext" \
  "Use 'weblens <url>' to read any webpage. It returns plain text with [ref=eN] IDs. To click: weblens do e5. To type: weblens do e5 --value 'text'."

# E2: Ultra-minimal prompt
run_experiment "E2_minimal" \
  "weblens <url> reads a webpage."

# E3: Directive prompt (tell model exactly what to run)
run_experiment "E3_directive" \
  "Run weblens <url> to read a page. Answer based on the output. Do not run any other commands unless the task requires clicking."

# E4: JSON output (old style - navigate + state)
run_experiment "E4_json_2step" \
  "You have 'weblens' CLI. Commands: navigate <url> (JSON), state (JSON page content), do <ref> (click). Use navigate then state to read a page."

# === OUTPUT FORMAT EXPERIMENTS ===

# E5: Depth-limited snapshot (depth=4)
run_experiment "E5_depth4" \
  "Run 'weblens navigate <url>' then 'weblens state --json | python3 -c \"import sys,json,requests; r=requests.get(\\\"http://127.0.0.1:\$(cat ~/.weblens/daemon.json | python3 -c \\\"import sys,json;print(json.load(sys.stdin)[\\\\\\\"port\\\\\\\"])\\\")/state?depth=4\\\"); print(r.json()[\\\"snapshot\\\"])\"' — actually just use 'weblens <url>' to read a page."

# Scratch that - E5 is too complex. Let me do it differently.
# For depth/limit tests, I'll modify the default command to use params.

# E6: Truncated to 3000 chars
run_experiment "E6_trunc3k" \
  "Run 'weblens <url> | head -c 3000' to read a webpage (truncated for speed). Answer from what you see."

# E7: Only interactive elements (grep for refs)
run_experiment "E7_interactive_only" \
  "Run 'weblens <url> | grep \"\\[e\"' to get interactive elements only. Answer from that."

# E8: Chrome MCP baseline
run_experiment "E8_chrome_mcp" \
  "Use the mcp__chrome-devtools tools to browse the web. First call mcp__chrome-devtools__new_page to open a tab. Then:"

echo ""
echo "=== DONE ==="
echo ""
cat experiment_results.txt
