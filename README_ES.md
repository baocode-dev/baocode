# BaoCode

[English](README.md) · [简体中文](README_CN.md) · [日本語](README_JA.md) · [Français](README_FR.md) · **Español**

**El plano de control de código abierto para [Claude Code](https://github.com/anthropics/claude-code). Mucho más que una interfaz.**

Más allá de una interfaz a 360 FPS cuidada hasta el último detalle: Claude Code en tus otras máquinas, control desde el móvil, una optimización a fondo para Windows, control del navegador 10× más rápido, un editor de código completo, cualquier API personalizada, el seguimiento del consumo, la orquestación de conversaciones y Bots.

[Sitio web](https://baocode.dev) · [Descargar](https://baocode.dev/download) · [Historial de cambios](https://baocode.dev/changelog)

![BaoCode en modo Agent: agentes en varias máquinas, una conversación en curso y su consumo](https://baocode.dev/readme/agent.webp)

![BaoCode en modo IDE: el árbol de archivos y el editor, con la conversación al lado](https://baocode.dev/readme/ide.webp)

![Lo que hace BaoCode: renderizado a 360 FPS, Claude Code por SSH, el navegador, cualquier modelo, Windows, uso y coste](https://baocode.dev/readme/features-en.webp)

> Presentación en español del README en inglés. Si hay diferencias, consulta [English](README.md). Los sitios y documentos enlazados no necesariamente están traducidos al español.

## Sin reinventar la rueda, solo lo que funciona

Claude Code ya es muy bueno; BaoCode solo añade lo que le falta. Funciona nada más instalarlo, sin nada nuevo que aprender, y se siente como siempre debió ser.

**¿Por qué Claude Code?** Personaliza lo suficiente cualquier núcleo de agente y acabará con la forma de Claude Code: las mismas herramientas, la misma gestión del contexto, los mismos skills y el mismo MCP. En lugar de reconstruirlo dando un rodeo, BaoCode lo usa directamente y conecta los demás modelos en la capa del protocolo, así que una sola configuración sirve para todos. Ejecuta el Claude Code que ya tienes, con tus ajustes, tu sesión iniciada y tu `CLAUDE.md`; donde Claude Code no está instalado, el agente integrado de BaoCode lee los mismos ajustes y funciona con un proveedor de modelos que añadas.

**Una conversación dirige el resto.** Sin lienzo de orquestación. A través del MCP integrado, la conversación principal dirige otras sesiones y subagentes, también en otros servidores; describe un flujo complejo una vez, o escríbelo como skill para reutilizarlo.

## Funciones

### Renderizado nativo por GPU a 360 FPS

Sin Electron, sin reflujo del DOM. BaoCode es una aplicación nativa que dibuja su interfaz directamente en la GPU: los flujos rápidos de tokens siguen la frecuencia de refresco de tu pantalla, el desplazamiento sigue tu mano y la aplicación se frena sola mientras espera.

| | BaoCode | VS Code | Cursor |
| --- | --- | --- | --- |
| Arranque | ≈ 0,18 s | ≈ 2–3 s | ≈ 2–3 s |
| Memoria, una ventana en reposo | ≈ 120 MB | ≈ 970 MB | ≈ 1,9 GB |
| Procesos, una ventana | 2 | 8 | 13 |
| Tamaño de descarga, Windows | ≈ 16 MB | ≈ 244 MB | ≈ 214 MB |

### Claude Code por SSH, en cualquier máquina

Conéctate a cualquier equipo Linux, macOS o Windows y usa el Claude Code instalado allí, sin perder el vínculo con tu propia máquina: el móvil Android conectado por USB-C, tu Chrome local, tus puertos. La ventana se queda contigo; archivos, Git, búsqueda, terminales, servidores de lenguaje y Claude Code se ejecutan en el equipo remoto. En Windows, las distribuciones de WSL se abren igual.

### Control del navegador 10× más rápido

Con la extensión de BaoCode (Chrome, Edge, Brave, Arc), los agentes trabajan en tu navegador real, con tu sesión iniciada, en lugar de en un bucle de capturas de pantalla a ciegas: entrada precisa como con un lápiz, estado de React y Vue, rastreo de WebSocket, puntos de interrupción en el código fuente y perfilado de rendimiento al milisegundo. Solo ven las pestañas que compartes con ellos, y todo se queda en tu ordenador.

### Todos los modelos, conectados directamente

DeepSeek, Kimi, ChatGPT, Gemini y los demás modelos líderes, y plataformas como OpenRouter y Ollama, se conectan directamente. BaoCode adapta cada protocolo (Anthropic Messages, OpenAI Chat Completions y Responses, Codex, Gemini) en un proxy local, sin tocar `~/.claude`, para que todos rindan igual de bien en Claude Code. Las claves se guardan en el llavero del sistema.

### Consumo y precios

Mira adónde van los tokens: entrada, salida, lecturas y escrituras de caché, la tasa de aciertos de caché y lo que te ha ahorrado. Los precios siguen las reglas de cada proveedor, con horas punta y valle, festivos y tarifas por tramos de contexto.

### Hecho para Windows

[bash.exe](https://github.com/baocode-dev/bash-exe) suaviza las diferencias de plataforma de tu Windows, para que funcione de forma muy parecida a WSL, y la interfaz se renderiza por la vía GPU de Skia, igual de fluida que en macOS. x64 y Arm64.

### Tu móvil, las mismas sesiones

Exactamente las mismas sesiones en directo, el desglose del contexto de 400K, las cuotas de los modelos y los repositorios remotos por SSH, reflejados de forma nativa en iOS y Android. Se empareja con un código QR; la conexión, directa o a través de los relés de BaoCode, va cifrada de extremo a extremo.

### Un editor de código completo

Un editor (Monaco, portado a Flutter), un terminal y control de versiones con grafo de commits, integrados, con servidores de lenguaje y atajos de VS Code, IntelliJ, Sublime y Atom. Claude Code redacta tus mensajes de commit. Tus temas de VS Code visten el editor, la conversación y la barra lateral por igual.

### Y además

- **Conserva o deshaz** cada cambio de Claude, archivo por archivo; los puntos de control se guardan en la carpeta de datos de BaoCode, nunca en el `.git` de tu repositorio.
- **Objetivos.** Escribe `/goal` y lo que quieres conseguir, y Claude sigue trabajando hasta lograrlo.
- **Una entrada de texto enriquecido.** El código copiado desde el editor llega como referencia a su archivo y sus líneas; las imágenes pegadas y los archivos arrastrados quedan donde los pones en la frase.
- **Plugins, servidores MCP, skills**, subagentes, reglas, comandos y hooks en un solo lugar, para ti o para un único proyecto.
- **Notificaciones** cuando un agente te necesita o termina. Cierra la ventana y los agentes siguen funcionando en la barra de menús o la bandeja del sistema.
- **Se actualiza solo** en segundo plano, manualmente, o nunca.

## Requisitos

- **Ordenador:** macOS 12 o posterior (Apple silicon o Intel), Windows 10 o posterior (x64 o Arm64), o Linux: Ubuntu 22.04 o posterior y otras distribuciones basadas en Debian (x64 o arm64).
- **Móvil:** Android 7.0 o posterior, o iOS 15 o posterior (beta en TestFlight), emparejado con BaoCode en un ordenador.
- **Extensión de navegador:** Chrome, Edge, Brave o Arc, en macOS o Windows.
- [Claude Code](https://github.com/anthropics/claude-code) si lo tienes; si no, un proveedor de modelos que añadas.

Todo está en la [página de descargas](https://baocode.dev/download).

## Compilar desde el código fuente

BaoCode es una aplicación Flutter (Dart SDK `^3.13.4`).

```sh
flutter pub get
flutter run -d macos        # o: flutter run -d windows
```

Para compilar lo que se publica, en `build/installers/`:

```sh
dart run tool/build_macos.dart            # BaoCode-<version>-{arm64,x64}.dmg y BaoCode-<version>-mac-{arm64,x64}.zip
dart run tool/build_windows.dart          # BaoCode-<version>-setup.exe (requiere Inno Setup)
flutter build linux --release && sh tool/package_linux_deb.sh   # BaoCode-<version>-linux-{amd64,arm64}.deb y .tar.gz, en Ubuntu
dart run tool/build_remote_server.dart    # el servidor remoto SSH, para equipos Linux, macOS y Windows
```

La suite de pruebas completa es lenta; ejecuta las pruebas de lo que hayas cambiado, por ejemplo `flutter test test/update`.

La CI compila y publica las versiones cuando se sube una etiqueta `v*`; las versiones, la firma y el destino de las publicaciones se explican en [docs/release.md](docs/release.md). Más documentación en [docs/](docs): [actualización automática](docs/auto-update.md), [SSH remoto](docs/ssh-remote.md), [Windows](docs/windows.md), [el enlace con el móvil](docs/mobile-link.md) (algunos están en chino).

## Estructura del repositorio

| Ruta | Qué es |
| --- | --- |
| [lib/](lib) | La aplicación |
| [packages/bao_agent](packages/bao_agent) | El agente integrado, que habla el protocolo stream-json de Claude Code |
| [packages/bao_editor](packages/bao_editor) | Monaco, portado a Flutter: el editor, su resaltado de sintaxis, los temas y atajos de VS Code |
| [packages/bao_xterm](packages/bao_xterm) | Un port de xterm.js a Dart |
| [packages/bao_pty](packages/bao_pty), [bao_conpty](packages/bao_conpty) | Pseudoterminales para Dart: forkpty en macOS y Linux, ConPTY en Windows |
| [packages/bao_remote](packages/bao_remote) | El equipo remoto servido por SSH |
| [packages/bao_link](packages/bao_link), [bao_iroh](packages/bao_iroh) | El enlace con tu móvil: emparejamiento por QR, conexiones cifradas de extremo a extremo sobre iroh |
| [packages/bao_markdown](packages/bao_markdown) | Un editor de Markdown que muestra el resultado mientras escribes |
| [packages/bao_websearch](packages/bao_websearch) | Búsqueda web para cualquier modelo, sin API de búsqueda |
| [browser_extension/](browser_extension) | La extensión de navegador |
| [macos/](macos), [windows/](windows), [linux/](linux) | Los lanzadores nativos |
| [tool/](tool) | Scripts de compilación, empaquetado y publicación |
| [site/](site) | El sitio web, [baocode.dev](https://baocode.dev) |
| [docs/](docs) | Notas de diseño |

## Comentarios

Las issues y las pull requests son bienvenidas. Comenta un cambio en una issue antes de escribirlo; no se aceptan pull requests grandes ni pull requests de cambios que no se hayan comentado antes. Consulta [CONTRIBUTING.md](CONTRIBUTING.md).

## Licencia

BaoCode se distribuye bajo la [GNU General Public License v3.0](LICENSE) (GPL-3.0-only). Los paquetes de editor y terminal en [packages/](packages) (bao_editor, bao_xterm, bao_pty) son MIT. Los componentes de terceros mantienen sus propias licencias, que se encuentran junto a ellos en el árbol de código fuente.

BaoCode es un proyecto independiente, no afiliado a Anthropic ni respaldado por Anthropic.
