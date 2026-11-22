# BaoCode

[English](README.md) · [简体中文](README_CN.md) · [日本語](README_JA.md) · **Français** · [Español](README_ES.md)

**Le plan de contrôle open source pour [Claude Code](https://github.com/anthropics/claude-code). Bien plus qu'une interface.**

Au-delà d'une interface à 360 FPS soignée jusque dans les détails : Claude Code sur vos autres machines, le contrôle depuis votre téléphone, une optimisation poussée pour Windows, un pilotage du navigateur 10× plus rapide, un éditeur de code complet, n'importe quelle API personnalisée, le suivi de la consommation, l'orchestration des conversations et des Bots.

[Site web](https://baocode.dev) · [Télécharger](https://baocode.dev/download) · [Historique des versions](https://baocode.dev/changelog)

![BaoCode en mode Agent : des agents sur plusieurs machines, une conversation en cours et sa consommation](https://baocode.dev/readme/agent.webp)

![BaoCode en mode IDE : l'arborescence et l'éditeur, avec la conversation à côté](https://baocode.dev/readme/ide.webp)

![Ce que fait BaoCode : rendu à 360 FPS, Claude Code via SSH, le navigateur, tous les modèles, Windows, usage et coût](https://baocode.dev/readme/features-en.webp)

> Présentation française du README anglais. En cas de différence, consultez la version [English](README.md). Les sites et documents liés ne sont pas nécessairement traduits en français.

## Ne pas réinventer la roue, juste ce qui marche

Claude Code est déjà très bon ; BaoCode n'ajoute que ce qui lui manque. Il fonctionne dès l'installation, sans rien de nouveau à apprendre, et se comporte comme il aurait toujours dû.

**Pourquoi Claude Code ?** Poussez assez loin la personnalisation de n'importe quel moteur d'agent, et il finit par ressembler à Claude Code : les mêmes outils, la même gestion du contexte, les mêmes skills et le même MCP. Plutôt que de le reconstruire par un long détour, BaoCode l'utilise directement et relie les autres modèles au niveau du protocole : une seule configuration les fait tous fonctionner. Il lance le Claude Code que vous avez déjà, avec vos réglages, votre connexion et votre `CLAUDE.md` ; là où Claude Code n'est pas installé, l'agent intégré de BaoCode lit les mêmes réglages et tourne sur un fournisseur de modèles que vous ajoutez.

**Une conversation dirige le reste.** Pas de canevas d'orchestration. Grâce au MCP intégré, la conversation principale pilote les autres sessions et sous-agents, y compris sur d'autres serveurs ; décrivez une fois un flux complexe, ou écrivez-le sous forme de skill pour le réutiliser.

## Fonctionnalités

### Rendu natif GPU à 360 FPS

Pas d'Electron, pas de reflow du DOM. BaoCode est une application native qui dessine son interface directement sur le GPU : les flux de tokens rapides suivent la fréquence de rafraîchissement de votre écran, le défilement suit votre main, et l'application ralentit d'elle-même pendant les attentes.

| | BaoCode | VS Code | Cursor |
| --- | --- | --- | --- |
| Lancement | ≈ 0,18 s | ≈ 2–3 s | ≈ 2–3 s |
| Mémoire, une fenêtre au repos | ≈ 120 Mo | ≈ 970 Mo | ≈ 1,9 Go |
| Processus, une fenêtre | 2 | 8 | 13 |
| Taille du téléchargement, Windows | ≈ 16 Mo | ≈ 244 Mo | ≈ 214 Mo |

### Claude Code via SSH, sur n'importe quelle machine

Connectez-vous à n'importe quel hôte Linux, macOS ou Windows et utilisez le Claude Code qui y est installé, tout en restant relié à votre propre machine : le téléphone Android branché en USB-C, votre Chrome local, vos ports. La fenêtre reste chez vous ; fichiers, Git, recherche, terminaux, serveurs de langage et Claude Code s'exécutent sur l'hôte. Sous Windows, les distributions WSL s'ouvrent de la même façon.

### Un navigateur piloté 10× plus vite

Avec l'extension BaoCode (Chrome, Edge, Brave, Arc), les agents travaillent dans votre vrai navigateur, déjà connecté, plutôt que dans une boucle de captures d'écran à l'aveugle : saisie précise comme au stylet, état React et Vue, traçage des WebSocket, points d'arrêt dans le code source et profilage des performances à la milliseconde. Ils ne voient que les onglets que vous partagez avec eux, et tout reste sur votre ordinateur.

### Tous les modèles, branchés directement

DeepSeek, Kimi, ChatGPT, Gemini et les autres grands modèles, ainsi que des plateformes comme OpenRouter et Ollama, se branchent directement. BaoCode adapte chaque protocole (Anthropic Messages, OpenAI Chat Completions et Responses, Codex, Gemini) dans un proxy local, sans toucher à `~/.claude`, pour que chacun donne le meilleur de lui-même dans Claude Code. Les clés restent dans le trousseau du système.

### Consommation et tarifs

Voyez où partent les tokens : entrée, sortie, lectures et écritures de cache, taux de succès du cache et économies réalisées. Les prix suivent les règles de chaque fournisseur, heures pleines et creuses, jours fériés et tarifs par paliers de contexte compris.

### Conçu pour Windows

[bash.exe](https://github.com/baocode-dev/bash-exe) gomme les différences de plateforme de votre Windows, pour un usage proche de WSL, et l'interface est rendue par le chemin GPU de Skia, aussi fluide que sur macOS. x64 et Arm64.

### Votre téléphone, les mêmes sessions

Exactement les mêmes sessions en direct, le détail du contexte de 400K, les quotas des modèles et les dépôts distants via SSH, reproduits nativement sur iOS et Android. Appairage par QR code ; la connexion, directe ou via les relais de BaoCode, est chiffrée de bout en bout.

### Un éditeur de code complet

Un éditeur (Monaco, porté sur Flutter), un terminal et le contrôle de version avec un graphe des commits, intégrés, avec serveurs de langage et raccourcis VS Code, IntelliJ, Sublime et Atom. Claude Code rédige vos messages de commit. Vos thèmes VS Code habillent l'éditeur, la conversation et la barre latérale.

### Et aussi

- **Conserver ou annuler** chaque modification de Claude, fichier par fichier ; les points de restauration sont rangés dans le dossier de données de BaoCode, jamais dans le `.git` de votre dépôt.
- **Objectifs.** Tapez `/goal` suivi de ce que vous voulez obtenir, et Claude continue jusqu'à ce que ce soit fait.
- **Une saisie en texte enrichi.** Le code copié depuis l'éditeur arrive comme une référence à son fichier et à ses lignes ; les images collées et les fichiers déposés restent là où vous les placez dans la phrase.
- **Plugins, serveurs MCP, skills**, sous-agents, règles, commandes et hooks au même endroit, pour vous ou pour un seul projet.
- **Notifications** quand un agent a besoin de vous ou a terminé. Fermez la fenêtre : les agents continuent dans la barre des menus ou la zone de notification.
- **Mise à jour automatique** en arrière-plan, manuelle, ou désactivée.

## Prérequis

- **Ordinateur :** macOS 12 ou ultérieur (Apple silicon ou Intel), Windows 10 ou ultérieur (x64 ou Arm64), ou Linux : Ubuntu 22.04 ou ultérieur et autres distributions basées sur Debian (x64 ou arm64).
- **Téléphone :** Android 7.0 ou ultérieur, ou iOS 15 ou ultérieur (bêta sur TestFlight), appairé avec BaoCode sur un ordinateur.
- **Extension de navigateur :** Chrome, Edge, Brave ou Arc, sous macOS ou Windows.
- [Claude Code](https://github.com/anthropics/claude-code) si vous l'avez ; sinon, un fournisseur de modèles que vous ajoutez.

Tout est sur la [page de téléchargement](https://baocode.dev/download).

## Compilation depuis les sources

BaoCode est une application Flutter (Dart SDK `^3.13.4`).

```sh
flutter pub get
flutter run -d macos        # ou : flutter run -d windows
```

Pour compiler les versions publiées, dans `build/installers/` :

```sh
dart run tool/build_macos.dart            # BaoCode-<version>-{arm64,x64}.dmg et BaoCode-<version>-mac-{arm64,x64}.zip
dart run tool/build_windows.dart          # BaoCode-<version>-setup.exe (nécessite Inno Setup)
flutter build linux --release && sh tool/package_linux_deb.sh   # BaoCode-<version>-linux-{amd64,arm64}.deb et .tar.gz, sous Ubuntu
dart run tool/build_remote_server.dart    # le serveur distant SSH, pour les hôtes Linux, macOS et Windows
```

La suite de tests complète est lente ; lancez les tests liés à vos modifications, par exemple `flutter test test/update`.

Les versions sont compilées et publiées par la CI lorsqu'un tag `v*` est poussé ; les numéros de version, la signature et la destination des publications sont décrits dans [docs/release.md](docs/release.md). Plus de documents dans [docs/](docs) : [mise à jour automatique](docs/auto-update.md), [SSH distant](docs/ssh-remote.md), [Windows](docs/windows.md), [la liaison avec le téléphone](docs/mobile-link.md) (certains sont en chinois).

## Structure du dépôt

| Chemin | Contenu |
| --- | --- |
| [lib/](lib) | L'application |
| [packages/bao_agent](packages/bao_agent) | L'agent intégré, qui parle le protocole stream-json de Claude Code |
| [packages/bao_editor](packages/bao_editor) | Monaco, porté sur Flutter : l'éditeur, sa coloration syntaxique, les thèmes et raccourcis de VS Code |
| [packages/bao_xterm](packages/bao_xterm) | Un portage de xterm.js en Dart |
| [packages/bao_pty](packages/bao_pty), [bao_conpty](packages/bao_conpty) | Pseudo-terminaux pour Dart : forkpty sous macOS et Linux, ConPTY sous Windows |
| [packages/bao_remote](packages/bao_remote) | L'hôte distant servi via SSH |
| [packages/bao_link](packages/bao_link), [bao_iroh](packages/bao_iroh) | La liaison avec votre téléphone : appairage par QR code, connexions chiffrées de bout en bout via iroh |
| [packages/bao_markdown](packages/bao_markdown) | Un éditeur Markdown qui affiche le rendu pendant la frappe |
| [packages/bao_websearch](packages/bao_websearch) | La recherche web pour tous les modèles, sans API de recherche |
| [browser_extension/](browser_extension) | L'extension de navigateur |
| [macos/](macos), [windows/](windows), [linux/](linux) | Les lanceurs natifs |
| [tool/](tool) | Scripts de compilation, d'empaquetage et de publication |
| [site/](site) | Le site web, [baocode.dev](https://baocode.dev) |
| [docs/](docs) | Notes de conception |

## Retours

Les issues et les pull requests sont les bienvenues. Discutez d'une modification dans une issue avant de l'écrire ; les grosses pull requests, et celles qui portent sur des changements non discutés au préalable, ne sont pas acceptées. Voir [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

BaoCode est distribué sous la [GNU General Public License v3.0](LICENSE) (GPL-3.0-only). Les paquets d'éditeur et de terminal dans [packages/](packages) (bao_editor, bao_xterm, bao_pty) sont sous licence MIT. Les composants tiers conservent leurs propres licences, placées à côté d'eux dans l'arborescence des sources.

BaoCode est un projet indépendant, ni affilié à Anthropic ni approuvé par Anthropic.
