#!/bin/bash
# Comprehensive weblens vs Chrome benchmark
# Measures: time, cost, tokens, turns, accuracy

OUT="benchmark_comprehensive_results.md"

# ── Task definitions ──────────────────────────────────────────────────────────
# Format: "ID|CATEGORY|URL_HINT|TASK|KW1,KW2,..."
TASKS=(
  # Read & Extract
  "simple_read|Read|example.com|Go to https://example.com and tell me exactly what text is on the page.|Example Domain,documentation"
  "table_extract|Read|the-internet tables|Go to https://the-internet.herokuapp.com/tables and tell me the last name and first name of the first row in Table 2 (the one with class/id attributes).|Smith,John"
  "wiki_facts|Read|wikipedia Anthropic|Go to https://en.wikipedia.org/wiki/Anthropic and tell me when it was founded and who the co-founders are.|2021,Dario,Daniela"
  "book_price|Read|books.toscrape.com|Go to https://books.toscrape.com and tell me the title and price of the first book.|Light in the Attic,51.77"

  # Form Interaction
  "form_text_multi|Forms|httpbin forms|Go to https://httpbin.org/forms/post, fill in customer name with 'Test User', telephone with '555-1234', and email with 'test@test.com'. Then list every field on the form.|Test User,555-1234,test@test.com,Submit"
  "form_dropdown|Forms|the-internet dropdown|Go to https://the-internet.herokuapp.com/dropdown and select 'Option 2' from the dropdown. Confirm what is selected.|Option 2"
  "form_radio_check|Forms|httpbin radio+checkbox|Go to https://httpbin.org/forms/post, select the Large pizza size and check Bacon and Extra Cheese toppings. Tell me what is checked/selected.|Large,Bacon,Extra Cheese"

  # Navigation & Login
  "login_flow|Navigation|the-internet login|Go to https://the-internet.herokuapp.com/login and log in with username 'tomsmith' and password 'SuperSecretPassword'. Tell me what page you land on.|secure,logged"
  "click_navigate|Navigation|the-internet checkboxes|Go to https://the-internet.herokuapp.com, click the Checkboxes link, and tell me the state of each checkbox.|checkbox,checked"
  "multi_step|Navigation|add remove elements|Go to https://the-internet.herokuapp.com/add_remove_elements/ and click the Add Element button exactly twice. How many Delete buttons are now on the page?|2,Delete"

  # Dynamic Content
  "dynamic_load|Dynamic|dynamic loading|Go to https://the-internet.herokuapp.com/dynamic_loading/2, click Start, and tell me the text that appears.|Hello World"
  "dynamic_controls|Dynamic|dynamic controls|Go to https://the-internet.herokuapp.com/dynamic_controls, click Enable, then type 'hello' in the text field once it is enabled. Confirm what you typed.|hello"
  "redirect|Dynamic|redirect|Go to https://the-internet.herokuapp.com/redirector and click the redirect link. What URL do you end up at?|status_codes"

  # Real-World
  "hn_top3|Real-World|hacker news|Go to https://news.ycombinator.com and tell me the titles and point counts of the top 3 stories.|points"
  "github_info|Real-World|github claude-code|Go to https://github.com/anthropics/claude-code and tell me the repository description and approximate star count.|Claude,star"
)

WEBLENS_PROMPT_PREFIX="weblens navigate <url> loads a page and returns a snapshot immediately — no need to call state after navigate. weblens do <ref> clicks or fills a field and returns an updated snapshot — no need to call state after do. Use weblens for all web browsing."
CHROME_PROMPT_PREFIX="Use the mcp__chrome-devtools tools for all web browsing. Call mcp__chrome-devtools__new_page first to open a tab, then mcp__chrome-devtools__navigate_page to load URLs, and mcp__chrome-devtools__take_snapshot to read page content."

# ── Helpers ───────────────────────────────────────────────────────────────────
score_accuracy() {
  local result="$1"
  local keywords="$2"
  local score=0
  local total=0
  IFS=',' read -ra KWS <<< "$keywords"
  for kw in "${KWS[@]}"; do
    total=$((total+1))
    echo "$result" | grep -qi "$kw" && score=$((score+1))
  done
  python3 -c "print(round($score/$total, 2))"
}

