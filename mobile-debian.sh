#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

VERSION="0.7.0"
REPO_RAW="https://raw.githubusercontent.com/juanfelipelt/mobile-debian-desktop/main"
DISTRO="${DISTRO:-debian}"
LINUX_USER="${LINUX_USER:-felipe}"
DISPLAY_NUM="${DISPLAY_NUM:-:1}"
TIMEZONE="${TIMEZONE:-America/Bogota}"

INSTALL_DEV_STACK="${INSTALL_DEV_STACK:-1}"
INSTALL_OFFICE="${INSTALL_OFFICE:-1}"
INSTALL_MEDIA="${INSTALL_MEDIA:-1}"
INSTALL_VSCODE="${INSTALL_VSCODE:-1}"
INSTALL_CHROMIUM="${INSTALL_CHROMIUM:-1}"
INSTALL_AI_CLI="${INSTALL_AI_CLI:-1}"
ENABLE_ANDROID_STORAGE="${ENABLE_ANDROID_STORAGE:-1}"

STATE_DIR="$HOME/.config/mobile-debian"
STATE_FILE="$STATE_DIR/installed"
CONFIG_FILE="$STATE_DIR/config"
X11_PID_FILE="$STATE_DIR/termux-x11.pid"
WAKE_LOCK_FILE="$STATE_DIR/wake-lock"
LOG_DIR="$HOME/.local/state/mobile-debian"
X11_LOG="$LOG_DIR/termux-x11.log"
XFCE_LOG="$LOG_DIR/xfce.log"
STORAGE_SOURCE="${STORAGE_SOURCE:-}"
mkdir -p "$STATE_DIR" "$LOG_DIR"

