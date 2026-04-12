# Weblens — Agent Instructions

## What This Is

Weblens is a web execution CLI for AI agents. It runs a visible browser and exposes structured page state via bash commands. The human can see and interact with the browser window — the agent sees their changes automatically.

## Commands

```
weblens navigate <url>              # load a page → snapshot included (no need for state after)
weblens state                       # re-read current page → snapshot
weblens do <ref> [--value "text"]   # click/type by ref ID → snapshot included (no need for state after)
weblens diff                        # what changed → {changes, network, urlChanged}
weblens session list                # list saved sessions (check this first!)
weblens session save <name>         # persist cookies/storage
weblens session load <name>         # restore a saved session
weblens stop                        # kill background browser
weblens describe                    # print full reference for LLM prompts
```

## Output

`weblens navigate` and `weblens do` output plain text snapshots directly. `weblens state`, `weblens diff`, and session commands output JSON.

## Snapshots and Refs

Both `weblens navigate` and `weblens do` return a snapshot automatically — **you don't need a separate `state` call after them**.

The snapshot is compact text. Each interactive element has a `[ref=eN]` ID you can pass to `do`. Elements marked `[?]` exist but have no ref (poorly labeled in ARIA) — use `weblens state --full` to inspect them.

```
[e3] link "More information" → https://www.iana.org/help/example-domains
[e6] button "Submit"
[?] textbox "Customer name"
h1 "Example Domain"
```

Use refs with `weblens do e6` to interact. Refs change on each page load — get a fresh snapshot before using refs.

## Human Activity

The browser is visible by default. If the human clicks/navigates in the browser window, your next command includes `humanActivity` with what they did. Use judgment — adjust if relevant, continue if not, ask if unclear.

## Sessions

Before navigating to a site you've used before, check `weblens session list`. Load a session to restore cookies/auth without logging in again.

## Large Pages

Some pages produce huge snapshots. Filter with:
```bash
weblens state | jq -r '.snapshot' | head -40
weblens state | jq -r '.snapshot' | grep -E '(link|button|heading).*\[ref='
```

## Building

```bash
bun install
bun link                          # makes `weblens` available globally
bunx playwright install chromium  # first time only
```
