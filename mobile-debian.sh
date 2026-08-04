#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

VERSION="0.5.0"
REPO_RAW="https://raw.githubusercontent.com/juanfelipelt/mobile-debian-desktop/main"
DISTRO="${DISTRO:-debian}"
LINUX_USER="${LINUX_USER:-felipe}"
DISPLAY_NUM="${DISPLAY_NUM:-:1}"
LOCALE="${LOCALE:-es_CO.UTF-8}"
X11_LEGACY_DRAWING="${X11_LEGACY_DRAWING:-1}"
X11_FORCE_BGRA="${X11_FORCE_BGRA:-0}"

INSTALL_DEV_STACK="${INSTALL_DEV_STACK:-1}"
INSTALL_OFFICE="${INSTALL_OFFICE:-1}"
INSTALL_MEDIA="${INSTALL_MEDIA:-1}"
INSTALL_VSCODE="${INSTALL_VSCODE:-1}"
INSTALL_CHROMIUM="${INSTALL_CHROMIUM:-1}"
INSTALL_AI_CLI="${INSTALL_AI_CLI:-1}"
INSTALL_GPU="${INSTALL_GPU:-0}"

STATE_DIR="$HOME/.config/mobile-debian"
STATE_FILE="$STATE_DIR/installed"
CONFIG_FILE="$STATE_DIR/config"
X11_PID_FILE="$STATE_DIR/termux-x11.pid"
APP_BRIDGE_PID_FILE="$STATE_DIR/app-bridge.pid"
APP_BRIDGE_DIR="$TMPDIR/mobile-debian-app-bridge"
WAKE_LOCK_FILE="$STATE_DIR/wake-lock"
LOG_DIR="$HOME/.local/state/mobile-debian"
X11_LOG="$LOG_DIR/termux-x11.log"
XFCE_LOG="$LOG_DIR/xfce.log"
HOST_APP_LOG="$LOG_DIR/host-apps.log"
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
  if [[ -f "$STATE_FILE" ]]; then
    return 0
  fi
  if proot-distro login "$DISTRO" -- test -x /usr/bin/xfce4-session >/dev/null 2>&1; then
    date -Iseconds > "$STATE_FILE"
    return 0
  fi
  return 1
}

acquire_wake_lock(){
  if command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock >/dev/null 2>&1 || warn "No se pudo activar el wake-lock."
    date -Iseconds > "$WAKE_LOCK_FILE"
    ok "Wake-lock activado"
  fi
}

release_wake_lock(){
  command -v termux-wake-unlock >/dev/null 2>&1 &&
    termux-wake-unlock >/dev/null 2>&1 || true
  rm -f "$WAKE_LOCK_FILE"
}

