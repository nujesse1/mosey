# mosey-browser

Web CLI for AI agents — navigate and interact with pages via snapshots.

The installed command is `mosey`.

## Install

```sh
npx mosey-browser
```

or for repeated use:

```sh
npm install -g mosey-browser
mosey https://example.com
```

First run also installs Chromium (~170 MB via Playwright's postinstall) and prompts once to add a short block to `~/.claude/CLAUDE.md` so Claude Code uses `mosey` automatically.

macOS Apple Silicon only for now (darwin-arm64). Other platforms TBD.

## Quick start

```sh
mosey https://example.com         # navigate, print snapshot
mosey do e5                       # click element [e5]
mosey do e7 --value "hello"       # type into a field
mosey state                       # re-read current page
mosey session save my_session     # persist cookies
mosey stop                        # kill the daemon
```

## License

Proprietary. See LICENSE. Published as a compiled binary only; source code is not distributed.
