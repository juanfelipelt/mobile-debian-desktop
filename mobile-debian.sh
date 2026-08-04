#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

VERSION="0.9.0"
REPO_RAW="https://raw.githubusercontent.com/juanfelipelt/mobile-debian-desktop/main"

# Las claves que se guardan en el archivo de configuración. Lo que el usuario
# exporta en el entorno tiene prioridad sobre el archivo, así que se anota aquí
# antes de aplicar cualquier valor por defecto.
CONFIG_VERSION_CURRENT=2
CONFIG_KEYS=(
  DISPLAY_NUM LOCALE LANGUAGE_VALUE TIMEZONE
  X11_LEGACY_DRAWING X11_FORCE_BGRA X11_SOFTWARE_GL LOW_MEMORY
  DESKTOP_THEME STORAGE_SOURCE
)
ENV_OVERRIDES=()
for config_key in "${CONFIG_KEYS[@]}"; do
  [[ -n "${!config_key+set}" ]] && ENV_OVERRIDES+=("$config_key=${!config_key}")
done
unset config_key

DISTRO="${DISTRO:-debian}"
LINUX_USER="${LINUX_USER:-felipe}"
DISPLAY_NUM="${DISPLAY_NUM:-:1}"
LOCALE="${LOCALE:-es_CO.UTF-8}"
LANGUAGE_VALUE="${LANGUAGE_VALUE:-es_CO:es}"
TIMEZONE="${TIMEZONE:-America/Bogota}"
# La ruta normal de Termux:X11 es la que usan los scripts de referencia. El
# dibujo heredado solo debe activarse a mano, porque en las versiones recientes
# de la aplicación produce pantalla negra.
X11_LEGACY_DRAWING="${X11_LEGACY_DRAWING:-0}"
X11_FORCE_BGRA="${X11_FORCE_BGRA:-0}"
X11_SOFTWARE_GL="${X11_SOFTWARE_GL:-1}"
# En equipos con poca RAM Android mata Termux con SIGKILL cuando Chromium abre
# un proceso por sitio. Esto recorta procesos a costa del aislamiento entre
# sitios, así que se activa por dispositivo, no por defecto.
LOW_MEMORY="${LOW_MEMORY:-0}"
# Aspecto del escritorio: mocha o default.
DESKTOP_THEME="${DESKTOP_THEME:-mocha}"

INSTALL_DEV_STACK="${INSTALL_DEV_STACK:-1}"
INSTALL_OFFICE="${INSTALL_OFFICE:-1}"
INSTALL_MEDIA="${INSTALL_MEDIA:-1}"
INSTALL_GRAPHICS="${INSTALL_GRAPHICS:-1}"
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

load_config(){
  local stored_version=0
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    stored_version="${CONFIG_VERSION:-1}"
  fi

  # Las configuraciones de la versión 1 guardaron -legacy-drawing activado. Esa
  # ruta produce pantalla negra con las versiones actuales de Termux:X11, así
  # que se descarta el valor heredado una sola vez y se deja migrado el archivo.
  if [[ "$stored_version" -gt 0 && "$stored_version" -lt "$CONFIG_VERSION_CURRENT" ]]; then
    warn "Configuración anterior detectada: se desactiva el dibujo heredado de Termux:X11."
    X11_LEGACY_DRAWING=0
    X11_SOFTWARE_GL="${X11_SOFTWARE_GL:-1}"
    save_config
  fi

  # El archivo nunca pisa lo que el usuario pasó por entorno.
  local override
  for override in ${ENV_OVERRIDES[@]+"${ENV_OVERRIDES[@]}"}; do
    printf -v "${override%%=*}" '%s' "${override#*=}"
  done
  X11_LEGACY_DRAWING="${X11_LEGACY_DRAWING:-0}"
  X11_FORCE_BGRA="${X11_FORCE_BGRA:-0}"
  X11_SOFTWARE_GL="${X11_SOFTWARE_GL:-1}"
  LOW_MEMORY="${LOW_MEMORY:-0}"
  DESKTOP_THEME="${DESKTOP_THEME:-mocha}"
  STORAGE_SOURCE="${STORAGE_SOURCE:-}"
}

save_config(){
  local key
  printf 'CONFIG_VERSION=%s\n' "$CONFIG_VERSION_CURRENT" > "$CONFIG_FILE"
  for key in "${CONFIG_KEYS[@]}"; do
    printf '%s=%q\n' "$key" "${!key-}" >> "$CONFIG_FILE"
  done
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
  log "Actualizando Termux e instalando componentes base"
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
  command -v termux-setup-storage >/dev/null 2>&1 ||
    die "No se encontró termux-setup-storage. Actualiza Termux desde GitHub o F-Droid."

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
    die "No se concedió el acceso al almacenamiento. Abre los permisos de Termux y vuelve a ejecutar."

  STORAGE_SOURCE="$(readlink -f "$HOME/storage/shared" 2>/dev/null || true)"
  [[ -n "$STORAGE_SOURCE" && -d "$STORAGE_SOURCE" ]] ||
    die "No se pudo resolver la ruta del almacenamiento compartido."
  ok "Almacenamiento Android disponible en $STORAGE_SOURCE"
}

