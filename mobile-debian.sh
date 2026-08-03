#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

VERSION="0.2.4"
DISTRO="debian"
LINUX_USER="${LINUX_USER:-felipe}"
DISPLAY_NUM="${DISPLAY_NUM:-:1}"
DISPLAY_ID="${DISPLAY_NUM#:}"
STATE="$HOME/.config/mobile-debian/installed"
LOGDIR="$HOME/.local/state/mobile-debian"
mkdir -p "$(dirname "$STATE")" "$LOGDIR"

log(){ printf '\033[1;36m[Mobile Debian]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
termux(){ [[ "${PREFIX:-}" == /data/data/com.termux/files/usr ]] || die "Ejecuta esto en Termux."; }

distro_exists(){
  command -v proot-distro >/dev/null 2>&1 || return 1
  proot-distro login "$DISTRO" -- /bin/true >/dev/null 2>&1
}

installed(){
  distro_exists || return 1
  [[ -f "$STATE" ]] && return 0

  if proot-distro login "$DISTRO" -- test -x /usr/bin/xfce4-session >/dev/null 2>&1; then
    date -Iseconds > "$STATE"
    return 0
  fi
  return 1
}

host_packages(){
  log "Actualizando Termux"
  pkg update -y
  pkg upgrade -y
  pkg install -y x11-repo
  pkg update -y
  pkg install -y termux-x11-nightly pulseaudio proot-distro curl git jq tar gzip procps
}

install_debian(){
  if ! distro_exists; then
    log "Instalando Debian"
    proot-distro install "$DISTRO"
  else
    log "Debian ya existe; actualizando y reparando componentes"
  fi

  cat > "$TMPDIR/debian-setup.sh" <<'DEBIAN'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

printf '[Debian] Actualizando paquetes\n'
apt-get update
apt-get dist-upgrade -y

printf '[Debian] Instalando XFCE y aplicaciones\n'
apt-get install -y --no-install-recommends \
  sudo locales tzdata ca-certificates curl wget gnupg jq file xz-utils \
  dbus-x11 xauth x11-xserver-utils xdg-utils desktop-base \
  xfce4 xfce4-terminal xfce4-whiskermenu-plugin xfce4-notifyd \
  thunar-archive-plugin file-roller mousepad ristretto tumbler gvfs pavucontrol \
  mesa-utils vulkan-tools chromium \
  libreoffice-writer libreoffice-l10n-es hunspell-es \
  vlc mpv ffmpeg git build-essential pkg-config \
  python3 python3-pip python3-venv nodejs npm \
  fonts-noto-core fonts-noto-color-emoji fonts-liberation fonts-crosextra-carlito

if ! id "$LINUX_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos '' "$LINUX_USER"
fi
usermod -aG sudo,audio,video "$LINUX_USER" || true
echo "$LINUX_USER ALL=(ALL:ALL) NOPASSWD: ALL" > "/etc/sudoers.d/90-$LINUX_USER"
HOME_DIR="$(getent passwd "$LINUX_USER" | cut -d: -f6)"

printf '[Debian] Instalando Visual Studio Code ARM64\n'
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
apt-get install -y code || printf '[AVISO] VS Code no pudo instalarse; se podrá reparar con update.\n'

printf '[Debian] Instalando Claude Code y Codex\n'
cat > /tmp/install-ai.sh <<'AI'
#!/usr/bin/env bash
set -e
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
grep -Fq '.local/bin' "$HOME/.profile" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.profile"
curl -fsSL https://claude.ai/install.sh | bash
curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=true sh
AI
chmod +x /tmp/install-ai.sh
su - "$LINUX_USER" -c 'bash /tmp/install-ai.sh' || printf '[AVISO] Alguna CLI de IA no pudo instalarse; se podrá reparar con update.\n'

printf '[Debian] Configurando aceleración gráfica general\n'
GPU_MODE=software
if [[ -e /dev/kgsl-3d0 && "$(dpkg --print-architecture)" == arm64 ]]; then
  CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-}")"
  if [[ "$CODENAME" == trixie ]]; then
    API=https://api.github.com/repos/lfdevs/mesa-for-android-container/releases/latest
    URL="$(curl -fsSL "$API" | jq -r '.assets[] | select(.name | endswith("debian_trixie_arm64.tar.gz")) | .browser_download_url' | head -n 1)"
    if [[ -n "$URL" && "$URL" != null ]]; then
      curl -fL "$URL" -o /tmp/mesa-adreno.tar.gz
      if tar -tzf /tmp/mesa-adreno.tar.gz | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
        printf '[ERROR] El paquete Mesa contiene rutas inseguras.\n' >&2
        exit 1
      fi
      tar -xzf /tmp/mesa-adreno.tar.gz -C /
      ldconfig
      GPU_MODE=kgsl
    fi
  fi
fi
echo "$GPU_MODE" > /etc/mobile-debian-gpu
printf '[Debian] Modo gráfico configurado: %s\n' "$GPU_MODE"

printf '[Debian] Configurando aplicaciones y escritorio\n'
install -d -m755 \
  /usr/local/bin \
  "$HOME_DIR/.local/share/applications" \
  "$HOME_DIR/Desktop" \
  "$HOME_DIR/.config/autostart" \
  "$HOME_DIR/.config/mobile-debian"

cat > /usr/local/bin/chromium-mobile <<'CHROME'
#!/bin/bash
exec chromium \
  --ozone-platform=x11 \
  --use-gl=angle \
  --use-angle=gl \
  --ignore-gpu-blocklist \
  --enable-gpu-rasterization \
  --disable-dev-shm-usage \
  --no-sandbox \
  "$@"
CHROME

cat > /usr/local/bin/code-mobile <<'CODE'
#!/bin/bash
exec code --no-sandbox --disable-dev-shm-usage "$@"
CODE
chmod +x /usr/local/bin/chromium-mobile /usr/local/bin/code-mobile

cat > "$HOME_DIR/.local/share/applications/chromium-mobile.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Chromium (GPU)
Exec=chromium-mobile %U
Icon=chromium
Terminal=false
Categories=Network;WebBrowser;
DESK

cat > "$HOME_DIR/.local/share/applications/word-online.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Microsoft Word Online
Exec=chromium-mobile --app=https://www.office.com/launch/word
Icon=libreoffice-writer
Terminal=false
Categories=Office;
DESK

cp "$HOME_DIR/.local/share/applications/chromium-mobile.desktop" "$HOME_DIR/Desktop/"
cp "$HOME_DIR/.local/share/applications/word-online.desktop" "$HOME_DIR/Desktop/"
for desktop_file in \
  /usr/share/applications/vlc.desktop \
  /usr/share/applications/libreoffice-writer.desktop \
  /usr/share/applications/code.desktop; do
  [[ -f "$desktop_file" ]] && cp "$desktop_file" "$HOME_DIR/Desktop/"
done
chmod +x "$HOME_DIR/Desktop/"*.desktop 2>/dev/null || true

WALLPAPER="$(find /usr/share/desktop-base -type f \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.svg' \) \
  -path '*/wallpaper/*' 2>/dev/null | sort | head -n 1 || true)"
printf '%s\n' "$WALLPAPER" > /etc/mobile-debian-wallpaper

cat > /usr/local/bin/mobile-debian-session-init <<'INIT'
#!/bin/bash
set -u
MARKER="$HOME/.config/mobile-debian/visuals-initialized"
[[ -f "$MARKER" ]] && exit 0
sleep 3
xfconf-query -c xfwm4 -p /general/use_compositing -t bool -s false --create >/dev/null 2>&1 || true
WALLPAPER="$(cat /etc/mobile-debian-wallpaper 2>/dev/null || true)"
if [[ -n "$WALLPAPER" && -f "$WALLPAPER" ]]; then
  mapfile -t PROPERTIES < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep '/last-image$' || true)
  if [[ ${#PROPERTIES[@]} -eq 0 ]]; then
    PROPERTIES=(/backdrop/screen0/monitor0/workspace0/last-image)
  fi
  for property in "${PROPERTIES[@]}"; do
    xfconf-query -c xfce4-desktop -p "$property" -t string -s "$WALLPAPER" --create >/dev/null 2>&1 || true
    xfconf-query -c xfce4-desktop -p "${property%/last-image}/image-style" -t int -s 5 --create >/dev/null 2>&1 || true
  done
  xfdesktop --reload >/dev/null 2>&1 || true
fi
mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
INIT
chmod +x /usr/local/bin/mobile-debian-session-init

cat > "$HOME_DIR/.config/autostart/mobile-debian-session-init.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Mobile Debian session setup
Exec=/usr/local/bin/mobile-debian-session-init
Terminal=false
X-GNOME-Autostart-enabled=true
DESK

for f in light-locker.desktop xiccd.desktop polkit-mate-authentication-agent-1.desktop xfce4-power-manager.desktop; do
  printf '[Desktop Entry]\nType=Application\nHidden=true\nX-GNOME-Autostart-enabled=false\n' > "$HOME_DIR/.config/autostart/$f"
done

chown -R "$LINUX_USER:$LINUX_USER" \
  "$HOME_DIR/.local" \
  "$HOME_DIR/.config" \
  "$HOME_DIR/Desktop"

printf '[Debian] Verificando componentes esenciales\n'
for command_name in xfce4-session chromium-mobile libreoffice vlc; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf '[ERROR] Falta el componente obligatorio: %s\n' "$command_name" >&2
    exit 1
  }
done

apt-get clean
printf '[Debian] Instalación y configuración completadas\n'
DEBIAN

  chmod +x "$TMPDIR/debian-setup.sh"
  proot-distro login "$DISTRO" --shared-tmp -- env LINUX_USER="$LINUX_USER" bash /tmp/debian-setup.sh
  date -Iseconds > "$STATE"
  log "Instalación completa"
}

cleanup_session(){
  if distro_exists; then
    proot-distro login "$DISTRO" --shared-tmp --user "$LINUX_USER" -- \
      bash -lc 'pkill -TERM -x xfce4-session 2>/dev/null || true; pkill -TERM -x xfwm4 2>/dev/null || true' \
      >/dev/null 2>&1 || true
  fi
  pkill -TERM -x termux-x11 2>/dev/null || true
  pulseaudio --kill 2>/dev/null || true
  rm -f "$TMPDIR/.X${DISPLAY_ID}-lock" "$TMPDIR/.X11-unix/X${DISPLAY_ID}"
}

stop(){
  termux
  cleanup_session
  am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 >/dev/null 2>&1 || true
}

start(){
  termux
  installed || die "No encuentro una instalación completa de Debian/XFCE. Ejecuta: $0 install"
  cleanup_session

  pulseaudio --start --exit-idle-time=-1
  sleep 1
  pactl load-module module-native-protocol-tcp \
    auth-ip-acl=127.0.0.1 \
    auth-anonymous=1 \
    >/dev/null 2>&1 || true

  export XDG_RUNTIME_DIR="$TMPDIR"
  mkdir -p "$TMPDIR/.X11-unix"
  termux-x11 "$DISPLAY_NUM" >"$LOGDIR/termux-x11.log" 2>&1 &
  local x11_pid=$!

  local socket="$TMPDIR/.X11-unix/X${DISPLAY_ID}"
  local ready=0
  for _ in $(seq 1 30); do
    if [[ -S "$socket" || -e "$socket" ]]; then
      ready=1
      break
    fi
    if ! kill -0 "$x11_pid" 2>/dev/null; then
      break
    fi
    sleep 0.2
  done

  if [[ "$ready" -ne 1 ]]; then
    tail -n 40 "$LOGDIR/termux-x11.log" >&2 2>/dev/null || true
    die "Termux:X11 no creó el socket $socket. Revisa $LOGDIR/termux-x11.log"
  fi

  am start --user 0 \
    -n com.termux.x11/com.termux.x11.MainActivity \
    >/dev/null 2>&1 || log "Abre Termux:X11 manualmente; el servidor ya está activo."

  local gpu
  gpu="$(proot-distro login "$DISTRO" -- cat /etc/mobile-debian-gpu 2>/dev/null || echo software)"
  log "Iniciando XFCE (GPU=$gpu, DISPLAY=$DISPLAY_NUM)"

  proot-distro login "$DISTRO" \
    --shared-tmp \
    --user "$LINUX_USER" \
    -- /bin/bash -lc '
      DISPLAY_VALUE="$1"
      USER_VALUE="$2"
      GPU_MODE="$3"

      export DISPLAY="$DISPLAY_VALUE"
      export PULSE_SERVER=127.0.0.1
      export XDG_RUNTIME_DIR="/tmp/runtime-$USER_VALUE"
      unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS

      mkdir -p "$XDG_RUNTIME_DIR"
      chmod 700 "$XDG_RUNTIME_DIR"
      rm -rf ~/.cache/sessions/* 2>/dev/null || true
      rm -f ~/.Xauthority 2>/dev/null || true

      if [[ "$GPU_MODE" == kgsl ]]; then
        export MESA_LOADER_DRIVER_OVERRIDE=kgsl
        export TU_DEBUG=noconform
      fi

      SOCKET="/tmp/.X11-unix/X${DISPLAY_VALUE#:}"
      [[ -e "$SOCKET" ]] || {
        echo "[ERROR] Socket X11 no visible dentro de Debian: $SOCKET" >&2
        ls -la /tmp/.X11-unix >&2 2>/dev/null || true
        exit 1
      }

      echo "[Debian] DISPLAY=$DISPLAY | GPU=$GPU_MODE"
      exec dbus-launch --exit-with-session xfce4-session
    ' mobile-debian "$DISPLAY_NUM" "$LINUX_USER" "$gpu"
}

install(){
  termux
  host_packages
  install_debian
}

doctor(){
  termux
  distro_exists || die "Debian no está instalado."
  proot-distro login "$DISTRO" --shared-tmp --user "$LINUX_USER" -- \
    /bin/bash -lc '
      echo "GPU mode: $(cat /etc/mobile-debian-gpu 2>/dev/null || echo software)"
      for c in xfce4-session chromium-mobile code-mobile libreoffice vlc claude codex glxinfo vulkaninfo; do
        if command -v "$c" >/dev/null 2>&1; then
          printf "OK   %s -> %s\n" "$c" "$(command -v "$c")"
        else
          printf "MISS %s\n" "$c"
        fi
      done
    '
}

case "${1:-auto}" in
  auto)
    if installed; then start; else install; start; fi
    ;;
  install) install ;;
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  update) install ;;
  doctor|status) doctor ;;
  *) echo "Uso: $0 [install|start|stop|restart|update|doctor]" ;;
esac
