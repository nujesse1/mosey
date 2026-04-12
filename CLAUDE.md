# weblens

A web execution CLI for AI agents. Runs a browser (visible by default) and exposes structured page state via bash commands. The human sees the browser window and can interact with it — the agent sees the changes automatically.

## Quick Start

```bash
weblens navigate https://example.com   # opens browser, loads page → snapshot included
weblens do e5                           # click element by ref → snapshot included
weblens do e7 --value "hello"           # type into a field → snapshot included
weblens state                           # re-read page (only needed if page changed on its own)
weblens diff                            # what changed since last command
weblens session save my_session         # persist cookies for later
weblens session load my_session         # restore in a future conversation
weblens session list                    # see saved sessions
weblens stop                            # kill browser
```

## Key Concepts

**Refs:** Every interactive element in the snapshot has a ref like `[e5]`. Use these with `weblens do e5` to interact. Elements marked `[?]` are visible but have no ref (poorly labeled in ARIA). Refs change on each page load — always use refs from the most recent snapshot.

**Snapshots:** `weblens navigate` and `weblens do` both return a snapshot automatically. Example:
```
[e3] link "More information" → https://www.iana.org/help/example-domains
[e6] button "Submit"
[?] textbox "Customer name"
h1 "Example Domain"
  text: This domain is for use in...
```

**Sessions:** Browser cookies/storage persist with `session save <name>`. Load them in any future conversation. Check `session list` at the start to see what's available.

**Human Activity:** The browser window is visible. The human can click/type/navigate directly. If they do, your next command will include `humanActivity` with what they did. Use judgment: if it's relevant to your task, adjust. If they're helping (navigating somewhere useful), continue with the new state. If unclear, ask them.

**Large Pages:** Some pages produce huge snapshots (LinkedIn ~29KB). Pipe through grep or head to focus:
```bash
weblens state | jq -r '.snapshot' | grep -E '(link|button|heading).*\[ref=' | head -30
```

## Common Patterns

```bash
# Browse and interact
weblens navigate https://example.com
weblens state | jq -r '.snapshot'
weblens do e6                            # click a link
weblens state | jq -r '.url'            # check where we ended up

# Use a saved session (e.g. LinkedIn)
weblens session list                     # check what's saved
weblens session load linkedin_jesse
weblens navigate https://linkedin.com/feed/

# Check what the human did
weblens state | jq '.humanActivity'
```

## Architecture

- **Daemon:** Background Playwright browser, auto-starts on first command, auto-stops after 5 min idle
- **CLI:** Thin HTTP client that talks to the daemon
- **Browser:** Visible by default (use `--headless` to hide)
- **State:** `~/.weblens/daemon.json` (running daemon), `~/.weblens/sessions/` (saved sessions)

## Development

Uses Bun. Prefer Bun APIs (`Bun.serve()`, `Bun.file()`, `Bun.write()`) over Node equivalents.

```bash
bun install                  # install deps
bun link                     # make `weblens` available globally
bunx playwright install chromium  # install browser (first time only)
```
