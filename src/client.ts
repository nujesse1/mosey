import { join } from "node:path";
import { homedir } from "node:os";
import { spawn } from "node:child_process";

const MOSEY_DIR = process.env.MOSEY_DIR ?? process.env.SCAMPER_DIR ?? process.env.WEBLENS_DIR ?? join(homedir(), ".mosey");
const DAEMON_FILE = join(MOSEY_DIR, "daemon.json");

interface DaemonInfo {
  pid: number;
  port: number;
  startedAt: string;
}

async function readDaemonInfo(): Promise<DaemonInfo | null> {
  try {
    const file = Bun.file(DAEMON_FILE);
    if (!(await file.exists())) return null;
    return await file.json();
  } catch {
    return null;
  }
}

async function isDaemonAlive(info: DaemonInfo): Promise<boolean> {
  try {
    const res = await fetch(`http://127.0.0.1:${info.port}/health`, {
      signal: AbortSignal.timeout(2000),
    });
    return res.ok;
  } catch {
    return false;
  }
}

let daemonArgs: string[] = [];

export function setDaemonArgs(args: string[]) {
  daemonArgs = args;
}

async function startDaemon(): Promise<DaemonInfo> {
  // Spawn ourself with the __daemon__ marker.
  // - In dev (bun run src/cli.ts): process.execPath = bun, argv[1] = resolved cli.ts path.
  // - In a compiled binary: process.execPath = the binary, argv[1] = first user arg.
  const execPath = process.execPath;
  const isBunDev = /[\\/]bun(\.exe)?$/i.test(execPath);
  const args = isBunDev
    ? ["run", process.argv[1]!, "__daemon__", ...daemonArgs]
    : ["__daemon__", ...daemonArgs];

  const child = spawn(execPath, args, {
    detached: true,
    stdio: "ignore",
  });
  child.unref();

  // Wait for daemon to be ready — poll fast
  for (let i = 0; i < 100; i++) {
    await Bun.sleep(100);
    const info = await readDaemonInfo();
    if (info && (await isDaemonAlive(info))) {
      return info;
    }
  }

  throw new Error("daemon failed to start within 10s");
}

export async function ensureDaemon(): Promise<DaemonInfo> {
  const info = await readDaemonInfo();
  if (info && (await isDaemonAlive(info))) {
    return info;
  }
  return await startDaemon();
}

export async function request(
  method: "GET" | "POST",
  path: string,
  body?: unknown
): Promise<unknown> {
  const info = await ensureDaemon();
  const url = `http://127.0.0.1:${info.port}${path}`;

  const res = await fetch(url, {
    method,
    headers: body ? { "Content-Type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(60000),
  });

  const data = await res.json();

  if (!res.ok) {
    const err = (data as any).error ?? `HTTP ${res.status}`;
    throw new Error(err);
  }

  // Print viewer URL to stderr so it's always visible
  if (path !== "/viewer-url" && path !== "/stop" && path !== "/health") {
    try {
      const vr = await fetch(`http://127.0.0.1:${info.port}/viewer-url`, { signal: AbortSignal.timeout(1000) });
      const v = await vr.json() as any;
      if (v?.url) process.stderr.write(`\x1b[1;36mviewer: ${v.url}\x1b[0m\n`);
    } catch {}
  }

  return data;
}