host_apps(){
  local -a apps=()
  pkg install -y x11-repo util-linux
  pkg update -y
  [[ "$INSTALL_CHROMIUM" == 1 ]] && apps+=(chromium)
  [[ "$INSTALL_VSCODE" == 1 ]] && apps+=(code-oss)
  if [[ ${#apps[@]} -gt 0 ]]; then
    log "Instalando aplicaciones gráficas nativas de Termux: ${apps[*]}"
    pkg install -y "${apps[@]}"
  fi
}

host_packages(){
  log "Actualizando Termux"
  pkg update -y
  pkg upgrade -y
  pkg install -y x11-repo
  pkg update -y
  pkg install -y termux-x11-nightly pulseaudio proot-distro curl wget git jq tar gzip coreutils procps util-linux
  host_apps
}

ensure_debian(){
  if distro_exists; then
    log "Debian ya está instalado"
  else
    log "Instalando Debian"
    proot-distro install "$DISTRO"
  fi
}

write_debian_configurator(){
  cat > "$TMPDIR/mobile-debian-configure.sh" <<'DEBIAN'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

MODE="$1"
LINUX_USER="$2"
LOCALE="$3"
INSTALL_DEV_STACK="$4"
INSTALL_OFFICE="$5"
INSTALL_MEDIA="$6"
INSTALL_VSCODE="$7"
INSTALL_CHROMIUM="$8"
INSTALL_AI_CLI="$9"
INSTALL_GPU="${10}"
AI_FORCE="${11}"
GPU_FORCE="${12}"
HOST_HAS_KGSL="${13}"

say(){ printf '[Debian] %s\n' "$*"; }
warn(){ printf '[AVISO] %s\n' "$*" >&2; }
die(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }

# Las aplicaciones Chromium/Electron se ejecutan nativamente en Termux.
# Elimina repositorios y paquetes antiguos que se ejecutaban dentro de PRoot.
rm -f /etc/apt/sources.list.d/vscode.sources \
      /etc/apt/sources.list.d/vscode.list \
      /usr/share/keyrings/microsoft.gpg

if [[ "$MODE" != apps-only ]]; then
  say "Actualizando paquetes"
  apt-get update
  apt-get dist-upgrade -y

  packages=(
    sudo locales tzdata ca-certificates curl wget gnupg jq file xz-utils
    dbus-x11 xauth x11-xserver-utils xdg-utils desktop-base
    xfce4 xfce4-terminal xfce4-whiskermenu-plugin xfce4-notifyd
    thunar-archive-plugin file-roller mousepad ristretto tumbler gvfs pavucontrol
    mesa-utils vulkan-tools
    libegl-mesa0 libgbm1 libgl1-mesa-dri libglx-mesa0 mesa-libgallium mesa-vulkan-drivers
    fonts-noto-core fonts-noto-color-emoji fonts-liberation fonts-crosextra-carlito
  )
  [[ "$INSTALL_OFFICE" == 1 ]] && packages+=(libreoffice-writer libreoffice-l10n-es hunspell-es)
  [[ "$INSTALL_MEDIA" == 1 ]] && packages+=(vlc mpv ffmpeg)
  [[ "$INSTALL_DEV_STACK" == 1 ]] && packages+=(git build-essential pkg-config python3 python3-pip python3-venv nodejs npm)

  say "Instalando y reparando XFCE y aplicaciones"
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
fi

id "$LINUX_USER" >/dev/null 2>&1 || die "No existe el usuario $LINUX_USER."
USER_HOME="$(getent passwd "$LINUX_USER" | cut -d: -f6)"

legacy_packages=()
for package_name in code chromium chromium-common; do
  dpkg-query -W -f='${db:Status-Abbrev}' "$package_name" 2>/dev/null | grep -q '^ii ' &&
    legacy_packages+=("$package_name")
done
if [[ ${#legacy_packages[@]} -gt 0 ]]; then
  say "Eliminando aplicaciones gráficas antiguas de Debian: ${legacy_packages[*]}"
  apt-get purge -y "${legacy_packages[@]}"
fi

if [[ "$MODE" == apps-only ]]; then
  say "Restaurando Mesa oficial de Debian"
  apt-get update
  apt-get install --reinstall -y \
    libegl-mesa0 libgbm1 libgl1-mesa-dri libglx-mesa0 \
    mesa-libgallium mesa-vulkan-drivers
fi
if [[ "$INSTALL_GPU" != 1 ]]; then
  printf 'software\n' > /etc/mobile-debian-gpu
fi

install_ai(){
  [[ "$MODE" != apps-only ]] || return 0
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
  su - "$LINUX_USER" -c "bash /tmp/mobile-debian-ai.sh '$AI_FORCE'" ||
    warn "Alguna CLI de IA no pudo instalarse."
}
install_ai

configure_gpu(){
  [[ "$MODE" != apps-only ]] || return 0
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
  url="$(
    curl -fsSL https://api.github.com/repos/lfdevs/mesa-for-android-container/releases/latest |
      jq -r '.assets[] | select(.name | endswith("debian_trixie_arm64.tar.gz")) | .browser_download_url' |
      head -n1
  )"
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

say "Configurando puente para aplicaciones nativas de Termux"
install -d -m755 \
  /usr/local/bin \
  "$USER_HOME/.local/share/applications" \
  "$USER_HOME/.local/share/pixmaps" \
  "$USER_HOME/Desktop" \
  "$USER_HOME/.config/autostart" \
  "$USER_HOME/.local/bin"

cat > /usr/local/bin/mobile-host-app <<'HOSTAPP'
#!/usr/bin/env bash
set -Eeuo pipefail
app="${1:?Uso: mobile-host-app chromium|code-oss [argumentos]}"
shift
bridge_dir=/tmp/mobile-debian-app-bridge
request_dir="$bridge_dir/requests"
[[ -d "$request_dir" ]] || {
  echo "[ERROR] El puente de aplicaciones de Termux no está activo." >&2
  exit 1
}

args=("$@")
if [[ "$app" == code-oss ]]; then
  rootfs="$(cat "$bridge_dir/rootfs" 2>/dev/null || true)"
  host_tmp="$(cat "$bridge_dir/host-tmp" 2>/dev/null || true)"
  translated=()
  for arg in "${args[@]}"; do
    if [[ "$arg" != -* && "$arg" != *://* && -e "$arg" ]]; then
      arg="$(realpath "$arg")"
    fi
    case "$arg" in
      /tmp/*)
        [[ -n "$host_tmp" ]] && arg="$host_tmp/${arg#/tmp/}"
        ;;
      /home/*|/root/*|/opt/*|/srv/*|/var/*|/etc/*|/usr/local/*)
        [[ -n "$rootfs" ]] && arg="$rootfs$arg"
        ;;
    esac
    translated+=("$arg")
  done
  args=("${translated[@]}")
fi

tmp="$(mktemp "$request_dir/request.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
{
  printf '%s\0' "$app"
  printf '%s\0' "${args[@]}"
} > "$tmp"
mv "$tmp" "$tmp.ready"
trap - EXIT
HOSTAPP
chmod 0755 /usr/local/bin/mobile-host-app

cat > /usr/local/bin/chromium-mobile <<'CHROME'
#!/usr/bin/env bash
exec mobile-host-app chromium "$@"
CHROME
chmod 0755 /usr/local/bin/chromium-mobile

cat > /usr/local/bin/code-mobile <<'CODE'
#!/usr/bin/env bash
exec mobile-host-app code-oss "$@"
CODE
chmod 0755 /usr/local/bin/code-mobile

rm -f /usr/local/bin/chromium-gpu \
      "$USER_HOME/.local/share/applications/chromium-gpu.desktop" \
      "$USER_HOME/.local/share/applications/code.desktop" \
      "$USER_HOME/Desktop/chromium-gpu.desktop" \
      "$USER_HOME/Desktop/code.desktop"

APP_DIR="$USER_HOME/.local/share/applications"
cat > "$APP_DIR/chromium-mobile.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Chromium
Comment=Chromium nativo de Termux para Termux:X11
Exec=chromium-mobile %U
Icon=chromium
Terminal=false
Categories=Network;WebBrowser;
DESK

cat > "$APP_DIR/code-mobile.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Code - OSS
Comment=Editor nativo de Termux para Termux:X11
Exec=code-mobile %F
Icon=com.visualstudio.code.oss
Terminal=false
Categories=Development;IDE;
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

rm -f "$USER_HOME/Desktop/chromium-mobile.desktop" \
      "$USER_HOME/Desktop/code-mobile.desktop" \
      "$USER_HOME/Desktop/word-online.desktop"
[[ "$INSTALL_CHROMIUM" == 1 ]] && cp "$APP_DIR/chromium-mobile.desktop" "$USER_HOME/Desktop/"
[[ "$INSTALL_VSCODE" == 1 ]] && cp "$APP_DIR/code-mobile.desktop" "$USER_HOME/Desktop/"
[[ "$INSTALL_OFFICE" == 1 && "$INSTALL_CHROMIUM" == 1 ]] && cp "$APP_DIR/word-online.desktop" "$USER_HOME/Desktop/"
for desktop_file in \
  /usr/share/applications/vlc.desktop \
  /usr/share/applications/libreoffice-writer.desktop; do
  [[ -f "$desktop_file" ]] && cp "$desktop_file" "$USER_HOME/Desktop/"
done
chmod +x "$USER_HOME/Desktop/"*.desktop 2>/dev/null || true

wallpaper="$(
  find /usr/share/desktop-base -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.svg' \) \
    -path '*/wallpaper/*' 2>/dev/null |
    sort |
    head -n1 || true
)"
printf '%s\n' "$wallpaper" > /etc/mobile-debian-wallpaper

cat > "$USER_HOME/.local/bin/mobile-xfce-fixups" <<'FIX'
#!/usr/bin/env bash
set -u
sleep 3
xfconf-query -c xfwm4 -p /general/use_compositing -t bool -s false --create >/dev/null 2>&1 || true
wallpaper="$(cat /etc/mobile-debian-wallpaper 2>/dev/null || true)"
if [[ -n "$wallpaper" && -f "$wallpaper" ]]; then
  mapfile -t properties < <(
    xfconf-query -c xfce4-desktop -l 2>/dev/null |
      grep '/last-image$' || true
  )
  if [[ ${#properties[@]} -eq 0 ]]; then
    properties=(/backdrop/screen0/monitor0/workspace0/last-image)
  fi
  for property in "${properties[@]}"; do
    xfconf-query -c xfce4-desktop -p "$property" -t string -s "$wallpaper" --create >/dev/null 2>&1 || true
    xfconf-query -c xfce4-desktop -p "${property%/last-image}/image-style" -t int -s 5 --create >/dev/null 2>&1 || true
  done
  xfdesktop --reload >/dev/null 2>&1 || true
fi
FIX
chmod 0755 "$USER_HOME/.local/bin/mobile-xfce-fixups"

for item in light-locker.desktop xiccd.desktop polkit-mate-authentication-agent-1.desktop xfce4-power-manager.desktop; do
  printf '[Desktop Entry]\nType=Application\nHidden=true\nX-GNOME-Autostart-enabled=false\n' \
    > "$USER_HOME/.config/autostart/$item"
done

chown -R "$LINUX_USER:$LINUX_USER" \
  "$USER_HOME/.local" \
  "$USER_HOME/.config" \
  "$USER_HOME/Desktop"

say "Verificando componentes esenciales"
for command_name in xfce4-session mobile-host-app; do
  command -v "$command_name" >/dev/null 2>&1 || die "Falta el componente obligatorio: $command_name"
done
[[ "$INSTALL_CHROMIUM" != 1 ]] || command -v chromium-mobile >/dev/null 2>&1 || warn "El lanzador de Chromium no está disponible."
[[ "$INSTALL_VSCODE" != 1 ]] || command -v code-mobile >/dev/null 2>&1 || warn "El lanzador de Code - OSS no está disponible."
[[ "$INSTALL_OFFICE" != 1 ]] || command -v libreoffice >/dev/null 2>&1 || warn "LibreOffice no está disponible."
[[ "$INSTALL_MEDIA" != 1 ]] || command -v vlc >/dev/null 2>&1 || warn "VLC no está disponible."

[[ "$MODE" == apps-only ]] || apt-get clean
say "Configuración terminada"
DEBIAN
  chmod 0755 "$TMPDIR/mobile-debian-configure.sh"
}

configure_debian(){
  local mode="${1:-full}"
  local ai_force="${2:-0}"
  local gpu_force="${3:-0}"
  local host_has_kgsl=0
  [[ -e /dev/kgsl-3d0 ]] && host_has_kgsl=1

  write_debian_configurator
  proot-distro login "$DISTRO" --shared-tmp -- \
    /bin/bash /tmp/mobile-debian-configure.sh \
      "$mode" "$LINUX_USER" "$LOCALE" \
      "$INSTALL_DEV_STACK" "$INSTALL_OFFICE" "$INSTALL_MEDIA" \
      "$INSTALL_VSCODE" "$INSTALL_CHROMIUM" "$INSTALL_AI_CLI" "$INSTALL_GPU" \
      "$ai_force" "$gpu_force" "$host_has_kgsl"

  local gpu
  gpu="$(proot-distro login "$DISTRO" -- cat /etc/mobile-debian-gpu 2>/dev/null || echo software)"
  cat > "$CONFIG_FILE" <<EOF_CONFIG
DISPLAY_NUM=$DISPLAY_NUM
GPU_MODE=$gpu
X11_LEGACY_DRAWING=$X11_LEGACY_DRAWING
X11_FORCE_BGRA=$X11_FORCE_BGRA
EOF_CONFIG
  date -Iseconds > "$STATE_FILE"
  ok "Configuración terminada. GPU=$gpu"
}

load_config(){
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi
  if [[ -z "${GPU_MODE:-}" ]] && distro_exists; then
    GPU_MODE="$(proot-distro login "$DISTRO" -- cat /etc/mobile-debian-gpu 2>/dev/null || echo software)"
  fi
  GPU_MODE="${GPU_MODE:-software}"
  X11_LEGACY_DRAWING="${X11_LEGACY_DRAWING:-1}"
  X11_FORCE_BGRA="${X11_FORCE_BGRA:-0}"
}

stop_debian_session(){
  distro_exists || return 0
  proot-distro login "$DISTRO" --shared-tmp --user "$LINUX_USER" -- bash -lc '
    for process_name in xfce4-session xfce4-panel xfdesktop xfwm4 Thunar xfce4-terminal chromium code; do
      pkill -TERM -x "$process_name" 2>/dev/null || true
    done
    sleep 0.5
    pkill -KILL -x chromium 2>/dev/null || true
    pkill -KILL -x code 2>/dev/null || true
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
    for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
    for _ in $(seq 1 40); do
      alive=0
      for pid in "${pids[@]}"; do kill -0 "$pid" 2>/dev/null && alive=1; done
      [[ "$alive" == 0 ]] && break
      sleep 0.1
    done
    for pid in "${pids[@]}"; do
      kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
    done
    sleep 0.5
  fi

  pkill -KILL -f '[c]om\.termux\.x11\.CmdEntryPoint' 2>/dev/null || true
  pkill -KILL -f '(^|/)[t]ermux-x11([[:space:]]|$)' 2>/dev/null || true
  sleep 0.3
  rm -f "$X11_PID_FILE"
}

rootfs_host_path(){
  local candidate
  for candidate in \
    "$PREFIX/var/lib/proot-distro/containers/$DISTRO/rootfs" \
    "$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"; do
    [[ -d "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

kill_tracked_host_apps(){
  local records="$APP_BRIDGE_DIR/pids"
  local app pid
  [[ -f "$records" ]] || return 0

  while IFS=: read -r app pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    if kill -0 "$pid" 2>/dev/null; then
      case "$app" in
        chromium|code-oss)
          kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
          ;;
      esac
    fi
  done < "$records"

  sleep 0.8
  while IFS=: read -r app pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
    fi
  done < "$records"
}

stop_host_bridge(){
  local pid=""
  rm -f "$APP_BRIDGE_DIR/run"

  if [[ -s "$APP_BRIDGE_PID_FILE" ]]; then
    pid="$(cat "$APP_BRIDGE_PID_FILE" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
      for _ in $(seq 1 30); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
      done
      kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
    fi
  fi

  kill_tracked_host_apps
  rm -f "$APP_BRIDGE_PID_FILE"
  rm -rf "$APP_BRIDGE_DIR"
}

start_host_bridge(){
  stop_host_bridge
  mkdir -p "$APP_BRIDGE_DIR/requests"
  : > "$APP_BRIDGE_DIR/pids"
  : > "$APP_BRIDGE_DIR/run"
  rootfs_host_path > "$APP_BRIDGE_DIR/rootfs" || die "No se encontró el rootfs de Debian."
  printf '%s\n' "$TMPDIR" > "$APP_BRIDGE_DIR/host-tmp"
  : > "$HOST_APP_LOG"

  cat > "$TMPDIR/mobile-debian-host-bridge.sh" <<'BRIDGE'
#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

display="$1"
bridge_dir="$2"
log_file="$3"
prefix="$4"
host_home="$5"
request_dir="$bridge_dir/requests"
pids_file="$bridge_dir/pids"
run_file="$bridge_dir/run"

launch_app(){
  local app="$1"
  shift
  local executable
  local -a base_args=()

  case "$app" in
    chromium)
      executable="$prefix/bin/chromium"
      base_args=(
        --no-sandbox
        --disable-dev-shm-usage
        --password-store=basic
        --ozone-platform=x11
      )
      ;;
    code-oss)
      executable="$prefix/bin/code-oss"
      base_args=(
        --no-sandbox
        --disable-dev-shm-usage
      )
      ;;
    *)
      printf '[bridge] Aplicación no permitida: %s\n' "$app" >> "$log_file"
      return 0
      ;;
  esac

  if [[ ! -x "$executable" ]]; then
    printf '[bridge] No existe: %s\n' "$executable" >> "$log_file"
    return 0
  fi

  env \
    -u LD_PRELOAD \
    -u LD_LIBRARY_PATH \
    -u MESA_LOADER_DRIVER_OVERRIDE \
    -u GALLIUM_DRIVER \
    -u TU_DEBUG \
    -u VK_ICD_FILENAMES \
    HOME="$host_home" \
    PREFIX="$prefix" \
    TMPDIR="$prefix/tmp" \
    XDG_RUNTIME_DIR="$prefix/tmp" \
    DISPLAY="$display" \
    PULSE_SERVER=127.0.0.1 \
    PATH="$prefix/bin:/system/bin:/system/xbin" \
    setsid "$executable" "${base_args[@]}" "$@" >> "$log_file" 2>&1 &
  printf '%s:%s\n' "$app" "$!" >> "$pids_file"
}

cleanup(){
  rm -f "$run_file"
}
trap cleanup EXIT INT TERM HUP

while [[ -e "$run_file" ]]; do
  shopt -s nullglob
  requests=("$request_dir"/*.ready)
  shopt -u nullglob

  if [[ ${#requests[@]} -eq 0 ]]; then
    sleep 0.2
    continue
  fi

  for request in "${requests[@]}"; do
    argv=()
    mapfile -d '' -t argv < "$request" || true
    rm -f "$request"
    [[ ${#argv[@]} -gt 0 ]] || continue
    launch_app "${argv[0]}" "${argv[@]:1}"
  done
done
BRIDGE
  chmod 0755 "$TMPDIR/mobile-debian-host-bridge.sh"

  "$TMPDIR/mobile-debian-host-bridge.sh" \
    "$DISPLAY_NUM" "$APP_BRIDGE_DIR" "$HOST_APP_LOG" "$PREFIX" "$HOME" &
  local pid=$!
  printf '%s\n' "$pid" > "$APP_BRIDGE_PID_FILE"
  sleep 0.3
  kill -0 "$pid" 2>/dev/null || {
    tail -n 40 "$HOST_APP_LOG" >&2 2>/dev/null || true
    die "No se pudo iniciar el puente de aplicaciones gráficas."
  }
  ok "Puente de Chromium y Code - OSS activo"
}

display_busy(){
  local id="$1"
  [[ -e "$TMPDIR/.X11-unix/X$id" || -e "$TMPDIR/.X$id-lock" ]] && return 0
  grep -qE "(@|/)([^ ]*/)?\.X11-unix/X${id}([[:space:]]|$)" /proc/net/unix 2>/dev/null
}

start_x11_server(){
  local requested_id="${DISPLAY_NUM#:}"
  local -a candidates=("$requested_id") x11_args=()
  local id candidate pid socket ready

  [[ "$X11_LEGACY_DRAWING" == 1 ]] && x11_args+=(-legacy-drawing)
  [[ "$X11_FORCE_BGRA" == 1 ]] && x11_args+=(-force-bgra)

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
    log "Iniciando Termux:X11 en $candidate ${x11_args[*]}"
    termux-x11 "$candidate" "${x11_args[@]}" >>"$X11_LOG" 2>&1 &
    pid=$!
    printf '%s\n' "$pid" > "$X11_PID_FILE"
    socket="$TMPDIR/.X11-unix/X$id"
    ready=0

    for _ in $(seq 1 60); do
      if [[ -e "$socket" ]]; then ready=1; break; fi
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

cleanup_runtime(){
  stop_debian_session
  stop_host_bridge
  stop_x11_servers
  pulseaudio --kill 2>/dev/null || true
  am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 >/dev/null 2>&1 || true
  release_wake_lock
}

start_desktop(){
  require_termux
  installed || die "La instalación no está completa. Ejecuta: $0 install"
  load_config
  cleanup_runtime
  acquire_wake_lock

  local cleaned=0
  session_cleanup(){
    local rc="${1:-0}"
    [[ "$cleaned" == 0 ]] || return 0
    cleaned=1
    trap - EXIT INT TERM HUP
    cleanup_runtime
    [[ "$rc" == 0 ]] && ok "Sesión cerrada y wake-lock liberado"
  }
  trap 'rc=$?; session_cleanup "$rc"; exit "$rc"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP

  log "Iniciando PulseAudio"
  unset PULSE_SERVER
  pulseaudio --start --exit-idle-time=-1
  sleep 1
  pactl load-module module-native-protocol-tcp \
    auth-ip-acl=127.0.0.1 auth-anonymous=1 >/dev/null 2>&1 || true

  start_x11_server
  start_host_bridge
  am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 ||
    warn "Abre Termux:X11 manualmente; el servidor ya está activo."

  cat > "$TMPDIR/mobile-debian-start.sh" <<'START'
#!/usr/bin/env bash
set -Eeuo pipefail
export DISPLAY="$1"
export PULSE_SERVER=127.0.0.1
export XDG_RUNTIME_DIR="/tmp/runtime-$2"
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
rm -rf "$HOME/.cache/sessions/"* 2>/dev/null || true
rm -f "$HOME/.Xauthority" 2>/dev/null || true
# No se fuerzan drivers Mesa sobre XFCE, Chromium ni Electron.
unset MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER TU_DEBUG VK_ICD_FILENAMES
socket="/tmp/.X11-unix/X${DISPLAY#:}"
[[ -e "$socket" ]] || { echo "[ERROR] Socket X11 no visible dentro de Debian: $socket" >&2; exit 1; }
printf '[Debian] DISPLAY=%s | Mesa disponible=%s | sin driver forzado\n' "$DISPLAY" "$3"
exec dbus-launch --exit-with-session bash -c '"$HOME/.local/bin/mobile-xfce-fixups" >/dev/null 2>&1 & exec xfce4-session'
START
  chmod 0755 "$TMPDIR/mobile-debian-start.sh"

  log "Iniciando XFCE (Mesa disponible=$GPU_MODE, DISPLAY=$DISPLAY_NUM)"
  set +e
  proot-distro login "$DISTRO" --shared-tmp --user "$LINUX_USER" -- \
    /bin/bash /tmp/mobile-debian-start.sh "$DISPLAY_NUM" "$LINUX_USER" "$GPU_MODE" \
    2>&1 | tee "$XFCE_LOG"
  local rc
  rc=${PIPESTATUS[0]}
  set -e

  session_cleanup "$rc"
  trap - EXIT INT TERM HUP
  return "$rc"
}

stop_desktop(){
  require_termux
  load_config
  cleanup_runtime
  ok "Sesión cerrada y wake-lock liberado"
}

install_all(){
  require_termux
  host_packages
  ensure_debian
  configure_debian full 0 0
}

update_all(){
  require_termux
  installed || die "Primero instala el entorno."
  host_packages
  configure_debian full 0 0
}

repair_apps(){
  require_termux
  installed || die "Primero instala el entorno."
  load_config
  cleanup_runtime
  log "Migrando Chromium y Code - OSS a paquetes nativos de Termux"
  host_apps
  configure_debian apps-only 0 0
  ok "Migración terminada. Inicia con: $HOME/mobile-debian.sh start"
}

update_ai(){
  require_termux
  installed || die "Primero instala el entorno."
  configure_debian full 1 0
}

refresh_gpu(){
  require_termux
  installed || die "Primero instala el entorno."
  warn "Mesa KGSL es experimental y se aplicará solo bajo solicitud explícita."
  INSTALL_GPU=1 configure_debian full 0 1
}

self_update(){
  require_termux
  local tmp="$TMPDIR/mobile-debian.new"
  curl -fsSL "$REPO_RAW/mobile-debian.sh" -o "$tmp"
  bash -n "$tmp" || die "La versión descargada no pasó la validación de sintaxis."
  install -m755 "$tmp" "$HOME/mobile-debian.sh"
  if curl -fsSL "$REPO_RAW/mobile-debian-session.sh" -o "$TMPDIR/mobile-debian-session.new"; then
    install -m755 "$TMPDIR/mobile-debian-session.new" "$HOME/mobile-debian-session.sh"
  fi
  ok "Script actualizado. Ejecuta repair-apps para aplicar cambios de lanzadores."
}

status(){
  require_termux
  load_config
  printf 'Mobile Debian Desktop %s\n' "$VERSION"
  printf 'Debian: %s\n' "$(distro_exists && echo disponible || echo ausente)"
  printf 'Display preferido: %s\n' "$DISPLAY_NUM"
  printf 'Termux:X11 legacy drawing: %s\n' "$X11_LEGACY_DRAWING"
  printf 'Mesa del contenedor: %s (no forzado globalmente)\n' "$GPU_MODE"
  printf 'Wake-lock solicitado: %s\n' "$([[ -f "$WAKE_LOCK_FILE" ]] && echo sí || echo no)"
  if [[ -s "$APP_BRIDGE_PID_FILE" ]] && kill -0 "$(cat "$APP_BRIDGE_PID_FILE")" 2>/dev/null; then
    printf 'Puente de aplicaciones: activo (PID %s)\n' "$(cat "$APP_BRIDGE_PID_FILE")"
  else
    printf 'Puente de aplicaciones: inactivo\n'
  fi
  printf 'Servidores X11 detectados:\n'
  x11_pids | sed 's/^/  PID /' || true
}

doctor(){
  require_termux
  installed || die "La instalación no está completa."
  load_config
  status
  for command_name in chromium code-oss; do
    if command -v "$command_name" >/dev/null 2>&1; then
      printf "OK   host:%s -> %s\n" "$command_name" "$(command -v "$command_name")"
    else
      printf "MISS host:%s\n" "$command_name"
    fi
  done
  proot-distro login "$DISTRO" --shared-tmp --user "$LINUX_USER" -- /bin/bash -lc '
    for command_name in xfce4-session chromium-mobile code-mobile libreoffice vlc claude codex glxinfo vulkaninfo; do
      if command -v "$command_name" >/dev/null 2>&1; then
        printf "OK   guest:%s -> %s\n" "$command_name" "$(command -v "$command_name")"
      else
        printf "MISS guest:%s\n" "$command_name"
      fi
    done
  '
}

case "${1:-auto}" in
  auto)
    if installed; then start_desktop; else install_all; start_desktop; fi
    ;;
  install) install_all ;;
  start) start_desktop ;;
  stop) stop_desktop ;;
  restart) stop_desktop; start_desktop ;;
  update) update_all ;;
  repair-apps) repair_apps ;;
  update-ai) update_ai ;;
  refresh-gpu) refresh_gpu ;;
  self-update) self_update ;;
  status) status ;;
  doctor) doctor ;;
  *)
    echo "Uso: $0 [install|start|stop|restart|update|repair-apps|update-ai|refresh-gpu|self-update|status|doctor]"
    exit 2
    ;;
esac
