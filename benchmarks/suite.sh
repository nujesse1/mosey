#!/usr/bin/env bash
# benchmarks/suite.sh — weblens vs mcp__claude-in-chrome benchmark suite
# bash 3.2 compatible (macOS default shell)
#
# Usage:
#   bash benchmarks/suite.sh                                        # full 26-task suite
#   RUNS=1 TASK_FILTER=simple_read bash benchmarks/suite.sh        # smoke test 1 task
#   TASK_FILTER=reading bash benchmarks/suite.sh                   # single category
#   RUNS=1 bash benchmarks/suite.sh                                # quick full pass
#
# Requires: claude CLI, weblens (bun link), python3
#
# Output:
#   benchmarks/results/YYYYMMDD_HHMM.csv   raw results
#   benchmarks/results/latest.csv          copy of latest
#
# Analyze:
#   python3 benchmarks/analyze.py benchmarks/results/latest.csv

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=benchmarks/tasks.sh
source "$SCRIPT_DIR/tasks.sh"

# ─── Config ─────────────────────────────────────────────────────────────────

RUNS="${RUNS:-3}"
MODEL="${MODEL:-claude-sonnet-4-6}"
TASK_FILTER="${TASK_FILTER:-}"
RESULTS_DIR="$SCRIPT_DIR/results"
TIMESTAMP=$(date +%Y%m%d_%H%M)
CSV="$RESULTS_DIR/$TIMESTAMP.csv"
LATEST_CSV="$RESULTS_DIR/latest.csv"

mkdir -p "$RESULTS_DIR"

# ─── Prerequisite check ─────────────────────────────────────────────────────

