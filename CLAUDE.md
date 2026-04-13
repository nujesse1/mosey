# mosey

A web execution CLI for AI agents. Runs a browser (visible by default) and exposes structured page state via bash commands. The human sees the browser window and can interact with it — the agent sees the changes automatically.

## Quick Start

```bash
mosey navigate https://example.com   # opens browser, loads page → snapshot included
mosey do e5                           # click element by ref → snapshot included
mosey do e7 --value "hello"           # type into a field → snapshot included
mosey do e9 --action hover            # hover over element → post-hover snapshot included
mosey state                           # re-read page (only needed if page changed on its own)
mosey diff                            # what changed since last command
mosey session save my_session         # persist cookies for later
mosey session load my_session         # restore in a future conversation
mosey session list                    # see saved sessions
mosey stop                            # kill browser
```

## Key Concepts

**Refs:** Every interactive element in the snapshot has a ref like `[e5]`. Use these with `mosey do e5` to interact. Elements marked `[?]` are visible but have no ref (poorly labeled in ARIA). Refs change on each page load — always use refs from the most recent snapshot.

**Snapshots:** `mosey navigate`, `mosey do`, and `mosey hover` all return a snapshot automatically. **Never call `mosey state` after `mosey do` or `mosey hover` — the response already contains the updated snapshot. Calling state immediately after is always redundant and wastes a turn.** Only use `mosey state` when the page changed on its own (e.g. polling, redirects, human activity).

Example snapshot:
```
[e3] link "More information" → https://www.iana.org/help/example-domains
[e6] button "Submit"
[?] textbox "Customer name"
[img1] img "Avatar of Jane"
h1 "Example Domain"
  text: This domain is for use in...
[2 image elements — hover with: mosey hover <ref>]
```

**Images:** Image elements appear in the snapshot with their ARIA ref. Use `mosey do <ref> --action hover` to reveal hover-triggered content (tooltips, overlays, dropdown reveals).

**Counting elements:** After multi-step actions, always count elements by their refs in the snapshot — do not infer from click history. A run of identical elements will show `(×N total)` on the last entry.

**Sessions:** Browser cookies/storage persist with `session save <name>`. Load them in any future conversation. Check `session list` at the start to see what's available.

**Human Activity:** The browser window is visible. The human can click/type/navigate directly. If they do, your next command will include `humanActivity` with what they did. Use judgment: if it's relevant to your task, adjust. If they're helping (navigating somewhere useful), continue with the new state. If unclear, ask them.

**Large Pages:** Some pages produce huge snapshots (LinkedIn ~29KB). Pipe through grep or head to focus:
```bash
mosey state | jq -r '.snapshot' | grep -E '(link|button|heading).*\[ref=' | head -30
```

## Common Patterns

```bash
# Browse and interact
mosey navigate https://example.com
mosey state | jq -r '.snapshot'
mosey do e6                            # click a link
mosey state | jq -r '.url'            # check where we ended up

# Use a saved session (e.g. LinkedIn)
mosey session list                     # check what's saved
mosey session load linkedin_jesse
mosey navigate https://linkedin.com/feed/

# Check what the human did
mosey state | jq '.humanActivity'
```

## Architecture

- **Daemon:** Background Playwright browser, auto-starts on first command, auto-stops after 5 min idle
- **CLI:** Thin HTTP client that talks to the daemon
- **Browser:** Visible by default (use `--headless` to hide)
- **State:** `~/.mosey/daemon.json` (running daemon), `~/.mosey/sessions/` (saved sessions)

## Development

Uses Bun. Prefer Bun APIs (`Bun.serve()`, `Bun.file()`, `Bun.write()`) over Node equivalents.

```bash
bun install                  # install deps
bun link                     # make `mosey` available globally
bunx playwright install chromium  # install browser (first time only)
```