ensure_debian(){
  if distro_exists; then
    log "Debian ya está instalado"
  else
    log "Instalando Debian"
    proot-distro install "$DISTRO"
  fi
}

distro_login(){
  local user="$1"
  shift
  local -a args=(login "$DISTRO" --shared-tmp)
  if [[ -n "${STORAGE_SOURCE:-}" && -d "$STORAGE_SOURCE" ]]; then
    args+=(--bind "$STORAGE_SOURCE:/mnt/android")
  fi
  [[ -n "$user" ]] && args+=(--user "$user")
  proot-distro "${args[@]}" -- "$@"
}

write_debian_configurator(){
  cat > "$TMPDIR/mobile-debian-configure.sh" <<'DEBIAN'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

LINUX_USER="$1"
LOCALE="$2"
LANGUAGE_VALUE="$3"
TIMEZONE="$4"
INSTALL_DEV_STACK="$5"
INSTALL_OFFICE="$6"
INSTALL_MEDIA="$7"
INSTALL_VSCODE="$8"
INSTALL_CHROMIUM="$9"
INSTALL_AI_CLI="${10}"
AI_FORCE="${11}"
STORAGE_ENABLED="${12}"
INSTALL_GRAPHICS="${13:-0}"
LOW_MEMORY="${14:-0}"

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
  mesa-utils libgl1-mesa-dri libglx-mesa0
  fonts-noto-core fonts-noto-color-emoji fonts-liberation fonts-crosextra-carlito
)
[[ "$INSTALL_CHROMIUM" == 1 ]] && packages+=(chromium)
[[ "$INSTALL_OFFICE" == 1 ]] && packages+=(libreoffice libreoffice-l10n-es hunspell-es)
[[ "$INSTALL_MEDIA" == 1 ]] && packages+=(vlc mpv ffmpeg)
[[ "$INSTALL_GRAPHICS" == 1 ]] && packages+=(gimp)
[[ "$INSTALL_DEV_STACK" == 1 ]] && packages+=(git build-essential pkg-config python3 python3-pip python3-venv nodejs npm)

say "Instalando XFCE y aplicaciones"
apt-get install -y --no-install-recommends "${packages[@]}"

if grep -q "^# *${LOCALE} UTF-8" /etc/locale.gen 2>/dev/null; then
  sed -i "s/^# *${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen
elif ! grep -q "^${LOCALE} UTF-8" /etc/locale.gen 2>/dev/null; then
  printf '%s UTF-8\n' "$LOCALE" >> /etc/locale.gen
fi
locale-gen
update-locale LANG="$LOCALE" LANGUAGE="$LANGUAGE_VALUE" LC_ALL="$LOCALE"
ln -snf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
printf '%s\n' "$TIMEZONE" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1 || true

if ! id "$LINUX_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos '' "$LINUX_USER"
fi
usermod -aG sudo,audio,video "$LINUX_USER" || true
printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$LINUX_USER" > "/etc/sudoers.d/90-$LINUX_USER"
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
  echo "Instalando Claude Code"
  curl -fsSL https://claude.ai/install.sh -o "$HOME/.cache/mobile-debian/installers/claude-install.sh"
  bash "$HOME/.cache/mobile-debian/installers/claude-install.sh"
else
  echo "Claude Code ya está instalado."
fi

if [[ "$force" == 1 ]] || ! command -v codex >/dev/null 2>&1; then
  echo "Instalando Codex CLI"
  curl -fsSL https://chatgpt.com/codex/install.sh -o "$HOME/.cache/mobile-debian/installers/codex-install.sh"
  CODEX_NON_INTERACTIVE=true sh "$HOME/.cache/mobile-debian/installers/codex-install.sh"
else
  echo "Codex CLI ya está instalado."
fi
AI
  chmod 0755 /tmp/mobile-debian-ai.sh
  chown "$LINUX_USER:$LINUX_USER" /tmp/mobile-debian-ai.sh
  su - "$LINUX_USER" -c "bash /tmp/mobile-debian-ai.sh '$AI_FORCE'" ||
    warn "Alguna CLI de IA no pudo instalarse."
}
install_ai

say "Configurando aplicaciones para PRoot y Termux:X11"
# Con LANG en español xdg-user-dirs crearía ~/Escritorio y xfdesktop dejaría de
# mirar ~/Desktop, donde este script deja los accesos directos. Se fija el
# mapeo antes del primer arranque para que ambos coincidan.
printf 'enabled=False\n' > /etc/xdg/user-dirs.conf
install -d -m755 \
  /usr/local/bin \
  "$USER_HOME/.local/share/applications" \
  "$USER_HOME/.config/autostart" \
  "$USER_HOME/.config/gtk-3.0" \
  "$USER_HOME/.local/bin" \
  "$USER_HOME/Desktop"

