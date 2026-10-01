// Port of VS Code src/vs/editor/test/common/services/languagesAssociations.test.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971. Associations are global and
// the tests build on each other, as upstream. Upstream runs on the host
// platform; here the suite runs once per operating system, clearing the
// associations before each run.

import 'package:flutter_test/flutter_test.dart' hide isWindows;
import 'package:bao_editor/monaco/vs/base/common/platform.dart';
import 'package:bao_editor/monaco/vs/editor/common/services/languages_associations.dart';

/// Upstream `URI.file`, with the separators of the emulated platform.
Uri file(String path) => Uri.file(path, windows: isWindows);

void main() {
  for (final os in OperatingSystem.values) {
    group('LanguagesAssociations (${os.name})', () {
      setUpAll(() {
        clearPlatformLanguageAssociations();
        clearConfiguredLanguageAssociations();
      });
      setUp(() => debugOperatingSystemOverride = os);
      tearDown(() => debugOperatingSystemOverride = null);
      _suite();
    });
  }

  group('Dart port', () {
    tearDown(() {
      debugOperatingSystemOverride = null;
      clearPlatformLanguageAssociations();
      clearConfiguredLanguageAssociations();
    });

    test('getLanguageIds mirrors getMimeTypes', () {
      clearPlatformLanguageAssociations();
      clearConfiguredLanguageAssociations();
      registerPlatformLanguageAssociation(
        const ILanguageAssociation(
          id: 'monaco',
          extension: '.monaco',
          mime: 'text/monaco',
        ),
      );
      expect(getLanguageIds(file('foo.monaco')), ['monaco', 'plaintext']);
      expect(getLanguageIds(file('foo.other')), ['unknown']);
      // No path gives unknown, even with a first line.
      registerPlatformLanguageAssociation(
        ILanguageAssociation(
          id: 'sh',
          mime: 'text/sh',
          firstline: RegExp('#!'),
        ),
      );
      expect(getLanguageIds(file('run'), '#!/bin/sh'), ['sh', 'plaintext']);
      expect(getLanguageIds(null), ['unknown']);
      expect(getLanguageIds(null, '#!/bin/sh'), ['unknown']);
      expect(getMimeTypes(null), ['application/unknown']);
    });

    test('clearing', () {
      registerPlatformLanguageAssociation(
        const ILanguageAssociation(id: 'p', extension: '.p', mime: 'text/p'),
      );
      registerConfiguredLanguageAssociation(
        const ILanguageAssociation(id: 'c', extension: '.p', mime: 'text/c'),
      );
      expect(getLanguageIds(file('a.p')), ['c', 'plaintext']);
      clearConfiguredLanguageAssociations();
      expect(getLanguageIds(file('a.p')), ['p', 'plaintext']);
      clearPlatformLanguageAssociations();
      expect(getLanguageIds(file('a.p')), ['unknown']);
    });

    test('Windows file paths use win32 basename and separators', () {
      debugOperatingSystemOverride = OperatingSystem.windows;
      registerPlatformLanguageAssociation(
        const ILanguageAssociation(
          id: 'monaco',
          filepattern: '**/dir/*.mon',
          mime: 'text/monaco',
        ),
      );
      registerPlatformLanguageAssociation(
        const ILanguageAssociation(
          id: 'code',
          filename: 'codefile',
          mime: 'text/code',
        ),
      );
      expect(getLanguageIds(Uri.file(r'C:\Work\DIR\x.MON', windows: true)), [
        'monaco',
        'plaintext',
      ]);
      expect(getLanguageIds(Uri.file(r'C:\Work\CodeFile', windows: true)), [
        'code',
        'plaintext',
      ]);
    });
  });
}

