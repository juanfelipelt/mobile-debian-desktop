# Mobile Debian Desktop

Escritorio Debian XFCE para Android mediante **Termux + PRoot-Distro + Termux:X11**, configurado para el Samsung Galaxy S25 Ultra y otros equipos ARM64.

La versión 0.7 mantiene la arquitectura Linux convencional de la 0.6 (las aplicaciones se instalan y ejecutan dentro de Debian, sin forzar controladores KGSL, Zink, ANGLE ni rasterización GPU experimental) y corrige el arranque gráfico que provocaba pantalla negra.

## Arquitectura

```text
Android
├── Termux
│   ├── Termux:X11
│   ├── PulseAudio
│   ├── PRoot-Distro
│   └── acceso al almacenamiento compartido
└── Debian
    ├── XFCE en español de Colombia
    ├── Chromium
    ├── Visual Studio Code oficial ARM64
    ├── LibreOffice completo
    ├── GIMP
    ├── VLC, mpv y FFmpeg
    ├── Git, Python, Node.js y herramientas de compilación
    └── Claude Code y Codex CLI
```

## Decisiones de estabilidad

- Chromium y Visual Studio Code se ejecutan dentro de Debian.
- Chromium usa únicamente los flags mínimos requeridos por PRoot: `--no-sandbox`, `--disable-dev-shm-usage` y X11.
- Visual Studio Code usa `--no-sandbox` y `--disable-dev-shm-usage`.
- No se exportan `MESA_LOADER_DRIVER_OVERRIDE`, `TU_DEBUG`, `GALLIUM_DRIVER` ni `VK_ICD_FILENAMES`.
- No se usa `--ignore-gpu-blocklist`, `--use-angle`, Zink ni rasterización GPU forzada.
- Mesa es la versión oficial de Debian, con `libgl1-mesa-dri` instalado y `LIBGL_ALWAYS_SOFTWARE=1`, porque PRoot no expone la GPU.
- Termux:X11 usa la ruta de dibujo normal, igual que los scripts de referencia. `-legacy-drawing` quedó desactivado por defecto porque en las versiones actuales de la aplicación produce pantalla negra.
- La sesión arranca con `startxfce4`, no con `xfce4-session` directamente, para que se inicien xfsettingsd, xfwm4, xfdesktop y el panel.
- El compositor de XFCE permanece desactivado y XFCE no guarda la sesión al salir.
- Antes de abrir un servidor nuevo se le pide a la aplicación Termux:X11 que se cierre y se espera a que suelte el display, para que la ventana no quede enganchada a un servidor muerto.

## Requisitos

Instala manualmente:

1. Termux desde GitHub o F-Droid.
2. La aplicación Android Termux:X11.

No mezcles instalaciones de Termux procedentes de fuentes distintas.

## Instalación limpia

Pega este comando en Termux:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/juanfelipelt/mobile-debian-desktop/main/mobile-debian.sh \
  -o "$HOME/mobile-debian.sh" &&
