# scamper

Web CLI for AI agents — navigate and interact with pages via snapshots.

## Install

```sh
npx scamper
```

First run downloads the platform binary (~60 MB) and Chromium (~170 MB via Playwright's postinstall), then prompts to wire up `~/.claude/CLAUDE.md` so Claude Code uses scamper automatically.

For repeated use:

```sh
npm install -g scamper
```

## Quick start

```sh
scamper https://example.com       # navigate and print snapshot
scamper do e5                     # click element [e5]
scamper do e7 --value "hello"     # type into a field
scamper state                     # re-read current page
scamper session save my_session   # persist cookies
scamper stop                      # kill the daemon
```

## License

Proprietary. See LICENSE. Published as a compiled binary only; source code is not distributed.
