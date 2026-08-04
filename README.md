# Mobile Debian Desktop

Escritorio Debian XFCE para Android mediante **Termux + PRoot-Distro + Termux:X11**.

La versión 0.7 recupera el flujo de arranque del commit estable `c07a55a`, que fue el último estado confirmado donde XFCE abría correctamente en el dispositivo de referencia.

## Arquitectura

```text
Android
├── Termux
│   ├── Termux:X11
│   ├── PulseAudio
│   └── PRoot-Distro
└── Debian
    ├── XFCE
    ├── Chromium
    ├── Visual Studio Code oficial ARM64
    ├── LibreOffice completo
    ├── VLC, mpv y FFmpeg
    ├── Git, Python, Node.js y npm
    └── Claude Code y Codex CLI
```

Chromium y Visual Studio Code se ejecutan dentro de Debian. No se usan paquetes gráficos nativos de Termux ni un puente entre sistemas.

## Decisiones de estabilidad

La configuración predeterminada:

- Inicia Termux:X11 en `:1`.
- Usa `--shared-tmp` para Debian PRoot.
- No usa `-legacy-drawing`.
- No envía `ACTION_STOP` durante el inicio.
- No fuerza `es_CO`, `LANGUAGE` ni `LC_ALL`.
- Usa `C.UTF-8` como locale neutro.
- No instala ni exporta Mesa KGSL experimental.
- No fuerza ANGLE, Zink, GPU rasterization ni `ignore-gpu-blocklist`.
- No modifica el compositor antes de iniciar XFCE.
- Mantiene el wake-lock durante la sesión.
- Conserva `ACTION_STOP` únicamente al cerrar.

## Instalación limpia

Instala manualmente las aplicaciones Android **Termux** y **Termux:X11**. Después ejecuta en Termux:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/juanfelipelt/mobile-debian-desktop/main/mobile-debian.sh \
  -o "$HOME/mobile-debian.sh" &&
chmod +x "$HOME/mobile-debian.sh" &&
"$HOME/mobile-debian.sh"
```

Durante la instalación acepta el permiso de almacenamiento solicitado por Android.

## Recuperación desde la versión 0.6

No reinstales Debian. Actualiza solamente el lanzador y restablece la configuración de XFCE:

```bash
$HOME/mobile-debian.sh stop 2>/dev/null || true

curl -fsSL \
  https://raw.githubusercontent.com/juanfelipelt/mobile-debian-desktop/main/mobile-debian.sh \
  -o "$HOME/mobile-debian.sh" &&
chmod +x "$HOME/mobile-debian.sh" &&

$HOME/mobile-debian.sh reset-desktop &&
$HOME/mobile-debian.sh start
```

`reset-desktop`:

- mueve `~/.config/xfce4` a una copia con fecha;
- elimina las sesiones XFCE guardadas;
- elimina `.Xauthority`;
- retira `LANG`, `LANGUAGE` y `LC_ALL` del perfil;
- deja `/etc/default/locale` con `LANG=C.UTF-8`;
- no elimina Debian, aplicaciones, proyectos ni archivos personales.

## Aplicaciones

Dentro de Debian se instalan:

- XFCE, Thunar, Mousepad y utilidades del escritorio;
- Chromium de Debian;
- Visual Studio Code oficial ARM64;
- LibreOffice completo con paquete de idioma español;
- VLC, mpv y FFmpeg;
- Git, Python, pip, venv, Node.js, npm y herramientas de compilación;
- Claude Code y Codex CLI.

No se instala Microsoft Word Online.

## Almacenamiento Android

Cuando el permiso está disponible, el almacenamiento compartido se monta en:

```text
/mnt/android
```

También se crean accesos:

```text
~/Android
~/Descargas-Android
~/Documentos-Android
```

Guarda repositorios Git, entornos virtuales y `node_modules` dentro de `/home/felipe`. Usa `/mnt/android` para importar y exportar archivos.

## Uso diario

Iniciar:

```bash
$HOME/mobile-debian.sh start
```

Cerrar:

```bash
$HOME/mobile-debian.sh stop
```

Comprobar la instalación:

```bash
$HOME/mobile-debian.sh doctor
```

## Comandos

| Comando | Acción |
|---|---|
| `install` | Instala y configura el entorno |
| `start` | Inicia PulseAudio, Termux:X11 y XFCE |
| `stop` | Cierra XFCE, Termux:X11 y libera el wake-lock |
| `restart` | Reinicia la sesión |
| `repair` | Repara paquetes y accesos sin reinstalar Debian |
| `reset-desktop` | Restablece únicamente la configuración de XFCE |
| `update-ai` | Actualiza Claude Code y Codex |
| `self-update` | Descarga los scripts actuales |
| `status` | Muestra el estado de la configuración |
| `doctor` | Verifica componentes principales |

## Registros

```text
~/.local/state/mobile-debian/termux-x11.log
~/.local/state/mobile-debian/xfce.log
```

## Fuentes técnicas

- Termux:X11: https://github.com/termux/termux-x11
- PRoot-Distro: https://github.com/termux/proot-distro
- Linux-on-Samsung: https://github.com/techjarves/Linux-on-Samsung
- Visual Studio Code para Linux: https://code.visualstudio.com/docs/setup/linux
