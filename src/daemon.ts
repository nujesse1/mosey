import { chromium, type Browser, type Page, type BrowserContext } from "playwright";
import { mkdir, unlink, readdir } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";

const WEBLENS_DIR = join(homedir(), ".weblens");
const DAEMON_FILE = join(WEBLENS_DIR, "daemon.json");
const SESSIONS_DIR = join(WEBLENS_DIR, "sessions");
const IDLE_TIMEOUT_MS = 5 * 60 * 1000;

const headless = process.argv.includes("--headless");

let browser: Browser;
let context: BrowserContext;
let page: Page;
let lastSnapshot: string | null = null;
let previousSnapshot: string | null = null;
let lastUrl: string | null = null;
let previousUrl: string | null = null;
let lastAgentActionUrl: string | null = null;
let networkLog: { method: string; url: string; status: number }[] = [];
let idleTimer: ReturnType<typeof setTimeout>;
let agentActing = false;
let humanBuffer: { url: string; title: string; ts: string }[] = [];

function resetIdleTimer() {
  clearTimeout(idleTimer);
  idleTimer = setTimeout(async () => {
    console.error("[weblens] idle timeout, shutting down");
    await shutdown();
  }, IDLE_TIMEOUT_MS);
}

async function shutdown() {
  try { await browser?.close(); } catch {}
  try { await unlink(DAEMON_FILE); } catch {}
  process.exit(0);
}

async function ensurePage(): Promise<Page> {
  if (!page || page.isClosed()) {
    page = await context.newPage();
    setupPageListeners(page);
  }
  return page;
}

function setupPageListeners(p: Page) {
  networkLog = [];
  p.on("response", (res) => {
    const type = res.request().resourceType();
    if (["document", "xhr", "fetch"].includes(type)) {
      networkLog.push({
        method: res.request().method(),
        url: res.request().url(),
        status: res.status(),
      });
    }
  });

  // Track human-initiated navigations
  p.on("framenavigated", async (frame) => {
    if (frame === p.mainFrame() && !agentActing) {
      const url = frame.url();
      if (url && url !== "about:blank" && url !== lastAgentActionUrl) {
        let title = "";
        try { title = await p.title(); } catch {}
        humanBuffer.push({ url, title, ts: new Date().toISOString() });
      }
    }
    // Inject interaction detector
    if (frame === p.mainFrame()) {
      try {
        await frame.evaluate(() => {
          (window as any).__weblens = { humanActive: false, lastEvent: null };
          const mark = (e: Event) => {
            (window as any).__weblens.humanActive = true;
            (window as any).__weblens.lastEvent = e.type;
          };
          document.addEventListener("mousedown", mark, true);
          document.addEventListener("keydown", mark, true);
        });
      } catch {}
    }
  });
}

