#!/bin/bash
# Benchmark v4: 3 runs, averaged

TASKS=(
  "Go to https://example.com and tell me exactly what text is on the page."
  "Go to https://news.ycombinator.com and tell me the titles of the top 3 stories."
  "Go to https://en.wikipedia.org/wiki/Anthropic and tell me when the company was founded and who founded it."
  "Go to https://httpbin.org/forms/post and fill in the customer name field with 'Test User' and the telephone field with '555-1234'. Tell me what fields you see on the form."
  "Go to https://books.toscrape.com, tell me the title and price of the first book listed."
)
TASK_NAMES=("simple_read" "list_extraction" "wiki_lookup" "form_interaction" "scrape_data")
RUNS=3

echo "# Benchmark v4 — $RUNS runs averaged" | tee benchmark_v4_results.md
echo "Date: $(date)" | tee -a benchmark_v4_results.md

# Pre-warm weblens daemon
weblens stop 2>/dev/null; pkill -f "bun.*daemon" 2>/dev/null; rm -f ~/.weblens/daemon.json; sleep 1
weblens --headless navigate https://example.com 2>/dev/null
echo "Daemon warm." | tee -a benchmark_v4_results.md
echo "" | tee -a benchmark_v4_results.md

for i in "${!TASKS[@]}"; do
  TASK="${TASKS[$i]}"
  NAME="${TASK_NAMES[$i]}"
  echo "## $NAME" | tee -a benchmark_v4_results.md

  W_TOTAL=0
  C_TOTAL=0

  for run in $(seq 1 $RUNS); do
    # WEBLENS
    START=$(python3 -c "import time; print(time.time())")
    claude --dangerously-skip-permissions -p "weblens <url> reads a webpage. weblens do <ref> clicks. weblens do <ref> --value x types. $TASK" --output-format text 2>&1 > /dev/null
    END=$(python3 -c "import time; print(time.time())")
    W_TIME=$(python3 -c "print(round($END - $START, 1))")
    W_TOTAL=$(python3 -c "print($W_TOTAL + $W_TIME)")

    # CHROME MCP
    START=$(python3 -c "import time; print(time.time())")
    claude --dangerously-skip-permissions -p "Use the mcp__chrome-devtools tools to browse the web. First call mcp__chrome-devtools__new_page to open a tab. Then: $TASK" --output-format text 2>&1 > /dev/null
    END=$(python3 -c "import time; print(time.time())")
    C_TIME=$(python3 -c "print(round($END - $START, 1))")
    C_TOTAL=$(python3 -c "print($C_TOTAL + $C_TIME)")

    echo "  Run $run: weblens=${W_TIME}s chrome=${C_TIME}s" | tee -a benchmark_v4_results.md
  done

  W_AVG=$(python3 -c "print(round($W_TOTAL / $RUNS, 1))")
  C_AVG=$(python3 -c "print(round($C_TOTAL / $RUNS, 1))")
  WINNER=$(python3 -c "print('WEBLENS' if $W_AVG < $C_AVG else 'CHROME')")

  echo "  **AVG: weblens=${W_AVG}s chrome=${C_AVG}s → $WINNER**" | tee -a benchmark_v4_results.md
  echo "" | tee -a benchmark_v4_results.md
done

# Cleanup
weblens stop 2>/dev/null
echo "Done." | tee -a benchmark_v4_results.md
