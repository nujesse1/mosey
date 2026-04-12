#!/usr/bin/env bash
# Task definitions for benchmarks/suite.sh
# Uses parallel indexed arrays (bash 3.2 compatible — no associative arrays)

TASK_IDS=()
TASK_CATEGORIES=()
TASK_WL_PROMPTS=()
TASK_CR_PROMPTS=()
TASK_EXPECTEDS=()

# ─── Prompt prefixes ────────────────────────────────────────────────────────

WL_PREFIX="weblens <url> navigates to a URL and returns a text snapshot immediately — no separate state call needed. weblens do <ref> clicks or types and returns an updated snapshot automatically. weblens state --json returns structured JSON. weblens diff shows what changed since the last command. weblens session save/load <name> persists browser state. Use weblens for ALL browsing — no other browser tools."

CR_PREFIX="Use the mcp__claude-in-chrome browser tools for all web browsing. Before using them, call ToolSearch with query 'select:mcp__claude-in-chrome__tabs_create_mcp,mcp__claude-in-chrome__navigate,mcp__claude-in-chrome__read_page,mcp__claude-in-chrome__find,mcp__claude-in-chrome__form_input,mcp__claude-in-chrome__computer,mcp__claude-in-chrome__javascript_tool' to load the tools. Then: call tabs_create_mcp to open a new tab, navigate to load URLs, read_page to read text, find to locate elements, form_input to fill fields. For visual tasks use computer for screenshots and hover interactions."

add_task() {
  TASK_IDS+=("$1")
  TASK_CATEGORIES+=("$2")
  TASK_WL_PROMPTS+=("$3")
  TASK_CR_PROMPTS+=("$4")
  TASK_EXPECTEDS+=("$5")
}

# ─── Category 1: Reading & Extraction ───────────────────────────────────────

add_task "simple_read" "reading" \
  "$WL_PREFIX Navigate to https://the-internet.herokuapp.com and report the page title and the main heading text." \
  "$CR_PREFIX Navigate to https://the-internet.herokuapp.com and report the page title and the main heading text." \
  "welcome,internet"

add_task "table_extract" "reading" \
  "$WL_PREFIX Navigate to https://the-internet.herokuapp.com/tables and extract the Last Name, First Name, and Email for all 4 rows in Table 1. List each row." \
  "$CR_PREFIX Navigate to https://the-internet.herokuapp.com/tables and extract the Last Name, First Name, and Email for all 4 rows in Table 1. List each row." \
  "Smith,Bach,Conway,Doe"

add_task "wiki_facts" "reading" \
  "$WL_PREFIX Navigate to https://en.wikipedia.org/wiki/Playwright_(software) and report the year Playwright was first released." \
  "$CR_PREFIX Navigate to https://en.wikipedia.org/wiki/Playwright_(software) and report the year Playwright was first released." \
  "2020"

add_task "book_price" "reading" \
  "$WL_PREFIX Navigate to https://books.toscrape.com and find and report the exact price of the book titled A Light in the Attic." \
  "$CR_PREFIX Navigate to https://books.toscrape.com and find and report the exact price of the book titled A Light in the Attic." \
  "51.77"

# ─── Category 2: Forms ──────────────────────────────────────────────────────

add_task "form_text_single" "forms" \
  "$WL_PREFIX Navigate to https://httpbin.org/forms/post and fill in only the Customer name field with the value Jane Smith. Report the ref you used and confirm the field shows that value." \
  "$CR_PREFIX Navigate to https://httpbin.org/forms/post and fill in only the Customer name field with the value Jane Smith. Confirm the field shows that value." \
  "Jane,Smith"

add_task "form_text_multi" "forms" \
  "$WL_PREFIX Navigate to https://httpbin.org/forms/post and fill in: Customer name = Jane Smith, Telephone = 555-9999, E-mail = jane@test.com. Report all three fields after filling." \
  "$CR_PREFIX Navigate to https://httpbin.org/forms/post and fill in: Customer name = Jane Smith, Telephone = 555-9999, E-mail = jane@test.com. Report all three fields after filling." \
  "Jane,555-9999,jane@test"

add_task "form_dropdown" "forms" \
  "$WL_PREFIX Navigate to https://the-internet.herokuapp.com/dropdown and select Option 2 from the dropdown. Report what is now selected." \
  "$CR_PREFIX Navigate to https://the-internet.herokuapp.com/dropdown and select Option 2 from the dropdown. Report what is now selected." \
  "Option 2"

add_task "form_radio" "forms" \
  "$WL_PREFIX Navigate to https://httpbin.org/forms/post and click the Large radio button for pizza size. Report which size is now selected." \
  "$CR_PREFIX Navigate to https://httpbin.org/forms/post and click the Large radio button for pizza size. Report which size is now selected." \
  "Large"

