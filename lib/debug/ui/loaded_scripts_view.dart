// The Loaded Scripts view: the sources the focused session's adapter has
// loaded (`loadedSources`, then `loadedSource` events), by path.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/browser/loadedScriptsView.ts.
//
// Deviations: a flat list sorted by path rather than a folder tree.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_list.dart';
import '../base/event.dart';
import '../common/debug_source.dart';
import '../common/debug_types.dart';
import '../service/debug_service.dart';
import '../session/debug_session.dart';
import 'debug_strings.dart';
import 'debug_widgets.dart';

class LoadedScriptsView extends StatefulWidget {
  const LoadedScriptsView({super.key, required this.service});

  final DebugService service;

  @override
  State<LoadedScriptsView> createState() => _LoadedScriptsViewState();
}

class _LoadedScriptsViewState extends State<LoadedScriptsView> {
  final DisposableStore _listeners = DisposableStore();
  DebugDisposable? _sessionListener;
  DebugSession? _session;
  final Map<String, Source> _sources = {};
  String? _selected;

  @override
  void initState() {
    super.initState();
    _listeners.add(widget.service.viewModel.onDidFocusSession(_focus));
    _focus(widget.service.viewModel.focusedSession);
  }

  @override
  void dispose() {
    _sessionListener?.dispose();
    _listeners.dispose();
    super.dispose();
  }

  Future<void> _focus(DebugSession? session) async {
    if (session == _session) return;
    _sessionListener?.dispose();
    _sessionListener = null;
    _session = session;
    _sources.clear();
    if (mounted) setState(() {});
    if (session == null || !session.capabilities.flag('supportsLoadedSourcesRequest')) return;
    _sessionListener = session.onDidLoadedSource.listen((event) {
      final key = event.source.uri.toString();
      setState(() {
        if (event.reason == 'removed') {
          _sources.remove(key);
        } else {
          _sources[key] = event.source;
        }
      });
    });
    try {
      final sources = await session.getLoadedSources();
      if (!mounted || session != _session) return;
      setState(() {
        for (final s in sources) {
          _sources[s.uri.toString()] = s;
        }
      });
    } on Object {
      // The adapter has none to give.
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = DebugStrings.of(context);
    final sources = _sources.values.toList()..sort((a, b) => a.uri.path.compareTo(b.uri.path));
    if (sources.isEmpty) return DebugEmptyMessage(s.noLoadedScripts);
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: sources.length,
      itemExtent: IdeListColors.rowHeight,
      itemBuilder: (context, index) {
        final source = sources[index];
        final path = source.uri.path;
        final slash = path.lastIndexOf('/');
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: IdeListColors.inset),
          child: IdeListRow(
            selected: _selected == source.uri.toString(),
            onTap: () {
              setState(() => _selected = source.uri.toString());
              final session = _session;
              if (session == null) return;
              unawaited(
                source.uri.scheme == debugScheme
                    ? widget.service.host.openDebugSource(session, source.uri)
                    : widget.service.host.openEditor(source.uri),
              );
            },
            builder: (context, hovered) => Padding(
              padding: const EdgeInsets.only(left: 16),
              child: IdeResourceLabel(
                name: source.name,
                description: slash > 0 ? path.substring(0, slash) : null,
              ),
            ),
          ),
        );
      },
    );
  }
}
