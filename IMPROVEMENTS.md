# Weblens — Issues to Solve

Sourced from benchmark run 2026-04-11 (15 tasks, weblens vs mcp__claude-in-chrome).
Each issue has a concrete failure example. Agents should propose solutions without running the full benchmark — read the problem, read the relevant source files, and design a fix.

---

## 1. Visual hover state not exposed in snapshot

**Problem:** Hover-triggered content (tooltips, overlays, dropdown reveals) is absent from weblens text snapshots. The agent has no indication that hovering would reveal additional content, so it either ignores it or thrashes.

**Benchmark result:** `hover_tooltip` — weblens spent **83 seconds and 322,970 tokens** (15 turns) attempting to interact with a page where the key content only appears on hover. Final accuracy: 83%. Chrome: 34s, 97K tokens, 100%.

**Example page:** `https://the-internet.herokuapp.com/hovers`
The page has three user avatar images. Hovering each reveals a name + "View profile" link. The weblens snapshot of this page shows:
```
h1 "Hovers"
  text: Hover over the images below to see the hidden text
```
No image refs appear — the agent sees only the heading and description, has nothing to interact with, and cannot complete the task.

**What needs to change:** Either (a) expose image elements with refs so the agent can attempt hover interactions via `weblens do`, (b) add a `weblens hover <ref>` command that triggers `mouseover`/`mouseenter` and returns a post-hover snapshot, or (c) annotate the snapshot to indicate that hovering over certain elements would reveal content.

**Relevant source:** `src/daemon.ts` — `compactSnapshot()` filters the ARIA snapshot; `POST /do` handles interactions.

---

## 2. Agent doesn't fail fast on visual-only tasks

**Problem:** When a task requires pixel-level perception (images, hover states, broken image detection), weblens gives the agent no signal that the information is unavailable. The agent wastes many turns attempting workarounds instead of quickly reporting the limitation.