void _suite() {
  test('Dynamically Register Text Mime', () {
    var guess = getMimeTypes(file('foo.monaco'));
    expect(guess, ['application/unknown']);

    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'monaco',
        extension: '.monaco',
        mime: 'text/monaco',
      ),
    );
    guess = getMimeTypes(file('foo.monaco'));
    expect(guess, ['text/monaco', 'text/plain']);

    guess = getMimeTypes(file('.monaco'));
    expect(guess, ['text/monaco', 'text/plain']);

    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'codefile',
        filename: 'Codefile',
        mime: 'text/code',
      ),
    );
    guess = getMimeTypes(file('Codefile'));
    expect(guess, ['text/code', 'text/plain']);

    guess = getMimeTypes(file('foo.Codefile'));
    expect(guess, ['application/unknown']);

    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'docker',
        filepattern: 'Docker*',
        mime: 'text/docker',
      ),
    );
    guess = getMimeTypes(file('Docker-debug'));
    expect(guess, ['text/docker', 'text/plain']);

    guess = getMimeTypes(file('docker-PROD'));
    expect(guess, ['text/docker', 'text/plain']);

    registerPlatformLanguageAssociation(
      ILanguageAssociation(
        id: 'niceregex',
        mime: 'text/nice-regex',
        firstline: RegExp('RegexesAreNice'),
      ),
    );
    guess = getMimeTypes(file('Randomfile.noregistration'), 'RegexesAreNice');
    expect(guess, ['text/nice-regex', 'text/plain']);

    guess = getMimeTypes(
      file('Randomfile.noregistration'),
      'RegexesAreNotNice',
    );
    expect(guess, ['application/unknown']);

    guess = getMimeTypes(file('Codefile'), 'RegexesAreNice');
    expect(guess, ['text/code', 'text/plain']);
  });

  test('Mimes Priority', () {
    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'monaco',
        extension: '.monaco',
        mime: 'text/monaco',
      ),
    );
    registerPlatformLanguageAssociation(
      ILanguageAssociation(
        id: 'foobar',
        mime: 'text/foobar',
        firstline: RegExp('foobar'),
      ),
    );

    var guess = getMimeTypes(file('foo.monaco'));
    expect(guess, ['text/monaco', 'text/plain']);

    guess = getMimeTypes(file('foo.monaco'), 'foobar');
    expect(guess, ['text/monaco', 'text/plain']);

    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'docker',
        filename: 'dockerfile',
        mime: 'text/winner',
      ),
    );
    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'docker',
        filepattern: 'dockerfile*',
        mime: 'text/looser',
      ),
    );
    guess = getMimeTypes(file('dockerfile'));
    expect(guess, ['text/winner', 'text/plain']);

    registerPlatformLanguageAssociation(
      ILanguageAssociation(
        id: 'azure-looser',
        mime: 'text/azure-looser',
        firstline: RegExp('azure'),
      ),
    );
    registerPlatformLanguageAssociation(
      ILanguageAssociation(
        id: 'azure-winner',
        mime: 'text/azure-winner',
        firstline: RegExp('azure'),
      ),
    );
    guess = getMimeTypes(file('azure'), 'azure');
    expect(guess, ['text/azure-winner', 'text/plain']);
  });

  test('Specificity priority 1', () {
    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'monaco2',
        extension: '.monaco2',
        mime: 'text/monaco2',
      ),
    );
    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'monaco2',
        filename: 'specific.monaco2',
        mime: 'text/specific-monaco2',
      ),
    );

    expect(getMimeTypes(file('specific.monaco2')), [
      'text/specific-monaco2',
      'text/plain',
    ]);
    expect(getMimeTypes(file('foo.monaco2')), ['text/monaco2', 'text/plain']);
  });

  test('Specificity priority 2', () {
    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'monaco3',
        filename: 'specific.monaco3',
        mime: 'text/specific-monaco3',
      ),
    );
    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'monaco3',
        extension: '.monaco3',
        mime: 'text/monaco3',
      ),
    );

    expect(getMimeTypes(file('specific.monaco3')), [
      'text/specific-monaco3',
      'text/plain',
    ]);
    expect(getMimeTypes(file('foo.monaco3')), ['text/monaco3', 'text/plain']);
  });

  test('Mimes Priority - Longest Extension wins', () {
    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'monaco',
        extension: '.monaco',
        mime: 'text/monaco',
      ),
    );
    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'monaco',
        extension: '.monaco.xml',
        mime: 'text/monaco-xml',
      ),
    );
    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'monaco',
        extension: '.monaco.xml.build',
        mime: 'text/monaco-xml-build',
      ),
    );

    var guess = getMimeTypes(file('foo.monaco'));
    expect(guess, ['text/monaco', 'text/plain']);

    guess = getMimeTypes(file('foo.monaco.xml'));
    expect(guess, ['text/monaco-xml', 'text/plain']);

    guess = getMimeTypes(file('foo.monaco.xml.build'));
    expect(guess, ['text/monaco-xml-build', 'text/plain']);
  });

  test('Mimes Priority - User configured wins', () {
    registerConfiguredLanguageAssociation(
      const ILanguageAssociation(
        id: 'monaco',
        extension: '.monaco.xnl',
        mime: 'text/monaco',
      ),
    );
    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'monaco',
        extension: '.monaco.xml',
        mime: 'text/monaco-xml',
      ),
    );

    final guess = getMimeTypes(file('foo.monaco.xnl'));
    expect(guess, ['text/monaco', 'text/plain']);
  });

  test('Mimes Priority - Pattern matches on path if specified', () {
    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'monaco',
        filepattern: '**/dot.monaco.xml',
        mime: 'text/monaco',
      ),
    );
    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'other',
        filepattern: '*ot.other.xml',
        mime: 'text/other',
      ),
    );

    final guess = getMimeTypes(file('/some/path/dot.monaco.xml'));
    expect(guess, ['text/monaco', 'text/plain']);
  });

  test('Mimes Priority - Last registered mime wins', () {
    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'monaco',
        filepattern: '**/dot.monaco.xml',
        mime: 'text/monaco',
      ),
    );
    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'other',
        filepattern: '**/dot.monaco.xml',
        mime: 'text/other',
      ),
    );

    final guess = getMimeTypes(file('/some/path/dot.monaco.xml'));
    expect(guess, ['text/other', 'text/plain']);
  });

  test('Data URIs', () {
    registerPlatformLanguageAssociation(
      const ILanguageAssociation(
        id: 'data',
        extension: '.data',
        mime: 'text/data',
      ),
    );

    // Upstream: URI.parse(`data:;label:something.data;description:data,`).
    // Dart's Uri.parse rejects that form, so the components are given.
    expect(
      getMimeTypes(
        Uri(scheme: 'data', path: ';label:something.data;description:data,'),
      ),
      ['text/data', 'text/plain'],
    );
  });

  test('Shebang detection for TypeScript runtimes', () {
    registerPlatformLanguageAssociation(
      ILanguageAssociation(
        id: 'typescript',
        mime: 'text/typescript',
        firstline: RegExp(r'^#!.*\b(deno|bun|ts-node)\b'),
      ),
    );

    // Deno shebangs
    expect(getMimeTypes(file('script'), '#!/usr/bin/env deno'), [
      'text/typescript',
      'text/plain',
    ]);
    expect(getMimeTypes(file('script'), '#!/usr/bin/env -S deno -A'), [
      'text/typescript',
      'text/plain',
    ]);
    expect(getMimeTypes(file('script'), '#!/usr/bin/deno'), [
      'text/typescript',
      'text/plain',
    ]);

    // Bun shebangs
    expect(getMimeTypes(file('script'), '#!/usr/bin/env bun'), [
      'text/typescript',
      'text/plain',
    ]);
    expect(getMimeTypes(file('script'), '#!/usr/bin/env -S bun run'), [
      'text/typescript',
      'text/plain',
    ]);

    // ts-node shebangs
    expect(getMimeTypes(file('script'), '#!/usr/bin/env ts-node'), [
      'text/typescript',
      'text/plain',
    ]);
    expect(getMimeTypes(file('script'), '#!/usr/bin/env -S ts-node --esm'), [
      'text/typescript',
      'text/plain',
    ]);

    // Should NOT match other shebangs
    expect(getMimeTypes(file('script'), '#!/usr/bin/env node'), [
      'application/unknown',
    ]);
    expect(getMimeTypes(file('script'), '#!/usr/bin/env python'), [
      'application/unknown',
    ]);
    expect(getMimeTypes(file('script'), '#!/bin/bash'), [
      'application/unknown',
    ]);
  });
}
