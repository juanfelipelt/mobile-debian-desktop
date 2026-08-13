# Mobile Debian Desktop

Escritorio Debian XFCE para Android mediante **Termux + PRoot-Distro + Termux:X11**. Desarrollado y probado en Samsung Galaxy S25 Ultra. Sirve en cualquier equipo ARM64 con memoria de sobra; en equipos ajustados de RAM, Android acaba matando la sesión.

Las aplicaciones se instalan y ejecutan dentro de Debian, sin forzar controladores KGSL, Zink, ANGLE ni rasterización GPU experimental. Todo se dibuja por CPU: PRoot no expone la GPU.

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
    └── Claude Code, Codex CLI y opencode
```

## Decisiones de estabilidad

- Chromium usa únicamente los flags mínimos requeridos por PRoot: `--no-sandbox`, `--disable-dev-shm-usage` y X11. Con `LOW_MEMORY=1` se le añaden los recortes de memoria descritos en Ajustes de Android.
- Se instala `gnome-keyring` y la sesión lo desbloquea al arrancar, así que las aplicaciones que guardan credenciales funcionan sin ajustes propios. Con `KEYRING=0` se desactiva y cada una vuelve a su apaño.
- No se fuerzan controladores gráficos por variables de entorno ni por flags de Chromium. Los intentos con KGSL y Zink son el origen de las pantallas blancas y negras que costó desenredar.
- Mesa es la versión oficial de Debian, con `libgl1-mesa-dri` instalado y `LIBGL_ALWAYS_SOFTWARE=1`, porque PRoot no expone la GPU.
- Termux:X11 usa la ruta de dibujo normal, igual que los scripts de referencia. `-legacy-drawing` quedó desactivado por defecto porque en las versiones actuales de la aplicación produce pantalla negra.
- La sesión arranca con `startxfce4`, no con `xfce4-session` directamente, para que se inicien xfsettingsd, xfwm4, xfdesktop y el panel.
- El compositor de XFCE viene activado y da sombras, transparencias y esquinas redondeadas. Lo que antes dejaba la pantalla negra era encenderlo sin `libgl1-mesa-dri`; con ese driver funciona, aunque se dibuje por CPU. Se apaga por dispositivo con `X11_COMPOSITING=0`.
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
- XFCE Terminal con starship, el preset Pastel Powerline y la fuente CaskaydiaCove Nerd.
- `lsd`, con `ls` y `cls` ya aliasados.
- Mousepad.
- Ristretto como visor de imágenes por defecto.
- Capturas de pantalla con xfce4-screenshooter.
- File Roller.
- Atril como lector de PDF por defecto.
- PulseAudio y Pavucontrol.

### Navegación y desarrollo

- Chromium de Debian ARM64, con sus traducciones y registrado como navegador por defecto. La sincronización con la cuenta de Google no funciona: la compilación de Debian no incluye las credenciales de Google para ese servicio.
- Visual Studio Code oficial ARM64 mediante el repositorio de Microsoft. Los accesos directos que traen los paquetes se ocultan, porque sin `--no-sandbox` no arrancan bajo PRoot y dejaban entradas duplicadas en el menú.
- Git.
- Python 3, pip y venv.
- Node.js y npm.
- Build Essential y pkg-config.
- Claude Code.
- OpenAI Codex CLI.
- opencode.

### Oficina y multimedia

- LibreOffice completo en español.
- Diccionario Hunspell en español.
- GIMP, con la memoria ajustada a la RAM del equipo.
- VLC.
- mpv.
- FFmpeg.

## Idioma y región

```text
Usuario: felipe
Idioma: es_CO.UTF-8
Interfaz: español de Colombia
Zona horaria: America/Bogota
```

El usuario tiene `sudo` sin contraseña dentro del contenedor.

## Qué sobrescribe una reinstalación

`self-update` solo reemplaza el script en Termux; no toca nada dentro de Debian.

`repair` reaplica la configuración del escritorio. **Conserva** el `starship.toml`, los alias del `.bashrc`, lo que hayas añadido al `.profile`, el resto del `gimprc` y los ajustes de Visual Studio Code que no sean el tema y la fuente.

**Reescribe** el `terminalrc` de la terminal, los accesos directos del escritorio, los envoltorios de Chromium y Visual Studio Code, y los ajustes de XFCE que gobierna el tema. Si has personalizado la terminal a mano, guarda una copia antes:

```bash
proot-distro login debian --user felipe -- \
  cp ~/.config/xfce4/terminal/terminalrc ~/terminalrc.mio
