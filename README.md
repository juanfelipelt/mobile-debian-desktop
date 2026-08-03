# Mobile Debian Desktop

Instalador y lanzador idempotente para ejecutar un escritorio Debian completo en Android mediante **Termux + PRoot-Distro + Termux:X11**.

Está optimizado para el **Samsung Galaxy S25 Ultra**, con Snapdragon 8 Elite y GPU Adreno, pero también funciona en otros dispositivos Android ARM64. La aceleración directa se activa únicamente cuando el dispositivo expone `/dev/kgsl-3d0` y existe un paquete Mesa compatible.

## Arquitectura

```text
Android
├── Termux
│   ├── Termux:X11
│   ├── PulseAudio
│   └── proot-distro
└── Debian
    ├── XFCE
    ├── Mesa Freedreno/Turnip KGSL
    ├── Chromium
    ├── Visual Studio Code
    ├── Claude Code y Codex CLI
    ├── LibreOffice Writer / Word Online
    └── VLC, mpv y FFmpeg
```

Termux se mantiene como anfitrión ligero. El escritorio y las aplicaciones se instalan dentro de Debian.

## Qué instala

### En Termux

- `x11-repo`
- `termux-x11-nightly`
- PulseAudio
- `proot-distro`
- Herramientas auxiliares como `curl`, `wget`, `git`, `jq`, `tar` y `procps`

### En Debian

- XFCE, Thunar, terminal, Mousepad, gestor de comprimidos y controles de audio
- Chromium configurado para Termux:X11 y PRoot
- Visual Studio Code oficial para ARM64
- Claude Code y OpenAI Codex CLI
- LibreOffice Writer, diccionario en español y acceso a Word Online
- Git, Python, Node.js, npm y herramientas de compilación
- VLC, mpv y FFmpeg
- Mesa Utils y Vulkan Tools
- Mesa Freedreno/Turnip mediante KGSL cuando el dispositivo es compatible

## Exclusiones intencionales

El instalador **no incluye**:

- Java, JDK ni Maven
- Servidores o clientes VNC
- Metasploit
- Wine/Hangover

Termux:X11 muestra el escritorio directamente, por lo que VNC no es necesario. Java puede instalarse después como una decisión específica de cada dispositivo o proyecto.

## Requisitos manuales

Antes de ejecutar el script instala:

1. Termux actualizado desde F-Droid o GitHub.
2. La aplicación Android Termux:X11 oficial.

Android exige confirmar manualmente la instalación del APK de Termux:X11. El script comprueba que la aplicación esté presente antes de continuar.

## Instalación en un comando

Con el repositorio público, pega este comando completo en una instalación limpia de Termux:

```bash
curl -fsSL https://raw.githubusercontent.com/juanfelipelt/mobile-debian-desktop/main/mobile-debian.sh -o "$HOME/mobile-debian.sh" && chmod +x "$HOME/mobile-debian.sh" && "$HOME/mobile-debian.sh"
```

El comando descarga el instalador, lo guarda en el directorio personal de Termux, le asigna permisos de ejecución e inicia la instalación completa. En las siguientes ejecuciones puedes iniciar el escritorio con:

```bash
$HOME/mobile-debian.sh
```

> El repositorio debe ser público para que `raw.githubusercontent.com` permita descargar el archivo sin un token de GitHub.

## Primer uso manual

También puedes descargar o copiar `mobile-debian.sh` al directorio personal de Termux y ejecutarlo así:

```bash
chmod +x mobile-debian.sh
./mobile-debian.sh
```

En la primera ejecución el script:

1. Actualiza Termux.
2. Instala las dependencias del anfitrión.
3. Instala Debian.
4. Actualiza Debian.
5. Instala XFCE, GPU y aplicaciones.
6. Inicia Termux:X11 y XFCE.

En ejecuciones posteriores, el mismo comando detecta la instalación existente y **solo inicia el escritorio**.

## Comandos

```bash
./mobile-debian.sh install
./mobile-debian.sh start
./mobile-debian.sh stop
./mobile-debian.sh restart
./mobile-debian.sh status
./mobile-debian.sh doctor
./mobile-debian.sh update
```

### Comportamiento de actualización

