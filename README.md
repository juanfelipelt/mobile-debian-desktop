# Mobile Debian Desktop

Instalador idempotente para ejecutar un escritorio Debian completo en Android mediante **Termux + PRoot-Distro + Termux:X11**.

Está optimizado para el Samsung Galaxy S25 Ultra con Snapdragon 8 Elite y Adreno 830, pero puede usarse en otros dispositivos Android ARM64. La aceleración directa se activa únicamente cuando el dispositivo expone `/dev/kgsl-3d0` y Debian es compatible con el paquete Mesa seleccionado.

## Instalación en un comando

Primero instala manualmente las aplicaciones Android **Termux** y **Termux:X11**. Después pega este comando completo en Termux:

```bash
curl -fsSL https://raw.githubusercontent.com/juanfelipelt/mobile-debian-desktop/main/mobile-debian.sh -o "$HOME/mobile-debian.sh" && chmod +x "$HOME/mobile-debian.sh" && "$HOME/mobile-debian.sh"
```

La primera ejecución instala el entorno completo. En las siguientes ejecuciones, el mismo comando inicia Termux:X11 y XFCE sin reinstalar Debian.

Para iniciar posteriormente:

```bash
$HOME/mobile-debian.sh start
```

## Arquitectura

```text
Android
├── Termux
│   ├── x11-repo
│   ├── termux-x11-nightly
│   ├── PulseAudio
│   └── proot-distro
└── Debian
    ├── XFCE
    ├── Mesa Freedreno/Turnip KGSL
    ├── Chromium
    ├── Visual Studio Code
    ├── Claude Code y Codex CLI
    ├── LibreOffice Writer y Word Online
    └── VLC, mpv y FFmpeg
```

El APK Android de Termux:X11 y el paquete `termux-x11-nightly` son componentes distintos. El APK se instala manualmente; el script instala el componente de Termux.

## Qué instala

En Termux:

- `x11-repo`
- `termux-x11-nightly`
- PulseAudio
- `proot-distro`
- `curl`, `wget`, `git`, `jq`, `tar`, `gzip`, `coreutils` y `procps`

En Debian:

- XFCE, Thunar, terminal, Mousepad y utilidades del escritorio
- Chromium con wrapper para X11, PRoot y aceleración gráfica
- Visual Studio Code oficial ARM64
- Claude Code y OpenAI Codex CLI
- LibreOffice Writer y acceso a Word Online
- VLC, mpv y FFmpeg
- Git, Python, Node.js, npm y herramientas de compilación
- Mesa Utils, Vulkan Tools y Mesa KGSL cuando el equipo es compatible
- Fondo de Debian y accesos de Chromium, VLC, LibreOffice y VS Code

## Exclusiones intencionales

El instalador no incluye:

- Java, JDK ni Maven
- VNC ni TigerVNC
- Wine/Hangover
- Metasploit u otras herramientas ofensivas

Termux:X11 muestra el escritorio directamente, por lo que VNC no es necesario.

## Comandos

```bash
$HOME/mobile-debian.sh install
$HOME/mobile-debian.sh start
$HOME/mobile-debian.sh stop
$HOME/mobile-debian.sh restart
$HOME/mobile-debian.sh update
$HOME/mobile-debian.sh update-ai
$HOME/mobile-debian.sh refresh-gpu
$HOME/mobile-debian.sh status
$HOME/mobile-debian.sh doctor
```

### Comportamiento

| Comando | Qué hace |
|---|---|
| Sin argumentos | Instala si hace falta; de lo contrario inicia XFCE |
| `install` | Instala o repara el entorno completo |
| `start` | Inicia PulseAudio, Termux:X11 y XFCE |
| `stop` | Cierra XFCE, el servidor X11 y PulseAudio |
| `restart` | Reinicia la sesión gráfica |
| `update` | Actualiza Termux y Debian sin reinstalar Claude Code, Codex ni Mesa |
| `update-ai` | Actualiza explícitamente Claude Code y Codex |
| `refresh-gpu` | Descarga e instala explícitamente el paquete Mesa compatible |
| `doctor` | Comprueba aplicaciones y estado básico |

`update` ejecuta `pkg update`, `pkg upgrade`, `apt-get update` y `apt-get dist-upgrade`. Los instaladores de Claude Code y Codex solo se ejecutan si la herramienta no existe. Para forzar su actualización se usa `update-ai`.

Mesa no se vuelve a descargar cuando `/etc/mobile-debian-gpu` ya indica `kgsl`. Para forzar una actualización del controlador se usa `refresh-gpu`.

## Gestión segura de Termux:X11

El script guarda el PID del servidor que inicia. Antes de reiniciar:

1. Detiene XFCE.
2. Envía `TERM` al proceso exacto `termux-x11`.
3. Espera a que termine.
4. Usa `KILL` solamente si sigue vivo.
5. Elimina el socket y el lock después de confirmar que el servidor murió.
6. Inicia un servidor limpio y espera a que aparezca el socket `X1`.

Esto evita el error:

```text
server already running
Cannot establish any listening sockets
```

La actividad Android de Termux:X11 solo se cierra con el comando `stop`. Un inicio normal conserva la aplicación abierta.

## Aceleración gráfica

Cuando se detectan Debian Trixie ARM64 y `/dev/kgsl-3d0`, la sesión exporta:

```bash
MESA_LOADER_DRIVER_OVERRIDE=kgsl
TU_DEBUG=noconform
```

Estas variables se aplican a toda la sesión XFCE, no solamente a Chromium.

Comprueba las herramientas instaladas con:

```bash
$HOME/mobile-debian.sh doctor
```

Dentro de Chromium abre:

```text
chrome://gpu
```

para revisar WebGL, composición y rasterización.

## Claude Code y Codex

Las dos herramientas se instalan como el usuario normal de Debian en `~/.local/bin`. El script no guarda contraseñas, claves de API ni sesiones.

Dentro de XFCE Terminal:

```bash
claude
codex
```

Para omitirlas durante una instalación nueva:

```bash
INSTALL_AI_CLI=0 $HOME/mobile-debian.sh install
```

Para actualizarlas explícitamente:

```bash
$HOME/mobile-debian.sh update-ai
```

## Opciones

```text
LINUX_USER
DISPLAY_NUM
LOCALE
INSTALL_DEV_STACK
INSTALL_OFFICE
INSTALL_MEDIA
INSTALL_VSCODE
INSTALL_AI_CLI
INSTALL_GPU
```

Ejemplo:

```bash
LINUX_USER=pipe DISPLAY_NUM=:1 $HOME/mobile-debian.sh install
```

## Registros

```text
~/.local/state/mobile-debian/termux-x11.log
~/.local/state/mobile-debian/xfce.log
```

## Fuentes técnicas

- Termux:X11: https://github.com/termux/termux-x11
- PRoot-Distro: https://github.com/termux/proot-distro
- Mesa para contenedores Android: https://github.com/lfdevs/mesa-for-android-container
- Visual Studio Code: https://code.visualstudio.com/docs/setup/linux
- Claude Code: https://github.com/anthropics/claude-code
- OpenAI Codex: https://github.com/openai/codex