**Benchmark result:** `hover_tooltip` — 15 turns, 83 seconds. The agent tried multiple approaches (calling `weblens state --full`, attempting refs that didn't exist, re-reading the page multiple times) before settling on a partial answer. A fast-fail would have been 1–2 turns.

**Example failure pattern:** Agent calls `weblens navigate https://the-internet.herokuapp.com/hovers`, receives a snapshot with no image refs, then proceeds to call `weblens state`, `weblens state --full`, tries to infer element refs, and eventually makes up an answer. Total wasted turns: ~13.

**What needs to change:** When `compactSnapshot()` drops image/figure elements that exist in the full ARIA tree, it could emit a note like `[3 image elements — use weblens hover <ref> or a visual tool to inspect]`. This tells the agent immediately what's missing and why, enabling a 1-turn decision rather than multi-turn thrashing.

**Relevant source:** `src/daemon.ts` — `compactSnapshot()` around line 130–160.

---

## 3. Images have no refs and are silently dropped from snapshot

**Problem:** Image elements (`<img>`) are not interactive in standard ARIA, so they get no ref and are dropped by `compactSnapshot()`. The agent cannot reference, click, or hover them. There is no indication in the snapshot that images exist on the page.

**Benchmark result:** `broken_images` — weblens correctly identified broken images (acc=1.0) but only because the page's alt text and surrounding text leaked the information. On pages without descriptive alt text, the agent would have 0 information. Chrome used 3x more tokens (115K vs 37K) but at least could see the images visually.

**Example:** `https://the-internet.herokuapp.com/broken_images` has 3 `<img>` tags (2 broken, 1 valid). The weblens snapshot contains no image entries. The agent inferred the answer from page text — not from actually seeing the images.

**What needs to change:** Include `img` elements in the snapshot output with their `alt` text, `src` (or just the filename), and a synthesized ref. Example output:
```
[e3] img "Broken image" src="asdf.png"
[e4] img "Broken image" src="hjkl.png"
[e5] img "Valid image" src="img1.png"
```
This would also enable future hover/interact support on images.

**Relevant source:** `src/daemon.ts` — `INTERACTIVE` set definition and `compactSnapshot()`.

---

## 4. Multi-step click counting fails — snapshot doesn't show cumulative state clearly

**Problem:** When an agent adds elements repeatedly (e.g. clicking "Add Element" 3 times), the snapshot after each click shows the new state, but agents consistently fail to count the resulting elements correctly.

**Benchmark result:** `multi_step_3` — both weblens and Chrome scored 67% (neither confirmed "3 Delete buttons"). The task: navigate to `/add_remove_elements/`, click "Add Element" 3 times, report count. Both tools made 5–7 turns but neither reported the correct count with confidence.

**Example failure:** After 3 clicks, the snapshot shows:
```
[e5] button "Delete"
[e6] button "Delete"
[e7] button "Delete"
[e11] button "Add Element"
```
The agent should count 3, but frequently reports "I clicked Add Element 3 times" without explicitly counting the resulting buttons, causing partial keyword match failure.

**What needs to change:** This is likely a prompt/snapshot clarity issue. The snapshot could annotate repeated identical elements: `[e5–e7] button "Delete" ×3`. Alternatively, the AGENTS.md / weblens instructions could explicitly tell agents to call `weblens state` and count refs after multi-step actions rather than inferring from click history.

**Relevant source:** `src/daemon.ts` — `compactSnapshot()` output formatting; `AGENTS.md` / `CLAUDE.md` agent instructions.

---

## 5. form_submit is slow — weblens takes 2× more turns than Chrome for multi-field forms with submission

**Problem:** For tasks that fill multiple fields and submit a form, weblens uses significantly more turns than Chrome. This drives up latency and cost.

**Benchmark result:** `form_submit` — weblens: **57 seconds, 13 turns, $0.142**. Chrome: 26.8 seconds, 9 turns, $0.101. Weblens was actually more accurate (100% vs Chrome's 67%) but took twice as long due to extra turns.

**Root cause hypothesis:** Each `weblens do <ref> --value "..."` call fills one field and returns a new snapshot. The agent then re-reads the snapshot to confirm the fill before moving to the next field, adding a verification turn per field. Chrome's `form_input` tool can fill multiple fields in fewer calls.

**Example turn sequence (weblens, form_submit):**
```
Turn 1: weblens navigate https://httpbin.org/forms/post
Turn 2: weblens do e5 --value "Test User"       # fill name
Turn 3: weblens state                             # verify name filled ← extra turn
Turn 4: weblens do e8 --value "555-1234"         # fill phone
Turn 5: weblens state                             # verify ← extra turn
Turn 6: weblens do e44                            # submit
...
```

**What needs to change:** Either (a) the agent instructions should explicitly say "do NOT call `weblens state` after each `do` — the returned snapshot already shows the updated state", or (b) add a batch fill command like `weblens fill e5="Test User" e8="555-1234"` that fills multiple fields in one daemon call. The agent instructions already say this in CLAUDE.md, but agents are not following it.

**Relevant source:** `CLAUDE.md` / `AGENTS.md` — reinforce "do returns a snapshot, no state call needed"; `src/daemon.ts` `POST /do` and `POST /navigate` for potential batch-fill endpoint.

---

## 6. table_extract is 2.6× slower with Chrome — no structural advantage from DOM

**Problem:** Chrome takes 69.5s and 233K tokens to extract a simple HTML table that weblens handles in 26.7s and 118K tokens. This is the inverse of what you'd expect — Chrome has full DOM access yet performs worse on structured data.

**Benchmark result:** `table_extract` — weblens: 26.7s, 6 turns, $0.083. Chrome: 69.5s, 11 turns, $0.162. Both 100% accuracy.

**Root cause:** Chrome's MCP tools appear to navigate the page, take a snapshot/screenshot, then extract table data through visual or text parsing across many turns. Weblens's compact ARIA snapshot exposes the table rows directly as text refs, which the agent can read in one pass.

**This is not necessarily a weblens bug** — it validates the design. But it suggests weblens could emphasize table/structured data extraction as a primary strength in documentation and agent prompts, and potentially add a `weblens table <ref>` command that returns table data as JSON directly.

**Relevant source:** `src/daemon.ts` — consider adding a `/table` endpoint that returns `{ headers: [], rows: [[]] }` for a given table ref. `src/cli.ts` — add `weblens table <ref>` command.