cat > "$USER_HOME/.config/user-dirs.dirs" <<'DIRS'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
DIRS
printf 'es_CO\n' > "$USER_HOME/.config/user-dirs.locale"
install -d -m755 \
  "$USER_HOME/Downloads" "$USER_HOME/Documents" \
  "$USER_HOME/Music" "$USER_HOME/Pictures" "$USER_HOME/Videos"

cat > /usr/local/bin/chromium-mobile <<CHROME
#!/usr/bin/env bash
unset MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER TU_DEBUG VK_ICD_FILENAMES
LOW_MEMORY="\${LOW_MEMORY:-$LOW_MEMORY}"
args=(
  --no-sandbox
  --disable-dev-shm-usage
  --password-store=basic
  --ozone-platform=x11
)
# Sin GPU el proceso gráfico falla y reintenta en bucle, y el aislamiento por
# sitio abre un proceso por dominio: las dos cosas juntas agotan la RAM y
# Android responde con SIGKILL sobre Termux.
if [[ "\$LOW_MEMORY" == 1 ]]; then
  args+=(
    --disable-gpu
    --disable-site-isolation-trials
    --disable-features=IsolateOrigins,site-per-process
    --renderer-process-limit=2
    --process-per-site
  )
fi
exec /usr/bin/chromium "\${args[@]}" "\$@"
CHROME
chmod 0755 /usr/local/bin/chromium-mobile

cat > /usr/local/bin/code-mobile <<CODE
#!/usr/bin/env bash
unset MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER TU_DEBUG VK_ICD_FILENAMES
LOW_MEMORY="\${LOW_MEMORY:-$LOW_MEMORY}"
args=(--no-sandbox --disable-dev-shm-usage)
[[ "\$LOW_MEMORY" == 1 ]] && args+=(--disable-gpu)
exec /usr/bin/code "\${args[@]}" "\$@"
CODE
chmod 0755 /usr/local/bin/code-mobile

APP_DIR="$USER_HOME/.local/share/applications"
rm -f \
  "$APP_DIR/word-online.desktop" \
  "$APP_DIR/chromium-gpu.desktop" \
  "$APP_DIR/code-mobile.desktop" \
  "$APP_DIR/chromium-mobile.desktop" \
  "$USER_HOME/Desktop/word-online.desktop" \
  "$USER_HOME/Desktop/chromium-gpu.desktop"

if [[ "$INSTALL_CHROMIUM" == 1 ]]; then
  cat > "$APP_DIR/chromium-mobile.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Chromium
Comment=Navegador web de Debian
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
Comment=Editor de código oficial
Exec=code-mobile %F
Icon=visual-studio-code
Terminal=false
Categories=Development;IDE;
DESK
  cp "$APP_DIR/code-mobile.desktop" "$USER_HOME/Desktop/"
fi

cat > "$APP_DIR/mobile-debian-logout.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Cerrar Mobile Debian
Comment=Cierra XFCE y permite limpiar Termux:X11 y el wake-lock
Exec=xfce4-session-logout --logout
Icon=system-log-out
Terminal=false
Categories=System;
DESK
cp "$APP_DIR/mobile-debian-logout.desktop" "$USER_HOME/Desktop/"

if [[ "$STORAGE_ENABLED" == 1 ]]; then
  cat > "$APP_DIR/android-storage.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Archivos de Android
Comment=Abre el almacenamiento compartido del teléfono
Exec=thunar /mnt/android
Icon=folder
Terminal=false
Categories=System;FileTools;
DESK
  cp "$APP_DIR/android-storage.desktop" "$USER_HOME/Desktop/"
  ln -sfn /mnt/android "$USER_HOME/Android"
  ln -sfn /mnt/android/Download "$USER_HOME/Descargas-Android"
  ln -sfn /mnt/android/Documents "$USER_HOME/Documentos-Android"
  ln -sfn /mnt/android/DCIM "$USER_HOME/Camara-Android"
  touch "$USER_HOME/.config/gtk-3.0/bookmarks"
  for bookmark in \
    'file:///mnt/android Archivos de Android' \
    'file:///mnt/android/Download Descargas de Android' \
    'file:///mnt/android/Documents Documentos de Android' \
    'file:///mnt/android/DCIM Cámara de Android'; do
    grep -Fqx "$bookmark" "$USER_HOME/.config/gtk-3.0/bookmarks" ||
      printf '%s\n' "$bookmark" >> "$USER_HOME/.config/gtk-3.0/bookmarks"
  done
fi

for desktop_file in \
  /usr/share/applications/libreoffice-startcenter.desktop \
  /usr/share/applications/vlc.desktop \
  /usr/share/applications/gimp.desktop; do
  [[ -f "$desktop_file" ]] && cp "$desktop_file" "$USER_HOME/Desktop/"
done
chmod +x "$USER_HOME/Desktop/"*.desktop 2>/dev/null || true

