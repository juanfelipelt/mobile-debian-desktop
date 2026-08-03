#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

VERSION="0.3.0"
DISTRO="debian"
LINUX_USER="${LINUX_USER:-felipe}"
DISPLAY_NUM="${DISPLAY_NUM:-:1}"
DISPLAY_ID="${DISPLAY_NUM#:}"
LOCALE="${LOCALE:-es_CO.UTF-8}"
INSTALL_DEV_STACK="${INSTALL_DEV_STACK:-1}"
INSTALL_OFFICE="${INSTALL_OFFICE:-1}"
INSTALL_MEDIA="${INSTALL_MEDIA:-1}"
INSTALL_VSCODE="${INSTALL_VSCODE:-1}"
INSTALL_AI_CLI="${INSTALL_AI_CLI:-1}"
INSTALL_GPU="${INSTALL_GPU:-1}"

STATE_DIR="$HOME/.config/mobile-debian"
STATE_FILE="$STATE_DIR/installed"
CONFIG_FILE="$STATE_DIR/config"
X11_PID_FILE="$STATE_DIR/termux-x11.pid"
LOG_DIR="$HOME/.local/state/mobile-debian"
X11_LOG="$LOG_DIR/termux-x11.log"
XFCE_LOG="$LOG_DIR/xfce.log"
mkdir -p "$STATE_DIR" "$LOG_DIR"