command -v claude  >/dev/null 2>&1 || { echo "ERROR: claude CLI not found" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found" >&2; exit 1; }
command -v weblens >/dev/null 2>&1 || { echo "ERROR: weblens not found (run: bun link)" >&2; exit 1; }

# ─── Helpers ────────────────────────────────────────────────────────────────

# parse_json <json_file> <dotted.key>
parse_json() {
  python3 - "$1" "$2" << 'PYEOF'
import sys, json
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    for k in sys.argv[2].split('.'):
        d = d.get(k, 0) if isinstance(d, dict) else 0
    print(d if d is not None else 0)
except Exception:
    print(0)
PYEOF
}

# score_accuracy <result_file> <comma_keywords>
score_accuracy() {
  python3 - "$1" "$2" << 'PYEOF'
import sys
try:
    result = open(sys.argv[1]).read().lower()
    kws = [k.strip().lower() for k in sys.argv[2].split(',') if k.strip()]
    if not kws:
        print(1.0)
    else:
        hits = sum(1 for kw in kws if kw in result)
        print(round(hits / len(kws), 2))
except Exception:
    print(0.0)
PYEOF
}

# ─── Task runner ────────────────────────────────────────────────────────────

run_task() {
  local tool="$1" task_id="$2" category="$3" prompt="$4" expected="$5" run="$6"

  local tmp_out tmp_prompt tmp_result
  tmp_out=$(mktemp /tmp/bench_out.XXXXXX)
  tmp_prompt=$(mktemp /tmp/bench_prompt.XXXXXX)
  tmp_result=$(mktemp /tmp/bench_result.XXXXXX)

  # Write prompt to a temp file — avoids shell quoting landmines with long strings
  printf '%s' "$prompt" > "$tmp_prompt"

  local error=0
  if ! claude --dangerously-skip-permissions \
       --model "$MODEL" \
       -p "$(cat "$tmp_prompt")" \
       --output-format json \
       2>/dev/null > "$tmp_out"; then
    error=1
  fi

  # Validate JSON; zero out if invalid
  if ! python3 -c "import json,sys; json.load(sys.stdin)" < "$tmp_out" 2>/dev/null; then
    error=1
    printf '%s' '{"result":"","duration_ms":0,"cost_usd":0,"num_turns":0,"usage":{"input_tokens":0,"output_tokens":0}}' > "$tmp_out"
  fi

  # Extract metrics — note: total_cost_usd, and input_tok = fresh+cache_read+cache_create
  local duration_ms time_s input_tok cached_read cached_create total_input output_tok cost_usd turns
  duration_ms=$(parse_json "$tmp_out" "duration_ms")
  time_s=$(python3 -c "print(round($duration_ms / 1000, 1))")
  # Total effective input = fresh tokens + cache reads + cache creation
  input_tok=$(parse_json "$tmp_out" "usage.input_tokens")
  cached_read=$(parse_json "$tmp_out" "usage.cache_read_input_tokens")
  cached_create=$(parse_json "$tmp_out" "usage.cache_creation_input_tokens")
  total_input=$(python3 -c "print(int($input_tok) + int($cached_read) + int($cached_create))")
  output_tok=$(parse_json "$tmp_out" "usage.output_tokens")
  cost_usd=$(parse_json "$tmp_out" "total_cost_usd")
  turns=$(parse_json "$tmp_out" "num_turns")

  # Extract result text for accuracy scoring
  python3 - "$tmp_out" > "$tmp_result" 2>/dev/null << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
print(d.get('result', ''))
PYEOF

  local accuracy
  accuracy=$(score_accuracy "$tmp_result" "$expected")

  printf "    %-7s run%s: %5ss | %6s tok (%s fresh) | acc=%-4s | err=%s\n" \
    "$tool" "$run" "$time_s" "$total_input" "$input_tok" "$accuracy" "$error"

  # CSV: total_input = all tokens (cost); fresh_tok = non-cached (per-task context overhead)
  echo "$task_id,$category,$tool,$run,$time_s,$total_input,$input_tok,$output_tok,$cost_usd,$turns,$accuracy,$error" >> "$CSV"

  rm -f "$tmp_out" "$tmp_prompt" "$tmp_result"
}

# ─── Main ───────────────────────────────────────────────────────────────────

echo "════════════════════════════════════════════════════════════"
echo " Weblens vs Chrome — Benchmark Suite"
printf " Model:   %s\n" "$MODEL"
printf " Runs:    %s per task per tool\n" "$RUNS"
printf " Filter:  %s\n" "${TASK_FILTER:-none (all 26 tasks)}"
printf " Output:  %s\n" "$CSV"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "task,category,tool,run,time_s,total_tok,fresh_tok,output_tok,cost_usd,turns,accuracy,error" > "$CSV"

# Count tasks that pass the filter
total_tasks=0
for i in "${!TASK_IDS[@]}"; do
  task_id="${TASK_IDS[$i]}"
  category="${TASK_CATEGORIES[$i]}"
  if [ -n "$TASK_FILTER" ]; then
    echo ",$TASK_FILTER," | grep -q ",$task_id,\|,$category," || continue
  fi
  total_tasks=$((total_tasks + 1))
done
total_runs=$((total_tasks * RUNS * 2))
printf "Running %s tasks × %s runs × 2 tools = %s agent calls\n\n" \
  "$total_tasks" "$RUNS" "$total_runs"

completed=0
for i in "${!TASK_IDS[@]}"; do
  task_id="${TASK_IDS[$i]}"
  category="${TASK_CATEGORIES[$i]}"
  wl_prompt="${TASK_WL_PROMPTS[$i]}"
  cr_prompt="${TASK_CR_PROMPTS[$i]}"
  expected="${TASK_EXPECTEDS[$i]}"

  if [ -n "$TASK_FILTER" ]; then
    echo ",$TASK_FILTER," | grep -q ",$task_id,\|,$category," || continue
  fi

  completed=$((completed + 1))
  printf "[%s/%s] [%s] %s\n" "$completed" "$total_tasks" "$category" "$task_id"

  for run in $(seq 1 "$RUNS"); do
    run_task "weblens" "$task_id" "$category" "$wl_prompt" "$expected" "$run"
    run_task "chrome"  "$task_id" "$category" "$cr_prompt" "$expected" "$run"
  done
  echo ""
done

cp "$CSV" "$LATEST_CSV"

echo "════════════════════════════════════════════════════════════"
printf " Done. Results: %s\n" "$CSV"
echo ""
printf " Analyze: python3 benchmarks/analyze.py %s\n" "$CSV"
echo "════════════════════════════════════════════════════════════"
