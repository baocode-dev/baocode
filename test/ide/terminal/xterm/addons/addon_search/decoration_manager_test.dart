// Copyright (c) 2026 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See
// lib/ide/terminal/xterm/addons/addon_search/LICENSE.
// Adapted from xterm.js addons/addon-search/src/DecorationManager.test.ts
// (c58ea36).
//
// Upstream runs in the browser terminal: this runs on [SearchTestTerminal],
// whose `registerDecorationMock` stands in for assigning
// `terminal.registerDecoration`. The store is disposed after each test.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/addons/addon_search/decoration_manager.dart';
import 'package:baocode/ide/terminal/xterm/addons/addon_search/search_engine.dart';
import 'package:baocode/ide/terminal/xterm/addons/addon_search/search_line_cache.dart';
import 'package:baocode/ide/terminal/xterm/addons/addon_search/typings/addon_search.dart';
import 'package:baocode/ide/terminal/xterm/common/lifecycle.dart';
import 'package:baocode/ide/terminal/xterm/typings/xterm.dart'
    show IDecorationOptions, ITerminalOptions;

import 'search_test_terminal.dart';

Future<void> writeP(SearchTestTerminal terminal, String data) {
  final c = Completer<void>();
  terminal.write(data, c.complete);
  return c.future;
}

void main() {
  group('DecorationManager', () {
    late DisposableStore store;
    late SearchTestTerminal terminal;
    late DecorationManager decorationManager;

    setUp(() {
      store = DisposableStore();
      terminal = store.add(
        SearchTestTerminal(ITerminalOptions(cols: 10, rows: 5)),
      );
      decorationManager = store.add(DecorationManager(terminal));
    });

    tearDown(() {
      store.dispose();
    });

    test('should split highlight decorations for a wrapped match', () async {
      await writeP(terminal, '0123456789abcde');
      final searchEngine = SearchEngine(
        terminal,
        store.add(SearchLineCache(terminal)),
      );
      final match = searchEngine.find('9abc', 0, 0);
      expect(match, isNotNull);

      final decorationOptions = <IDecorationOptions>[];
      final registerDecoration = terminal.decorationService.registerDecoration;
      terminal.registerDecorationMock = (IDecorationOptions options) {
        decorationOptions.add(options);
        return registerDecoration(options);
      };

      final options = ISearchDecorationOptions(
        matchOverviewRuler: '#ff0000',
        activeMatchColorOverviewRuler: '#00ff00',
      );
      decorationManager.createHighlightDecorations([match!], options);

      expect(decorationOptions.length, 2);
      expect(decorationOptions[0].x, 9);
      expect(decorationOptions[0].width, 1);
      expect(decorationOptions[1].x, 0);
      expect(decorationOptions[1].width, 3);

      final withOverviewRuler = decorationOptions
          .where((o) => o.overviewRulerOptions != null)
          .toList();
      expect(withOverviewRuler.length, 2);
    });

    test('should only add one overview ruler marker per buffer line', () async {
      await writeP(terminal, 'abcdefghij');
      final decorationOptions = <IDecorationOptions>[];
      final registerDecoration = terminal.decorationService.registerDecoration;
      terminal.registerDecorationMock = (IDecorationOptions options) {
        decorationOptions.add(options);
        return registerDecoration(options);
      };

      final options = ISearchDecorationOptions(
        matchOverviewRuler: '#ff0000',
        activeMatchColorOverviewRuler: '#00ff00',
      );
      decorationManager.createHighlightDecorations([
        ISearchResult(term: 'a', col: 0, row: 0, size: 1),
        ISearchResult(term: 'f', col: 5, row: 0, size: 1),
      ], options);

      final withOverviewRuler = decorationOptions
          .where((o) => o.overviewRulerOptions != null)
          .toList();
      expect(withOverviewRuler.length, 1);
      expect(withOverviewRuler[0].x, 0);
    });
  });
}
