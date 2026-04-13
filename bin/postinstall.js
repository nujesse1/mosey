#!/usr/bin/env node
// Postinstall: wire up CLAUDE.md and download Chromium so the first `mosey <url>` is instant.
// Best-effort: any failure here is non-fatal — the user can retry with `mosey install-deps`.

const { spawnSync } = require("node:child_process");
const path = require("node:path");
const fs = require("node:fs");

const bin = path.join(
  __dirname,
  "..",
  "vendor",
  "mosey" + (process.platform === "win32" ? ".exe" : "")
);

if (!fs.existsSync(bin)) {
  // Binary missing for this platform — silent exit, the bin/mosey launcher will print a clear error later.
  process.exit(0);
}

console.log("\n  ✓ mosey-browser installed.");

// 1. CLAUDE.md wire-up (idempotent — safe to re-run on every install).
spawnSync(bin, ["setup"], { stdio: "inherit" });

// 2. Trigger Chromium download by starting the daemon once against about:blank.
//    Playwright's chromium download is the slow step; daemon startup itself is <1s once Chromium is present.
console.log("  Downloading Chromium for first run (~170MB, one-time)…");
const navRes = spawnSync(bin, ["navigate", "about:blank"], {
  stdio: "inherit",
  // generous timeout: cold Playwright Chromium download can take a few minutes on slow links
  timeout: 10 * 60_000,
});
spawnSync(bin, ["stop"], { stdio: "ignore" });

if (navRes.status === 0) {
  console.log("  ✓ Ready. Try: mosey https://example.com\n");
} else {
  console.log(
    "  ⚠ Chromium not downloaded (network/timeout). Run `mosey install-deps` to retry.\n"
  );
  // Don't fail the npm install for this — user can recover later.
}