| Comando | Termux | Debian | Inicia XFCE |
|---|---:|---:|---:|
| `./mobile-debian.sh` en instalación nueva | Actualiza | Actualiza | Sí |
| `./mobile-debian.sh` ya instalado | No | No | Sí |
| `./mobile-debian.sh install` | Actualiza | Actualiza | No |
| `./mobile-debian.sh update` | Actualiza | Actualiza | No |
| `./mobile-debian.sh start` | No | No | Sí |

En Termux se ejecutan:

```bash
pkg update -y
pkg upgrade -y
```

Después de habilitar `x11-repo`, se refrescan nuevamente los índices antes de instalar Termux:X11.

Dentro de Debian se ejecutan:

```bash
apt-get update
apt-get dist-upgrade -y
```

## Opciones

Los grupos opcionales pueden desactivarse en la primera instalación o durante una reparación:

```bash
INSTALL_MEDIA=0 INSTALL_OFFICE=0 INSTALL_AI_CLI=0 ./mobile-debian.sh install
```

Variables disponibles:

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
LINUX_USER=pipe DISPLAY_NUM=:1 ./mobile-debian.sh install
```

## Aceleración gráfica

Cuando se detectan Debian 13 ARM64 y `/dev/kgsl-3d0`, el instalador descarga una versión compatible de Mesa para contenedores Android y configura la sesión completa con KGSL.

La aceleración no se limita a Chromium: las aplicaciones iniciadas dentro de XFCE heredan la configuración gráfica de la sesión.

Comprueba el resultado con:

```bash
./mobile-debian.sh doctor
```

El renderer OpenGL debería mencionar Adreno, Freedreno o FD830. Si aparece `llvmpipe`, la sesión está usando renderizado por software.

## Chromium

El acceso **Chromium (GPU)** utiliza un wrapper preparado para:

- X11 mediante Ozone
- ANGLE/OpenGL
- Rasterización GPU
- Las limitaciones de memoria compartida y sandbox de PRoot

Dentro de Chromium abre:

```text
chrome://gpu
```

para revisar el estado de WebGL, composición y rasterización.

## Claude Code y Codex

Los dos asistentes se instalan como el usuario normal de Debian en `~/.local/bin`. El script no almacena claves, tokens ni contraseñas.

Después de instalar:

```bash
claude
codex
```

Cada herramienta inicia su propio proceso de autenticación.

Para omitirlas:

```bash
INSTALL_AI_CLI=0 ./mobile-debian.sh install
```

Para instalarlas o repararlas posteriormente:

```bash
INSTALL_AI_CLI=1 ./mobile-debian.sh update
```

## VLC y oficina

VLC se instala por defecto junto con mpv y FFmpeg cuando `INSTALL_MEDIA=1`.

Para documentos se incluyen:

- LibreOffice Writer para uso sin conexión
- Microsoft Word Online mediante Chromium

No se instala Word de escritorio ni Wine.

## Diagnóstico

```bash
./mobile-debian.sh status
./mobile-debian.sh doctor
```

Los registros se guardan en:

```text
~/.local/state/mobile-debian/
```

## Seguridad

Chromium y VS Code utilizan `--no-sandbox` porque el sandbox basado en namespaces normalmente no puede inicializarse dentro de PRoot. Para banca, contraseñas u operaciones sensibles, utiliza el navegador Android.

Claude Code y Codex pueden leer, modificar y ejecutar archivos según los permisos concedidos. Úsalos dentro de repositorios Git y revisa las operaciones antes de aprobarlas.

El script no usa `termux-x11 -ac`, no fuerza variables GPU globales en Termux y no instala herramientas ofensivas.

## Fuentes técnicas

- Termux:X11: https://github.com/termux/termux-x11
- PRoot-Distro: https://github.com/termux/proot-distro
- Termux Desktops: https://github.com/LinuxDroidMaster/Termux-Desktops
- Mesa para contenedores Android: https://github.com/lfdevs/mesa-for-android-container
- Visual Studio Code: https://code.visualstudio.com/docs/setup/linux
- Claude Code: https://github.com/anthropics/claude-code
- OpenAI Codex: https://github.com/openai/codex
