#!/usr/bin/env node
/**
 * Writes the mosey browser-automation instructions block to ~/.claude/CLAUDE.md.
 * Idempotent via sentinel marker. Plain Node; no Bun APIs.
 */
const { homedir } = require("os");
const { join } = require("path");
const fs = require("fs");

const SENTINEL_OPEN = "<!-- mosey-claude-instructions -->";
const SENTINEL_CLOSE = "<!-- end-mosey-claude-instructions -->";
const CLAUDE_DIR = join(homedir(), ".claude");
const CLAUDE_MD = join(CLAUDE_DIR, "CLAUDE.md");

const SECTION = `
${SENTINEL_OPEN}
# mosey browser automation
Use \`mosey\` CLI commands for ALL web browsing and browser automation. Do NOT use \`mcp__claude-in-chrome__*\` or \`mcp__chrome-devtools__*\` MCP tools — prefer mosey instead.

\`\`\`bash
mosey <url>                        # navigate and get page snapshot
mosey do <ref>                     # click/interact with element by ref
mosey do <ref> --value "text"      # type into an element
mosey state                        # get current page state
mosey diff                         # see what changed since last command
mosey session save/load <name>     # persist/restore sessions
mosey stop                         # kill the browser
\`\`\`
${SENTINEL_CLOSE}
`;

function run() {
  try {
    fs.mkdirSync(CLAUDE_DIR, { recursive: true });
  } catch {}

  let current = "";
  if (fs.existsSync(CLAUDE_MD)) {
    current = fs.readFileSync(CLAUDE_MD, "utf8");
  }

  if (current.includes(SENTINEL_OPEN)) {
    console.log(`[mosey] ${CLAUDE_MD} already has mosey instructions — skipping.`);
    return;
  }

  const next = current ? current + "\n" + SECTION : SECTION.trimStart();
  fs.writeFileSync(CLAUDE_MD, next);
  console.log(`[mosey] Added mosey instructions to ${CLAUDE_MD}`);
}

try {
  run();
} catch (err) {
  console.warn(`[mosey] Could not update CLAUDE.md: ${err && err.message ? err.message : err}`);
}