function compactSnapshot(snapshot: string): string {
  // Flatten the YAML tree into a compact indexed list
  // Only keep: interactive elements, headings, text content, URLs
  const INTERACTIVE = new Set([
    "link", "button", "textbox", "checkbox", "radio",
    "combobox", "searchbox", "switch", "slider", "spinbutton",
    "menuitem", "option", "tab",
  ]);
  const CONTENT = new Set(["heading", "paragraph", "article", "banner", "main", "navigation", "contentinfo", "search"]);

  const lines = snapshot.split("\n");
  const output: string[] = [];
  let lastUrl: string | null = null;

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;

    // Capture URLs and attach to the previous element
    const urlMatch = trimmed.match(/^- \/url:\s*(.+)/);
    if (urlMatch) {
      lastUrl = urlMatch[1].trim();
      // Append URL to previous line if it was a link
      if (output.length > 0 && !output[output.length - 1].includes("→")) {
        output[output.length - 1] += ` → ${lastUrl}`;
      }
      continue;
    }

    // Text content lines
    const textMatch = trimmed.match(/^- text:\s*(.+)/);
    if (textMatch) {
      const text = textMatch[1].replace(/^["']|["']$/g, "").slice(0, 100);
      if (text.length > 2 && text !== "|") {
        output.push(`  text: ${text}`);
      }
      continue;
    }

    // Element lines — handle both `- link "name" [ref=e5]` and `- 'link "name" [ref=e5]':`
    const roleMatch = trimmed.match(/^-\s+'?(\w+)(?:\s+"([^"]*)")?/);
    if (!roleMatch || !roleMatch[1]) continue;
    const refMatch = trimmed.match(/\[ref=(\w+)\]/);

    const role = roleMatch[1];
    const name = roleMatch[2];
    const ref = refMatch?.[1];

    // Interactive elements — always include
    if (INTERACTIVE.has(role)) {
      const nameStr = name ? ` "${name.slice(0, 80)}"` : "";
      const refStr = ref ? `[${ref}]` : "[?]";
      const checkedStr = trimmed.includes("[checked]") ? " [checked]" : "";
      output.push(`${refStr} ${role}${nameStr}${checkedStr}`);
      lastUrl = null;
      continue;
    }

    // Headings — always include
    if (role === "heading") {
      const levelMatch = trimmed.match(/\[level=(\d)\]/);
      const level = levelMatch ? `h${levelMatch[1]}` : "heading";
      const nameStr = name ? ` "${name.slice(0, 100)}"` : "";
      output.push(`${level}${nameStr}`);
      continue;
    }

    // Landmark regions — include as context markers
    if (CONTENT.has(role) && name) {
      output.push(`--- ${role}: ${name.slice(0, 60)} ---`);
      continue;
    }

    // Paragraphs with inline text
    if (role === "paragraph") {
      const inlineText = trimmed.match(/:\s+(.{3,})/);
      if (inlineText) {
        output.push(`  text: ${inlineText[1].slice(0, 120)}`);
      }
      continue;
    }
  }

  const result = output.join("\n");
  const MAX_CHARS = 10000;
  if (result.length > MAX_CHARS) {
    return result.slice(0, MAX_CHARS) + "\n... (truncated — use `weblens state --full` for complete snapshot)";
  }
  return result;
}

function parseRefFromSnapshot(snapshot: string, ref: string): { role: string; name?: string } | null {
  const lines = snapshot.split("\n");
  const refPattern = new RegExp(`\\[ref=${ref}\\]`);
  for (const line of lines) {
    if (refPattern.test(line)) {
      const match = line.match(/-\s+(\w+)(?:\s+"([^"]*)")?/);
      if (match) {
        return { role: match[1], name: match[2] };
      }
    }
  }
  return null;
}

function diffSnapshots(prev: string, curr: string): unknown[] {
  const prevLines = new Set(prev.split("\n").map((l) => l.trim()).filter(Boolean));
  const currLines = new Set(curr.split("\n").map((l) => l.trim()).filter(Boolean));
  const changes: unknown[] = [];

  for (const line of currLines) {
    if (!prevLines.has(line)) {
      const match = line.match(/-\s+(\w+)(?:\s+"([^"]*)")?\s*(?:\[ref=(\w+)\])?/);
      if (match) {
        changes.push({ type: "added", role: match[1], name: match[2] ?? null, ref: match[3] ?? null });
      }
    }
  }
  for (const line of prevLines) {
    if (!currLines.has(line)) {
      const match = line.match(/-\s+(\w+)(?:\s+"([^"]*)")?\s*(?:\[ref=(\w+)\])?/);
      if (match) {
        changes.push({ type: "removed", role: match[1], name: match[2] ?? null, ref: match[3] ?? null });
      }
    }
  }
  return changes;
}

// Drain the human activity buffer — returns what the human did since the last agent command
function drainHumanActivity(): { humanTookOver: boolean; actions: typeof humanBuffer } | null {
  if (humanBuffer.length === 0) return null;
  const actions = [...humanBuffer];
  humanBuffer = [];
  return {
    humanTookOver: true,
    actions,
    note: "The human interacted with the browser between your commands. Decide: if this is relevant to your current task, adjust your plan or ask the human what they need. If they seem to be helping (e.g. navigating to a page you need), continue with the new state. If it seems unrelated, keep going with your task.",
  };
}

async function handleRequest(req: Request): Promise<Response> {
  resetIdleTimer();
  const url = new URL(req.url);
  const path = url.pathname;
  const json = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data, null, 2), {
      status,
      headers: { "Content-Type": "application/json" },
    });

  try {
    if (path === "/health") {
      return json({ status: "ok", pid: process.pid, headless });
    }

    if (path === "/navigate" && req.method === "POST") {
      const humanActivity = drainHumanActivity();
      const body = (await req.json()) as { url: string };
      const p = await ensurePage();
      networkLog = [];
      agentActing = true;
      const response = await p.goto(body.url, { waitUntil: "domcontentloaded", timeout: 30000 });
      previousSnapshot = null;
      previousUrl = lastUrl;
      lastSnapshot = await p.ariaSnapshot({ mode: "ai" });
      lastUrl = p.url();
      lastAgentActionUrl = p.url();
      agentActing = false;
      const result: any = {
        url: p.url(),
        title: await p.title(),
        status: response?.status() ?? null,
        snapshot: compactSnapshot(lastSnapshot),
      };
      if (humanActivity) result.humanActivity = humanActivity;
      return json(result);
    }

    if (path === "/state" && req.method === "GET") {
      const humanActivity = drainHumanActivity();
      const p = await ensurePage();
      const full = url.searchParams.get("full") === "1";
      const depth = url.searchParams.get("depth") ? parseInt(url.searchParams.get("depth")!) : undefined;
      const limit = url.searchParams.get("limit") ? parseInt(url.searchParams.get("limit")!) : undefined;
      previousSnapshot = lastSnapshot;
      previousUrl = lastUrl;
      lastSnapshot = await p.ariaSnapshot({ mode: "ai", ...(depth ? { depth } : {}) });
      lastUrl = p.url();
      lastAgentActionUrl = p.url();
      let snapshot = full ? lastSnapshot : compactSnapshot(lastSnapshot);
      if (limit && snapshot.length > limit) {
        snapshot = snapshot.slice(0, limit) + "\n... (truncated)";
      }
      const result: any = { url: p.url(), title: await p.title(), snapshot };
      if (humanActivity) result.humanActivity = humanActivity;
      return json(result);
    }

    if (path === "/do" && req.method === "POST") {
      const body = (await req.json()) as { ref: string; value?: string };
      const p = await ensurePage();
      networkLog = [];
      previousSnapshot = lastSnapshot;
      previousUrl = lastUrl;

      const humanActivity = drainHumanActivity();
      const parsed = parseRefFromSnapshot(lastSnapshot ?? "", body.ref);
      if (!parsed) {
        return json({ error: `ref "${body.ref}" not found in snapshot` }, 404);
      }

      const locator = p.getByRole(parsed.role as any, parsed.name ? { name: parsed.name, exact: false } : undefined).first();

      agentActing = true;
      let actionDesc = "click";
      if (body.value !== undefined) {
        await locator.fill(body.value);
        actionDesc = "fill";
      } else {
        await locator.click();
      }

      await p.waitForTimeout(500);
      lastSnapshot = await p.ariaSnapshot({ mode: "ai" });
      lastUrl = p.url();
      lastAgentActionUrl = p.url();
      agentActing = false;

      const result: any = { success: true, action: actionDesc, ref: body.ref, name: parsed.name ?? null, snapshot: compactSnapshot(lastSnapshot), url: p.url() };
      if (humanActivity) result.humanActivity = humanActivity;
      return json(result);
    }

    if (path === "/diff" && req.method === "GET") {
      const humanActivity = drainHumanActivity();
      const p = await ensurePage();
      const freshSnapshot = await p.ariaSnapshot({ mode: "ai" });
      const currentUrl = p.url();
      const prev = previousSnapshot ?? lastSnapshot ?? "";
      const changes = diffSnapshots(prev, freshSnapshot);
      const urlChanged = previousUrl && previousUrl !== currentUrl
        ? { from: previousUrl, to: currentUrl }
        : null;
      previousSnapshot = lastSnapshot;
      previousUrl = lastUrl;
      lastSnapshot = freshSnapshot;
      lastUrl = currentUrl;
      lastAgentActionUrl = currentUrl;
      const result: any = {
        url: currentUrl,
        title: await p.title(),
        urlChanged,
        changes,
        network: networkLog,
      };
      if (humanActivity) result.humanActivity = humanActivity;
      return json(result);
    }

    if (path === "/current-url" && req.method === "GET") {
      const p = await ensurePage();
      return json({ url: p.url(), title: await p.title() });
    }

    if (path === "/session/save" && req.method === "POST") {
      const body = (await req.json()) as { name: string };
      const sessionDir = join(SESSIONS_DIR, body.name);
      await mkdir(sessionDir, { recursive: true });

      const state = await context.storageState();
      await Bun.write(join(sessionDir, "state.json"), JSON.stringify(state, null, 2));

      const p = await ensurePage();
      const domains = [...new Set(state.cookies.map((c: any) => c.domain))];
      const meta = { name: body.name, domains, savedAt: new Date().toISOString(), url: p.url() };
      await Bun.write(join(sessionDir, "meta.json"), JSON.stringify(meta, null, 2));

      return json({ saved: true, name: body.name, domains });
    }

    if (path === "/session/load" && req.method === "POST") {
      const body = (await req.json()) as { name: string };
      const stateFile = Bun.file(join(SESSIONS_DIR, body.name, "state.json"));
      if (!(await stateFile.exists())) {
        return json({ error: `session "${body.name}" not found` }, 404);
      }

      const state = await stateFile.json();
      const newContext = await browser.newContext({
        storageState: state as any,
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
      });
      await context.close();
      context = newContext;
      page = await context.newPage();
      setupPageListeners(page);

      return json({ loaded: true, name: body.name });
    }

    if (path === "/session/list" && req.method === "GET") {
      const sessions: unknown[] = [];
      try {
        const dirs = await readdir(SESSIONS_DIR);
        for (const dir of dirs) {
          const metaFile = Bun.file(join(SESSIONS_DIR, dir, "meta.json"));
          if (await metaFile.exists()) {
            sessions.push(await metaFile.json());
          }
        }
      } catch {}
      return json(sessions);
    }

    if (path === "/stop" && req.method === "POST") {
      setTimeout(() => shutdown(), 100);
      return json({ stopped: true });
    }

    return json({ error: "not found" }, 404);
  } catch (err: any) {
    return json({ error: err.message ?? String(err) }, 500);
  }
}

async function main() {
  await mkdir(WEBLENS_DIR, { recursive: true });
  await mkdir(SESSIONS_DIR, { recursive: true });

  browser = await chromium.launch({ headless });
  context = await browser.newContext({
    userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
  });
  page = await context.newPage();
  setupPageListeners(page);

  const server = Bun.serve({
    port: 0,
    hostname: "127.0.0.1",
    fetch: handleRequest,
  });

  await Bun.write(DAEMON_FILE, JSON.stringify({
    pid: process.pid,
    port: server.port,
    headless,
    startedAt: new Date().toISOString(),
  }));
  console.error(`[weblens] daemon started on port ${server.port} (pid ${process.pid})${headless ? " [headless]" : ""}`);
  resetIdleTimer();

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}

main().catch((err) => {
  console.error("[weblens] daemon failed to start:", err.message);
  process.exit(1);
});