```

## Terminal

Viene con **starship** usando el preset Pastel Powerline, la fuente **CaskaydiaCove Nerd** —que es la que tiene los glifos que el preset dibuja— y **lsd** con dos alias:

```bash
alias ls='lsd'
alias cls='clear'
```

El `~/.config/starship.toml` solo se escribe si no existe, y los alias se añaden al `~/.bashrc` sin duplicarse. A partir de ahí esos archivos son tuyos: reinstalar o reparar no los sobrescribe. Se omite todo con `INSTALL_SHELL_TOOLS=0`.

## Llavero

Las aplicaciones guardan sus credenciales en un llavero del sistema vía libsecret: el token de GitHub de Visual Studio Code, la sesión de Google en Chromium. Sin llavero cada una necesita su propio apaño y algunas simplemente pierden la sesión en cada arranque.

La sesión desbloquea el llavero **una vez al iniciarse**, no una vez por aplicación. Por defecto lo hace con contraseña vacía, sin preguntar nada. Para cifrarlo de verdad:

```bash
KEYRING_PASSWORD=ask $HOME/mobile-debian.sh start
```

Eso pide la contraseña en Termux antes de abrir XFCE. No se guarda en ningún sitio, así que hay que teclearla en cada arranque; a cambio el llavero queda cifrado en reposo. Con contraseña vacía las aplicaciones funcionan igual, pero los secretos quedan legibles para cualquier cosa que corra como tu usuario, igual que antes.

## Memoria de GIMP

El caché de mosaico marca a partir de cuánta memoria GIMP empieza a descargar a disco. Viene en 8 GB, y la memoria de deshacer en 2 GB, dimensionados para un equipo de 12 GB o más.

```bash
GIMP_TILE_CACHE=4G GIMP_UNDO_MEMORY=1G $HOME/mobile-debian.sh repair
```

Bájalos en equipos con menos memoria: por encima de la RAM libre GIMP deja de descargar mosaicos y Android mata Termux al abrir una imagen grande. El resto del `gimprc` no se toca, solo esas dos claves.

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
| `repair` | Reaplica configuración y tema sin reinstalar Debian |
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
KEYRING
KEYRING_PASSWORD
LOW_MEMORY
DESKTOP_THEME
KEYBOARD_LAYOUT
KEYBOARD_VARIANT
GIMP_TILE_CACHE
GIMP_UNDO_MEMORY
INSTALL_DEV_STACK
INSTALL_OFFICE
INSTALL_MEDIA
INSTALL_GRAPHICS
INSTALL_SHELL_TOOLS
INSTALL_VSCODE
INSTALL_CHROMIUM
INSTALL_AI_CLI
ENABLE_ANDROID_STORAGE
```

Las variables de entorno tienen prioridad sobre el archivo de configuración guardado, y el valor queda anotado para las siguientes ejecuciones:

