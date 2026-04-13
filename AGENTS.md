# Mosey — Agent Instructions

## What This Is

Mosey is a web execution CLI for AI agents. It runs a visible browser and exposes structured page state via bash commands. The human can see and interact with the browser window — the agent sees their changes automatically.

## Commands

```
mosey navigate <url>              # load a page → snapshot included (no need for state after)
mosey state                       # re-read current page → snapshot
mosey do <ref> [--value "text"]   # click/type by ref ID → snapshot included (no need for state after)
mosey diff                        # what changed → {changes, network, urlChanged}
mosey session list                # list saved sessions (check this first!)
mosey session save <name>         # persist cookies/storage
mosey session load <name>         # restore a saved session
mosey stop                        # kill background browser
mosey describe                    # print full reference for LLM prompts
```

## Output

`mosey navigate` and `mosey do` output plain text snapshots directly. `mosey state`, `mosey diff`, and session commands output JSON.

## Snapshots and Refs

Both `mosey navigate` and `mosey do` return a snapshot automatically — **you don't need a separate `state` call after them**.

The snapshot is compact text. Each interactive element has a `[ref=eN]` ID you can pass to `do`. Elements marked `[?]` exist but have no ref (poorly labeled in ARIA) — use `mosey state --full` to inspect them.

```
[e3] link "More information" → https://www.iana.org/help/example-domains
[e6] button "Submit"
[?] textbox "Customer name"
h1 "Example Domain"
```

Use refs with `mosey do e6` to interact. Refs change on each page load — get a fresh snapshot before using refs.

## Human Activity

The browser is visible by default. If the human clicks/navigates in the browser window, your next command includes `humanActivity` with what they did. Use judgment — adjust if relevant, continue if not, ask if unclear.

## Sessions

Before navigating to a site you've used before, check `mosey session list`. Load a session to restore cookies/auth without logging in again.

## Large Pages

Some pages produce huge snapshots. Filter with:
```bash
mosey state | jq -r '.snapshot' | head -40
mosey state | jq -r '.snapshot' | grep -E '(link|button|heading).*\[ref='
```

## Building

```bash
bun install
bun link                          # makes `mosey` available globally
bunx playwright install chromium  # first time only
```