log(){ printf '\033[1;36m[Mobile Debian]\033[0m %s\n' "$*"; }
ok(){ printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[AVISO]\033[0m %s\n' "$*" >&2; }
die(){ printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

require_termux(){
  [[ "${PREFIX:-}" == /data/data/com.termux/files/usr ]] ||
    die "Ejecuta el script en Termux."
  [[ "$(uname -m)" == aarch64 ]] ||
    die "Se requiere Android ARM64/aarch64."
}

distro_exists(){
  command -v proot-distro >/dev/null 2>&1 || return 1
  proot-distro login "$DISTRO" -- /bin/true >/dev/null 2>&1
}

installed(){
  distro_exists || return 1
  [[ -f "$STATE_FILE" ]] && return 0
  if proot-distro login "$DISTRO" -- test -x /usr/bin/xfce4-session >/dev/null 2>&1; then
    date -Iseconds > "$STATE_FILE"
    return 0
  fi
  return 1
}

load_config(){
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi
  STORAGE_SOURCE="${STORAGE_SOURCE:-}"
}

save_config(){
  cat > "$CONFIG_FILE" <<EOF
DISPLAY_NUM=$DISPLAY_NUM
STORAGE_SOURCE=$STORAGE_SOURCE
EOF
}

acquire_wake_lock(){
  if command -v termux-wake-lock >/dev/null 2>&1; then
    if termux-wake-lock >/dev/null 2>&1; then
      date -Iseconds > "$WAKE_LOCK_FILE"
      ok "Wake-lock activado"
    else
      warn "No se pudo activar el wake-lock."
    fi
  fi
}

release_wake_lock(){
  command -v termux-wake-unlock >/dev/null 2>&1 &&
    termux-wake-unlock >/dev/null 2>&1 || true
  rm -f "$WAKE_LOCK_FILE"
}

host_packages(){
  log "Actualizando Termux"
  pkg update -y
  pkg upgrade -y
  pkg install -y x11-repo
  pkg update -y
  pkg install -y \
    termux-x11-nightly pulseaudio proot-distro \
    curl wget git jq tar gzip coreutils procps psmisc
}

setup_android_storage(){
  [[ "$ENABLE_ANDROID_STORAGE" == 1 ]] || return 0

  if [[ ! -d "$HOME/storage/shared" ]]; then
    log "Solicitando acceso al almacenamiento de Android"
    termux-setup-storage
    log "Acepta el permiso de archivos que muestra Android"
  fi

  for _ in $(seq 1 120); do
    [[ -d "$HOME/storage/shared" ]] && break
    sleep 1
  done

  [[ -d "$HOME/storage/shared" ]] ||
    die "No se concedió el acceso al almacenamiento."

  STORAGE_SOURCE="$(readlink -f "$HOME/storage/shared" 2>/dev/null || true)"
  [[ -n "$STORAGE_SOURCE" && -d "$STORAGE_SOURCE" ]] ||
    die "No se pudo resolver el almacenamiento compartido."
  ok "Almacenamiento Android disponible"
}

ensure_debian(){
  if distro_exists; then
    log "Debian ya está instalado"
  else
    log "Instalando Debian"
    proot-distro install "$DISTRO"
  fi
}

login_args(){
  LOGIN_ARGS=(login "$DISTRO" --shared-tmp)
  if [[ -n "${STORAGE_SOURCE:-}" && -d "$STORAGE_SOURCE" ]]; then
    LOGIN_ARGS+=(--bind "$STORAGE_SOURCE:/mnt/android")
  fi
}

configure_debian(){
  local ai_force="${1:-0}"
  login_args

  cat > "$TMPDIR/mobile-debian-configure.sh" <<'DEBIAN'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

LINUX_USER="$1"
TIMEZONE="$2"
INSTALL_DEV_STACK="$3"
INSTALL_OFFICE="$4"
INSTALL_MEDIA="$5"
INSTALL_VSCODE="$6"
INSTALL_CHROMIUM="$7"
INSTALL_AI_CLI="$8"
AI_FORCE="$9"
STORAGE_ENABLED="${10}"

say(){ printf '[Debian] %s\n' "$*"; }
warn(){ printf '[AVISO] %s\n' "$*" >&2; }
die(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }

say "Actualizando Debian"
apt-get update
apt-get upgrade -y

packages=(
  sudo locales tzdata ca-certificates curl wget gnupg jq file xz-utils procps psmisc
  dbus-x11 xauth x11-xserver-utils xdg-utils xdg-user-dirs xdg-user-dirs-gtk desktop-base
  xfce4 xfce4-terminal xfce4-whiskermenu-plugin xfce4-notifyd
  thunar-archive-plugin file-roller mousepad ristretto tumbler gvfs gvfs-backends pavucontrol
  mesa-utils
  fonts-noto-core fonts-noto-color-emoji fonts-liberation fonts-crosextra-carlito
)
[[ "$INSTALL_CHROMIUM" == 1 ]] && packages+=(chromium)
[[ "$INSTALL_OFFICE" == 1 ]] && packages+=(libreoffice libreoffice-l10n-es hunspell-es)
[[ "$INSTALL_MEDIA" == 1 ]] && packages+=(vlc mpv ffmpeg)
[[ "$INSTALL_DEV_STACK" == 1 ]] &&
  packages+=(git build-essential pkg-config python3 python3-pip python3-venv nodejs npm)

say "Instalando XFCE y aplicaciones"
apt-get install -y --no-install-recommends "${packages[@]}"

# Base neutra y estable. No se fuerza es_CO, LANGUAGE ni LC_ALL al iniciar XFCE.
cat > /etc/default/locale <<'EOF_LOCALE'
LANG=C.UTF-8
EOF_LOCALE
ln -snf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
printf '%s\n' "$TIMEZONE" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1 || true

if ! id "$LINUX_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos '' "$LINUX_USER"
fi
usermod -aG sudo,audio,video "$LINUX_USER" || true
printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$LINUX_USER" \
  > "/etc/sudoers.d/90-$LINUX_USER"
chmod 0440 "/etc/sudoers.d/90-$LINUX_USER"
USER_HOME="$(getent passwd "$LINUX_USER" | cut -d: -f6)"

if [[ "$INSTALL_VSCODE" == 1 ]]; then
  say "Instalando Visual Studio Code oficial ARM64"
  install -d -m755 /etc/apt/keyrings /etc/apt/sources.list.d
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc |
    gpg --dearmor --yes -o /etc/apt/keyrings/packages.microsoft.gpg
  chmod 0644 /etc/apt/keyrings/packages.microsoft.gpg
  cat > /etc/apt/sources.list.d/vscode.sources <<'SRC'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: arm64
Signed-By: /etc/apt/keyrings/packages.microsoft.gpg
SRC
  apt-get update
  apt-get install -y code
fi

install_ai(){
  [[ "$INSTALL_AI_CLI" == 1 ]] || return 0
  cat > /tmp/mobile-debian-ai.sh <<'AI'
#!/usr/bin/env bash
set -Eeuo pipefail
force="${1:-0}"
mkdir -p "$HOME/.local/bin" "$HOME/.cache/mobile-debian/installers"
export PATH="$HOME/.local/bin:$PATH"
touch "$HOME/.profile"
grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.profile" ||
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.profile"

if [[ "$force" == 1 ]] || ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh \
    -o "$HOME/.cache/mobile-debian/installers/claude-install.sh"
  bash "$HOME/.cache/mobile-debian/installers/claude-install.sh"
fi

if [[ "$force" == 1 ]] || ! command -v codex >/dev/null 2>&1; then
  curl -fsSL https://chatgpt.com/codex/install.sh \
    -o "$HOME/.cache/mobile-debian/installers/codex-install.sh"
  CODEX_NON_INTERACTIVE=true \
    sh "$HOME/.cache/mobile-debian/installers/codex-install.sh"
fi
AI
  chmod 0755 /tmp/mobile-debian-ai.sh
  chown "$LINUX_USER:$LINUX_USER" /tmp/mobile-debian-ai.sh
  su - "$LINUX_USER" -c "bash /tmp/mobile-debian-ai.sh '$AI_FORCE'" ||
    warn "Alguna CLI de IA no pudo instalarse."
}
install_ai

install -d -m755 \
  /usr/local/bin \
  "$USER_HOME/.local/share/applications" \
  "$USER_HOME/.config/autostart" \
  "$USER_HOME/.config/gtk-3.0" \
  "$USER_HOME/.local/bin" \
  "$USER_HOME/Desktop"

cat > /usr/local/bin/chromium-mobile <<'CHROME'
#!/usr/bin/env bash
unset MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER TU_DEBUG VK_ICD_FILENAMES
exec /usr/bin/chromium \
  --no-sandbox \
  --disable-dev-shm-usage \
  --password-store=basic \
  --ozone-platform=x11 \
  "$@"
CHROME
chmod 0755 /usr/local/bin/chromium-mobile

cat > /usr/local/bin/code-mobile <<'CODE'
#!/usr/bin/env bash
unset MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER TU_DEBUG VK_ICD_FILENAMES
exec /usr/bin/code \
  --no-sandbox \
  --disable-dev-shm-usage \
  "$@"
CODE
chmod 0755 /usr/local/bin/code-mobile

APP_DIR="$USER_HOME/.local/share/applications"
rm -f \
  "$APP_DIR/word-online.desktop" \
  "$APP_DIR/chromium-gpu.desktop" \
  "$USER_HOME/Desktop/word-online.desktop" \
  "$USER_HOME/Desktop/chromium-gpu.desktop"

if [[ "$INSTALL_CHROMIUM" == 1 ]]; then
  cat > "$APP_DIR/chromium-mobile.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Chromium
Exec=chromium-mobile %U
Icon=chromium
Terminal=false
Categories=Network;WebBrowser;
DESK
  cp "$APP_DIR/chromium-mobile.desktop" "$USER_HOME/Desktop/"
fi

if [[ "$INSTALL_VSCODE" == 1 ]]; then
  cat > "$APP_DIR/code-mobile.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Visual Studio Code
Exec=code-mobile %F
Icon=visual-studio-code
Terminal=false
Categories=Development;IDE;
DESK
  cp "$APP_DIR/code-mobile.desktop" "$USER_HOME/Desktop/"
fi

if [[ "$STORAGE_ENABLED" == 1 ]]; then
  cat > "$APP_DIR/android-storage.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Archivos de Android
Exec=thunar /mnt/android
Icon=folder
Terminal=false
Categories=System;FileTools;
DESK
  cp "$APP_DIR/android-storage.desktop" "$USER_HOME/Desktop/"
  ln -sfn /mnt/android "$USER_HOME/Android"
  ln -sfn /mnt/android/Download "$USER_HOME/Descargas-Android"
  ln -sfn /mnt/android/Documents "$USER_HOME/Documentos-Android"
fi

for desktop_file in \
  /usr/share/applications/libreoffice-startcenter.desktop \
  /usr/share/applications/vlc.desktop; do
  [[ -f "$desktop_file" ]] && cp "$desktop_file" "$USER_HOME/Desktop/"
done
chmod +x "$USER_HOME/Desktop/"*.desktop 2>/dev/null || true

# Quita los locales forzados que dejó la versión 0.6.
touch "$USER_HOME/.profile"
sed -i \
  -e '/^[[:space:]]*export LANG=/d' \
  -e '/^[[:space:]]*export LANGUAGE=/d' \
  -e '/^[[:space:]]*export LC_ALL=/d' \
  "$USER_HOME/.profile"

for item in light-locker.desktop xiccd.desktop \
            polkit-mate-authentication-agent-1.desktop \
            xfce4-power-manager.desktop; do
  printf '[Desktop Entry]\nType=Application\nHidden=true\nX-GNOME-Autostart-enabled=false\n' \
    > "$USER_HOME/.config/autostart/$item"
done

chown -R "$LINUX_USER:$LINUX_USER" \
  "$USER_HOME/.local" \
  "$USER_HOME/.config" \
  "$USER_HOME/Desktop" \
  "$USER_HOME/.profile"

required=(xfce4-session)
[[ "$INSTALL_CHROMIUM" == 1 ]] && required+=(chromium-mobile)
[[ "$INSTALL_VSCODE" == 1 ]] && required+=(code-mobile)
[[ "$INSTALL_OFFICE" == 1 ]] && required+=(libreoffice)
[[ "$INSTALL_MEDIA" == 1 ]] && required+=(vlc)
for command_name in "${required[@]}"; do
  command -v "$command_name" >/dev/null 2>&1 ||
    die "Falta el componente: $command_name"
done

apt-get clean
say "Configuración terminada"
DEBIAN

  proot-distro "${LOGIN_ARGS[@]}" -- \
    /bin/bash /tmp/mobile-debian-configure.sh \
      "$LINUX_USER" "$TIMEZONE" \
      "$INSTALL_DEV_STACK" "$INSTALL_OFFICE" "$INSTALL_MEDIA" \
      "$INSTALL_VSCODE" "$INSTALL_CHROMIUM" "$INSTALL_AI_CLI" \
      "$ai_force" "$ENABLE_ANDROID_STORAGE"

  save_config
  date -Iseconds > "$STATE_FILE"
  ok "Debian configurado"
}

stop_debian_session(){
  distro_exists || return 0
  login_args
  proot-distro "${LOGIN_ARGS[@]}" --user "$LINUX_USER" -- bash -lc '
    for process_name in xfce4-session xfce4-panel xfdesktop xfwm4 \
                        Thunar xfce4-terminal chromium code soffice.bin vlc; do
      pkill -TERM -x "$process_name" 2>/dev/null || true
    done
  ' >/dev/null 2>&1 || true
}

x11_pids(){
  {
    [[ -s "$X11_PID_FILE" ]] && cat "$X11_PID_FILE" || true
    pgrep -f '[c]om\.termux\.x11(\.CmdEntryPoint)?' 2>/dev/null || true
    pgrep -f '(^|/)[t]ermux-x11([[:space:]]|$)' 2>/dev/null || true
  } |
    awk -v self="$$" -v parent="$PPID" '
      /^[0-9]+$/ && $0 != self && $0 != parent && !seen[$0]++ { print }
    '
}

stop_x11_servers(){
  local -a pids=()
  local pid alive=0
  mapfile -t pids < <(x11_pids)

  if [[ ${#pids[@]} -gt 0 ]]; then
    log "Cerrando servidor Termux:X11 anterior"
    for pid in "${pids[@]}"; do
      kill -TERM "$pid" 2>/dev/null || true
    done
    for _ in $(seq 1 40); do
      alive=0
      for pid in "${pids[@]}"; do
        kill -0 "$pid" 2>/dev/null && alive=1
      done
      [[ "$alive" == 0 ]] && break
      sleep 0.1
    done
    for pid in "${pids[@]}"; do
      kill -0 "$pid" 2>/dev/null &&
        kill -KILL "$pid" 2>/dev/null || true
    done
    sleep 0.5
  fi

  pkill -KILL -f '[c]om\.termux\.x11\.CmdEntryPoint' 2>/dev/null || true
  pkill -KILL -f '(^|/)[t]ermux-x11([[:space:]]|$)' 2>/dev/null || true
  sleep 0.3
  rm -f "$X11_PID_FILE"
}

display_busy(){
  local id="$1"
  [[ -e "$TMPDIR/.X11-unix/X$id" || -e "$TMPDIR/.X$id-lock" ]] &&
    return 0
  grep -qE "(@|/)([^ ]*/)?\.X11-unix/X${id}([[:space:]]|$)" \
    /proc/net/unix 2>/dev/null
}

start_x11_server(){
  local requested_id="${DISPLAY_NUM#:}"
  local -a candidates=("$requested_id")
  local id candidate pid socket ready

  for id in 1 2 3 4 5 6 7 8 9; do
    [[ "$id" == "$requested_id" ]] || candidates+=("$id")
  done

  export XDG_RUNTIME_DIR="$TMPDIR"
  mkdir -p "$TMPDIR/.X11-unix"
  : > "$X11_LOG"

  for id in "${candidates[@]}"; do
    if display_busy "$id"; then
      warn "El display :$id sigue ocupado; probando otro."
      continue
    fi

    rm -f "$TMPDIR/.X$id-lock" "$TMPDIR/.X11-unix/X$id"
    candidate=":$id"
    log "Iniciando Termux:X11 en $candidate"
    termux-x11 "$candidate" >>"$X11_LOG" 2>&1 &
    pid=$!
    printf '%s\n' "$pid" > "$X11_PID_FILE"
    socket="$TMPDIR/.X11-unix/X$id"
    ready=0

    for _ in $(seq 1 60); do
      if [[ -e "$socket" ]]; then
        ready=1
        break
      fi
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.2
    done

    if [[ "$ready" == 1 ]]; then
      DISPLAY_NUM="$candidate"
      ok "Termux:X11 listo en $DISPLAY_NUM"
      return 0
    fi

    kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    warn "No se pudo iniciar Termux:X11 en $candidate."
  done

  tail -n 60 "$X11_LOG" >&2 2>/dev/null || true
  die "No se encontró un display X11 libre entre :1 y :9."
}

start_desktop(){
  require_termux
  installed ||
    die "La instalación no está completa. Ejecuta: $0 install"
  load_config

  # Flujo restaurado desde c07a55a: no ACTION_STOP durante el inicio,
  # no legacy drawing, no locale regional forzado y no GPU global.
  stop_debian_session
  stop_x11_servers
  pulseaudio --kill 2>/dev/null || true
  acquire_wake_lock

  log "Iniciando PulseAudio"
  unset PULSE_SERVER
  pulseaudio --start --exit-idle-time=-1
  sleep 1
  pactl load-module module-native-protocol-tcp \
    auth-ip-acl=127.0.0.1 \
    auth-anonymous=1 \
    >/dev/null 2>&1 || true

  start_x11_server

  am start --user 0 \
    -n com.termux.x11/com.termux.x11.MainActivity \
    >/dev/null 2>&1 ||
    warn "Abre Termux:X11 manualmente; el servidor ya está activo."

  cat > "$TMPDIR/mobile-debian-start.sh" <<'START'
#!/usr/bin/env bash
set -Eeuo pipefail
export DISPLAY="$1"
export PULSE_SERVER=127.0.0.1
export XDG_RUNTIME_DIR="/tmp/runtime-$2"

# No se fuerza es_CO, LANGUAGE ni LC_ALL.
export LANG=C.UTF-8
unset LANGUAGE LC_ALL
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
unset MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER TU_DEBUG VK_ICD_FILENAMES

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
rm -rf "$HOME/.cache/sessions/"* 2>/dev/null || true
rm -f "$HOME/.Xauthority" 2>/dev/null || true

socket="/tmp/.X11-unix/X${DISPLAY#:}"
[[ -e "$socket" ]] || {
  echo "[ERROR] Socket X11 no visible dentro de Debian: $socket" >&2
  exit 1
}

printf '[Debian] DISPLAY=%s | inicio estable c07a55a | GPU sin forzar\n' \
  "$DISPLAY"

exec dbus-launch --exit-with-session bash -c 'exec xfce4-session'
START
  chmod 0755 "$TMPDIR/mobile-debian-start.sh"

  log "Iniciando XFCE con el flujo estable"
  login_args
  set +e
  proot-distro "${LOGIN_ARGS[@]}" --user "$LINUX_USER" -- \
    /bin/bash /tmp/mobile-debian-start.sh \
      "$DISPLAY_NUM" "$LINUX_USER" \
    2>&1 | tee "$XFCE_LOG"
  local rc=${PIPESTATUS[0]}
  set -e

  stop_debian_session
  stop_x11_servers
  pulseaudio --kill 2>/dev/null || true
  am broadcast -a com.termux.x11.ACTION_STOP \
    -p com.termux.x11 >/dev/null 2>&1 || true
  release_wake_lock
  return "$rc"
}

stop_desktop(){
  require_termux
  load_config
  stop_debian_session
  stop_x11_servers
  pulseaudio --kill 2>/dev/null || true
  am broadcast -a com.termux.x11.ACTION_STOP \
    -p com.termux.x11 >/dev/null 2>&1 || true
  release_wake_lock
  ok "Sesión cerrada y wake-lock liberado"
}

reset_desktop(){
  require_termux
  installed || die "Primero instala el entorno."
  load_config
  stop_desktop

  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  login_args

  proot-distro "${LOGIN_ARGS[@]}" -- /bin/bash -lc "
    set -e
    home_dir=\$(getent passwd '$LINUX_USER' | cut -d: -f6)
    if [ -d \"\$home_dir/.config/xfce4\" ]; then
      mv \"\$home_dir/.config/xfce4\" \
         \"\$home_dir/.config/xfce4.backup-$stamp\"
    fi
    rm -rf \"\$home_dir/.cache/sessions\"
    rm -f \"\$home_dir/.Xauthority\"
    touch \"\$home_dir/.profile\"
    sed -i \
      -e '/^[[:space:]]*export LANG=/d' \
      -e '/^[[:space:]]*export LANGUAGE=/d' \
      -e '/^[[:space:]]*export LC_ALL=/d' \
      \"\$home_dir/.profile\"
    chown -R '$LINUX_USER:$LINUX_USER' \
      \"\$home_dir/.config\" \"\$home_dir/.cache\" \"\$home_dir/.profile\"
    cat > /etc/default/locale <<'EOF_LOCALE'
LANG=C.UTF-8
EOF_LOCALE
  "

  ok "XFCE restablecido. Copia anterior: ~/.config/xfce4.backup-$stamp"
}

install_all(){
  require_termux
  host_packages
  setup_android_storage
  ensure_debian
  configure_debian 0
}

repair(){
  require_termux
  installed || die "Primero instala el entorno."
  load_config
  setup_android_storage
  configure_debian 0
}

update_ai(){
  require_termux
  installed || die "Primero instala el entorno."
  load_config
  configure_debian 1
}

self_update(){
  require_termux
  local tmp="$TMPDIR/mobile-debian.new"
  curl -fsSL "$REPO_RAW/mobile-debian.sh" -o "$tmp"
  bash -n "$tmp" ||
    die "La versión descargada no pasó la validación de sintaxis."
  install -m755 "$tmp" "$HOME/mobile-debian.sh"

  if curl -fsSL "$REPO_RAW/mobile-debian-session.sh" \
       -o "$TMPDIR/mobile-debian-session.new"; then
    install -m755 "$TMPDIR/mobile-debian-session.new" \
      "$HOME/mobile-debian-session.sh"
  fi
  ok "Scripts actualizados"
}

status(){
  require_termux
  load_config
  printf 'Mobile Debian Desktop %s\n' "$VERSION"
  printf 'Base de arranque: c07a55a\n'
  printf 'Debian: %s\n' \
    "$(distro_exists && echo disponible || echo ausente)"
  printf 'Usuario: %s\n' "$LINUX_USER"
  printf 'Locale del arranque: C.UTF-8\n'
  printf 'Display preferido: %s\n' "$DISPLAY_NUM"
  printf 'GPU experimental: desactivada\n'
  printf 'Almacenamiento Android: %s\n' \
    "${STORAGE_SOURCE:-no configurado}"
}

doctor(){
  require_termux
  installed || die "La instalación no está completa."
  load_config
  status
  login_args
  proot-distro "${LOGIN_ARGS[@]}" --user "$LINUX_USER" -- \
    /bin/bash -lc '
      for command_name in xfce4-session chromium-mobile code-mobile \
                          libreoffice vlc mpv ffmpeg git python3 node \
                          npm claude codex glxinfo; do
        if command -v "$command_name" >/dev/null 2>&1; then
          printf "OK   %s -> %s\n" \
            "$command_name" "$(command -v "$command_name")"
        else
          printf "MISS %s\n" "$command_name"
        fi
      done
    '
}

case "${1:-auto}" in
  auto)
    if installed; then
      start_desktop
    else
      install_all
      start_desktop
    fi
    ;;
  install) install_all ;;
  start) start_desktop ;;
  stop) stop_desktop ;;
  restart) stop_desktop; start_desktop ;;
  repair) repair ;;
  reset-desktop) reset_desktop ;;
  update-ai) update_ai ;;
  self-update) self_update ;;
  status) status ;;
  doctor) doctor ;;
  *)
    echo "Uso: $0 [install|start|stop|restart|repair|reset-desktop|update-ai|self-update|status|doctor]"
    exit 2
    ;;
esac