chmod +x "$HOME/mobile-debian.sh" &&
"$HOME/mobile-debian.sh"
```

Durante la instalación Android solicitará acceso a los archivos. Concédelo para que Debian pueda abrir el almacenamiento compartido.

La primera ejecución instala y luego inicia el escritorio. Las siguientes ejecuciones inician directamente XFCE.

## Aplicaciones incluidas

### Escritorio

- XFCE.
- Thunar.
- XFCE Terminal.
- Mousepad.
- Ristretto.
- File Roller.
- PulseAudio y Pavucontrol.

### Navegación y desarrollo

- Chromium de Debian ARM64.
- Visual Studio Code oficial ARM64 mediante el repositorio de Microsoft.
- Git.
- Python 3, pip y venv.
- Node.js y npm.
- Build Essential y pkg-config.
- Claude Code.
- OpenAI Codex CLI.

### Oficina y multimedia

- LibreOffice completo en español.
- Diccionario Hunspell en español.
- GIMP.
- VLC.
- mpv.
- FFmpeg.

Microsoft Word Online no se instala ni se crea como acceso directo.

## Idioma y región

```text
Usuario: felipe
Idioma: es_CO.UTF-8
Interfaz: español de Colombia
Zona horaria: America/Bogota
```

El usuario tiene `sudo` sin contraseña dentro del contenedor.

## Almacenamiento de Android

El instalador ejecuta `termux-setup-storage` y enlaza el almacenamiento compartido en:

```text
/mnt/android
```

También crea en el escritorio el acceso **Archivos de Android** y accesos en el directorio personal:

```text
~/Android
~/Descargas-Android
~/Documentos-Android
~/Camara-Android
```

Usa esas carpetas para importar, exportar o compartir archivos. Los proyectos de Git, entornos virtuales y dependencias de Node deben permanecer en `/home/felipe`, porque el almacenamiento público de Android no admite correctamente permisos Unix, enlaces simbólicos ni todas las operaciones necesarias para desarrollo.

## Uso diario

Iniciar:

```bash
$HOME/mobile-debian.sh start
```

Cerrar:

```bash
$HOME/mobile-debian.sh stop
```

También puedes abrir **Cerrar Mobile Debian** desde el escritorio. Al terminar XFCE, el script cierra Termux:X11 y PulseAudio y libera el wake-lock.

## Comandos

| Comando | Acción |
|---|---|
| Sin argumentos | Instala si hace falta; después inicia XFCE |
| `install` | Instala o repara todos los componentes |
| `start` | Activa wake-lock, audio, X11 y XFCE |
| `stop` | Cierra la sesión y libera el wake-lock |
| `restart` | Reinicia la sesión gráfica |
| `repair` | Reaplica configuración sin reinstalar Debian |
| `update` | Actualiza Termux, Debian y aplicaciones |
| `update-ai` | Fuerza la actualización de Claude Code y Codex |
| `self-update` | Descarga los scripts actuales del repositorio |
| `status` | Muestra idioma, almacenamiento, wake-lock y X11 |
| `doctor` | Verifica las aplicaciones principales |

## Registros

```text
~/.local/state/mobile-debian/termux-x11.log
~/.local/state/mobile-debian/xfce.log
```

## Opciones

```text
DISTRO
LINUX_USER
DISPLAY_NUM
LOCALE
LANGUAGE_VALUE
TIMEZONE
X11_LEGACY_DRAWING
X11_FORCE_BGRA
X11_SOFTWARE_GL
INSTALL_DEV_STACK
INSTALL_OFFICE
INSTALL_MEDIA
INSTALL_GRAPHICS
INSTALL_VSCODE
INSTALL_CHROMIUM
INSTALL_AI_CLI
ENABLE_ANDROID_STORAGE
```

Las variables de entorno tienen prioridad sobre el archivo de configuración guardado. Ejemplo para probar el dibujo heredado de Termux:X11:

```bash
X11_LEGACY_DRAWING=1 $HOME/mobile-debian.sh start
```

## Pantalla negra

La causa más frecuente es que la aplicación Termux:X11 y el paquete `termux-x11-nightly` tengan versiones distintas. `pkg upgrade` actualiza el paquete, pero la APK de Android se actualiza a mano, así que la pareja se desincroniza sola con el tiempo.

Comprueba las dos versiones:

```bash
$HOME/mobile-debian.sh doctor
```

Si no coinciden, instala la APK correspondiente desde las [releases de termux-x11](https://github.com/termux/termux-x11/releases). El script avisa al arrancar cuando detecta la diferencia.

Si las versiones coinciden y la pantalla sigue negra:

1. Cierra todo y vuelve a empezar: `$HOME/mobile-debian.sh stop` y luego `start`.
2. Prueba el dibujo heredado: `X11_LEGACY_DRAWING=1 $HOME/mobile-debian.sh start`.
3. Revisa los registros de `~/.local/state/mobile-debian/`.
4. Reaplica la configuración del escritorio: `$HOME/mobile-debian.sh repair`.

## Exclusiones intencionales

- No Java, JDK ni Maven.
- No VNC ni TigerVNC.
- No Wine ni Hangover.
- No Metasploit ni herramientas ofensivas.
- No paquetes gráficos nativos de Termux como `chromium` o `code-oss`.
- No Mesa KGSL externa.
- No Microsoft Word Online.

## Fuentes técnicas

- Termux:X11: https://github.com/termux/termux-x11
- PRoot-Distro: https://github.com/termux/proot-distro
- Chromium para Debian ARM64: https://packages.debian.org/trixie/arm64/chromium
- Visual Studio Code para Linux: https://code.visualstudio.com/docs/setup/linux
- Termux storage y sistema de archivos: https://github.com/termux/termux-packages/wiki/Termux-file-system-layout
