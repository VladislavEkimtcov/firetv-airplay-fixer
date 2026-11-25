#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$(uname -s)" == "Darwin" ]]; then
  exec "$DIR/macos/install.sh" "$@"
else
  echo "On Windows, run: powershell -ExecutionPolicy Bypass -File windows\\install.ps1" >&2
  exit 1
fi