run_task() {
  local tool="$1"   # weblens or chrome
  local prompt="$2"
  local json
  json=$(claude --dangerously-skip-permissions -p "$prompt" --output-format json 2>/dev/null)
  echo "$json"
}

# ── Setup ─────────────────────────────────────────────────────────────────────
echo "# Comprehensive Benchmark: weblens vs Chrome MCP" > "$OUT"
echo "Date: $(date)" >> "$OUT"
echo "Model: claude-sonnet-4-6 (claude --dangerously-skip-permissions)" >> "$OUT"
echo "" >> "$OUT"

# Warm up weblens daemon
weblens stop 2>/dev/null
pkill -f "bun.*daemon" 2>/dev/null
rm -f ~/.weblens/daemon.json
sleep 0.5
weblens --headless navigate https://example.com >/dev/null 2>&1
echo "Daemon warm." >> "$OUT"
echo "" >> "$OUT"

# ── Results table header ──────────────────────────────────────────────────────
echo "## Results" >> "$OUT"
echo "" >> "$OUT"
printf "| %-20s | %-10s | %8s | %8s | %7s | %6s | %6s | %8s | %8s | %8s | %8s | %8s | %8s |\n" \
  "task" "category" "wl_time" "cr_time" "wl_cost" "cr_cost" "wl_turns" "cr_turns" "wl_in_tok" "cr_in_tok" "wl_out_tok" "cr_out_tok" "wl_acc" "cr_acc" >> "$OUT"
printf "| %-20s | %-10s | %8s | %8s | %7s | %6s | %6s | %8s | %8s | %8s | %8s | %8s | %8s |\n" \
  "----" "--------" "-------" "-------" "-------" "------" "--------" "--------" "---------" "---------" "----------" "----------" "------" "------" >> "$OUT"

# Also write CSV
CSV="benchmark_comprehensive.csv"
echo "task,category,wl_time_s,cr_time_s,wl_cost,cr_cost,wl_turns,cr_turns,wl_input_tok,cr_input_tok,wl_output_tok,cr_output_tok,wl_accuracy,cr_accuracy" > "$CSV"

# Totals for summary
WL_TOTAL_TIME=0; CR_TOTAL_TIME=0
WL_TOTAL_COST=0; CR_TOTAL_COST=0
WL_TOTAL_ACC=0; CR_TOTAL_ACC=0
TASK_COUNT=0

