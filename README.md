# Mobile Debian Desktop

Escritorio Debian XFCE para Android mediante **Termux + PRoot-Distro + Termux:X11**, configurado para el Samsung Galaxy S25 Ultra y otros equipos ARM64.

La versión 0.10 mantiene la arquitectura Linux convencional: las aplicaciones se instalan y ejecutan dentro de Debian, sin forzar controladores KGSL, Zink, ANGLE ni rasterización GPU experimental. Sobre esa base, la 0.7 corrigió el arranque gráfico que terminaba en pantalla negra, la 0.8 añadió el perfil de bajo consumo para equipos con poca RAM, la 0.9 el tema Catppuccin Mocha y la 0.10 la distribución de teclado y las traducciones de Chromium.

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
- Chromium usa únicamente los flags mínimos requeridos por PRoot: `--no-sandbox`, `--disable-dev-shm-usage` y X11. Con `LOW_MEMORY=1` se le añaden los recortes de memoria descritos en Ajustes de Android.
- Visual Studio Code usa `--no-sandbox` y `--disable-dev-shm-usage`.
- No se exportan `MESA_LOADER_DRIVER_OVERRIDE`, `TU_DEBUG`, `GALLIUM_DRIVER` ni `VK_ICD_FILENAMES`.
- No se usa `--ignore-gpu-blocklist`, `--use-angle`, Zink ni rasterización GPU forzada.
- Mesa es la versión oficial de Debian, con `libgl1-mesa-dri` instalado y `LIBGL_ALWAYS_SOFTWARE=1`, porque PRoot no expone la GPU.
- Termux:X11 usa la ruta de dibujo normal, igual que los scripts de referencia. `-legacy-drawing` quedó desactivado por defecto porque en las versiones actuales de la aplicación produce pantalla negra.
- La sesión arranca con `startxfce4`, no con `xfce4-session` directamente, para que se inicien xfsettingsd, xfwm4, xfdesktop y el panel.
- El compositor de XFCE viene desactivado y se activa por dispositivo con `X11_COMPOSITING=1`. Sin `libgl1-mesa-dri` producía pantalla negra; con él funciona, a costa de CPU. Apagado la personalización es plana y el tema cuadra los menús para que sus esquinas no se dibujen negras.
- XFCE no guarda la sesión al salir.
- Antes de abrir un servidor nuevo se le pide a la aplicación Termux:X11 que se cierre y se espera a que suelte el display, para que la ventana no quede enganchada a un servidor muerto.

## Requisitos

Instala manualmente:

1. Termux desde GitHub o F-Droid.
2. La aplicación Android Termux:X11.

No mezcles instalaciones de Termux procedentes de fuentes distintas.

Antes de usar el escritorio, revisa **Configuración de Termux:X11**: son ajustes de la aplicación Android que el script no puede aplicar y que hacen falta en cada dispositivo nuevo.

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

La instalación descarga varios GB y toma el wake-lock ella misma, así que puedes apagar la pantalla mientras trabaja.

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

- Chromium de Debian ARM64, con sus traducciones.
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
| `install` | Instala todos los componentes y aplica el tema |
| `start` | Activa wake-lock, audio, X11 y XFCE |
| `stop` | Cierra la sesión y libera el wake-lock |
| `restart` | Reinicia la sesión gráfica |
| `repair` | Reaplica configuración sin reinstalar Debian |
| `theme [mocha\|default]` | Alterna entre Catppuccin Mocha y el aspecto original |
| `update` | Actualiza Termux, Debian y aplicaciones |
| `update-ai` | Fuerza la actualización de Claude Code y Codex |
| `self-update` | Descarga los scripts actuales del repositorio |
| `status` | Idioma, almacenamiento, RAM, tema, wake-lock y versiones de X11 |
| `doctor` | Verifica las aplicaciones y la sincronía de Termux:X11 |

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
X11_COMPOSITING
LOW_MEMORY
DESKTOP_THEME
KEYBOARD_LAYOUT
KEYBOARD_VARIANT
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

## Personalización

La instalación deja el escritorio en **Catppuccin Mocha**. Para alternar:

```bash
$HOME/mobile-debian.sh stop
$HOME/mobile-debian.sh theme default   # aspecto original de XFCE
$HOME/mobile-debian.sh theme mocha     # vuelve a Catppuccin
$HOME/mobile-debian.sh start
```

