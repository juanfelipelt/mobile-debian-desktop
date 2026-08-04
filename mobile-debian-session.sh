#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

VERSION="0.3.0"
BASE_SCRIPT="${BASE_SCRIPT:-$HOME/mobile-debian.sh}"

[[ -x "$BASE_SCRIPT" ]] || {
  echo "[ERROR] No encuentro $BASE_SCRIPT" >&2
  exit 1
}

command_name="${1:-start}"
case "$command_name" in
  start|stop|restart|status|doctor)
    exec "$BASE_SCRIPT" "$command_name"
    ;;
  *)
    echo "Uso: $0 [start|stop|restart|status|doctor]"
    exit 2
    ;;
esac