cat > "$USER_HOME/.local/bin/mobile-xfce-fixups" <<'FIX'
#!/usr/bin/env bash
set -u
sleep 3
xfconf-query -c xfwm4 -p /general/use_compositing -t bool -s false --create >/dev/null 2>&1 || true
# Sin esto XFCE guarda la sesión al salir y restaura una sesión rota en el
# arranque siguiente, que se ve como una pantalla negra sin panel.
xfconf-query -c xfce4-session -p /general/SaveOnExit -t bool -s false --create >/dev/null 2>&1 || true
xfconf-query -c xsettings -p /Gtk/FontName -t string -s 'Noto Sans 10' --create >/dev/null 2>&1 || true
FIX
chmod 0755 "$USER_HOME/.local/bin/mobile-xfce-fixups"

for item in light-locker.desktop xiccd.desktop polkit-mate-authentication-agent-1.desktop xfce4-power-manager.desktop; do
  printf '[Desktop Entry]\nType=Application\nHidden=true\nX-GNOME-Autostart-enabled=false\n' \
    > "$USER_HOME/.config/autostart/$item"
done

cat > "$USER_HOME/.profile" <<EOF_PROFILE
export LANG=$LOCALE
export LANGUAGE=$LANGUAGE_VALUE
export LC_ALL=$LOCALE
export PATH="\$HOME/.local/bin:\$PATH"
EOF_PROFILE

chown -R "$LINUX_USER:$LINUX_USER" \
  "$USER_HOME/.local" \
  "$USER_HOME/.config" \
  "$USER_HOME/Desktop" \
  "$USER_HOME/Downloads" \
  "$USER_HOME/Documents" \
  "$USER_HOME/Music" \
  "$USER_HOME/Pictures" \
  "$USER_HOME/Videos" \
  "$USER_HOME/.profile"
for link in Android Descargas-Android Documentos-Android Camara-Android; do
  [[ -L "$USER_HOME/$link" ]] && chown -h "$LINUX_USER:$LINUX_USER" "$USER_HOME/$link" || true
done

say "Verificando instalación"
required=(xfce4-session)
[[ "$INSTALL_CHROMIUM" == 1 ]] && required+=(chromium-mobile)
[[ "$INSTALL_VSCODE" == 1 ]] && required+=(code-mobile)
[[ "$INSTALL_OFFICE" == 1 ]] && required+=(libreoffice)
[[ "$INSTALL_MEDIA" == 1 ]] && required+=(vlc)
[[ "$INSTALL_GRAPHICS" == 1 ]] && required+=(gimp)
for command_name in "${required[@]}"; do
  command -v "$command_name" >/dev/null 2>&1 || die "Falta el componente: $command_name"
done

apt-get clean
say "Configuración terminada"
DEBIAN
  chmod 0755 "$TMPDIR/mobile-debian-configure.sh"
}

configure_debian(){
  local ai_force="${1:-0}"
  write_debian_configurator
  distro_login "" \
    /bin/bash /tmp/mobile-debian-configure.sh \
      "$LINUX_USER" "$LOCALE" "$LANGUAGE_VALUE" "$TIMEZONE" \
      "$INSTALL_DEV_STACK" "$INSTALL_OFFICE" "$INSTALL_MEDIA" \
      "$INSTALL_VSCODE" "$INSTALL_CHROMIUM" "$INSTALL_AI_CLI" \
      "$ai_force" "$ENABLE_ANDROID_STORAGE" "$INSTALL_GRAPHICS" \
      "$LOW_MEMORY"
  save_config
  date -Iseconds > "$STATE_FILE"
  ok "Debian configurado"
}

