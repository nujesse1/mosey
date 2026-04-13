import { Command } from "commander";
import { request, setDaemonArgs } from "./client";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { createInterface } from "node:readline";

// Dispatch: if invoked with the hidden __daemon__ marker, run the daemon instead of the CLI.
// One compiled binary serves both roles (CLI + detached daemon child).
if (process.argv.includes("__daemon__")) {
  await import("./daemon");
  // daemon.ts self-invokes main() which keeps the event loop alive.
  // Block forever here so we don't fall through to CLI code below.
  await new Promise<never>(() => {});
}

const APP_NAME = "mosey";
const STATE_DIR = process.env.MOSEY_DIR ?? join(homedir(), `.${APP_NAME}`);
const SETUP_SENTINEL = join(STATE_DIR, "setup-complete");

const CLAUDE_SENTINEL_OPEN = `<!-- ${APP_NAME}-claude-instructions -->`;
const CLAUDE_SENTINEL_CLOSE = `<!-- end-${APP_NAME}-claude-instructions -->`;
const CLAUDE_SECTION = `
${CLAUDE_SENTINEL_OPEN}
# ${APP_NAME} browser automation
Use \`${APP_NAME}\` CLI commands for ALL web browsing and browser automation. Do NOT use \`mcp__claude-in-chrome__*\` or \`mcp__chrome-devtools__*\` MCP tools — prefer ${APP_NAME} instead.

\`\`\`bash
${APP_NAME} <url>                        # navigate and get page snapshot
${APP_NAME} do <ref>                     # click/interact with element by ref
${APP_NAME} do <ref> --value "text"      # type into an element
${APP_NAME} state                        # get current page state
${APP_NAME} diff                         # see what changed since last command
${APP_NAME} session save/load <name>     # persist/restore sessions
${APP_NAME} stop                         # kill the browser
\`\`\`
${CLAUDE_SENTINEL_CLOSE}
`;

function writeClaudeInstructions(): void {
  const claudeDir = join(homedir(), ".claude");
  const claudeMd = join(claudeDir, "CLAUDE.md");
  try { mkdirSync(claudeDir, { recursive: true }); } catch {}
  let current = "";
  try { current = readFileSync(claudeMd, "utf8"); } catch {}
  if (current.includes(CLAUDE_SENTINEL_OPEN)) {
    process.stderr.write(`[${APP_NAME}] ${claudeMd} already wired up.\n`);
    return;
  }
  const next = current ? current + "\n" + CLAUDE_SECTION : CLAUDE_SECTION.trimStart();
  writeFileSync(claudeMd, next);
  process.stderr.write(`[${APP_NAME}] Added instructions to ${claudeMd}\n`);
}

async function firstRunSetup(): Promise<void> {
  if (existsSync(SETUP_SENTINEL)) return;
  if (!process.stdin.isTTY) return;

  const rl = createInterface({ input: process.stdin, output: process.stderr });
  const ask = (q: string) => new Promise<string>((r) => rl.question(q, r));
  process.stderr.write(`\n👋 Welcome to ${APP_NAME}.\n`);
  const ans = (await ask(`Add ${APP_NAME} instructions to ~/.claude/CLAUDE.md so Claude Code uses it automatically? [Y/n] `)).trim().toLowerCase();
  rl.close();

  if (ans === "" || ans === "y" || ans === "yes") {
    writeClaudeInstructions();
  } else {
    process.stderr.write(`Skipped. Re-run later with: ${APP_NAME} setup\n`);
  }

  mkdirSync(STATE_DIR, { recursive: true });
  writeFileSync(SETUP_SENTINEL, new Date().toISOString());
  process.stderr.write("\n");
}

const program = new Command();

program
  .name(APP_NAME)
  .version("1.0.0")
  .description("Web CLI for AI agents — navigate and interact with pages via snapshots")
  .hook("preAction", async () => { await firstRunSetup(); })
  .option("--headless", "Run browser without visible window")
  .argument("[url]", "URL to navigate to and read (shorthand for navigate + state)")
  .action(async (url?: string) => {
    await firstRunSetup();
    if (!url) {
      program.help();
      return;
    }
    // Default command: navigate + return plain text snapshot
    if (!url.startsWith("http://") && !url.startsWith("https://")) {
      url = `https://${url}`;
    }
    if (program.opts().headless) setDaemonArgs(["--headless"]);
    const result = await request("POST", "/navigate", { url }) as any;
    console.log(`# ${result.title}`);
    console.log(`# ${result.url}`);
    console.log("");
    console.log(result.snapshot);
    if (result.humanActivity) {
      console.log("");
      console.log(`[human activity: ${result.humanActivity.actions.map((a: any) => a.url).join(", ")}]`);
    }
  });

program.hook("preSubcommand", () => {
  if (program.opts().headless) setDaemonArgs(["--headless"]);
});

program
  .command("navigate <url>")
  .description("Navigate to a URL and return snapshot")
  .action(async (url: string) => {
    if (!url.startsWith("http://") && !url.startsWith("https://")) {
      url = `https://${url}`;
    }
    const result = await request("POST", "/navigate", { url }) as any;
    console.log(`# ${result.title}`);
    console.log(`# ${result.url}`);
    console.log("");
    console.log(result.snapshot);
    if (result.humanActivity) {
      console.log("");
      console.log(`[human activity: ${result.humanActivity.actions.map((a: any) => a.url).join(", ")}]`);
    }
  });

