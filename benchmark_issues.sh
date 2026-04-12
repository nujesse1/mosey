#!/bin/bash
# Targeted tests for known weblens failure modes

TASKS=(
  "Go to https://httpbin.org/forms/post, fill in ALL text fields (customer name='Test User', telephone='555-1234', email='test@test.com', delivery instructions='Leave at door'), then tell me every single field on the form."
  "Go to https://www.wikipedia.org, search for 'Playwright browser automation', and tell me the title of the first result."
  "Go to https://hacker-news.firebaseio.com/v0/topstories.json and tell me the first 5 item IDs."
  "Go to https://httpbin.org/forms/post, select the 'Large' pizza size and check the 'Extra Cheese' and 'Bacon' toppings. Confirm what's selected."
)
TASK_NAMES=("form_fill_all" "search_and_navigate" "json_api" "form_radio_checkbox")

echo "# Weblens Issue Tests"
echo "Date: $(date)"
echo ""

weblens stop 2>/dev/null; sleep 0.3
weblens --headless navigate https://example.com 2>/dev/null
echo "Daemon warm."
echo ""

for i in "${!TASKS[@]}"; do
  TASK="${TASKS[$i]}"
  NAME="${TASK_NAMES[$i]}"
  echo "## $NAME"

  START=$(python3 -c "import time; print(time.time())")
  RESULT=$(claude --dangerously-skip-permissions -p "weblens navigate <url> loads a page AND returns snapshot (no need for state after). weblens do <ref> clicks/fills AND returns snapshot (no need for state after). $TASK" --output-format text 2>&1)
  END=$(python3 -c "import time; print(time.time())")
  TIME=$(python3 -c "print(round($END - $START, 1))")

  echo "**Time: ${TIME}s**"
  echo '```'
  echo "$RESULT"
  echo '```'
  echo ""
done

weblens stop 2>/dev/null
echo "Done."
