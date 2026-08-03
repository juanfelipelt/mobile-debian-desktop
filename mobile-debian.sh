#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

VERSION="0.2.2"
DISTRO=debian
LINUX_USER="${LINUX_USER:-felipe}"
DISPLAY_NUM="${DISPLAY_NUM:-:1}"
DISPLAY_ID="${DISPLAY_NUM#:}"
STATE="$HOME/.config/mobile-debian/installed"
ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"
LOGDIR="$HOME/.local/state/mobile-debian"
mkdir -p "$(dirname "$STATE")" "$LOGDIR"

log(){ printf '\033[1;36m[Mobile Debian]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
termux(){ [[ "${PREFIX:-}" == /data/data/com.termux/files/usr ]] || die "Ejecuta esto en Termux."; }
installed(){ [[ -f "$STATE" && -d "$ROOTFS" ]]; }

host_packages(){
  log "Actualizando Termux"
  pkg update -y && pkg upgrade -y
  pkg install -y x11-repo
  pkg update -y
  pkg install -y termux-x11-nightly pulseaudio proot-distro curl git jq tar gzip procps
}

install_debian(){
  [[ -d "$ROOTFS" ]] || proot-distro install "$DISTRO"
  cat > "$TMPDIR/debian-setup.sh" <<'DEBIAN'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get dist-upgrade -y
apt-get install -y --no-install-recommends \
  sudo locales tzdata ca-certificates curl wget gnupg jq file xz-utils \
  dbus-x11 xauth x11-xserver-utils xdg-utils \
  xfce4 xfce4-terminal xfce4-whiskermenu-plugin xfce4-notifyd \
  thunar-archive-plugin file-roller mousepad ristretto tumbler gvfs pavucontrol \
  mesa-utils vulkan-tools chromium \
  libreoffice-writer libreoffice-l10n-es hunspell-es \
  vlc mpv ffmpeg git build-essential pkg-config \
  python3 python3-pip python3-venv nodejs npm \
  fonts-noto-core fonts-noto-color-emoji fonts-liberation fonts-crosextra-carlito

if ! id "$LINUX_USER" >/dev/null 2>&1; then adduser --disabled-password --gecos '' "$LINUX_USER"; fi
usermod -aG sudo,audio,video "$LINUX_USER" || true
echo "$LINUX_USER ALL=(ALL:ALL) NOPASSWD: ALL" > "/etc/sudoers.d/90-$LINUX_USER"
HOME_DIR="$(getent passwd "$LINUX_USER"|cut -d: -f6)"

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
apt-get install -y code || true

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
su - "$LINUX_USER" -c 'bash /tmp/install-ai.sh' || true

GPU_MODE=software
if [[ -e /dev/kgsl-3d0 && "$(dpkg --print-architecture)" == arm64 ]]; then
  CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-}")"
  if [[ "$CODENAME" == trixie ]]; then
    API=https://api.github.com/repos/lfdevs/mesa-for-android-container/releases/latest
    URL="$(curl -fsSL "$API" | jq -r '.assets[]|select(.name|endswith("debian_trixie_arm64.tar.gz"))|.browser_download_url' | head -1)"
    if [[ -n "$URL" && "$URL" != null ]]; then
      curl -fL "$URL" -o /tmp/mesa-adreno.tar.gz
      tar -tzf /tmp/mesa-adreno.tar.gz | grep -Eq '(^/|(^|/)\.\.(/|$))' && exit 1 || true
      tar -xzf /tmp/mesa-adreno.tar.gz -C /
      ldconfig
      GPU_MODE=kgsl
    fi
  fi
fi
echo "$GPU_MODE" > /etc/mobile-debian-gpu

install -d -m755 /usr/local/bin "$HOME_DIR/.local/share/applications" "$HOME_DIR/Desktop" "$HOME_DIR/.config/autostart"
cat > /usr/local/bin/chromium-mobile <<'CHROME'
#!/bin/bash
exec chromium --ozone-platform=x11 --use-gl=angle --use-angle=gl --ignore-gpu-blocklist --enable-gpu-rasterization --disable-dev-shm-usage --no-sandbox "$@"
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
cp "$HOME_DIR/.local/share/applications/"*.desktop "$HOME_DIR/Desktop/"

for f in light-locker.desktop xiccd.desktop polkit-mate-authentication-agent-1.desktop xfce4-power-manager.desktop; do
  printf '[Desktop Entry]\nType=Application\nHidden=true\nX-GNOME-Autostart-enabled=false\n' > "$HOME_DIR/.config/autostart/$f"
done
chown -R "$LINUX_USER:$LINUX_USER" "$HOME_DIR/.local" "$HOME_DIR/.config" "$HOME_DIR/Desktop"
apt-get clean
DEBIAN
  chmod +x "$TMPDIR/debian-setup.sh"
  proot-distro login "$DISTRO" --shared-tmp -- env LINUX_USER="$LINUX_USER" bash /tmp/debian-setup.sh
  date -Iseconds > "$STATE"
}

cleanup_session(){
  if [[ -d "$ROOTFS" ]]; then
    proot-distro login "$DISTRO" --shared-tmp --user "$LINUX_USER" -- bash -lc 'pkill -TERM -x xfce4-session 2>/dev/null||true; pkill -TERM -x xfwm4 2>/dev/null||true' >/dev/null 2>&1 || true
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
  installed || die "Primero ejecuta la instalación."
  cleanup_session
  pulseaudio --start --exit-idle-time=-1
  sleep 1
  pactl load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1 >/dev/null 2>&1 || true
  export XDG_RUNTIME_DIR="$TMPDIR"
  termux-x11 "$DISPLAY_NUM" >"$LOGDIR/termux-x11.log" 2>&1 &
  sleep 3

  # El APK se instala manualmente. Intentar mostrar su actividad es útil,
  # pero nunca debe bloquear la sesión si Android no permite lanzarla.
  am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || \
    log "Termux:X11 no pudo abrirse automáticamente; abre la app manualmente."

  GPU="$(proot-distro login "$DISTRO" -- cat /etc/mobile-debian-gpu 2>/dev/null || echo software)"
  EXTRA=''; [[ "$GPU" == kgsl ]] && EXTRA='export MESA_LOADER_DRIVER_OVERRIDE=kgsl; export TU_DEBUG=noconform;'
  log "Iniciando XFCE (GPU=$GPU)"
  proot-distro login "$DISTRO" --shared-tmp --user "$LINUX_USER" -- env DISPLAY="$DISPLAY_NUM" PULSE_SERVER=127.0.0.1 XDG_RUNTIME_DIR="/tmp/runtime-$LINUX_USER" GPU="$EXTRA" bash -lc 'mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"; rm -rf ~/.cache/sessions/*; eval "$GPU"; exec dbus-launch --exit-with-session xfce4-session'
}

install(){ termux; host_packages; install_debian; }
doctor(){
  termux
  proot-distro login "$DISTRO" --shared-tmp --user "$LINUX_USER" -- env DISPLAY="$DISPLAY_NUM" bash -lc 'for c in xfce4-session chromium-mobile code-mobile libreoffice vlc claude codex glxinfo vulkaninfo; do command -v "$c" || true; done; glxinfo -B 2>/dev/null|grep -E "OpenGL vendor|OpenGL renderer|OpenGL version"||true'
}

case "${1:-auto}" in
  auto) if installed; then start; else install; start; fi;;
  install) install;; start) start;; stop) stop;; restart) stop; start;;
  update) install;; doctor|status) doctor;;
  *) echo "Uso: $0 [install|start|stop|restart|update|doctor]";;
esac