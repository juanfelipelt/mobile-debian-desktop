#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Lanzador de compatibilidad. El wake-lock y la limpieza ahora los maneja
# directamente mobile-debian.sh para evitar bloqueos dobles.
BASE_SCRIPT="${BASE_SCRIPT:-$HOME/mobile-debian.sh}"
[[ -x "$BASE_SCRIPT" ]] || {
  echo "[ERROR] No encuentro $BASE_SCRIPT" >&2
  exit 1
}

case "${1:-start}" in
  start|stop|restart|status)
    exec "$BASE_SCRIPT" "${1:-start}"
    ;;
  *)
    echo "Uso: $0 [start|stop|restart|status]" >&2
    exit 2
    ;;
esac