program
  .command("state")
  .description("Get page state as plain text (--json for JSON, --full for uncompacted)")
  .option("--full", "Include all elements")
  .option("--json", "Output as JSON instead of plain text")
  .action(async (opts: { full?: boolean; json?: boolean }) => {
    const path = opts.full ? "/state?full=1" : "/state";
    const result = await request("GET", path) as any;
    if (opts.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log(result.snapshot);
    }
  });

program
  .command("do <ref>")
  .description("Interact with an element by ref ID")
  .option("--value <text>", "Value to type/select")
  .option("--key <key>", "Keyboard key to press after action (e.g. Enter, Tab, Escape)")
  .option("--action <type>", "Action to perform: hover (default: click)")
  .action(async (ref: string, opts: { value?: string; key?: string; action?: string }) => {
    const body: any = { ref };
    if (opts.value !== undefined) body.value = opts.value;
    if (opts.key !== undefined) body.key = opts.key;
    if (opts.action !== undefined) body.action = opts.action;
    const result = await request("POST", "/do", body);
    console.log(JSON.stringify(result, null, 2));
  });

program
  .command("diff")
  .description("Show changes since last snapshot")
  .action(async () => {
    const result = await request("GET", "/diff");
    console.log(JSON.stringify(result, null, 2));
  });

const session = program
  .command("session")
  .description("Manage browser sessions");

session
  .command("save <name>")
  .description("Save current session (cookies, storage)")
  .action(async (name: string) => {
    const result = await request("POST", "/session/save", { name });
    console.log(JSON.stringify(result, null, 2));
  });

session
  .command("load <name>")
  .description("Load a saved session")
  .action(async (name: string) => {
    const result = await request("POST", "/session/load", { name });
    console.log(JSON.stringify(result, null, 2));
  });

session
  .command("list")
  .description("List saved sessions")
  .action(async () => {
    const result = await request("GET", "/session/list");
    console.log(JSON.stringify(result, null, 2));
  });

program
  .command("stop")
  .description("Stop the background browser daemon")
  .action(async () => {
    try {
      const result = await request("POST", "/stop");
      console.log(JSON.stringify(result, null, 2));
    } catch {
      console.log(JSON.stringify({ stopped: true, note: "daemon was not running" }));
    }
  });

program
  .command("describe")
  .description(`Output a prompt snippet describing ${APP_NAME} for LLMs`)
  .action(() => {
    console.log(`${APP_NAME} <url> reads a webpage. ${APP_NAME} do <ref> clicks an element. ${APP_NAME} do <ref> --value "x" types. ${APP_NAME} state re-reads. ${APP_NAME} session list/load/save manages auth.`);
  });

program
  .command("setup")
  .description(`(Re-)run the CLAUDE.md wire-up so Claude Code uses ${APP_NAME} automatically`)
  .action(() => {
    writeClaudeInstructions();
    mkdirSync(STATE_DIR, { recursive: true });
    writeFileSync(SETUP_SENTINEL, new Date().toISOString());
  });

program
  .command("links [filter]")
  .description("List all links on the page, optionally filtered by text or URL")
  .action(async (filter?: string) => {
    const path = filter ? `/links?q=${encodeURIComponent(filter)}` : "/links";
    const result = await request("GET", path);
    console.log(JSON.stringify(result, null, 2));
  });

program
  .command("view")
  .description("Open the live browser mirror viewer (screenshot + activity log)")
  .option("--no-open", "Print URL only, don't open browser")
  .action(async (opts: { open: boolean }) => {
    const data = await request("GET", "/viewer-url") as any;
    console.log(data.url);
    if (opts.open !== false) {
      const openCmd = process.platform === "darwin" ? "open" : "xdg-open";
      Bun.spawn([openCmd, data.url], { stdio: ["ignore", "ignore", "inherit"] });
    }
  });

program
  .command("tunnel")
  .description("Expose the viewer publicly via ngrok")
  .action(async () => {
    const data = await request("GET", "/viewer-url") as any;
    const localUrl: string = data.url;
    const port = new URL(localUrl).port;
    const token = new URL(localUrl).searchParams.get("token") ?? "";

    // Check ngrok is available
    const which = Bun.spawnSync(["which", "ngrok"]);
    if (which.exitCode !== 0) {
      console.error("ngrok not found. Install it: brew install ngrok");
      process.exit(1);
    }

    // Start ngrok
    const ngrok = Bun.spawn(["ngrok", "http", port, "--log=false"], {
      stdio: ["ignore", "ignore", "ignore"],
    });

    // Poll ngrok local API for the public URL
    let publicUrl = "";
    for (let i = 0; i < 30; i++) {
      await Bun.sleep(500);
      try {
        const res = await fetch("http://127.0.0.1:4040/api/tunnels", { signal: AbortSignal.timeout(1000) });
        const json = await res.json() as any;
        const tunnel = json.tunnels?.find((t: any) => t.proto === "https");
        if (tunnel?.public_url) { publicUrl = tunnel.public_url; break; }
      } catch {}
    }

    if (!publicUrl) {
      console.error("ngrok failed to start. Is it authenticated? Run: ngrok config add-authtoken <token>");
      ngrok.kill();
      process.exit(1);
    }

    const viewerUrl = `${publicUrl}/viewer?token=${token}`;
    process.stderr.write(`\x1b[1;36mviewer (public): ${viewerUrl}\x1b[0m\n`);
    console.log(viewerUrl);

    // Keep alive — ngrok dies when this process exits
    process.on("SIGINT", () => { ngrok.kill(); process.exit(0); });
    process.on("SIGTERM", () => { ngrok.kill(); process.exit(0); });
    await new Promise(() => {}); // wait forever
  });

program.parseAsync(process.argv).catch((err) => {
  console.error(err.message);
  process.exit(1);
});