# ── Run tasks ─────────────────────────────────────────────────────────────────
for entry in "${TASKS[@]}"; do
  IFS='|' read -r TASK_ID CATEGORY URL_HINT TASK KEYWORDS <<< "$entry"

  echo ""
  echo "Running: $TASK_ID ..."

  # Weblens
  WL_JSON=$(run_task "weblens" "$WEBLENS_PROMPT_PREFIX $TASK")
  WL_TIME_MS=$(echo "$WL_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('duration_ms',0))" 2>/dev/null || echo 0)
  WL_TIME_S=$(python3 -c "print(round($WL_TIME_MS/1000,1))")
  WL_COST=$(echo "$WL_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(round(d.get('cost_usd',0),4))" 2>/dev/null || echo 0)
  WL_TURNS=$(echo "$WL_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('num_turns',0))" 2>/dev/null || echo 0)
  WL_IN_TOK=$(echo "$WL_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('usage',{}).get('input_tokens',0))" 2>/dev/null || echo 0)
  WL_OUT_TOK=$(echo "$WL_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('usage',{}).get('output_tokens',0))" 2>/dev/null || echo 0)
  WL_RESULT=$(echo "$WL_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null || echo "")
  WL_ACC=$(score_accuracy "$WL_RESULT" "$KEYWORDS")

  # Chrome
  CR_JSON=$(run_task "chrome" "$CHROME_PROMPT_PREFIX $TASK")
  CR_TIME_MS=$(echo "$CR_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('duration_ms',0))" 2>/dev/null || echo 0)
  CR_TIME_S=$(python3 -c "print(round($CR_TIME_MS/1000,1))")
  CR_COST=$(echo "$CR_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(round(d.get('cost_usd',0),4))" 2>/dev/null || echo 0)
  CR_TURNS=$(echo "$CR_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('num_turns',0))" 2>/dev/null || echo 0)
  CR_IN_TOK=$(echo "$CR_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('usage',{}).get('input_tokens',0))" 2>/dev/null || echo 0)
  CR_OUT_TOK=$(echo "$CR_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('usage',{}).get('output_tokens',0))" 2>/dev/null || echo 0)
  CR_RESULT=$(echo "$CR_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null || echo "")
  CR_ACC=$(score_accuracy "$CR_RESULT" "$KEYWORDS")

  echo "  weblens: ${WL_TIME_S}s \$${WL_COST} acc=${WL_ACC}"
  echo "  chrome:  ${CR_TIME_S}s \$${CR_COST} acc=${CR_ACC}"

  # Write row
  printf "| %-20s | %-10s | %8s | %8s | %7s | %6s | %6s | %8s | %8s | %8s | %8s | %8s | %8s |\n" \
    "$TASK_ID" "$CATEGORY" "${WL_TIME_S}s" "${CR_TIME_S}s" "\$$WL_COST" "\$$CR_COST" \
    "$WL_TURNS" "$CR_TURNS" "$WL_IN_TOK" "$CR_IN_TOK" "$WL_OUT_TOK" "$CR_OUT_TOK" \
    "$WL_ACC" "$CR_ACC" >> "$OUT"

  echo "$TASK_ID,$CATEGORY,$WL_TIME_S,$CR_TIME_S,$WL_COST,$CR_COST,$WL_TURNS,$CR_TURNS,$WL_IN_TOK,$CR_IN_TOK,$WL_OUT_TOK,$CR_OUT_TOK,$WL_ACC,$CR_ACC" >> "$CSV"

  # Accumulate totals
  WL_TOTAL_TIME=$(python3 -c "print($WL_TOTAL_TIME + $WL_TIME_S)")
  CR_TOTAL_TIME=$(python3 -c "print($CR_TOTAL_TIME + $CR_TIME_S)")
  WL_TOTAL_COST=$(python3 -c "print(round($WL_TOTAL_COST + $WL_COST, 4))")
  CR_TOTAL_COST=$(python3 -c "print(round($CR_TOTAL_COST + $CR_COST, 4))")
  WL_TOTAL_ACC=$(python3 -c "print($WL_TOTAL_ACC + $WL_ACC)")
  CR_TOTAL_ACC=$(python3 -c "print($CR_TOTAL_ACC + $CR_ACC)")
  TASK_COUNT=$((TASK_COUNT+1))
done

# ── Summary ───────────────────────────────────────────────────────────────────
WL_AVG_TIME=$(python3 -c "print(round($WL_TOTAL_TIME/$TASK_COUNT,1))")
CR_AVG_TIME=$(python3 -c "print(round($CR_TOTAL_TIME/$TASK_COUNT,1))")
WL_AVG_ACC=$(python3 -c "print(round($WL_TOTAL_ACC/$TASK_COUNT,2))")
CR_AVG_ACC=$(python3 -c "print(round($CR_TOTAL_ACC/$TASK_COUNT,2))")
SPEED_RATIO=$(python3 -c "print(round($CR_AVG_TIME/$WL_AVG_TIME,2)) if $WL_AVG_TIME > 0 else print('N/A')")

echo "" >> "$OUT"
echo "## Summary" >> "$OUT"
echo "" >> "$OUT"
echo "| Metric | weblens | chrome | winner |" >> "$OUT"
echo "|--------|---------|--------|--------|" >> "$OUT"
echo "| avg time | ${WL_AVG_TIME}s | ${CR_AVG_TIME}s | $(python3 -c "print('weblens' if $WL_AVG_TIME < $CR_AVG_TIME else 'chrome')") |" >> "$OUT"
echo "| total cost | \$$WL_TOTAL_COST | \$$CR_TOTAL_COST | $(python3 -c "print('weblens' if $WL_TOTAL_COST < $CR_TOTAL_COST else 'chrome')") |" >> "$OUT"
echo "| avg accuracy | $WL_AVG_ACC | $CR_AVG_ACC | $(python3 -c "print('weblens' if $WL_AVG_ACC > $CR_AVG_ACC else 'chrome' if $CR_AVG_ACC > $WL_AVG_ACC else 'tie')") |" >> "$OUT"
echo "| speed ratio | ${SPEED_RATIO}x faster than chrome | — | — |" >> "$OUT"
echo "" >> "$OUT"

weblens stop 2>/dev/null
echo "Done. Results in $OUT and $CSV"
cat "$OUT"
