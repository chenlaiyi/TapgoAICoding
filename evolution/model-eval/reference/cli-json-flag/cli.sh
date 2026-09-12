#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--json" ]]; then
  echo '{"ok": true}'
else
  echo "ok"
fi
