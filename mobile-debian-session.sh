#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

VERSION="0.1.0"
BASE_SCRIPT="${BASE_SCRIPT:-$HOME/mobile-debian.sh}"
STATE_DIR="$HOME/.config/mobile-debian"
WRAPPER_PID_FILE="$STATE_DIR/session-wrapper.pid"
WAKE_LOCK_FILE="$STATE_DIR/wake-lock"
mkdir -p "$STATE_DIR"

log(){ printf '\033[1;36m[Mobile Debian Session]\033[0m %s\n' "$*"; }
ok(){ printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[AVISO]\033[0m %s\n' "$*" >&2; }
die(){ printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

require_termux(){
  [[ "${PREFIX:-}" == /data/data/com.termux/files/usr ]] || die "Ejecuta esto en Termux."
  [[ -x "$BASE_SCRIPT" ]] || die "No encuentro el lanzador base en $BASE_SCRIPT"
}

pid_is_ours(){
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  [[ -r "/proc/$pid/cmdline" ]] || return 1
  tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q 'mobile-debian-session.sh'
}

acquire_wake_lock(){
  if ! command -v termux-wake-lock >/dev/null 2>&1; then
    warn "termux-wake-lock no está disponible; la sesión continuará sin wake-lock."
    return 0
  fi

  if termux-wake-lock; then
    date -Iseconds > "$WAKE_LOCK_FILE"
    ok "Wake-lock activado"
  else
    warn "No se pudo activar el wake-lock; la sesión continuará."
  fi
}

release_wake_lock(){
  if command -v termux-wake-unlock >/dev/null 2>&1; then
    termux-wake-unlock >/dev/null 2>&1 || true
  fi
  rm -f "$WAKE_LOCK_FILE"
}

clear_own_pid(){
  local saved=""
  [[ -s "$WRAPPER_PID_FILE" ]] || return 0
  saved="$(cat "$WRAPPER_PID_FILE" 2>/dev/null || true)"
  [[ "$saved" == "$$" ]] && rm -f "$WRAPPER_PID_FILE"
}

cleanup(){
  local rc=$?
  trap - EXIT INT TERM HUP
  log "Cerrando escritorio y servicios"
  "$BASE_SCRIPT" stop >/dev/null 2>&1 || true
  release_wake_lock
  clear_own_pid
  [[ "$rc" -eq 0 ]] && ok "Sesión cerrada y wake-lock liberado"
  exit "$rc"
}

stop_previous_wrapper(){
  local pid=""
  [[ -s "$WRAPPER_PID_FILE" ]] || return 0
  pid="$(cat "$WRAPPER_PID_FILE" 2>/dev/null || true)"
  [[ "$pid" != "$$" ]] || return 0

  if kill -0 "$pid" 2>/dev/null && pid_is_ours "$pid"; then
    log "Cerrando lanzador anterior"
    "$BASE_SCRIPT" stop >/dev/null 2>&1 || true
    kill -TERM "$pid" 2>/dev/null || true
    for _ in $(seq 1 50); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
  fi

  rm -f "$WRAPPER_PID_FILE"
}

start_session(){
  require_termux
  stop_previous_wrapper
  printf '%s\n' "$$" > "$WRAPPER_PID_FILE"

  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP

  acquire_wake_lock
  "$BASE_SCRIPT" start
}

stop_session(){
  require_termux
  local pid=""

  "$BASE_SCRIPT" stop >/dev/null 2>&1 || true

  if [[ -s "$WRAPPER_PID_FILE" ]]; then
    pid="$(cat "$WRAPPER_PID_FILE" 2>/dev/null || true)"
    if [[ "$pid" != "$$" ]] && kill -0 "$pid" 2>/dev/null && pid_is_ours "$pid"; then
      kill -TERM "$pid" 2>/dev/null || true
      for _ in $(seq 1 30); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
      done
    fi
  fi

  release_wake_lock
  rm -f "$WRAPPER_PID_FILE"
  ok "Sesión cerrada y wake-lock liberado"
}

status_session(){
  require_termux
  "$BASE_SCRIPT" status || true
  if [[ -s "$WRAPPER_PID_FILE" ]]; then
    local pid
    pid="$(cat "$WRAPPER_PID_FILE" 2>/dev/null || true)"
    if kill -0 "$pid" 2>/dev/null && pid_is_ours "$pid"; then
      printf 'Lanzador automático: activo (PID %s)\n' "$pid"
    else
      printf 'Lanzador automático: marcador obsoleto\n'
    fi
  else
    printf 'Lanzador automático: inactivo\n'
  fi
  printf 'Wake-lock solicitado: %s\n' "$([[ -f "$WAKE_LOCK_FILE" ]] && echo sí || echo no)"
}

case "${1:-start}" in
  start) start_session ;;
  stop) stop_session ;;
  restart) stop_session; start_session ;;
  status) status_session ;;
  *) echo "Uso: $0 [start|stop|restart|status]"; exit 2 ;;
esac
