# Mobile Debian Desktop

Escritorio Debian XFCE para Android mediante **Termux + PRoot-Distro + Termux:X11**, orientado al Samsung Galaxy S25 Ultra y otros dispositivos ARM64.

La versión 0.5 usa una arquitectura híbrida para evitar los cierres `zygote ... Broken pipe`, los perfiles bloqueados y los artefactos que aparecían al ejecutar Chromium y Electron dentro de PRoot:

```text
Android
├── Termux
│   ├── Termux:X11 y PulseAudio
│   ├── Chromium nativo
│   ├── Code - OSS nativo
│   └── puente de aplicaciones hacia el escritorio
└── Debian PRoot
    ├── XFCE
    ├── terminal y herramientas de desarrollo
    ├── LibreOffice
    ├── VLC, mpv y FFmpeg
    └── lanzadores de Chromium y Code - OSS
```

Chromium y Code - OSS se instalan desde el repositorio gráfico oficial de Termux y se ejecutan **fuera de PRoot**, aunque sus ventanas aparecen dentro del escritorio Debian. El puente traduce rutas habituales de Debian, por ejemplo `/home/felipe/proyecto`, a la ubicación real del rootfs para que Code - OSS pueda abrirlas.

## Requisitos

- Android ARM64/aarch64.
- Termux instalado desde GitHub o F-Droid.
- Aplicación Android Termux:X11.
- El paquete compañero `termux-x11-nightly`, instalado automáticamente.

Termux:X11 necesita tanto el APK Android como el paquete de Termux. Para PRoot se inicia siempre con `--shared-tmp`.

## Instalación nueva

```bash
curl -fsSL \
  https://raw.githubusercontent.com/juanfelipelt/mobile-debian-desktop/main/mobile-debian.sh \
  -o "$HOME/mobile-debian.sh" &&
chmod +x "$HOME/mobile-debian.sh" &&
"$HOME/mobile-debian.sh"
```

## Migración desde una versión anterior

Esta secuencia actualiza únicamente los scripts y migra las aplicaciones gráficas. No ejecuta `apt dist-upgrade`, no reinstala Claude Code/Codex y no vuelve a descargar Mesa KGSL.

```bash
$HOME/mobile-debian-session.sh stop 2>/dev/null || \
  $HOME/mobile-debian.sh stop 2>/dev/null || true

curl -fsSL \
  https://raw.githubusercontent.com/juanfelipelt/mobile-debian-desktop/main/mobile-debian.sh \
  -o "$HOME/mobile-debian.sh" &&
chmod +x "$HOME/mobile-debian.sh" &&
$HOME/mobile-debian.sh repair-apps
```

Después inicia normalmente:

```bash
$HOME/mobile-debian.sh start
```

`repair-apps` realiza estas acciones:

- Instala `chromium` y `code-oss` en Termux desde `x11-repo`.
- Elimina de Debian los paquetes antiguos `code`, `chromium` y `chromium-common`.
- Elimina el repositorio y la llave de Microsoft que se usaban para VS Code dentro de PRoot.
- Elimina el acceso experimental `Chromium (GPU)`.
- Crea el puente host y los accesos `Chromium` y `Code - OSS`.
- Reinstala los paquetes Mesa oficiales de Debian y deja el driver sin forzar.

## Uso diario

```bash
$HOME/mobile-debian.sh start
```

Al iniciar:

1. Cierra sesiones anteriores.
2. Activa `termux-wake-lock`.
3. Inicia PulseAudio.
4. Inicia Termux:X11.
5. Inicia el puente de aplicaciones nativas.
6. Inicia XFCE dentro de Debian.

Al cerrar XFCE, usar `Ctrl+C` o ejecutar `stop`, se cierran el puente, las aplicaciones rastreadas, XFCE, Termux:X11 y PulseAudio; después se libera el wake-lock.

```bash
$HOME/mobile-debian.sh stop
```

El antiguo lanzador sigue siendo compatible y delega al script principal:

```bash
$HOME/mobile-debian-session.sh start
$HOME/mobile-debian-session.sh stop
```

## Termux:X11 y pantalla blanca

En este dispositivo se usa por defecto:

```text
-legacy-drawing
```

Termux:X11 recomienda esta opción cuando la ruta normal produce una pantalla negra o vacía. El compositor de XFCE permanece desactivado porque al activarlo produjo una superficie blanca.

Para probar la ruta normal manualmente:

```bash
X11_LEGACY_DRAWING=0 $HOME/mobile-debian.sh start
```

No se guarda ese cambio salvo que se vuelva a ejecutar una configuración con esa variable.

## Aplicaciones gráficas

### Chromium

Se instala con:

```bash
pkg install x11-repo chromium
```

El lanzador usa Chromium normal, sin `--ignore-gpu-blocklist`, sin `--use-angle=gl` y sin rasterización GPU forzada.

### Code - OSS

Se instala con:

```bash
pkg install x11-repo code-oss
```

`code-oss` pertenece actualmente al repositorio X11 oficial de Termux. No es necesario agregar `tur-repo` para estas dos aplicaciones.

Code - OSS se ejecuta con el entorno de Termux. Su terminal integrada también abre Termux; para entrar en Debian desde esa terminal:

```bash
proot-distro login debian --shared-tmp --user felipe
```

## Mesa y GPU

Mesa KGSL dejó de forzarse globalmente sobre XFCE, Chromium y Electron. La extracción directa de builds experimentales puede sobrescribir archivos de Mesa y su propio proyecto la describe como un método de prueba que requiere restaurar los paquetes de la distribución para desinstalarlo.

La configuración predeterminada es:

```bash
INSTALL_GPU=0
```

El comando siguiente conserva la opción experimental, pero no se recomienda para el escritorio diario:

```bash
$HOME/mobile-debian.sh refresh-gpu
```

## Comandos

| Comando | Acción |
|---|---|
| `start` | Inicia wake-lock, audio, X11, puente y XFCE |
| `stop` | Cierra la sesión completa y libera el wake-lock |
| `restart` | Detiene e inicia nuevamente |
| `repair-apps` | Migra Chromium y Code - OSS sin actualizar todo Debian |
| `self-update` | Descarga los scripts actuales desde GitHub |
| `update` | Actualiza Termux y Debian; úsalo solo para mantenimiento general |
| `update-ai` | Actualiza explícitamente Claude Code y Codex |
| `refresh-gpu` | Instala explícitamente Mesa KGSL experimental |
| `status` | Muestra display, wake-lock, puente y procesos X11 |
| `doctor` | Comprueba aplicaciones del host y componentes de Debian |

## Eliminación manual de las aplicaciones antiguas

El comando recomendado es `repair-apps`. Para hacerlo manualmente, primero cierra la sesión:

```bash
$HOME/mobile-debian.sh stop
```

Después elimina Chromium y VS Code antiguos de Debian. No se ejecuta `autoremove`, para no retirar dependencias compartidas por otras aplicaciones:

```bash
proot-distro login debian -- /bin/bash -lc '
  apt-get purge -y code chromium chromium-common
  rm -f /etc/apt/sources.list.d/vscode.sources \
        /etc/apt/sources.list.d/vscode.list \
        /usr/share/keyrings/microsoft.gpg \
        /usr/local/bin/chromium-gpu
'
```

Para borrar solamente los perfiles de prueba creados durante el diagnóstico:

```bash
proot-distro login debian --user felipe -- /bin/bash -lc '
  rm -rf \
    "$HOME/.config/chromium-safe" \
    "$HOME/.config/chromium-stable" \
    "$HOME/.config/chromium-balanced" \
    "$HOME/.config/chromium-gpu"
'
```

No borres `~/.config/chromium` ni `~/.config/Code` salvo que quieras perder el historial, sesiones y ajustes antiguos del contenedor.

## Exclusiones intencionales

El instalador no incluye:

- Java, JDK ni Maven.
- VNC ni TigerVNC.
- Wine/Hangover.
- Metasploit u otras herramientas ofensivas.

## Registros

```text
~/.local/state/mobile-debian/termux-x11.log
~/.local/state/mobile-debian/xfce.log
~/.local/state/mobile-debian/host-apps.log
```

El último archivo contiene la salida de Chromium y Code - OSS nativos.

## Fuentes técnicas

- Termux:X11: https://github.com/termux/termux-x11
- Paquete Chromium de Termux: https://github.com/termux/termux-packages/tree/master/x11-packages/chromium
- Paquete Code - OSS de Termux: https://github.com/termux/termux-packages/tree/master/x11-packages/code-oss
- PRoot-Distro: https://github.com/termux/proot-distro
- Linux-on-Samsung: https://github.com/techjarves/Linux-on-Samsung
- Mesa para contenedores Android: https://github.com/lfdevs/mesa-for-android-container
