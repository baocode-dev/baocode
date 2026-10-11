# BaoCode

[English](README.md) · [简体中文](README_CN.md) · [日本語](README_JA.md) · **Français** · [Español](README_ES.md)

Une interface de bureau conviviale pour [Claude Code](https://github.com/anthropics/claude-code), avec un IDE intégré qui répond en quelques millisecondes.

[Site web](https://baocode.dev) · [Télécharger](https://baocode.dev/download) · [Historique des versions](https://baocode.dev/changelog)

![Fenêtre principale de BaoCode : agents regroupés par projet, deux conversations côte à côte et sélecteur de modèle](site/shots/main.png)

> Présentation française du README anglais. En cas de différence, consultez la version [English](README.md). Les sites et documents liés ne sont pas nécessairement traduits en français.

## Pourquoi BaoCode ?

Nous utilisons Claude Code tous les jours. Le terminal convient pour l'exécuter, mais moins pour lire ses résultats : les longs diffs disparaissent de l'écran, les étapes précédentes sont difficiles à retrouver et vérifier les changements oblige à changer d'application. BaoCode est la fenêtre que nous souhaitions autour de cet outil.

BaoCode n'intègre volontairement aucun agent propre. Claude Code est l'agent, avec son écosystème d'outils, de skills, de plugins, de serveurs MCP, de sous-agents et de hooks. BaoCode lui offre une interface lisible et rend les fonctions périphériques immédiatement utilisables. Il lance le Claude Code déjà installé, avec vos paramètres et votre `CLAUDE.md`.

## Fonctionnalités

- **Une interface pensée pour la lecture.** Lectures de fichiers, recherches et commandes se replient sur une seule ligne. Conservez ou annulez les modifications de Claude fichier par fichier. Les points de contrôle restent dans le dossier de données de BaoCode, jamais dans le `.git` du dépôt.
- **Objectifs.** Saisissez `/goal` suivi du résultat souhaité : Claude poursuit son travail jusqu'à l'atteindre. L'objectif et sa progression apparaissent au-dessus de la zone de saisie.
- **Saisie enrichie.** Le code copié depuis l'éditeur devient une référence à son fichier et à ses lignes. Les images collées et les fichiers déposés se placent à l'endroit choisi dans la phrase.
- **IDE rapide.** Éditeur, terminal et gestion du code source avec graphe des commits sont intégrés. Claude Code peut rédiger les messages de commit. Des configurations de raccourcis et des serveurs de langage sont pris en charge.
- **Thèmes cohérents.** L'éditeur, la conversation et la barre latérale suivent le même thème.
- **Skills, serveurs MCP et autres extensions.** Gérez plugins, serveurs MCP, skills, sous-agents, règles, commandes et hooks au même endroit, pour votre compte ou un projet précis.
- **Plusieurs modèles.** Ajoutez un fournisseur compatible avec l'API Anthropic, OpenAI Chat Completions ou OpenAI Responses. Un proxy local traduit le protocole pour Claude Code. Les clés restent dans le trousseau du système.
- **Projets distants par SSH.** La fenêtre reste sur votre machine ; fichiers, Git, recherches, terminaux, serveurs de langage et Claude Code s'exécutent sur l'hôte distant (Linux, x64 ou arm64).
- **Notifications.** Notification système, son et badge vous avertissent lorsqu'un agent termine ou a besoin de vous. Les agents peuvent continuer dans la barre de menus ou la zone de notification lorsque la fenêtre est fermée.
- **Mises à jour.** Choisissez les mises à jour automatiques en arrière-plan, les mises à jour manuelles ou leur désactivation.

## Rapidité

BaoCode est une application native qui dessine directement son interface sur le GPU. Les chiffres suivants proviennent du README anglais ; ils n'ont pas été remesurés pour cette traduction. Les résultats réels dépendent du matériel, de la version et de l'utilisation.

| Indicateur | BaoCode |
| --- | --- |
| Démarrage | ≈ 0,18 s |
| Mémoire, une fenêtre inactive | ≈ 120 MB |
| Processus, une fenêtre | 2 |
| Taille du téléchargement Windows | ≈ 16 MB |

## Prérequis

- macOS 12 ou ultérieur (un téléchargement pour Apple silicon, un pour Intel), ou Windows 10 ou ultérieur (x64).
- [Claude Code](https://github.com/anthropics/claude-code) installé.

## Compilation depuis les sources

BaoCode est une application Flutter ; le SDK Dart requis est `^3.13.4`.

```sh
flutter pub get
flutter run -d macos        # Windows : flutter run -d windows
```

Pour créer les distributions dans `build/installers/` :

```sh
dart run tool/build_macos.dart            # BaoCode-<version>-{arm64,x64}.dmg et BaoCode-<version>-mac-{arm64,x64}.zip
dart run tool/build_windows.dart          # BaoCode-<version>-setup.exe (nécessite Inno Setup)
dart run tool/build_remote_server.dart    # serveur SSH distant pour Linux x64 et arm64
```

La suite complète de tests est lente : n'exécutez que les tests liés à vos modifications, par exemple `flutter test test/update`.

La CI compile et publie les versions lorsqu'un tag `v*` est poussé. Versions, signatures et destinations de publication sont décrites dans [docs/release.md](docs/release.md). D'autres documents se trouvent dans [docs/](docs), notamment les [mises à jour automatiques](docs/auto-update.md), [SSH distant](docs/ssh-remote.md) et [Windows](docs/windows.md). Certains sont en chinois.

## Structure du dépôt

| Chemin | Contenu |
| --- | --- |
| [lib/](lib) | L'application |
| [packages/bao_editor](packages/bao_editor) | Éditeur, coloration syntaxique, thèmes et raccourcis |
| [packages/bao_xterm](packages/bao_xterm) | Portage de xterm.js en Dart |
| [packages/bao_pty](packages/bao_pty) | Pseudo-terminaux Dart : forkpty sur macOS et Linux, ConPTY sur Windows |
| [packages/bao_remote](packages/bao_remote) | Composant distant servi par SSH |
| [macos/](macos), [windows/](windows) | Lanceurs natifs |
| [tool/](tool) | Scripts de compilation, de packaging et de publication |
| [site/](site) | Sources du site [baocode.dev](https://baocode.dev) |
| [docs/](docs) | Notes de conception |

## Retours

Les issues sont les bienvenues. Le projet amont n'accepte pas les Pull Requests.

## Licence

BaoCode est distribué sous [GNU General Public License v3.0](LICENSE) (GPL-3.0-only). Les paquets d'éditeur et de terminal de [packages/](packages) (bao_editor, bao_xterm, bao_pty) utilisent la licence MIT. Les composants tiers conservent leurs licences respectives, présentes à côté de leurs sources.

BaoCode est un projet indépendant, sans affiliation avec Anthropic ni approbation de sa part.
