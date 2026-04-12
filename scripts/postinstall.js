#!/usr/bin/env node
/**
 * Postinstall: download the platform-appropriate compiled binary from the
 * GitHub Release for this package version.
 */
const fs = require("fs");
const path = require("path");
const https = require("https");

const pkg = require("../package.json");
const RELEASE_BASE = pkg.binaryRelease;
if (!RELEASE_BASE) {
  console.warn("[scamper] package.json missing binaryRelease; skipping binary download.");
  process.exit(0);
}

const PLATFORM_MAP = {
  "darwin-arm64": `${pkg.name}-darwin-arm64`,
  "darwin-x64":   `${pkg.name}-darwin-x64`,
  "linux-x64":    `${pkg.name}-linux-x64`,
  "linux-arm64":  `${pkg.name}-linux-arm64`,
  "win32-x64":    `${pkg.name}-windows-x64.exe`,
};

const key = `${process.platform}-${process.arch}`;
const asset = PLATFORM_MAP[key];
if (!asset) {
  console.error(`[scamper] unsupported platform: ${key}`);
  process.exit(1);
}

const url = `${RELEASE_BASE}/v${pkg.version}/${asset}`;
const vendorDir = path.join(__dirname, "..", "vendor");
const outPath = path.join(vendorDir, `${pkg.name}${process.platform === "win32" ? ".exe" : ""}`);

fs.mkdirSync(vendorDir, { recursive: true });

console.log(`[scamper] downloading binary: ${url}`);

function download(url, dest, redirects = 0, cb) {
  if (redirects > 5) return cb(new Error("too many redirects"));
  https.get(url, { headers: { "User-Agent": "scamper-install" } }, (res) => {
    if (res.statusCode === 301 || res.statusCode === 302 || res.statusCode === 307) {
      return download(res.headers.location, dest, redirects + 1, cb);
    }
    if (res.statusCode !== 200) {
      return cb(new Error(`HTTP ${res.statusCode} for ${url}`));
    }
    const file = fs.createWriteStream(dest, { mode: 0o755 });
    res.pipe(file);
    file.on("finish", () => file.close(() => cb(null)));
    file.on("error", cb);
  }).on("error", cb);
}

download(url, outPath, 0, (err) => {
  if (err) {
    console.error(`[scamper] binary download failed: ${err.message}`);
    process.exit(1);
  }
  try { fs.chmodSync(outPath, 0o755); } catch {}
  console.log("[scamper] binary installed.");
});