Sin argumento, `theme` reaplica el que esté guardado. La elección se conserva en la configuración del dispositivo y `status` la muestra.

Los ajustes no se escriben en el momento: el comando deja un aplicador en `~/.local/bin/mobile-xfce-theme` que la sesión ejecuta al arrancar, junto a `mobile-xfce-fixups`. Es la razón de que el cambio se vea al hacer `start` y no antes. Aplicarlos con el escritorio cerrado no es fiable, porque `xfconfd` vive en un bus de D-Bus temporal y puede morir antes de volcarlos al disco.

El tema se instala en `~/.themes/Catppuccin-Mocha`, con ese nombre y no con el del paquete original, para que sea legible en Ajustes → Apariencia. Los dos aspectos quedan siempre disponibles ahí, así que también puedes cambiarlos a mano sin usar el comando.

Catppuccin Mocha lleva acento azul: tema GTK y decoración de ventanas desde las releases de [catppuccin/gtk](https://github.com/catppuccin/gtk), iconos Papirus-Dark, paleta oficial en la terminal, fondo liso `#1e1e2e`, panel sólido de 40 píxeles y tipografía monoespaciada JetBrains Mono, Fira Code o Cascadia Code, la primera que esté disponible.

Por defecto el escritorio queda **plano**: sin transparencias, desenfoque ni sombras, porque todo eso necesita el compositor. Catppuccin aguanta bien esa restricción porque su identidad está en la paleta, no en los efectos, y el tema cuadra las esquinas de los menús para que no se dibujen con recuadros negros.

Si el equipo lo aguanta, se puede activar el compositor y recuperar sombras y esquinas redondeadas:

```bash
X11_COMPOSITING=1 $HOME/mobile-debian.sh repair
$HOME/mobile-debian.sh theme
$HOME/mobile-debian.sh restart
```

El tema se adapta solo: con el compositor activo deja de cuadrar las esquinas. Todo se dibuja por CPU, así que en equipos lentos se nota.

Si la descarga del tema falla, el escritorio queda en Adwaita-dark en lugar de romperse. El tema solo se descarga una vez: las aplicaciones posteriores reutilizan el que ya está en `~/.themes`.

Tres aplicaciones no siguen el tema del sistema:

- **Visual Studio Code**: el comando instala la extensión oficial de Catppuccin y la deja seleccionada.
- **LibreOffice**: con el complemento gtk3 sigue el tema oscuro automáticamente. Si no lo hace, ponlo en Herramientas → Opciones → Ver → Apariencia.
- **Chromium**: solo lo sigue en parte. El resto se ajusta desde sus propios temas.

`theme default` devuelve XFCE a Adwaita, restaura la configuración previa de la terminal desde `~/.config/xfce4/terminal/terminalrc.previo` y deja Visual Studio Code en su tema oscuro estándar.

## Configuración de Termux:X11

Nada de esta sección la configura el script: son ajustes de la aplicación Android, y hay que repetirlos en cada dispositivo. Se llega a ellos desde el botón **Preferences** de la notificación persistente de Termux:X11, o desde el menú de la propia aplicación.

### Prefer scancodes when possible

**Actívalo.** Sin esta opción la aplicación entrega caracteres ya resueltos, X11 nunca ve la pulsación real y las teclas muertas no componen: el acento sale suelto, `t´ilde` en vez de `tílde`. Hace falta además de la distribución de teclado que aplica el script, no en su lugar.

### Resolución y escala

Termux:X11 expone un único modo de pantalla, así que el diálogo de Ajustes de pantalla de XFCE no sirve para cambiarlo. Se hace en **Display resolution mode** de la aplicación, con la opción personalizada.

Bajar la resolución agranda toda la interfaz y además da un escritorio más fluido, porque sin GPU cada píxel se dibuja por CPU. Conviene mantener la relación de aspecto del panel para que no se deforme:

| Dispositivo | Nativa | Relación | Para el doble de tamaño |
|---|---|---|---|
| Galaxy Tab S9 | 2560x1600 | 16:10 | 1280x800 |
| Galaxy S25 Ultra | 3120x1440 | 19.5:9 | 1560x720 |

Deja desactivada la opción de estirar la imagen, o rellenará la pantalla deformándola.

### Versión de la aplicación

La APK y el paquete `termux-x11-nightly` deben ser de la misma versión. `pkg upgrade` actualiza el paquete pero no la aplicación, así que la pareja se desincroniza sola con el tiempo y el resultado es pantalla negra o blanca. `doctor` compara ambas y el arranque avisa si difieren.

### Dibujo heredado

Lo controla el script con `X11_LEGACY_DRAWING`, no la aplicación. Está desactivado porque en las versiones actuales de Termux:X11 produce pantalla negra.

### Batería y segundo plano

La aplicación necesita los mismos permisos que Termux, descritos en Ajustes de Android. Si el sistema la mata, la ventana se queda en negro aunque el servidor X siga vivo.

### Samsung DeX

DeX dibuja su barra de ventana arriba y la barra de tareas abajo, y una aplicación no puede ocultarlas: reaparecen al acercarse a esos bordes e interrumpen el uso de XFCE. También intercepta atajos de teclado como Alt+Tab antes de que lleguen a la sesión.

Dos mitigaciones: mover el panel de XFCE a un lateral, con clic derecho sobre él → Panel → Preferencias, desmarcando *Bloquear el panel*; y activar el ocultado automático de la barra de tareas en los ajustes de DeX.

Fuera de DeX no ocurre ninguna de las dos cosas, así que si no dependes de un monitor externo, usar Termux:X11 en modo normal a pantalla completa sale más a cuenta.

## Teclado

XFCE usa por defecto la distribución de Estados Unidos, donde el acento agudo no es tecla muerta. El script aplica `latam` en cada sesión, configurable por dispositivo:

```bash
KEYBOARD_LAYOUT=es $HOME/mobile-debian.sh repair    # español de España
KEYBOARD_LAYOUT= $HOME/mobile-debian.sh repair      # no tocar la distribución
```

Esto por sí solo no basta: hace falta también **Prefer scancodes when possible** en Termux:X11.

Si los acentos tampoco funcionan en aplicaciones de Android fuera de XFCE, el problema es la distribución del teclado físico en el propio sistema, y se cambia en Ajustes → Administración general → Configuración del teclado físico.

## Ajustes de Android

Android puede matar Termux con `SIGKILL`, lo que en la terminal aparece como `[Process completed (signal 9) - press Enter]`. No es un fallo del escritorio: es la política de segundo plano del sistema. Estos ajustes hay que aplicarlos a mano en cada dispositivo.

Para **Termux** y también para **Termux:X11**, porque si Android se lleva la segunda te quedas con la pantalla en negro:

1. Ajustes → Aplicaciones → *la aplicación* → Batería → **Sin restricciones**.
2. Ajustes → Batería → Límites de uso en segundo plano → añadir a **Aplicaciones que nunca entran en reposo**, y sacarlas de las listas de reposo y reposo profundo.
3. Ajustes → Batería → **Batería adaptable** desactivada.
4. Botón Recientes → mantener pulsado el icono → **Mantener abierta**.

En **Opciones de desarrollador**, que se habilitan tocando siete veces "Número de compilación" en Información del software:

1. **Desactivar restricciones de procesos secundarios**, si existe en esa versión de One UI. Es la más efectiva, porque PRoot lanza muchos procesos hijo.
2. **Suspender ejecución para apps en caché** desactivado, que es el equivalente cuando la opción anterior no está.
3. **Límite de procesos en segundo plano** en *Límite estándar*.
4. **No mantener actividades** desactivado.

Reinicia el dispositivo al terminar.

Estos ajustes evitan que Android mate por política, no por falta real de memoria. En equipos de 8 GB, Chromium con varias pestañas junto a Visual Studio Code puede agotar la RAM de verdad, y entonces interviene el OOM killer del núcleo. Para ese caso:

```bash
LOW_MEMORY=1 $HOME/mobile-debian.sh repair
```

Eso recorta el consumo de Chromium desactivando su proceso de GPU, que sin aceleración solo falla y reintenta, y el aislamiento por sitio, que abre un proceso por dominio. A cambio se pierde la separación de seguridad entre pestañas de sitios distintos, así que está desactivado por defecto y se activa solo en los equipos que lo necesitan.

## Pantalla negra

La causa más frecuente es el desajuste de versiones entre la aplicación y el paquete que se describe en Configuración de Termux:X11.

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