add_task "form_checkboxes" "forms" \
  "$WL_PREFIX Navigate to https://httpbin.org/forms/post and check both the Bacon and Extra Cheese checkboxes. Report which toppings are now checked." \
  "$CR_PREFIX Navigate to https://httpbin.org/forms/post and check both the Bacon and Extra Cheese checkboxes. Report which toppings are now checked." \
  "Bacon,Extra Cheese"

add_task "form_submit" "forms" \
  "$WL_PREFIX Navigate to https://httpbin.org/forms/post, fill Customer name = Test User and Telephone = 555-1234, then click Submit order. Report the URL and content of the resulting page." \
  "$CR_PREFIX Navigate to https://httpbin.org/forms/post, fill Customer name = Test User and Telephone = 555-1234, then click Submit order. Report the URL and content of the resulting page." \
  "custname,Test User,post"

# ─── Category 3: Navigation & Multi-step ────────────────────────────────────

add_task "click_link" "navigation" \
  "$WL_PREFIX Navigate to https://the-internet.herokuapp.com and click the link named Form Authentication. Report the URL and heading of the page you land on." \
  "$CR_PREFIX Navigate to https://the-internet.herokuapp.com and click the link named Form Authentication. Report the URL and heading of the page you land on." \
  "Login,Username,Password"

add_task "login_flow" "navigation" \
  "$WL_PREFIX Navigate to https://the-internet.herokuapp.com/login and log in with username tomsmith and password SuperSecretPassword! then report what text appears on the page after logging in successfully." \
  "$CR_PREFIX Navigate to https://the-internet.herokuapp.com/login and log in with username tomsmith and password SuperSecretPassword! then report what text appears on the page after logging in successfully." \
  "secure,logged in,Welcome,Flash"

add_task "multi_step_3" "navigation" \
  "$WL_PREFIX Navigate to https://the-internet.herokuapp.com/add_remove_elements/ and click the Add Element button exactly 3 times. After clicking 3 times, report how many Delete buttons are on the page." \
  "$CR_PREFIX Navigate to https://the-internet.herokuapp.com/add_remove_elements/ and click the Add Element button exactly 3 times. After clicking 3 times, report how many Delete buttons are on the page." \
  "3,three,Delete"

add_task "pagination" "navigation" \
  "$WL_PREFIX Navigate to https://quotes.toscrape.com then click the Next button to go to page 2. Report the text of the first quote shown on page 2." \
  "$CR_PREFIX Navigate to https://quotes.toscrape.com then click the Next button to go to page 2. Report the text of the first quote shown on page 2." \
  "world,choices,Einstein,created,process"

add_task "search_navigate" "navigation" \
  "$WL_PREFIX Navigate to https://en.wikipedia.org/wiki/Main_Page and find the search box. Type Chromium browser and press Enter or click Go. Report the title and opening sentence of the article you land on." \
  "$CR_PREFIX Navigate to https://en.wikipedia.org/wiki/Main_Page and find the search box. Type Chromium browser and submit. Report the title and opening sentence of the article you land on." \
  "Chromium,Google,browser,open-source,web"

# ─── Category 4: Dynamic Content ────────────────────────────────────────────

add_task "dynamic_load" "dynamic" \
  "$WL_PREFIX Navigate to https://the-internet.herokuapp.com/dynamic_loading/1 and click the Start button. Wait a moment then call: weblens state to get the updated page. Report what text appeared after loading." \
  "$CR_PREFIX Navigate to https://the-internet.herokuapp.com/dynamic_loading/1 and click the Start button. Wait for the page to finish loading then read the page and report what text appeared." \
  "Hello,World"

add_task "dynamic_controls" "dynamic" \
  "$WL_PREFIX Navigate to https://the-internet.herokuapp.com/dynamic_controls and click the Remove button. Wait for it to finish, then call weblens state to get updated page. Report whether the checkbox is gone and what message appears." \
  "$CR_PREFIX Navigate to https://the-internet.herokuapp.com/dynamic_controls and click the Remove button. Wait for the operation to complete, then read the page and report whether the checkbox is gone and what message appears." \
  "removed,gone,gone!"

add_task "redirect" "dynamic" \
  "$WL_PREFIX Navigate to https://the-internet.herokuapp.com/redirector and click the redirect link. Report the final URL you ended up on." \
  "$CR_PREFIX Navigate to https://the-internet.herokuapp.com/redirector and click the redirect link. Report the final URL you ended up on." \
  "status_codes,redirect"

add_task "status_404" "dynamic" \
  "$WL_PREFIX Navigate to https://the-internet.herokuapp.com/status_codes/404 and report the status code shown on the page and any message displayed." \
  "$CR_PREFIX Navigate to https://the-internet.herokuapp.com/status_codes/404 and report the status code shown on the page and any message displayed." \
  "404"

