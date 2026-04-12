#!/bin/bash
# Benchmark: weblens vs browser-use on 5 tasks
# Each task is run via a fresh claude --dangerously-skip-permissions instance
# We time the full end-to-end including model inference

RESULTS_FILE="benchmark_results.md"
echo "# Weblens vs Browser-Use Benchmark" > $RESULTS_FILE
echo "Date: $(date)" >> $RESULTS_FILE
echo "Model: claude-opus-4-6 (via Claude Code)" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

TASKS=(
  "Go to https://example.com and tell me exactly what text is on the page."
  "Go to https://news.ycombinator.com and tell me the titles of the top 3 stories."
  "Go to https://en.wikipedia.org/wiki/Anthropic and tell me when the company was founded and who founded it."
  "Go to https://httpbin.org/forms/post and fill in the customer name field with 'Test User' and the telephone field with '555-1234'. Tell me what fields you see on the form."
  "Go to https://books.toscrape.com, tell me the title and price of the first book listed."
)

TASK_NAMES=(
  "simple_read"
  "list_extraction"
  "wiki_lookup"
  "form_interaction"
  "scrape_data"
)

for i in "${!TASKS[@]}"; do
  TASK="${TASKS[$i]}"
  NAME="${TASK_NAMES[$i]}"

  echo "=== Task $((i+1)): $NAME ==="
  echo "" >> $RESULTS_FILE
  echo "## Task $((i+1)): $NAME" >> $RESULTS_FILE
  echo "**Prompt:** $TASK" >> $RESULTS_FILE
  echo "" >> $RESULTS_FILE

  # --- WEBLENS --- (daemon stays alive between tasks for realistic perf)
  echo "  Running weblens..."
  START=$(python3 -c "import time; print(time.time())")

  WEBLENS_OUT=$(claude --dangerously-skip-permissions -p "You have 'weblens' CLI for web browsing. Commands: navigate <url>, state (get page content), do <ref> (click element by ref ID), stop. Output is JSON. $TASK" --output-format text 2>&1)

  END=$(python3 -c "import time; print(time.time())")
  WEBLENS_TIME=$(python3 -c "print(f'{$END - $START:.1f}')")

  echo "  weblens: ${WEBLENS_TIME}s"
  echo "### weblens: ${WEBLENS_TIME}s" >> $RESULTS_FILE
  echo '```' >> $RESULTS_FILE
  echo "$WEBLENS_OUT" | tail -10 >> $RESULTS_FILE
  echo '```' >> $RESULTS_FILE
  echo "" >> $RESULTS_FILE

  # --- BROWSER-USE (via Claude in Chrome MCP) ---
  echo "  Running chrome MCP..."
  START=$(python3 -c "import time; print(time.time())")

  CHROME_OUT=$(claude --dangerously-skip-permissions -p "Use the mcp__chrome-devtools tools to browse the web. First call mcp__chrome-devtools__new_page to open a tab. Then: $TASK" --output-format text 2>&1)

  END=$(python3 -c "import time; print(time.time())")
  CHROME_TIME=$(python3 -c "print(f'{$END - $START:.1f}')")

  echo "  chrome MCP: ${CHROME_TIME}s"
  echo "### chrome MCP: ${CHROME_TIME}s" >> $RESULTS_FILE
  echo '```' >> $RESULTS_FILE
  echo "$CHROME_OUT" | tail -10 >> $RESULTS_FILE
  echo '```' >> $RESULTS_FILE
  echo "" >> $RESULTS_FILE

done

# Cleanup at the end
weblens stop 2>/dev/null
pkill -f "bun.*daemon" 2>/dev/null
rm -f ~/.weblens/daemon.json

echo ""
echo "Results saved to $RESULTS_FILE"
cat $RESULTS_FILE
