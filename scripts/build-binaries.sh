#!/usr/bin/env bash
# Build per-platform compiled binaries. Run before publishing a release.
# Uploads are manual: create a GitHub Release tagged v<version>, attach dist/*.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(node -p "require('./package.json').version")
NAME=$(node -p "require('./package.json').name")
OUTDIR=dist
rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

TARGETS=(
  "bun-darwin-arm64:${NAME}-darwin-arm64"
  "bun-darwin-x64:${NAME}-darwin-x64"
  "bun-linux-x64:${NAME}-linux-x64"
  "bun-linux-arm64:${NAME}-linux-arm64"
  "bun-windows-x64:${NAME}-windows-x64.exe"
)

for entry in "${TARGETS[@]}"; do
  IFS=":" read -r target out <<<"$entry"
  echo ">>> building $out"
  bun build --compile \
    --target="$target" \
    --external chromium-bidi --external electron --external playwright-core \
    src/cli.ts \
    --outfile="$OUTDIR/$out"

  # macOS kernel kills unsigned binaries on arm64. Strip + ad-hoc re-sign.
  case "$target" in
    bun-darwin-*)
      codesign --remove-signature "$OUTDIR/$out" 2>/dev/null || true
      codesign --force -s - "$OUTDIR/$out"
      ;;
  esac
done

echo
echo "built $NAME@$VERSION binaries:"
ls -lh "$OUTDIR"
echo
echo "next: gh release create v$VERSION $OUTDIR/* --title v$VERSION --notes ''"
