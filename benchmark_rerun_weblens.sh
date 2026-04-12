#!/bin/bash
# Re-run weblens only on all 15 tasks, merging Chrome results from existing CSV.
# Chrome results are kept from benchmark_comprehensive.csv where available.

OUT="benchmark_rerun_results.md"
CSV_PREV="benchmark_comprehensive.csv"

TASKS=(
  "simple_read|Read|Go to https://example.com and tell me exactly what text is on the page.|Example Domain,documentation"
  "table_extract|Read|Go to https://the-internet.herokuapp.com/tables and tell me the last name and first name of the first row in Table 2 (the one with class/id attributes).|Smith,John"
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

WEBLENS_PROMPT_PREFIX="You are using weblens for web browsing. Key rules:
- weblens navigate <url>  →  loads page AND returns snapshot (never call state after)
- weblens do <ref>        →  clicks/fills AND returns updated snapshot (never call state after)
- weblens do <ref> --action hover  →  hovers element, reveals tooltip/overlay content
- Image elements appear in snapshots with refs like [e42] — hover them to reveal hidden content
- Count elements by their refs in the snapshot, not by how many times you clicked
Task: "

score_accuracy() {
  local result="$1"; local keywords="$2"
  local score=0; local total=0
  IFS=',' read -ra KWS <<< "$keywords"
  for kw in "${KWS[@]}"; do
    total=$((total+1))
    echo "$result" | grep -qi "$kw" && score=$((score+1))
  done
  python3 -c "print(round($score/$total,2))"
}

lookup_chrome() {
  local task_id="$1"; local field="$2"
  if [ ! -f "$CSV_PREV" ]; then echo "—"; return; fi
  python3 - "$task_id" "$field" "$CSV_PREV" <<'EOF'
import sys, csv
tid, field, path = sys.argv[1], sys.argv[2], sys.argv[3]
fields = ["task","category","wl_time_s","cr_time_s","wl_cost","cr_cost",
          "wl_turns","cr_turns","wl_input_tok","cr_input_tok",
          "wl_output_tok","cr_output_tok","wl_accuracy","cr_accuracy"]
with open(path) as f:
    for row in csv.DictReader(f):
        if row["task"] == tid:
            print(row.get(field, "—"))
            sys.exit()
print("—")
EOF
}

# Build weblens first
echo "Building weblens..."
cd "$(dirname "$0")"
bun install --silent 2>/dev/null
bun link --silent 2>/dev/null

# Warm daemon
weblens stop 2>/dev/null
pkill -f "bun.*daemon" 2>/dev/null
rm -f ~/.weblens/daemon.json
sleep 0.5
weblens --headless navigate https://example.com >/dev/null 2>&1
echo "Daemon warm."

# Output header
{
echo "# weblens Rerun vs Chrome (preserved)"
echo "Date: $(date)"
echo "weblens: new build with hover + img fixes"
echo ""
echo "## Results"
echo ""
printf "| %-20s | %-10s | %8s | %8s | %5s | %5s | %7s | %8s |\n" \
  "task" "category" "wl_time" "cr_time" "wl_acc" "cr_acc" "wl_turns" "cr_turns"
printf "| %-20s | %-10s | %8s | %8s | %5s | %5s | %7s | %8s |\n" \
  "----" "--------" "-------" "-------" "------" "------" "--------" "--------"
} > "$OUT"

NEW_CSV="benchmark_rerun.csv"
echo "task,category,wl_time_s,cr_time_s,wl_accuracy,cr_accuracy,wl_turns,cr_turns" > "$NEW_CSV"

WL_TOTAL_TIME=0; WL_TOTAL_ACC=0; TASK_COUNT=0

for entry in "${TASKS[@]}"; do
  IFS='|' read -r TASK_ID CATEGORY TASK KEYWORDS <<< "$entry"
  echo ""
  echo "Running: $TASK_ID ..."

  WL_JSON=$(claude --dangerously-skip-permissions -p "${WEBLENS_PROMPT_PREFIX}${TASK}" --output-format json 2>/dev/null)
  WL_TIME_MS=$(echo "$WL_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('duration_ms',0))" 2>/dev/null || echo 0)
  WL_TIME_S=$(python3 -c "print(round($WL_TIME_MS/1000,1))")
  WL_TURNS=$(echo "$WL_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('num_turns',0))" 2>/dev/null || echo 0)
  WL_RESULT=$(echo "$WL_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null || echo "")
  WL_ACC=$(score_accuracy "$WL_RESULT" "$KEYWORDS")

  CR_TIME=$(lookup_chrome "$TASK_ID" "cr_time_s")
  CR_ACC=$(lookup_chrome  "$TASK_ID" "cr_accuracy")
  CR_TURNS=$(lookup_chrome "$TASK_ID" "cr_turns")

  echo "  weblens: ${WL_TIME_S}s turns=${WL_TURNS} acc=${WL_ACC}"
  echo "  chrome (prev): ${CR_TIME}s acc=${CR_ACC}"

  printf "| %-20s | %-10s | %8s | %8s | %5s | %5s | %7s | %8s |\n" \
    "$TASK_ID" "$CATEGORY" "${WL_TIME_S}s" "${CR_TIME}s" "$WL_ACC" "$CR_ACC" "$WL_TURNS" "$CR_TURNS" >> "$OUT"

  echo "$TASK_ID,$CATEGORY,$WL_TIME_S,$CR_TIME,$WL_ACC,$CR_ACC,$WL_TURNS,$CR_TURNS" >> "$NEW_CSV"

  WL_TOTAL_TIME=$(python3 -c "print($WL_TOTAL_TIME + $WL_TIME_S)")
  WL_TOTAL_ACC=$(python3 -c "print($WL_TOTAL_ACC + $WL_ACC)")
  TASK_COUNT=$((TASK_COUNT+1))
done

WL_AVG_TIME=$(python3 -c "print(round($WL_TOTAL_TIME/$TASK_COUNT,1))")
WL_AVG_ACC=$(python3 -c "print(round($WL_TOTAL_ACC/$TASK_COUNT,2))")

{
echo ""
echo "## Summary (weblens new build)"
echo ""
echo "| metric | value |"
echo "|--------|-------|"
echo "| avg time | ${WL_AVG_TIME}s |"
echo "| avg accuracy | $WL_AVG_ACC |"
echo "| tasks | $TASK_COUNT |"
} >> "$OUT"

weblens stop 2>/dev/null
echo ""
echo "Done. Results in $OUT and $NEW_CSV"
cat "$OUT"
