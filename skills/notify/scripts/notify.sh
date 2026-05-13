#!/usr/bin/env bash
# notify.sh — OS dispatcher; delegates to notify-macos.sh or notify-linux.sh.
# All CLI args are forwarded as-is.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
  Darwin) exec "$SCRIPT_DIR/notify-macos.sh" "$@" ;;
  Linux)  exec "$SCRIPT_DIR/notify-linux.sh" "$@" ;;
  *)
    echo "notify.sh: unsupported OS '$(uname -s)'" >&2
    exit 1
    ;;
esac
