# mosey

Web CLI for AI agents — navigate and interact with pages via snapshots.

A local Playwright browser you drive from the shell. The human sees the browser window; the agent reads structured snapshots and clicks elements by ref. Built for Claude Code and similar agents.

## Install

```sh
npx mosey
```

That's it. First run downloads Bun and Chromium (one-time, ~250MB), then prompts to wire up `~/.claude/CLAUDE.md` so Claude Code uses mosey automatically in every project.

For repeated use, install globally once:

```sh
npm install -g mosey
```

## Quick start

```sh
mosey https://example.com        # navigate and print snapshot
mosey do e5                      # click element [e5] from the snapshot
mosey do e7 --value "hello"      # type into a field
mosey state                      # re-read current page
mosey session save my_session    # persist cookies
mosey stop                       # kill the daemon
```

See the in-repo `CLAUDE.md` for full command reference and snapshot format.

## What the first-run setup does

Prompts once before adding a short section to `~/.claude/CLAUDE.md` telling Claude to prefer `mosey` commands over other browser-automation MCP tools. Skip with `n`; re-run later via `mosey setup`.

## License

MIT
