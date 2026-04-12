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

// Viewer state
let viewerToken = "";
let daemonPort = 0;
const sseClients = new Set<ReadableStreamDefaultController>();
const MAX_ACTION_LOG = 50;
let actionLog: Array<{ time: string; type: string; description: string }> = [];
const sseEncoder = new TextEncoder();

// ── Viewer helpers ────────────────────────────────────────────────────────────

function generateToken(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

function logAction(type: string, description: string) {
  actionLog.push({ time: new Date().toISOString(), type, description });
  if (actionLog.length > MAX_ACTION_LOG) actionLog = actionLog.slice(-MAX_ACTION_LOG);
}

function broadcastSSE(event: string, data: unknown) {
  const payload = sseEncoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  for (const c of sseClients) {
    try { c.enqueue(payload); } catch { sseClients.delete(c); }
  }
}

function checkAuth(req: Request): boolean {
  const reqUrl = new URL(req.url);
  if (reqUrl.searchParams.get("token") === viewerToken && viewerToken !== "") return true;
  const cookieHeader = req.headers.get("cookie") ?? "";
  const cookies = Object.fromEntries(
    cookieHeader.split(";").map((c) => {
      const [k, ...v] = c.trim().split("=");
      return [(k ?? "").trim(), v.join("=")];
    })
  );
  return cookies["weblens-token"] === viewerToken && viewerToken !== "";
}

function unauthorized() {
  return new Response(JSON.stringify({ error: "unauthorized" }), {
    status: 401,
    headers: { "Content-Type": "application/json" },
  });
}

// ── HTML templates ────────────────────────────────────────────────────────────

const AUTH_FORM_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>weblens viewer</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  background: #0f0f0f; color: #e0e0e0;
  display: flex; align-items: center; justify-content: center; min-height: 100vh;
}
.card {
  background: #1a1a1a; border: 1px solid #2a2a2a; border-radius: 12px;
  padding: 2rem; width: 320px; text-align: center;
}
h1 { font-size: 1rem; color: #666; margin-bottom: 1.5rem; letter-spacing: 0.08em; text-transform: uppercase; }
input {
  width: 100%; padding: 0.7rem 1rem; background: #111; border: 1px solid #333;
  border-radius: 8px; color: #e0e0e0; font-size: 0.9rem; margin-bottom: 0.75rem;
  font-family: monospace; outline: none;
}
input:focus { border-color: #4a90d9; }
button {
  width: 100%; padding: 0.7rem; background: #4a90d9; border: none;
  border-radius: 8px; color: #fff; font-size: 0.9rem; cursor: pointer; font-weight: 500;
}
button:hover { background: #357abd; }
</style>
</head>
<body>
<div class="card">
  <h1>weblens viewer</h1>
  <input type="text" id="tok" placeholder="paste token" autofocus />
  <button onclick="go()">Open</button>
</div>
<script>
document.getElementById('tok').addEventListener('keydown', function(e) {
  if (e.key === 'Enter') go();
});
function go() {
  var t = document.getElementById('tok').value.trim();
  if (t) location.href = '/viewer?token=' + encodeURIComponent(t);
}
</script>
</body>
</html>`;

const VIEWER_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>weblens live viewer</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  background: #0f0f0f; color: #e0e0e0; height: 100vh;
  display: flex; flex-direction: column; overflow: hidden;
}
header {
  background: #141414; border-bottom: 1px solid #222;
  padding: 0.5rem 1rem; display: flex; align-items: center; gap: 0.6rem; flex-shrink: 0;
}
.dot { width: 7px; height: 7px; border-radius: 50%; background: #4caf50; flex-shrink: 0; transition: background 0.3s; }
.dot.off { background: #444; }
#url-bar {
  font-family: monospace; font-size: 0.82rem; color: #888;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap; flex: 1; min-width: 0;
}
#status { font-size: 0.72rem; color: #555; flex-shrink: 0; }
.body { display: flex; flex: 1; overflow: hidden; }
.shot-pane {
  flex: 1; display: flex; align-items: flex-start; justify-content: center;
  background: #0a0a0a; overflow: auto; padding: 1rem;
}
#shot {
  max-width: 100%; height: auto; border: 1px solid #222; border-radius: 3px;
  display: block;
}
.log-pane {
  width: 260px; flex-shrink: 0; border-left: 1px solid #222;
  background: #111; display: flex; flex-direction: column;
}
.log-title {
  padding: 0.5rem 0.75rem; font-size: 0.7rem; color: #555;
  border-bottom: 1px solid #1e1e1e; letter-spacing: 0.06em; text-transform: uppercase;
}
.log-list { flex: 1; overflow-y: auto; padding: 0.4rem; }
.entry {
  padding: 0.35rem 0.5rem; margin-bottom: 0.2rem; border-radius: 3px;
  font-size: 0.75rem; line-height: 1.4; border-left: 2px solid #333;
}
.entry.navigate { border-left-color: #4a90d9; }
.entry.action    { border-left-color: #e8a030; }
.entry.session   { border-left-color: #7c4dff; }
.entry.human     { border-left-color: #4caf50; }
.etime { display: block; color: #444; font-size: 0.68rem; margin-bottom: 0.1rem; }
.edesc { color: #bbb; word-break: break-all; }
</style>
</head>
<body>
<header>
  <div class="dot" id="dot"></div>
  <div id="url-bar">connecting…</div>
  <div id="status">connecting</div>
</header>
<div class="body">
  <div class="shot-pane">
    <img id="shot" src="/screenshot" alt="browser" />
  </div>
  <div class="log-pane">
    <div class="log-title">Activity</div>
    <div class="log-list" id="log"></div>
  </div>
</div>
<script>
var shot = document.getElementById('shot');
var urlBar = document.getElementById('url-bar');
var statusEl = document.getElementById('status');
var dotEl = document.getElementById('dot');
var logEl = document.getElementById('log');
var pollTimer = null;

function refreshShot() {
  shot.src = '/screenshot?t=' + Date.now();
}

function addEntry(type, desc) {
  var t = new Date().toLocaleTimeString([], {hour: '2-digit', minute: '2-digit', second: '2-digit'});
  var el = document.createElement('div');
  el.className = 'entry ' + type;
  el.innerHTML = '<span class="etime">' + t + '</span><span class="edesc">' + esc(desc) + '</span>';
  logEl.insertBefore(el, logEl.firstChild);
  while (logEl.children.length > 20) logEl.removeChild(logEl.lastChild);
}

function esc(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function setLive(live) {
  dotEl.className = 'dot' + (live ? '' : ' off');
  statusEl.textContent = live ? 'live' : 'reconnecting…';
}

function connect() {
  var es = new EventSource('/events');

  es.addEventListener('connected', function() {
    setLive(true);
    refreshShot();
    clearInterval(pollTimer);
    pollTimer = setInterval(refreshShot, 2000);
  });

  es.addEventListener('navigation', function(e) {
    var d = JSON.parse(e.data);
    urlBar.textContent = d.url || '';
    var label = (d.source === 'human' ? '[human] ' : '') + 'Navigated to ' + (d.url || '');
    addEntry(d.source === 'human' ? 'human' : 'navigate', label);
    refreshShot();
  });

  es.addEventListener('action', function(e) {
    var d = JSON.parse(e.data);
    var label = d.type + ' \u2192 ' + (d.name || d.ref || '');
    addEntry('action', label);
    refreshShot();
  });

  es.addEventListener('session', function(e) {
    var d = JSON.parse(e.data);
    addEntry('session', 'Loaded session: ' + (d.name || ''));
  });

  es.addEventListener('screenshot', function() {
    refreshShot();
  });

  es.onerror = function() {
    setLive(false);
    clearInterval(pollTimer);
    es.close();
    setTimeout(connect, 3000);
  };
}

connect();
</script>
</body>
</html>`;

// ── Core helpers ──────────────────────────────────────────────────────────────

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
        logAction("human", `Human navigated to ${url}`);
        broadcastSSE("navigation", { url, title, source: "human" });
        broadcastSSE("screenshot", { ts: Date.now() });
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

// ── Request handler ───────────────────────────────────────────────────────────

async function handleRequest(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;
  const json = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data, null, 2), {
      status,
      headers: { "Content-Type": "application/json" },
    });

  try {
    // ── Viewer endpoints (no idle timer reset — passive observation) ──────────

    if (path === "/viewer" && req.method === "GET") {
      const queryToken = url.searchParams.get("token");
      // Valid token in URL: set cookie and redirect to clean URL
      if (queryToken !== null && queryToken === viewerToken && viewerToken !== "") {
        return new Response(null, {
          status: 302,
          headers: {
            "Location": "/viewer",
            "Set-Cookie": `weblens-token=${viewerToken}; Path=/; HttpOnly; SameSite=Strict`,
          },
        });
      }
      if (checkAuth(req)) {
        return new Response(VIEWER_HTML, {
          headers: { "Content-Type": "text/html; charset=utf-8" },
        });
      }
      return new Response(AUTH_FORM_HTML, {
        headers: { "Content-Type": "text/html; charset=utf-8" },
      });
    }

    if (path === "/screenshot" && req.method === "GET") {
      if (!checkAuth(req)) return unauthorized();
      const p = await ensurePage();
      try {
        const png = await p.screenshot({ type: "png" });
        return new Response(png, {
          headers: { "Content-Type": "image/png", "Cache-Control": "no-store" },
        });
      } catch {
        return new Response("screenshot unavailable", { status: 503 });
      }
    }

    if (path === "/events" && req.method === "GET") {
      if (!checkAuth(req)) return unauthorized();
      let controller!: ReadableStreamDefaultController;
      const stream = new ReadableStream({
        start(c) {
          controller = c;
          sseClients.add(c);
          c.enqueue(sseEncoder.encode(`event: connected\ndata: ${JSON.stringify({ ts: Date.now() })}\n\n`));
        },
        cancel() {
          sseClients.delete(controller);
        },
      });
      return new Response(stream, {
        headers: {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          "Connection": "keep-alive",
          "X-Accel-Buffering": "no",
        },
      });
    }

    if (path === "/viewer-url" && req.method === "GET") {
      // No auth — already loopback-only (same trust model as /stop)
      const viewUrl = `http://127.0.0.1:${daemonPort}/viewer?token=${viewerToken}`;
      return json({ url: viewUrl, token: viewerToken });
    }

    // ── Agent endpoints (reset idle timer) ───────────────────────────────────

    resetIdleTimer();

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
      const navTitle = await p.title();
      logAction("navigate", `Navigated to ${p.url()}`);
      broadcastSSE("navigation", { url: p.url(), title: navTitle });
      broadcastSSE("screenshot", { ts: Date.now() });
      const result: any = {
        url: p.url(),
        title: navTitle,
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
        // Use selectOption only for real <select> elements (listbox), not text inputs with role=combobox
        const tagName = await locator.evaluate((el) => (el as HTMLElement).tagName.toLowerCase()).catch(() => "");
        if (tagName === "select") {
          await locator.selectOption({ label: body.value });
          actionDesc = "select";
        } else {
          await locator.fill(body.value);
          actionDesc = "fill";
        }
      } else {
        await locator.click();
      }

      await p.waitForTimeout(500);
      lastSnapshot = await p.ariaSnapshot({ mode: "ai" });
      lastUrl = p.url();
      lastAgentActionUrl = p.url();
      agentActing = false;

      const actionVerb = body.value !== undefined ? "Filled" : "Clicked";
      logAction("action", `${actionVerb} ${parsed.name ?? body.ref}`);
      broadcastSSE("action", { type: actionDesc, ref: body.ref, name: parsed.name ?? null, url: p.url() });
      broadcastSSE("screenshot", { ts: Date.now() });

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
      logAction("session", `Loaded session "${body.name}"`);
      broadcastSSE("session", { name: body.name });

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

// ── Entry point ───────────────────────────────────────────────────────────────

async function main() {
  await mkdir(WEBLENS_DIR, { recursive: true });
  await mkdir(SESSIONS_DIR, { recursive: true });

  viewerToken = generateToken();

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

  daemonPort = server.port!;

  await Bun.write(DAEMON_FILE, JSON.stringify({
    pid: process.pid,
    port: server.port,
    headless,
    startedAt: new Date().toISOString(),
    viewerToken,
  }));

  const viewerUrl = `http://127.0.0.1:${server.port}/viewer?token=${viewerToken}`;
  console.error(`[weblens] daemon started on port ${server.port} (pid ${process.pid})${headless ? " [headless]" : ""}`);
  console.error(`[weblens] viewer: ${viewerUrl}`);

  resetIdleTimer();

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}

main().catch((err) => {
  console.error("[weblens] daemon failed to start:", err.message);
  process.exit(1);
});