log(){ printf '\033[1;36m[Mobile Debian]\033[0m %s\n' "$*"; }
ok(){ printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[AVISO]\033[0m %s\n' "$*" >&2; }
die(){ printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

require_termux(){
  [[ "${PREFIX:-}" == /data/data/com.termux/files/usr ]] || die "Ejecuta el script en Termux."
  [[ "$(uname -m)" == aarch64 ]] || die "Se requiere Android ARM64/aarch64."
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

usage(){
  cat <<EOF
Mobile Debian Desktop $VERSION

Uso:
  $0                 Instala si hace falta; de lo contrario inicia XFCE.
  $0 install         Instala o repara el entorno.
  $0 start           Inicia Termux:X11 y XFCE.
  $0 stop            Cierra XFCE, X11 y PulseAudio.
  $0 restart         Reinicia la sesión.
  $0 update          Actualiza Termux/Debian sin reinstalar IA ni Mesa.
  $0 update-ai       Actualiza explícitamente Claude Code y Codex.
  $0 refresh-gpu     Reinstala explícitamente Mesa KGSL.
  $0 doctor          Comprueba aplicaciones y GPU.
  $0 status          Muestra el estado.
EOF
}

host_packages(){
  log "Actualizando Termux"
  pkg update -y
  pkg upgrade -y
  pkg install -y x11-repo
  pkg update -y
  pkg install -y termux-x11-nightly pulseaudio proot-distro curl wget git jq tar gzip coreutils procps
}

ensure_debian(){
  if distro_exists; then
    log "Debian ya existe; se conservará."
  else
    log "Instalando Debian"
    proot-distro install "$DISTRO"
  fi
}

write_debian_setup(){
  cat > "$TMPDIR/mobile-debian-setup.sh" <<'DEBIAN'
#!/usr/bin/env bash
set -Eeuo pipefail

: "${LINUX_USER:?}" "${LOCALE:?}"
: "${INSTALL_DEV_STACK:?}" "${INSTALL_OFFICE:?}" "${INSTALL_MEDIA:?}"
: "${INSTALL_VSCODE:?}" "${INSTALL_AI_CLI:?}" "${INSTALL_GPU:?}"
: "${AI_FORCE:?}" "${GPU_FORCE:?}" "${HOST_HAS_KGSL:?}"

export DEBIAN_FRONTEND=noninteractive
say(){ printf '[Debian] %s\n' "$*"; }
warn(){ printf '[Debian aviso] %s\n' "$*" >&2; }

say "Actualizando paquetes"
apt-get update
apt-get dist-upgrade -y

packages=(
  sudo locales tzdata ca-certificates curl wget gnupg jq gawk file xz-utils
  dbus-x11 xauth x11-xserver-utils xdg-utils desktop-base
  xfce4 xfce4-terminal xfce4-whiskermenu-plugin xfce4-notifyd
  thunar-archive-plugin file-roller mousepad ristretto tumbler gvfs pavucontrol
  mesa-utils vulkan-tools chromium
  fonts-noto-core fonts-noto-color-emoji fonts-liberation
  fonts-crosextra-carlito fonts-crosextra-caladea
)
[[ "$INSTALL_OFFICE" == 1 ]] && packages+=(libreoffice-writer libreoffice-l10n-es hunspell-es)
[[ "$INSTALL_MEDIA" == 1 ]] && packages+=(vlc mpv ffmpeg)
[[ "$INSTALL_DEV_STACK" == 1 ]] && packages+=(git build-essential pkg-config python3 python3-pip python3-venv nodejs npm)

say "Instalando o reparando XFCE y aplicaciones"
apt-get install -y --no-install-recommends "${packages[@]}"

if ! grep -q "^${LOCALE} UTF-8" /etc/locale.gen 2>/dev/null; then
  sed -i "s/^# *${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen || true
fi
locale-gen >/dev/null 2>&1 || true
update-locale LANG="$LOCALE" LC_ALL="$LOCALE" >/dev/null 2>&1 || true

if ! id "$LINUX_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos '' "$LINUX_USER"
fi
usermod -aG sudo,audio,video "$LINUX_USER" || true
printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$LINUX_USER" > "/etc/sudoers.d/90-$LINUX_USER"
chmod 0440 "/etc/sudoers.d/90-$LINUX_USER"
USER_HOME="$(getent passwd "$LINUX_USER" | cut -d: -f6)"

if [[ "$INSTALL_VSCODE" == 1 ]]; then
  say "Configurando Visual Studio Code ARM64"
  install -d -m755 /usr/share/keyrings
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor --yes -o /usr/share/keyrings/microsoft.gpg
  cat > /etc/apt/sources.list.d/vscode.sources <<'SRC'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: arm64
Signed-By: /usr/share/keyrings/microsoft.gpg
SRC
  apt-get update
  apt-get install -y code || warn "VS Code no pudo instalarse."
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
grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.profile" || printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.profile"

if [[ "$force" == 1 ]] || ! command -v claude >/dev/null 2>&1; then
  echo "Instalando/actualizando Claude Code"
  curl -fsSL https://claude.ai/install.sh -o "$HOME/.cache/mobile-debian/installers/claude-install.sh"
  bash "$HOME/.cache/mobile-debian/installers/claude-install.sh"
else
  echo "Claude Code ya está instalado; no se reinstala."
fi

if [[ "$force" == 1 ]] || ! command -v codex >/dev/null 2>&1; then
  echo "Instalando/actualizando Codex CLI"
  curl -fsSL https://chatgpt.com/codex/install.sh -o "$HOME/.cache/mobile-debian/installers/codex-install.sh"
  CODEX_NON_INTERACTIVE=true sh "$HOME/.cache/mobile-debian/installers/codex-install.sh"
else
  echo "Codex CLI ya está instalado; no se reinstala."
fi
AI
  chmod 0755 /tmp/mobile-debian-ai.sh
  chown "$LINUX_USER:$LINUX_USER" /tmp/mobile-debian-ai.sh
  su - "$LINUX_USER" -c "bash /tmp/mobile-debian-ai.sh '$AI_FORCE'" || warn "Alguna CLI de IA no pudo instalarse."
}
install_ai

configure_gpu(){
  local mode=software arch codename url
  arch="$(dpkg --print-architecture)"
  codename="$(. /etc/os-release; printf '%s' "${VERSION_CODENAME:-}")"

  if [[ "$INSTALL_GPU" != 1 || "$HOST_HAS_KGSL" != 1 || ! -e /dev/kgsl-3d0 ]]; then
    printf '%s\n' "$mode" > /etc/mobile-debian-gpu
    return
  fi
  if [[ "$arch" != arm64 || "$codename" != trixie ]]; then
    warn "Mesa KGSL automático requiere Debian Trixie ARM64."
    printf '%s\n' "$mode" > /etc/mobile-debian-gpu
    return
  fi
  if [[ "$GPU_FORCE" != 1 ]] && grep -Fxq kgsl /etc/mobile-debian-gpu 2>/dev/null; then
    say "Mesa KGSL ya está configurado; no se vuelve a descargar."
    return
  fi

  say "Descargando Mesa KGSL compatible"
  url="$(curl -fsSL https://api.github.com/repos/lfdevs/mesa-for-android-container/releases/latest \
    | jq -r '.assets[] | select(.name | endswith("debian_trixie_arm64.tar.gz")) | .browser_download_url' \
    | head -n1)"
  if [[ -z "$url" || "$url" == null ]]; then
    warn "No se encontró un paquete Mesa compatible."
    printf '%s\n' "$mode" > /etc/mobile-debian-gpu
    return
  fi
  curl -fL --retry 3 "$url" -o /tmp/mobile-debian-mesa.tar.gz
  if tar -tzf /tmp/mobile-debian-mesa.tar.gz | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    die "El paquete Mesa contiene rutas inseguras."
  fi
  tar -xzf /tmp/mobile-debian-mesa.tar.gz -C /
  ldconfig
  printf 'kgsl\n' > /etc/mobile-debian-gpu
  say "Mesa KGSL configurado"
}
configure_gpu

say "Configurando aplicaciones y escritorio"
install -d -m755 /usr/local/bin "$USER_HOME/.local/share/applications" "$USER_HOME/Desktop" "$USER_HOME/.config/autostart" "$USER_HOME/.local/bin"

cat > /usr/local/bin/chromium-mobile <<'CHROME'
#!/usr/bin/env bash
[[ -e /dev/kgsl-3d0 ]] && export MESA_LOADER_DRIVER_OVERRIDE=kgsl TU_DEBUG=noconform
exec chromium --no-sandbox --disable-dev-shm-usage --password-store=basic \
  --ozone-platform=x11 --use-gl=angle --use-angle=gl --ignore-gpu-blocklist \
  --enable-gpu-rasterization "$@"
CHROME
chmod 0755 /usr/local/bin/chromium-mobile

if command -v code >/dev/null 2>&1; then
  cat > /usr/local/bin/code-mobile <<'CODE'
#!/usr/bin/env bash
exec code --no-sandbox --disable-dev-shm-usage "$@"
CODE
  chmod 0755 /usr/local/bin/code-mobile
fi

APP_DIR="$USER_HOME/.local/share/applications"
cat > "$APP_DIR/chromium-mobile.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Chromium (GPU)
Exec=chromium-mobile %U
Icon=chromium
Terminal=false
Categories=Network;WebBrowser;
DESK
cat > "$APP_DIR/word-online.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Microsoft Word Online
Exec=chromium-mobile --app=https://www.office.com/launch/word
Icon=libreoffice-writer
Terminal=false
Categories=Office;
DESK

cp -f "$APP_DIR/chromium-mobile.desktop" "$USER_HOME/Desktop/"
[[ "$INSTALL_OFFICE" == 1 ]] && cp -f "$APP_DIR/word-online.desktop" "$USER_HOME/Desktop/" || true
for file in /usr/share/applications/vlc.desktop /usr/share/applications/libreoffice-writer.desktop /usr/share/applications/code.desktop /usr/share/applications/com.visualstudio.code.desktop; do
  [[ -f "$file" ]] && cp -f "$file" "$USER_HOME/Desktop/" || true
done
chmod +x "$USER_HOME/Desktop/"*.desktop 2>/dev/null || true

wallpaper="$(find /usr/share/desktop-base -type f \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.svg' \) \
  -path '*/wallpaper/*' 2>/dev/null | head -n1 || true)"
printf '%s\n' "$wallpaper" > /etc/mobile-debian-wallpaper

cat > "$USER_HOME/.local/bin/mobile-xfce-fixups" <<'FIX'
#!/usr/bin/env bash
sleep 4
xfconf-query -c xfwm4 -p /general/use_compositing -t bool -s false --create >/dev/null 2>&1 || true
xfconf-query -c xfce4-session -p /general/SaveOnExit -t bool -s false --create >/dev/null 2>&1 || true
marker="$HOME/.config/mobile-debian/visuals-v1"
if [[ ! -f "$marker" ]]; then
  wallpaper="$(cat /etc/mobile-debian-wallpaper 2>/dev/null || true)"
  if [[ -n "$wallpaper" && -f "$wallpaper" ]]; then
    mapfile -t props < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep '/last-image$' || true)
    [[ ${#props[@]} -gt 0 ]] || props=(/backdrop/screen0/monitor0/workspace0/last-image)
    for prop in "${props[@]}"; do
      xfconf-query -c xfce4-desktop -p "$prop" -t string -s "$wallpaper" --create >/dev/null 2>&1 || true
      xfconf-query -c xfce4-desktop -p "${prop%/last-image}/image-style" -t int -s 5 --create >/dev/null 2>&1 || true
    done
    xfdesktop --reload >/dev/null 2>&1 || true
  fi
  mkdir -p "$(dirname "$marker")"
  touch "$marker"
fi
FIX
chmod 0755 "$USER_HOME/.local/bin/mobile-xfce-fixups"

for item in light-locker.desktop xiccd.desktop polkit-mate-authentication-agent-1.desktop xfce4-power-manager.desktop; do
  printf '[Desktop Entry]\nType=Application\nHidden=true\nX-GNOME-Autostart-enabled=false\n' > "$USER_HOME/.config/autostart/$item"
done

chown -R "$LINUX_USER:$LINUX_USER" "$USER_HOME/.local" "$USER_HOME/.config" "$USER_HOME/Desktop"

say "Verificando componentes esenciales"
for cmd in xfce4-session chromium-mobile libreoffice vlc; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Falta el componente obligatorio: $cmd" >&2; exit 1; }
done
apt-get clean
say "Instalación y configuración completadas"
DEBIAN
  chmod 0755 "$TMPDIR/mobile-debian-setup.sh"
}

configure_debian(){
  local ai_force="${1:-0}" gpu_force="${2:-0}" kgsl=0 gpu
  [[ -e /dev/kgsl-3d0 ]] && kgsl=1
  write_debian_setup
  proot-distro login "$DISTRO" --shared-tmp -- env \
    LINUX_USER="$LINUX_USER" LOCALE="$LOCALE" \
    INSTALL_DEV_STACK="$INSTALL_DEV_STACK" INSTALL_OFFICE="$INSTALL_OFFICE" \
    INSTALL_MEDIA="$INSTALL_MEDIA" INSTALL_VSCODE="$INSTALL_VSCODE" \
    INSTALL_AI_CLI="$INSTALL_AI_CLI" INSTALL_GPU="$INSTALL_GPU" \
    AI_FORCE="$ai_force" GPU_FORCE="$gpu_force" HOST_HAS_KGSL="$kgsl" \
    bash /tmp/mobile-debian-setup.sh
  gpu="$(proot-distro login "$DISTRO" -- cat /etc/mobile-debian-gpu 2>/dev/null || echo software)"
  cat > "$CONFIG_FILE" <<EOF
VERSION=$VERSION
DISTRO=$DISTRO
LINUX_USER=$LINUX_USER
DISPLAY_NUM=$DISPLAY_NUM
GPU_MODE=$gpu
EOF
  date -Iseconds > "$STATE_FILE"
  ok "Configuración terminada. GPU=$gpu"
}

load_config(){
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    DISPLAY_ID="${DISPLAY_NUM#:}"
  fi
}

stop_debian_session(){
  distro_exists || return 0
  proot-distro login "$DISTRO" --shared-tmp --user "$LINUX_USER" -- bash -lc '
    for p in xfce4-session xfce4-panel xfdesktop xfwm4 Thunar xfce4-terminal; do
      pkill -TERM -x "$p" 2>/dev/null || true
    done
  ' >/dev/null 2>&1 || true
}

x11_pids(){
  { [[ -s "$X11_PID_FILE" ]] && cat "$X11_PID_FILE" || true; pgrep -x termux-x11 2>/dev/null || true; } \
    | awk '/^[0-9]+$/ && !seen[$0]++'
}

stop_x11_server(){
  local -a pids=()
  local pid alive
  mapfile -t pids < <(x11_pids)
  if [[ ${#pids[@]} -gt 0 ]]; then
    for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
    for _ in $(seq 1 40); do
      alive=0
      for pid in "${pids[@]}"; do kill -0 "$pid" 2>/dev/null && alive=1; done
      [[ "$alive" == 0 ]] && break
      sleep 0.1
    done
    for pid in "${pids[@]}"; do kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true; done
    for _ in $(seq 1 20); do pgrep -x termux-x11 >/dev/null 2>&1 || break; sleep 0.1; done
  fi
  pgrep -x termux-x11 >/dev/null 2>&1 && die "Termux:X11 sigue activo; no se tocarán sus sockets."
  rm -f "$X11_PID_FILE" "$TMPDIR/.X${DISPLAY_ID}-lock" "$TMPDIR/.X11-unix/X${DISPLAY_ID}"
}

start_desktop(){
  require_termux
  installed || die "La instalación no está completa. Ejecuta: $0 install"
  load_config
  stop_debian_session
  stop_x11_server
  pulseaudio --kill 2>/dev/null || true

  log "Iniciando PulseAudio"
  unset PULSE_SERVER
  pulseaudio --start --exit-idle-time=-1
  sleep 1
  pactl load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1 >/dev/null 2>&1 || true

  log "Iniciando Termux:X11 en $DISPLAY_NUM"
  export XDG_RUNTIME_DIR="$TMPDIR"
  mkdir -p "$TMPDIR/.X11-unix"
  : > "$X11_LOG"
  termux-x11 "$DISPLAY_NUM" >"$X11_LOG" 2>&1 &
  local pid=$! socket="$TMPDIR/.X11-unix/X${DISPLAY_ID}" ready=0
  printf '%s\n' "$pid" > "$X11_PID_FILE"
  for _ in $(seq 1 60); do
    [[ -e "$socket" ]] && { ready=1; break; }
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
  done
  if [[ "$ready" != 1 ]]; then
    tail -n 50 "$X11_LOG" >&2 || true
    die "Termux:X11 no creó el socket $socket"
  fi

  am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || warn "Abre Termux:X11 manualmente; el servidor ya está activo."

  cat > "$TMPDIR/mobile-debian-start.sh" <<'START'
#!/usr/bin/env bash
set -Eeuo pipefail
export DISPLAY="$1"
export PULSE_SERVER=127.0.0.1
export XDG_RUNTIME_DIR="/tmp/runtime-$2"
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
rm -rf ~/.cache/sessions/* 2>/dev/null || true
rm -f ~/.Xauthority 2>/dev/null || true
if [[ "$3" == kgsl ]]; then export MESA_LOADER_DRIVER_OVERRIDE=kgsl TU_DEBUG=noconform; fi
socket="/tmp/.X11-unix/X${DISPLAY#:}"
[[ -e "$socket" ]] || { echo "Socket X11 no visible en Debian: $socket" >&2; exit 1; }
printf '[Debian] DISPLAY=%s | GPU=%s\n' "$DISPLAY" "$3"
exec dbus-launch --exit-with-session bash -c '"$HOME/.local/bin/mobile-xfce-fixups" >/dev/null 2>&1 & exec xfce4-session'
START
  chmod 0755 "$TMPDIR/mobile-debian-start.sh"

  log "Iniciando XFCE (GPU=${GPU_MODE:-software}, DISPLAY=$DISPLAY_NUM)"
  proot-distro login "$DISTRO" --shared-tmp --user "$LINUX_USER" -- \
    /bin/bash /tmp/mobile-debian-start.sh "$DISPLAY_NUM" "$LINUX_USER" "${GPU_MODE:-software}" \
    2>&1 | tee "$XFCE_LOG"
}

stop_desktop(){
  require_termux
  load_config
  stop_debian_session
  stop_x11_server
  pulseaudio --kill 2>/dev/null || true
  am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 >/dev/null 2>&1 || true
  ok "Sesión cerrada"
}

install_all(){ require_termux; host_packages; ensure_debian; configure_debian 0 0; }
update_all(){ require_termux; installed || die "Primero instala el entorno."; host_packages; configure_debian 0 0; }
update_ai(){ require_termux; installed || die "Primero instala el entorno."; configure_debian 1 0; }
refresh_gpu(){ require_termux; installed || die "Primero instala el entorno."; configure_debian 0 1; }

status(){
  require_termux
  load_config
  printf 'Mobile Debian Desktop %s\n' "$VERSION"
  printf 'Debian: %s\n' "$(distro_exists && echo disponible || echo ausente)"
  printf 'Display: %s\n' "$DISPLAY_NUM"
  printf 'GPU: %s\n' "${GPU_MODE:-desconocida}"
  printf 'Termux:X11: %s\n' "$(pgrep -x termux-x11 >/dev/null 2>&1 && echo activo || echo inactivo)"
  printf 'Socket: %s\n' "$([[ -e "$TMPDIR/.X11-unix/X${DISPLAY_ID}" ]] && echo activo || echo inactivo)"
}

doctor(){
  require_termux
  installed || die "La instalación no está completa."
  load_config
  status
  proot-distro login "$DISTRO" --shared-tmp --user "$LINUX_USER" -- bash -lc '
    for cmd in xfce4-session chromium-mobile code-mobile libreoffice vlc claude codex glxinfo vulkaninfo; do
      command -v "$cmd" >/dev/null 2>&1 && printf "OK   %-18s %s\n" "$cmd" "$(command -v "$cmd")" || printf "MISS %s\n" "$cmd"
    done
  '
}

case "${1:-auto}" in
  auto) if installed; then start_desktop; else install_all; start_desktop; fi ;;
  install) install_all ;;
  start) start_desktop ;;
  stop) stop_desktop ;;
  restart) stop_desktop; start_desktop ;;
  update) update_all ;;
  update-ai) update_ai ;;
  refresh-gpu) refresh_gpu ;;
  doctor) doctor ;;
  status) status ;;
  -h|--help|help) usage ;;
  *) usage; die "Comando desconocido: $1" ;;
esac