# ─── Category 5: Visual Tasks (Chrome expected to win) ──────────────────────
# weblens text snapshots contain no image pixel data — purely visual tasks favor Chrome

add_task "broken_images" "visual" \
  "$WL_PREFIX Navigate to https://the-internet.herokuapp.com/broken_images. The page has images. Inspect the page snapshot and report how many image elements you can see and whether you can determine if any are broken from the text snapshot alone." \
  "$CR_PREFIX Navigate to https://the-internet.herokuapp.com/broken_images. Take a screenshot and count how many broken images you can see (images that fail to load showing a broken icon). Report the count." \
  "broken,image,2,3"

add_task "hover_tooltip" "visual" \
  "$WL_PREFIX Navigate to https://the-internet.herokuapp.com/hovers. Describe what the page shows. If you see any image or figure refs in the snapshot, attempt to hover using weblens do. Report any additional info that appears after the interaction." \
  "$CR_PREFIX Navigate to https://the-internet.herokuapp.com/hovers. Hover over the first image on the page using the computer tool. Report what additional information or tooltip appears after hovering." \
  "name,profile,user,View,Hover,image"

add_task "modal_dialog" "visual" \
  "$WL_PREFIX Navigate to https://demoqa.com/modal-dialogs and find and click the Small modal button. Report the title and body text of the modal that appears, then close it." \
  "$CR_PREFIX Navigate to https://demoqa.com/modal-dialogs and click the Small modal button. Take a screenshot to see the modal. Report the title and body text shown in the modal, then close it." \
  "Small Modal,body,This is,close"

# ─── Category 6: Weblens-Specific Features ──────────────────────────────────

add_task "diff_after_action" "weblens_specific" \
  "$WL_PREFIX Navigate to https://the-internet.herokuapp.com/dynamic_controls and click the Remove button. Then immediately run: weblens diff and report the full diff output showing what changed." \
  "$CR_PREFIX Navigate to https://the-internet.herokuapp.com/dynamic_controls. Take a screenshot to record initial state. Click the Remove button and wait for completion. Take another screenshot. Describe the differences between the before and after states." \
  "removed,gone,changed,checkbox,disappear"

add_task "session_save_load" "weblens_specific" \
  "$WL_PREFIX Navigate to https://quotes.toscrape.com/page/3 to verify you are on page 3. Then run: weblens session save bench_sess_test. Then navigate to https://example.com. Then run: weblens session load bench_sess_test. Then check the current URL with weblens state and report whether you are back at quotes page 3." \
  "$CR_PREFIX Navigate to https://quotes.toscrape.com/page/3 and verify you are on page 3. Note the URL. Then navigate to https://example.com. Then navigate back to https://quotes.toscrape.com/page/3 using the direct URL. Confirm you are on page 3 by reporting the page content." \
  "page/3,page 3,quotes"

add_task "large_page_grep" "weblens_specific" \
  "$WL_PREFIX Navigate to https://en.wikipedia.org/wiki/Python_(programming_language). Then run this bash command and report the number it outputs: weblens state 2>/dev/null | jq -r .snapshot | grep -ci python. If jq is unavailable try: weblens state 2>/dev/null | grep -ci python. Report only the count number." \
  "$CR_PREFIX Navigate to https://en.wikipedia.org/wiki/Python_(programming_language). Read the page and count how many times the word Python (case-insensitive) appears in links, headings, or visible text. Report the approximate count." \
  "python,count,link,mention"

add_task "state_json" "weblens_specific" \
  "$WL_PREFIX Navigate to https://httpbin.org/forms/post then run: weblens state --json 2>/dev/null and parse the JSON output. Report the value of the title field and the url field from the JSON." \
  "$CR_PREFIX Navigate to https://httpbin.org/forms/post. Report the page title and the current URL." \
  "httpbin,forms,Customer,Pizza,Customer name"

# ─── Category 7: Real-World Sites ───────────────────────────────────────────

add_task "hn_top3" "real_world" \
  "$WL_PREFIX Navigate to https://news.ycombinator.com and list the titles of the top 3 stories currently shown on the front page." \
  "$CR_PREFIX Navigate to https://news.ycombinator.com and list the titles of the top 3 stories currently shown on the front page." \
  "points,ago,comments"

add_task "hn_score" "real_world" \
  "$WL_PREFIX Navigate to https://news.ycombinator.com and report the score (number of points) of the number 1 ranked story on the front page." \
  "$CR_PREFIX Navigate to https://news.ycombinator.com and report the score (number of points) of the number 1 ranked story on the front page." \
  "points"
