#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# This PC playtest uses a separate development save slot. Production keeps false.
MARS_DEV_TOOLS="${MARS_DEV_TOOLS:-true}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
MARS_WEB_BASE_HREF="${MARS_WEB_BASE_HREF:-/}"
MARS_WEB_SAVE_NAMESPACE="${MARS_WEB_SAVE_NAMESPACE:-}"
if [[ ! "$MARS_WEB_BASE_HREF" =~ ^/([a-zA-Z0-9_-]+/)*$ ]]; then
  echo 'MARS_WEB_BASE_HREF must be a slash-delimited absolute directory path.' >&2
  exit 1
fi
if [[ ! "$MARS_WEB_SAVE_NAMESPACE" =~ ^[a-zA-Z0-9_-]*$ ]]; then
  echo 'MARS_WEB_SAVE_NAMESPACE must use letters, digits, hyphens or underscores.' >&2
  exit 1
fi
"$FLUTTER_BIN" --no-version-check --suppress-analytics build web --release \
  --no-web-resources-cdn --no-wasm-dry-run \
  --base-href="$MARS_WEB_BASE_HREF" \
  --dart-define="WEB_SAVE_NAMESPACE=$MARS_WEB_SAVE_NAMESPACE" \
  --dart-define="DEV_TOOLS=$MARS_DEV_TOOLS"
python3 tools/prepare_web_preview.py
