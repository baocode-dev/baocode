// 九.2: Docker from Open VSX (ms-azuretools.vscode-docker, which brings
// Container Tools with its Dockerfile and Compose language servers) in a
// fresh data folder: a Dockerfile's diagnostics, hover and completions,
// a Compose file's completions, and the Images view listing the machine's
// images through its Docker CLI (read only).
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'open_vsx_workspace.dart';

/// The repositories of the machine's images, or null without a Docker
/// daemon.
List<String>? _images() {
  try {
    final result = Process.runSync('docker', [
      'images',
      '--format',
      '{{.Repository}}',
    ]);
    if (result.exitCode != 0) return null;
    return [
      for (final line in '${result.stdout}'.split('\n'))
        if (line.trim().isNotEmpty && line.trim() != '<none>') line.trim(),
    ];
  } on ProcessException {
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '九.2: Docker: Dockerfile and Compose language, Images view',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['ms-azuretools.vscode-docker'],
        files: {
          'Dockerfile': ['FROM alpine:3.20', 'RUNN echo hi', '', ''].join('\n'),
          'compose.yaml': [
            'services:',
            '  web:',
            '    image: alpine:3.20',
            '    ',
          ].join('\n'),
        },
      );
      final dockerfile = w.path('Dockerfile');
      await w.show('Dockerfile');
      expect(w.extensions.languageIdFor(dockerfile), 'dockerfile');
      await w.activated('ms-azuretools.vscode-containers');
      final languages = w.extensions.languageRoot.language;

      // The Dockerfile language server: the unknown instruction, FROM's
      // documentation, the instructions to complete.
      final diagnostics = await eventually('the Dockerfile diagnostic', () {
        final found = languages.diagnosticsFor(dockerfile);
        return found.any((d) => d.message.contains('RUNN')) ? found : null;
      }, timeout: const Duration(minutes: 2));
      expect(
        diagnostics.firstWhere((d) => d.message.contains('RUNN')).range.start,
        const LspPosition(1, 0),
      );
      final hover = await eventually('the FROM hover', () async {
        final found = await languages.hover(
          dockerfile,
          const LspPosition(0, 1),
        );
        return found != null && found.markdown.isNotEmpty ? found : null;
      });
      expect(hover.markdown, contains('FROM baseImage'));
      var seen = <String>[];
      final instructions = await eventually('the instructions', () async {
        final list = await languages.completion(
          dockerfile,
          const LspPosition(2, 0),
        );
        final labels = seen = [for (final i in list.items) i.label];
        return labels.any((l) => l.startsWith('COPY ')) ? labels : null;
      }).catchError((Object e) => fail('$e\nCompletions: $seen'));
      // Snippets, labelled with their placeholders.
      for (final instruction in ['RUN ', 'WORKDIR ', 'ENTRYPOINT ']) {
        expect(instructions, contains(startsWith(instruction)));
      }

      // The Compose language server: a service's keys.
      final compose = await w.open('compose.yaml');
      expect(w.extensions.languageIdFor(compose), 'dockercompose');
      final keys = await eventually('the service keys', () async {
        final list = await languages.completion(
          compose,
          const LspPosition(3, 4),
        );
        final labels = [for (final i in list.items) i.label];
        return labels.any((l) => l.startsWith('ports')) ? labels : null;
      }, timeout: const Duration(minutes: 2));
      expect(keys, contains(startsWith('environment')));

      // The Images view: the machine's images, by repository.
      final images = _images();
      if (images == null) {
        markTestSkipped('No Docker daemon: the Images view is not checked');
      } else if (images.isNotEmpty) {
        final views = w.extensions.views;
        views.setVisibleViews({'vscode-containers.views.images'});
        final tree = views.treeView('vscode-containers.views.images')!;
        final labels = await eventually('the images', () {
          final roots = tree.roots;
          if (roots == null || roots.isEmpty || tree.isLoading) return null;
          final labels = [for (final r in roots) r.displayLabel];
          return labels.any(images.contains) ? labels : null;
        }, timeout: const Duration(minutes: 2));
        expect(labels, isNot(contains(contains('Failed'))));
        expect(tree.roots!.first.hasChildren, isTrue);
      }
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: const Timeout(Duration(minutes: 8)),
    skip: openVsxSkip(),
  );
}