stop_debian_session(){
  distro_exists || return 0
  distro_login "$LINUX_USER" bash -lc '
    for process_name in xfce4-session xfce4-panel xfdesktop xfwm4 Thunar xfce4-terminal chromium code soffice.bin vlc; do
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

stop_x11_app(){
  # La aplicación de Android corre con otro UID: Termux no puede matarla con
  # kill, solo pedirle que se cierre. Si queda viva conservando la conexión
  # anterior, la ventana se queda en negro aunque el servidor nuevo funcione.
  am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 >/dev/null 2>&1 || true
}

stop_x11_servers(){
  local -a pids=()
  local pid alive=0
  stop_x11_app
  mapfile -t pids < <(x11_pids)

  if [[ ${#pids[@]} -gt 0 ]]; then
    log "Cerrando Termux:X11 anterior"
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
  fi

  pkill -KILL -f '[c]om\.termux\.x11\.CmdEntryPoint' 2>/dev/null || true
  pkill -KILL -f '(^|/)[t]ermux-x11([[:space:]]|$)' 2>/dev/null || true
  sleep 0.3
  rm -f "$X11_PID_FILE"
  for id in 0 1 2 3 4 5 6 7 8 9; do
    rm -f "$TMPDIR/.X$id-lock" "$TMPDIR/.X11-unix/X$id"
  done
  # La aplicación tarda un momento en soltar el socket abstracto; sin esta
  # espera el arranque siguiente cree que el display sigue ocupado y salta a
  # otro, dejando la ventana conectada al servidor muerto.
  wait_display_free "${DISPLAY_NUM#:}" 30 || true
}

wait_display_free(){
  local id="$1" attempts="${2:-30}"
  local _
  for _ in $(seq 1 "$attempts"); do
    display_busy "$id" || return 0
    sleep 0.1
  done
  return 1
}

x11_apk_version(){
  command -v pm >/dev/null 2>&1 || return 0
  pm dump com.termux.x11 2>/dev/null |
    sed -n 's/.*versionName=\([0-9][0-9.]*\).*/\1/p' | head -n 1 || true
}

x11_pkg_version(){
  command -v dpkg-query >/dev/null 2>&1 || return 0
  dpkg-query -W -f='${Version}' termux-x11-nightly 2>/dev/null |
    sed -n 's/^\([0-9][0-9.]*\).*/\1/p' || true
}

check_x11_versions(){
  local apk pkg
  apk="$(x11_apk_version)"
  pkg="$(x11_pkg_version)"
  [[ -n "$apk" && -n "$pkg" ]] || return 0
  if [[ "$apk" != "$pkg" ]]; then
    warn "Termux:X11 desincronizado: paquete $pkg contra aplicación $apk."
    warn "Esa diferencia es la causa habitual de pantalla negra o blanca."
    warn "Instala la APK que corresponde a $pkg desde github.com/termux/termux-x11."
    return 1
  fi
  return 0
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

  # Conviene insistir en el display pedido: la aplicación de Android se reengancha
  # al servidor nuevo sin problema, pero saltar de display por un socket que
  # todavía no se ha liberado deja la ventana en negro.
  if display_busy "$requested_id"; then
    log "Esperando a que se libere el display :$requested_id"
    wait_display_free "$requested_id" 50 || true
  fi

  for id in "${candidates[@]}"; do
    if display_busy "$id"; then
      warn "El display :$id sigue ocupado; probando otro."
      continue
    fi

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
  stop_x11_servers
  pulseaudio --kill 2>/dev/null || true
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

  check_x11_versions || true
  start_x11_server
  am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 ||
    warn "Abre Termux:X11 manualmente; el servidor ya está activo."
  sleep 1

  cat > "$TMPDIR/mobile-debian-start.sh" <<'START'
#!/usr/bin/env bash
set -Eeuo pipefail
export DISPLAY="$1"
export PULSE_SERVER=127.0.0.1
export XDG_RUNTIME_DIR="/tmp/runtime-$2"
export LANG="$3"
export LANGUAGE="$4"
export LC_ALL="$3"
software_gl="$5"
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
unset MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER TU_DEBUG VK_ICD_FILENAMES
# PRoot no expone la GPU, así que Mesa debe resolver por software. Sin esto
# xfwm4 y xfdesktop pueden abortar al no encontrar un driver DRI y la pantalla
# se queda en negro con el servidor X funcionando.
[[ "$software_gl" == 1 ]] && export LIBGL_ALWAYS_SOFTWARE=1
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
rm -rf "$HOME/.cache/sessions/"* 2>/dev/null || true
rm -f "$HOME/.Xauthority" 2>/dev/null || true
socket="/tmp/.X11-unix/X${DISPLAY#:}"
[[ -e "$socket" ]] || { echo "[ERROR] Socket X11 no visible en Debian: $socket" >&2; exit 1; }
if command -v xdpyinfo >/dev/null 2>&1 && ! timeout 20 xdpyinfo >/dev/null 2>&1; then
  echo "[ERROR] El servidor X responde en $socket pero no acepta clientes." >&2
  echo "[ERROR] Revisa que la versión de la APK Termux:X11 coincida con el paquete." >&2
  exit 1
fi
printf '[Debian] DISPLAY=%s | LANG=%s | GL por software=%s\n' "$DISPLAY" "$LANG" "$software_gl"
# startxfce4 prepara XDG_CONFIG_DIRS, xinitrc y el arranque de xfsettingsd,
# xfwm4, xfdesktop y el panel. Llamar a xfce4-session directamente deja el
# escritorio sin gestor de ventanas ni fondo en una instalación mínima.
if command -v startxfce4 >/dev/null 2>&1; then
  session_command=startxfce4
else
  session_command=xfce4-session
fi
exec dbus-launch --exit-with-session bash -c \
  '"$HOME/.local/bin/mobile-xfce-fixups" >/dev/null 2>&1 & exec "$1"' _ "$session_command"
START
  chmod 0755 "$TMPDIR/mobile-debian-start.sh"

  log "Iniciando XFCE en español de Colombia"
  set +e
  distro_login "$LINUX_USER" \
    /bin/bash /tmp/mobile-debian-start.sh \
      "$DISPLAY_NUM" "$LINUX_USER" "$LOCALE" "$LANGUAGE_VALUE" "$X11_SOFTWARE_GL" \
    2>&1 | tee "$XFCE_LOG"
  local rc=${PIPESTATUS[0]}
  set -e

  if [[ "$rc" != 0 ]]; then
    warn "XFCE terminó con código $rc. Últimas líneas de Termux:X11:"
    tail -n 25 "$X11_LOG" >&2 2>/dev/null || true
  fi

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
  # Una instalación completa descarga varios GB. Sin wake-lock Android puede
  # dormir el equipo y cortarla a la mitad.
  acquire_wake_lock
  host_packages
  setup_android_storage
  ensure_debian
  configure_debian 0
  # El escritorio nuevo arranca ya con el tema elegido.
  theme_apply_inner "$DESKTOP_THEME"
  release_wake_lock
}

write_theme_script(){
  cat > "$TMPDIR/mobile-debian-theme.sh" <<'THEME_ROOT'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
LINUX_USER="$1"
CHOICE="${2:-mocha}"

say(){ printf '[Tema] %s\n' "$*"; }
warn(){ printf '[AVISO] %s\n' "$*" >&2; }

if [[ "$CHOICE" == mocha ]]; then
  say "Instalando iconos y tipografías"
  apt-get install -y --no-install-recommends papirus-icon-theme unzip ||
    warn "No se pudieron instalar los iconos Papirus."
  for font_package in fonts-jetbrains-mono fonts-firacode fonts-cascadia-code; do
    say "Probando la tipografía $font_package (puede tardar, descarga en silencio)"
    if apt-get install -y --no-install-recommends "$font_package" >/dev/null 2>&1; then
      say "Tipografía instalada: $font_package"
      break
    fi
  done
fi

cat > /tmp/mobile-debian-theme-user.sh <<'THEME_USER'
#!/usr/bin/env bash
set -Eeuo pipefail
CHOICE="${1:-mocha}"

# El paquete oficial se llama catppuccin-mocha-blue-standard+default, que es
# ilegible en el selector de Xfce, así que se renombra al desempaquetar.
UPSTREAM="catppuccin-mocha-blue-standard+default"
THEME_URL="https://github.com/catppuccin/gtk/releases/download/v1.0.3/${UPSTREAM}.zip"
THEME_NAME="Catppuccin-Mocha"
say(){ printf '[Tema] %s\n' "$*"; }
warn(){ printf '[AVISO] %s\n' "$*" >&2; }

mkdir -p "$HOME/.themes" "$HOME/.config/xfce4/terminal" \
  "$HOME/.cache/mobile-debian/installers"

mono_font="Monospace 11"
for candidate in "JetBrains Mono" "Fira Code" "Cascadia Code"; do
  if fc-list : family 2>/dev/null | grep -Fq "$candidate"; then
    mono_font="$candidate 11"
    break
  fi
done

install_mocha(){
  say "Descargando el tema (278 KB)"
  local archive="$HOME/.cache/mobile-debian/installers/catppuccin-gtk.zip"
  local staging="$HOME/.cache/mobile-debian/installers/catppuccin-gtk"
  gtk_theme="Adwaita-dark"
  wm_theme="Default"

  if [[ -d "$HOME/.themes/$THEME_NAME/gtk-3.0" ]]; then
    say "Catppuccin Mocha ya estaba instalado"
  else
    rm -rf "$staging"
    if curl -fsSL "$THEME_URL" -o "$archive" && unzip -oq "$archive" -d "$staging"; then
      rm -rf "$HOME/.themes/$THEME_NAME"
      mv "$staging/$UPSTREAM" "$HOME/.themes/$THEME_NAME"
      # Las variantes -hdpi y -xhdpi solo cambian la separación de los botones
      # y no traen index.theme, así que no sirven como tema completo.
      rm -rf "$staging"
      sed -i "s/^Name=.*/Name=$THEME_NAME/" "$HOME/.themes/$THEME_NAME/index.theme" 2>/dev/null || true
      say "Catppuccin Mocha instalado"
    else
      warn "No se pudo descargar Catppuccin. Se usa Adwaita-dark como respaldo."
      rm -rf "$staging"
      return 0
    fi
  fi

  gtk_theme="$THEME_NAME"
  [[ -d "$HOME/.themes/$THEME_NAME/xfwm4" ]] && wm_theme="$THEME_NAME"

  say "Aplicando la paleta a la terminal"
  [[ -f "$HOME/.config/xfce4/terminal/terminalrc" ]] &&
    cp -n "$HOME/.config/xfce4/terminal/terminalrc" \
          "$HOME/.config/xfce4/terminal/terminalrc.previo" 2>/dev/null || true
  cat > "$HOME/.config/xfce4/terminal/terminalrc" <<TERMINALRC
[Configuration]
FontName=$mono_font
MiscAlwaysShowTabs=FALSE
MiscBell=FALSE
MiscCursorBlinks=TRUE
MiscCursorShape=TERMINAL_CURSOR_SHAPE_BLOCK
MiscDefaultGeometry=100x28
MiscMenubarDefault=FALSE
MiscToolbarDefault=FALSE
ScrollingUnlimited=TRUE
ColorForeground=#cdd6f4
ColorBackground=#1e1e2e
ColorCursor=#f5e0dc
ColorSelection=#585b70
ColorSelectionUseDefault=FALSE
ColorBold=#cdd6f4
ColorPalette=#45475a;#f38ba8;#a6e3a1;#f9e2af;#89b4fa;#f5c2e7;#94e2d5;#bac2de;#585b70;#f38ba8;#a6e3a1;#f9e2af;#89b4fa;#f5c2e7;#94e2d5;#a6adc8
TERMINALRC
}

restore_default(){
  gtk_theme="Adwaita"
  wm_theme="Default"
  say "Restaurando el aspecto original de XFCE"
  if [[ -f "$HOME/.config/xfce4/terminal/terminalrc.previo" ]]; then
    mv -f "$HOME/.config/xfce4/terminal/terminalrc.previo" \
          "$HOME/.config/xfce4/terminal/terminalrc"
  else
    rm -f "$HOME/.config/xfce4/terminal/terminalrc"
  fi
}

if [[ "$CHOICE" == mocha ]]; then
  install_mocha
  icon_theme="Papirus-Dark"
  ui_font="Noto Sans 11"
  title_font="Noto Sans Bold 13"
  panel_size=40
  panel_style=1
  backdrop_style=0
else
  restore_default
  icon_theme="Adwaita"
  ui_font="Noto Sans 10"
  title_font="Noto Sans Bold 9"
  panel_size=32
  panel_style=0
  backdrop_style=5
fi

say "Aplicando ajustes de XFCE"
apply(){
  dbus-launch --exit-with-session bash -s <<APPLY
set -u
xfconf-query -c xsettings -p /Net/ThemeName -t string -s '$gtk_theme' --create
xfconf-query -c xsettings -p /Net/IconThemeName -t string -s '$icon_theme' --create
xfconf-query -c xsettings -p /Gtk/FontName -t string -s '$ui_font' --create
xfconf-query -c xsettings -p /Gtk/MonospaceFontName -t string -s '$mono_font' --create
xfconf-query -c xsettings -p /Gtk/CursorThemeSize -t int -s 32 --create
xfconf-query -c xfwm4 -p /general/theme -t string -s '$wm_theme' --create
xfconf-query -c xfwm4 -p /general/title_font -t string -s '$title_font' --create
xfconf-query -c xfwm4 -p /general/use_compositing -t bool -s false --create
xfconf-query -c xfce4-panel -p /panels/panel-1/size -t int -s $panel_size --create
xfconf-query -c xfce4-panel -p /panels/panel-1/background-style -t int -s $panel_style --create
xfconf-query -c xfce4-panel -p /panels/panel-1/background-rgba \\
  -t double -t double -t double -t double \\
  -s 0.1176 -s 0.1176 -s 0.1804 -s 1 --create

# El fondo se define por monitor y espacio de trabajo, y el nombre del monitor
# depende de Termux:X11, así que se recorren los que existan.
for prop in \$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E '/workspace[0-9]+/last-image\$' || true); do
  base="\${prop%/last-image}"
  xfconf-query -c xfce4-desktop -p "\$base/image-style" -t int -s $backdrop_style --create
  xfconf-query -c xfce4-desktop -p "\$base/color-style" -t int -s 0 --create
  xfconf-query -c xfce4-desktop -p "\$base/rgba1" \\
    -t double -t double -t double -t double \\
    -s 0.1176 -s 0.1176 -s 0.1804 -s 1 --create
done
sleep 2
APPLY
}
apply || warn "Algún ajuste de XFCE no se pudo aplicar."

if command -v code >/dev/null 2>&1; then
  if [[ "$CHOICE" == mocha ]]; then
    code_theme="Catppuccin Mocha"
    say "Instalando la extensión de VS Code (arranca Code en PRoot, tarda un minuto)"
    code --install-extension Catppuccin.catppuccin-vsc --force >/dev/null 2>&1 ||
      warn "No se pudo instalar la extensión Catppuccin de VS Code."
  else
    code_theme="Default Dark Modern"
  fi
  settings="$HOME/.config/Code/User/settings.json"
  mkdir -p "$(dirname "$settings")"
  [[ -s "$settings" ]] || printf '{}\n' > "$settings"
  merged="$(mktemp)"
  if jq --arg theme "$code_theme" --arg font "${mono_font% *}, monospace" \
       '. + {"workbench.colorTheme":$theme,"editor.fontFamily":$font}' \
       "$settings" > "$merged" 2>/dev/null; then
    mv "$merged" "$settings"
  else
    rm -f "$merged"
    warn "settings.json de VS Code no es JSON válido; se dejó intacto."
  fi
fi

say "Listo"
THEME_USER

chmod 0755 /tmp/mobile-debian-theme-user.sh
chown "$LINUX_USER:$LINUX_USER" /tmp/mobile-debian-theme-user.sh
su - "$LINUX_USER" -c "bash /tmp/mobile-debian-theme-user.sh '$CHOICE'"
THEME_ROOT
  chmod 0755 "$TMPDIR/mobile-debian-theme.sh"
}

theme_apply_inner(){
  local choice="$1"
  write_theme_script
  distro_login "" /bin/bash /tmp/mobile-debian-theme.sh "$LINUX_USER" "$choice"
}

apply_theme(){
  local choice="${1:-$DESKTOP_THEME}"
  case "$choice" in
    mocha|default) ;;
    *) die "Tema desconocido: $choice. Usa 'mocha' o 'default'." ;;
  esac
  require_termux
  installed || die "Primero instala el entorno."
  load_config
  if x11_pids | grep -q .; then
    warn "Hay una sesión gráfica activa. Ciérrala con '$0 stop' para que los"
    warn "ajustes no se sobrescriban al salir de XFCE."
  fi
  acquire_wake_lock
  theme_apply_inner "$choice"
  DESKTOP_THEME="$choice"
  save_config
  release_wake_lock
  ok "Tema '$choice' aplicado. Inicia la sesión con: $0 start"
}

update_all(){
  require_termux
  installed || die "Primero instala el entorno."
  load_config
  acquire_wake_lock
  setup_android_storage
  host_packages
  configure_debian 0
  release_wake_lock
}

repair(){
  require_termux
  installed || die "Primero instala el entorno."
  load_config
  acquire_wake_lock
  setup_android_storage
  configure_debian 0
  release_wake_lock
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
  bash -n "$tmp" || die "La versión descargada no pasó la validación de sintaxis."
  if curl -fsSL "$REPO_RAW/mobile-debian-session.sh" -o "$TMPDIR/mobile-debian-session.new"; then
    chmod 0755 "$TMPDIR/mobile-debian-session.new"
    mv -f "$TMPDIR/mobile-debian-session.new" "$HOME/mobile-debian-session.sh"
  fi
  # mv reemplaza el enlace del directorio en vez de reescribir el archivo que
  # bash está leyendo ahora mismo, así que la ejecución en curso no se corrompe.
  chmod 0755 "$tmp"
  mv -f "$tmp" "$HOME/mobile-debian.sh"
  ok "Scripts actualizados"
  exit 0
}

total_ram_mb(){
  awk '/^MemTotal:/ { printf "%d", $2 / 1024; exit }' /proc/meminfo 2>/dev/null || true
}

status(){
  require_termux
  load_config
  local ram
  ram="$(total_ram_mb)"
  printf 'Mobile Debian Desktop %s\n' "$VERSION"
  printf 'Debian: %s\n' "$(distro_exists && echo disponible || echo ausente)"
  printf 'Usuario: %s\n' "$LINUX_USER"
  printf 'Idioma: %s (%s)\n' "$LOCALE" "$LANGUAGE_VALUE"
  printf 'Zona horaria: %s\n' "$TIMEZONE"
  printf 'Display preferido: %s\n' "$DISPLAY_NUM"
  printf 'Termux:X11 legacy drawing: %s\n' "$X11_LEGACY_DRAWING"
  printf 'Termux:X11 paquete: %s\n' "$(x11_pkg_version || true)"
  printf 'Termux:X11 aplicación: %s\n' "$(x11_apk_version || true)"
  printf 'GL por software: %s\n' "$X11_SOFTWARE_GL"
  printf 'Tema del escritorio: %s\n' "$DESKTOP_THEME"
  printf 'GPU experimental: desactivada\n'
  printf 'RAM total: %s\n' "$([[ -n "$ram" ]] && echo "$ram MB" || echo desconocida)"
  printf 'Perfil de bajo consumo: %s\n' \
    "$([[ "$LOW_MEMORY" == 1 ]] && echo activado || echo desactivado)"
  printf 'Almacenamiento Android: %s\n' "${STORAGE_SOURCE:-no configurado}"
  printf 'Wake-lock solicitado: %s\n' "$([[ -f "$WAKE_LOCK_FILE" ]] && echo sí || echo no)"
  printf 'Servidores X11 detectados:\n'
  x11_pids | sed 's/^/  PID /' || true
  if [[ -n "$ram" && "$ram" -lt 10000 && "$LOW_MEMORY" != 1 ]]; then
    warn "Este equipo tiene poca RAM. Si Android mata Termux con signal 9:"
    warn "  LOW_MEMORY=1 $0 repair"
  fi
}

doctor(){
  require_termux
  installed || die "La instalación no está completa."
  load_config
  status
  check_x11_versions && ok "Termux:X11 sincronizado entre paquete y aplicación"
  distro_login "$LINUX_USER" /bin/bash -lc '
    printf "LANG=%s\n" "$LANG"
    printf "Escritorio XDG=%s\n" "$(xdg-user-dir DESKTOP 2>/dev/null || echo desconocido)"
    for command_name in startxfce4 xfce4-session xfwm4 xfdesktop xfce4-panel chromium-mobile code-mobile libreoffice gimp vlc mpv ffmpeg git python3 node npm claude codex glxinfo; do
      if command -v "$command_name" >/dev/null 2>&1; then
        printf "OK   %s -> %s\n" "$command_name" "$(command -v "$command_name")"
      else
        printf "MISS %s\n" "$command_name"
      fi
    done
    if [[ -d /mnt/android ]]; then
      printf "OK   /mnt/android disponible\n"
    else
      printf "MISS /mnt/android\n"
    fi
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
  repair) repair ;;
  theme) apply_theme "${2:-}" ;;
  update-ai) update_ai ;;
  self-update) self_update ;;
  status) status ;;
  doctor) doctor ;;
  *)
    echo "Uso: $0 [install|start|stop|restart|update|repair|theme [mocha|default]|update-ai|self-update|status|doctor]"
    exit 2
    ;;
esac
