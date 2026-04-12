#!/usr/bin/env bash
# benchmarks/preflight.sh — measure weblens text snapshot sizes for each test URL
#
# Run once before benchmarking to understand context efficiency:
#   bash benchmarks/preflight.sh
#
# This measures how many bytes each URL's snapshot takes as text (weblens)
# vs the estimated size of a Chrome screenshot. The difference explains why
# weblens uses dramatically fewer input tokens.

set -euo pipefail

command -v weblens >/dev/null 2>&1 || { echo "Error: weblens not found (run: bun link)"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Error: python3 not found"; exit 1; }

# Representative URL for each test category
declare -A TEST_URLS
TEST_URLS[simple_read]="https://the-internet.herokuapp.com"
TEST_URLS[table_extract]="https://the-internet.herokuapp.com/tables"
TEST_URLS[wiki_facts]="https://en.wikipedia.org/wiki/Playwright_(software)"
TEST_URLS[book_price]="https://books.toscrape.com"
TEST_URLS[form_page]="https://httpbin.org/forms/post"
TEST_URLS[dropdown]="https://the-internet.herokuapp.com/dropdown"
TEST_URLS[login_page]="https://the-internet.herokuapp.com/login"
TEST_URLS[dynamic_controls]="https://the-internet.herokuapp.com/dynamic_controls"
TEST_URLS[broken_images]="https://the-internet.herokuapp.com/broken_images"
TEST_URLS[hovers]="https://the-internet.herokuapp.com/hovers"
TEST_URLS[demoqa_modals]="https://demoqa.com/modal-dialogs"
TEST_URLS[hn]="https://news.ycombinator.com"
TEST_URLS[python_wiki]="https://en.wikipedia.org/wiki/Python_(programming_language)"

echo "════════════════════════════════════════════════════════════"
echo " Weblens Snapshot Size Preflight"
echo " Measures text snapshot bytes per URL (weblens) vs estimated"
echo " screenshot KB (Chrome). Context efficiency comparison."
echo "════════════════════════════════════════════════════════════"
echo ""
printf "%-32s %12s %18s %14s\n" "Page" "Text bytes" "Est. screenshot" "Ratio"
printf "%-32s %12s %18s %14s\n" "────────────────────────────────" "──────────" "───────────────" "─────────"

# Chrome full-page screenshot estimate: 1280px wide, height varies
# Typical compressed PNG: ~100-600KB. Base64 in JSON: ~1.33x. Then tokenized.
# Claude images: roughly 1 token per 32x32 tile at low res, more at high res.
# Conservative estimate: 1280x800 viewport → ~180KB PNG → ~240KB base64 → ~2000 tokens
# We'll show KB estimate based on typical 1280x800 viewport PNG size.
TYPICAL_SCREENSHOT_KB=180  # median across typical pages

for page_id in $(echo "${!TEST_URLS[@]}" | tr ' ' '\n' | sort); do
  url="${TEST_URLS[$page_id]}"

  echo -n "  Measuring $page_id ... "

  # Kill existing daemon so each measurement starts fresh (avoids cached state)
  weblens stop 2>/dev/null || true
  sleep 0.5

  # Measure snapshot size in bytes
  SNAPSHOT_BYTES=$(weblens navigate "$url" 2>/dev/null | wc -c | tr -d ' ')

  # Estimate Chrome screenshot size (rough heuristic: text-heavy pages have smaller screenshots)
  # We use a fixed estimate since actual screenshot size requires running Chrome
  EST_SCREENSHOT_KB=$TYPICAL_SCREENSHOT_KB

  # Efficiency ratio: how many weblens snapshots fit in one Chrome screenshot
  RATIO=$(python3 -c "
snap = $SNAPSHOT_BYTES
shot_bytes = $EST_SCREENSHOT_KB * 1024
ratio = shot_bytes / snap if snap > 0 else 0
print(f'{ratio:.1f}x')
")

  printf "%-32s %12s %18s %14s\n" \
    "$page_id" \
    "${SNAPSHOT_BYTES} B" \
    "~${EST_SCREENSHOT_KB} KB" \
    "$RATIO"
done

weblens stop 2>/dev/null || true

echo ""
echo "  Note: Screenshot size estimate assumes 1280×800 viewport, ~180KB PNG."
echo "  Actual Chrome token cost depends on image resolution and content."
echo "  Token cost: weblens ~ bytes/4,  Chrome ~ (width×height)/750 tokens/screenshot."
echo ""
echo "  Weblens uses plain text; Chrome sends base64-encoded PNG per page view."
echo "  Multiply turns × screenshot_tokens to estimate Chrome's full context cost."
echo "════════════════════════════════════════════════════════════"
