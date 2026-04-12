#!/bin/bash
# Fair head-to-head: weblens vs Chrome, all tasks, both run in parallel
WORKERS=${1:-4}
OUT="benchmark_fair_results.md"
TMPDIR_BASE=$(mktemp -d)

TASKS=(
  "simple_read|Read|Go to https://example.com and tell me exactly what text is on the page.|Example Domain,documentation"
  "table_extract|Read|Go to https://the-internet.herokuapp.com/tables and tell me the last name and first name of the first row in Table 2.|Smith,John"
  "wiki_facts|Read|Go to https://en.wikipedia.org/wiki/Anthropic and tell me when it was founded and who the co-founders are.|2021,Dario,Daniela"
  "book_price|Read|Go to https://books.toscrape.com and tell me the title and price of the first book.|Light in the Attic,51.77"
  "form_text_multi|Forms|Go to https://httpbin.org/forms/post, fill in customer name with 'Test User', telephone with '555-1234', and email with 'test@test.com'. Then list every field on the form.|Test User,555-1234,test@test.com,Submit"
  "form_dropdown|Forms|Go to https://the-internet.herokuapp.com/dropdown and select 'Option 2' from the dropdown. Confirm what is selected.|Option 2"
  "form_radio_check|Forms|Go to https://httpbin.org/forms/post, select the Large pizza size and check Bacon and Extra Cheese toppings. Tell me what is checked/selected.|Large,Bacon,Extra Cheese"
  "login_flow|Navigation|Go to https://the-internet.herokuapp.com/login and log in with username 'tomsmith' and password 'SuperSecretPassword'. Tell me what page you land on.|secure,logged"
  "click_navigate|Navigation|Go to https://the-internet.herokuapp.com, click the Checkboxes link, and tell me the state of each checkbox.|checkbox,checked"
  "multi_step|Navigation|Go to https://the-internet.herokuapp.com/add_remove_elements/ and click the Add Element button exactly twice. How many Delete buttons are now on the page?|2,Delete"
  "dynamic_load|Dynamic|Go to https://the-internet.herokuapp.com/dynamic_loading/2, click Start, and tell me the text that appears.|Hello World"
  "dynamic_controls|Dynamic|Go to https://the-internet.herokuapp.com/dynamic_controls, click Enable, then type 'hello' in the text field once it is enabled. Confirm what you typed.|hello"
  "redirect|Dynamic|Go to https://the-internet.herokuapp.com/redirector and click the redirect link. What URL do you end up at?|status_codes"
  "hn_top3|Real-World|Go to https://news.ycombinator.com and tell me the titles and point counts of the top 3 stories.|points"
  "github_info|Real-World|Go to https://github.com/anthropics/claude-code and tell me the repository description and approximate star count.|Claude,star"
  "hover_tooltip|Hover|Go to https://the-internet.herokuapp.com/hovers and tell me the name shown when you hover over the first avatar image.|name,profile"
)

WL_PREFIX="You are using weblens for web browsing. Rules:
- weblens navigate <url> loads page AND returns snapshot (never call state after)
- weblens do <ref> clicks/fills AND returns updated snapshot (never call state after)
- weblens do <ref> --action hover triggers hover, reveals tooltips/overlays
- Count elements by their refs in the snapshot, not by click history
Task: "

CR_PREFIX="Use mcp__chrome-devtools tools for all web browsing. Call mcp__chrome-devtools__new_page first, then mcp__chrome-devtools__navigate_page to load URLs, and mcp__chrome-devtools__take_snapshot to read page content. Task: "

score_accuracy() {
  local result="$1" keywords="$2" score=0 total=0
  IFS=',' read -ra KWS <<< "$keywords"
  for kw in "${KWS[@]}"; do
    total=$((total+1))
    echo "$result" | grep -qi "$kw" && score=$((score+1))
  done
  python3 -c "print(round($score/$total,2))"
}

run_weblens() {
  local entry="$1" worker="$2"
  IFS='|' read -r TASK_ID CATEGORY TASK KEYWORDS <<< "$entry"
  local wdir="$TMPDIR_BASE/wl-$worker"
  mkdir -p "$wdir"
  WEBLENS_DIR="$wdir" weblens --headless navigate https://example.com >/dev/null 2>&1
  local start=$(python3 -c "import time; print(time.time())")
  local json
  json=$(WEBLENS_DIR="$wdir" claude --dangerously-skip-permissions \
    -p "${WL_PREFIX}${TASK}" --output-format json 2>/dev/null)
  local end=$(python3 -c "import time; print(time.time())")
  local time_s=$(python3 -c "print(round($end-$start,1))")
  local turns=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('num_turns',0))" 2>/dev/null || echo 0)
  local result=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null || echo "")
  local acc=$(score_accuracy "$result" "$KEYWORDS")
  WEBLENS_DIR="$wdir" weblens stop >/dev/null 2>&1
  echo "$TASK_ID|$CATEGORY|$time_s|$turns|$acc"
}

