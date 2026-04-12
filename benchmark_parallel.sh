#!/bin/bash
# Parallel weblens benchmark — each task gets its own daemon
# Usage: ./benchmark_parallel.sh [workers]
WORKERS=${1:-4}
OUT="benchmark_parallel_results.md"
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

PROMPT_PREFIX="You are using weblens for web browsing. Rules:
- weblens navigate <url> loads page AND returns snapshot (never call state after)
- weblens do <ref> clicks/fills AND returns updated snapshot (never call state after)
- weblens do <ref> --action hover triggers hover, reveals tooltips/overlays
- Count elements by their refs in the snapshot, not by click history
Task: "

score_accuracy() {
  local result="$1" keywords="$2" score=0 total=0
  IFS=',' read -ra KWS <<< "$keywords"
  for kw in "${KWS[@]}"; do
    total=$((total+1))
    echo "$result" | grep -qi "$kw" && score=$((score+1))
  done
  python3 -c "print(round($score/$total,2))"
}

run_one() {
  local entry="$1" worker="$2"
  IFS='|' read -r TASK_ID CATEGORY TASK KEYWORDS <<< "$entry"

  local wdir="$TMPDIR_BASE/worker-$worker"
  mkdir -p "$wdir"

  # Warm this worker's daemon
  WEBLENS_DIR="$wdir" weblens --headless navigate https://example.com >/dev/null 2>&1

  local start=$(python3 -c "import time; print(time.time())")
  local json
  json=$(WEBLENS_DIR="$wdir" claude --dangerously-skip-permissions \
    -p "${PROMPT_PREFIX}${TASK}" --output-format json 2>/dev/null)
  local end=$(python3 -c "import time; print(time.time())")

  local time_s=$(python3 -c "print(round($end-$start,1))")
  local turns=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('num_turns',0))" 2>/dev/null || echo 0)
  local result=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null || echo "")
  local acc=$(score_accuracy "$result" "$KEYWORDS")

  WEBLENS_DIR="$wdir" weblens stop >/dev/null 2>&1

  echo "$TASK_ID|$CATEGORY|$time_s|$turns|$acc"
}

export -f run_one score_accuracy
export TMPDIR_BASE PROMPT_PREFIX

# Build
echo "Building weblens..."
bun link --silent 2>/dev/null

echo "Running ${#TASKS[@]} tasks with $WORKERS parallel workers..."
WALL_START=$(python3 -c "import time; print(time.time())")

# Write tasks to temp file for xargs
TASK_FILE=$(mktemp)
for i in "${!TASKS[@]}"; do
  echo "${TASKS[$i]}|||$((i % WORKERS))"
done > "$TASK_FILE"

# Run in parallel, collect results
RESULTS=()
pids=()
result_files=()

for i in "${!TASKS[@]}"; do
  worker=$((i % WORKERS))
  rfile=$(mktemp)
  result_files+=("$rfile")
  (run_one "${TASKS[$i]}" "$worker" > "$rfile") &
  pids+=($!)
  # Stagger starts slightly to avoid daemon collision
  sleep 0.3
done

# Wait for all
for pid in "${pids[@]}"; do
  wait "$pid"
done

WALL_END=$(python3 -c "import time; print(time.time())")
WALL_TIME=$(python3 -c "print(round($WALL_END-$WALL_START,1))")

# Collect and display results
{
echo "# Parallel Benchmark Results"
echo "Date: $(date)"
echo "Workers: $WORKERS | Wall time: ${WALL_TIME}s"
echo ""
printf "| %-20s | %-10s | %8s | %7s | %6s |\n" "task" "category" "time" "turns" "acc"
printf "| %-20s | %-10s | %8s | %7s | %6s |\n" "----" "--------" "----" "-----" "---"
} > "$OUT"

TOTAL_ACC=0
COUNT=0
for rfile in "${result_files[@]}"; do
  line=$(cat "$rfile")
  IFS='|' read -r tid cat ts turns acc <<< "$line"
  echo "  $tid: ${ts}s turns=$turns acc=$acc"
  printf "| %-20s | %-10s | %8s | %7s | %6s |\n" "$tid" "$cat" "${ts}s" "$turns" "$acc" >> "$OUT"
  TOTAL_ACC=$(python3 -c "print($TOTAL_ACC + $acc)")
  COUNT=$((COUNT+1))
done

AVG_ACC=$(python3 -c "print(round($TOTAL_ACC/$COUNT,2))")

{
echo ""
echo "## Summary"
echo "| metric | value |"
echo "|--------|-------|"
echo "| wall time | ${WALL_TIME}s |"
echo "| avg accuracy | $AVG_ACC |"
echo "| tasks | $COUNT |"
echo "| workers | $WORKERS |"
} >> "$OUT"

rm -rf "$TMPDIR_BASE" "$TASK_FILE" "${result_files[@]}"

echo ""
echo "Wall time: ${WALL_TIME}s | Avg acc: $AVG_ACC"
echo "Results in $OUT"
cat "$OUT"