```bash
X11_COMPOSITING=0 $HOME/mobile-debian.sh repair
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

Los cambios se ven al iniciar la sesión, no al terminar el comando.

Ambos aspectos quedan disponibles en Ajustes → Apariencia, así que también puedes cambiarlos desde ahí.

Con el compositor activado, que es como viene, el tema mantiene lo que Catppuccin trae de fábrica: esquinas redondeadas en los menús, sombras bajo las ventanas, panel y terminal translúcidos al 80 %.

Con `X11_COMPOSITING=0` el tema se adapta solo: menús de esquina recta y sin transparencias, porque sin compositor esas zonas se dibujarían negras.

```bash
X11_COMPOSITING=0 $HOME/mobile-debian.sh repair
$HOME/mobile-debian.sh restart
```

Todo se dibuja por CPU, así que en equipos lentos el compositor se nota.

Si la terminal estaba abierta al aplicar el tema, conserva su configuración anterior y sobrescribe la nueva al cerrarse. Ajusta la opacidad en Editar → Preferencias → Apariencia, o cierra la terminal antes de aplicar el tema.

Si la descarga del tema falla, el escritorio queda en Adwaita-dark en lugar de romperse. El tema solo se descarga una vez: las aplicaciones posteriores reutilizan el que ya está en `~/.themes`.

Tres aplicaciones no siguen el tema del sistema:

- **Visual Studio Code**: el comando instala la extensión oficial de Catppuccin y la deja seleccionada.
- **LibreOffice**: con el complemento gtk3 sigue el tema oscuro automáticamente. Si no lo hace, ponlo en Herramientas → Opciones → Ver → Apariencia.
- **Chromium**: solo lo sigue en parte. El resto se ajusta desde sus propios temas.

`theme default` devuelve XFCE a Adwaita, restaura la configuración previa de la terminal desde `~/.config/xfce4/terminal/terminalrc.previo` y deja Visual Studio Code en su tema oscuro estándar.

## Configuración de Termux:X11

Nada de esta sección la configura el script: son ajustes de la aplicación Android, y hay que repetirlos en cada dispositivo. Se llega a ellos desde el botón **Preferences** de la notificación persistente de Termux:X11, o desde el menú de la propia aplicación.

### Teclado

Dos ajustes que van juntos, y esta es la combinación que funciona:

| Ajuste | Estado |
|---|---|
| Prefer scancodes when possible | **activado** |
| Hardware keyboard scancodes workaround | **desactivado** |

Sin el primero la aplicación entrega caracteres ya resueltos, X11 no ve la pulsación real y las teclas muertas no componen: sale `t´ilde` en vez de `tílde`. Pero el segundo reescribe los códigos de tecla, y con ambos activos se pierde el Bloq Mayús. Activando uno y desactivando el otro funcionan las dos cosas.

Esto va además de la distribución que aplica el script, no en su lugar.

### Resolución y escala

Termux:X11 expone un único modo de pantalla, así que el diálogo de Ajustes de pantalla de XFCE no sirve para cambiarlo. Se hace en **Display resolution mode** de la aplicación, con la opción personalizada.

Bajar la resolución agranda toda la interfaz y además da un escritorio más fluido, porque sin GPU cada píxel se dibuja por CPU. Conviene mantener la relación de aspecto del panel para que no se deforme:

| Dispositivo | Nativa | Relación | Para el doble de tamaño |
|---|---|---|---|
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

Hace falta además la pareja de ajustes descrita en Configuración de Termux:X11. Si los acentos tampoco funcionan fuera de XFCE, en aplicaciones de Android, el problema es el teclado físico del sistema y se cambia en Ajustes → Administración general → Configuración del teclado físico.

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

Estos ajustes evitan que Android mate por política, no por falta real de memoria. Si Chromium con varias pestañas junto a Visual Studio Code agota la RAM de verdad, interviene el OOM killer del núcleo y ningún ajuste lo impide. Para bajar el consumo:

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

## Fuentes técnicas

- Termux:X11: https://github.com/termux/termux-x11
- PRoot-Distro: https://github.com/termux/proot-distro
- Chromium para Debian ARM64: https://packages.debian.org/trixie/arm64/chromium
- Visual Studio Code para Linux: https://code.visualstudio.com/docs/setup/linux
- Termux storage y sistema de archivos: https://github.com/termux/termux-packages/wiki/Termux-file-system-layout
- Catppuccin para GTK: https://github.com/catppuccin/gtk