run_chrome() {
  local entry="$1"
  IFS='|' read -r TASK_ID CATEGORY TASK KEYWORDS <<< "$entry"
  local start=$(python3 -c "import time; print(time.time())")
  local json
  json=$(claude --dangerously-skip-permissions \
    -p "${CR_PREFIX}${TASK}" --output-format json 2>/dev/null)
  local end=$(python3 -c "import time; print(time.time())")
  local time_s=$(python3 -c "print(round($end-$start,1))")
  local turns=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('num_turns',0))" 2>/dev/null || echo 0)
  local result=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null || echo "")
  local acc=$(score_accuracy "$result" "$KEYWORDS")
  echo "$TASK_ID|$CATEGORY|$time_s|$turns|$acc"
}

export -f run_weblens run_chrome score_accuracy
export TMPDIR_BASE WL_PREFIX CR_PREFIX

bun link --silent 2>/dev/null
echo "Running ${#TASKS[@]} tasks — weblens + Chrome in parallel (${WORKERS} weblens workers)..."
WALL_START=$(python3 -c "import time; print(time.time())")

wl_result_files=()
cr_result_files=()
pids=()

for i in "${!TASKS[@]}"; do
  worker=$((i % WORKERS))
  wrf=$(mktemp); wl_result_files+=("$wrf")
  crf=$(mktemp); cr_result_files+=("$crf")
  (run_weblens "${TASKS[$i]}" "$worker" > "$wrf") &
  pids+=($!)
  sleep 0.3
  (run_chrome "${TASKS[$i]}" > "$crf") &
  pids+=($!)
done

for pid in "${pids[@]}"; do wait "$pid"; done

WALL_END=$(python3 -c "import time; print(time.time())")
WALL_TIME=$(python3 -c "print(round($WALL_END-$WALL_START,1))")

{
echo "# Fair Benchmark: weblens vs Chrome"
echo "Date: $(date) | Wall time: ${WALL_TIME}s | Workers: $WORKERS"
echo ""
printf "| %-20s | %-10s | %8s | %8s | %7s | %8s | %6s | %6s |\n" \
  "task" "category" "wl_time" "cr_time" "wl_turn" "cr_turn" "wl_acc" "cr_acc"
printf "| %-20s | %-10s | %8s | %8s | %7s | %8s | %6s | %6s |\n" \
  "----" "--------" "-------" "-------" "-------" "--------" "------" "------"
} > "$OUT"

WL_TOTAL=0; CR_TOTAL=0; WL_ACC_T=0; CR_ACC_T=0; COUNT=0

for i in "${!wl_result_files[@]}"; do
  wl=$(cat "${wl_result_files[$i]}")
  cr=$(cat "${cr_result_files[$i]}")
  IFS='|' read -r wtid wcat wt wturns wacc <<< "$wl"
  IFS='|' read -r ctid ccat ct cturns cacc <<< "$cr"

  echo "  $wtid — weblens: ${wt}s acc=$wacc | chrome: ${ct}s acc=$cacc"

  printf "| %-20s | %-10s | %8s | %8s | %7s | %8s | %6s | %6s |\n" \
    "$wtid" "$wcat" "${wt}s" "${ct}s" "$wturns" "$cturns" "$wacc" "$cacc" >> "$OUT"

  WL_TOTAL=$(python3 -c "print($WL_TOTAL+$wt)")
  CR_TOTAL=$(python3 -c "print($CR_TOTAL+$ct)")
  WL_ACC_T=$(python3 -c "print($WL_ACC_T+$wacc)")
  CR_ACC_T=$(python3 -c "print($CR_ACC_T+$cacc)")
  COUNT=$((COUNT+1))
done

WL_AVG=$(python3 -c "print(round($WL_TOTAL/$COUNT,1))")
CR_AVG=$(python3 -c "print(round($CR_TOTAL/$COUNT,1))")
WL_AVG_ACC=$(python3 -c "print(round($WL_ACC_T/$COUNT,2))")
CR_AVG_ACC=$(python3 -c "print(round($CR_ACC_T/$COUNT,2))")
WINNER_SPEED=$(python3 -c "print('weblens' if $WL_AVG < $CR_AVG else 'chrome')")
WINNER_ACC=$(python3 -c "print('weblens' if $WL_AVG_ACC > $CR_AVG_ACC else 'chrome' if $CR_AVG_ACC > $WL_AVG_ACC else 'tie')")

{
echo ""
echo "## Summary"
echo "| metric | weblens | chrome | winner |"
echo "|--------|---------|--------|--------|"
echo "| avg time/task | ${WL_AVG}s | ${CR_AVG}s | $WINNER_SPEED |"
echo "| avg accuracy | $WL_AVG_ACC | $CR_AVG_ACC | $WINNER_ACC |"
echo "| wall time | ${WALL_TIME}s | — | — |"
} >> "$OUT"

rm -rf "$TMPDIR_BASE" "${wl_result_files[@]}" "${cr_result_files[@]}"
echo ""
echo "Done in ${WALL_TIME}s"
echo "weblens: avg ${WL_AVG}s acc=${WL_AVG_ACC} | chrome: avg ${CR_AVG}s acc=${CR_AVG_ACC} | winner: speed=$WINNER_SPEED acc=$WINNER_ACC"
cat "$OUT"
