import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import '../git/git_model.dart';
import '../lsp/lsp_protocol.dart';

/// Decorates files and folders in the file tree with problem indicators
/// (error red, warning yellow, info blue) and problem counts / dots,
/// matching VS Code and Cursor behavior.
class IdeProblemDecorations {
  IdeProblemDecorations(
    Map<String, List<LspDiagnostic>> allDiagnostics, {
    p.Context? paths,
  }) : _paths = paths ?? p.context {
    for (final MapEntry(key: path, value: diagnostics) in allDiagnostics.entries) {
      final problems = [
        for (final d in diagnostics)
          if (d.severity != LspDiagnosticSeverity.hint) d,
      ];
      if (problems.isEmpty) continue;

      var errors = 0;
      var warnings = 0;
      var infos = 0;
      var maxSeverity = LspDiagnosticSeverity.information;

      for (final p in problems) {
        switch (p.severity) {
          case LspDiagnosticSeverity.error:
            errors++;
            maxSeverity = LspDiagnosticSeverity.error;
          case LspDiagnosticSeverity.warning:
            warnings++;
            if (maxSeverity != LspDiagnosticSeverity.error) {
              maxSeverity = LspDiagnosticSeverity.warning;
            }
          case LspDiagnosticSeverity.information:
            infos++;
          case LspDiagnosticSeverity.hint:
            break;
        }
      }

      final count = problems.length;
      final tooltip = _tooltip(errors, warnings, infos);

      final canon = _canonicalize(path, _paths);
      _files[canon] = (maxSeverity, count, tooltip);
      if (_isWindows) {
        _files[canon.toLowerCase()] = (maxSeverity, count, tooltip);
      }

      var folder = _paths.dirname(canon);
      while (true) {
        final current = _folders[folder];
        if (current == null || maxSeverity.index < current.index) {
          _folders[folder] = maxSeverity;
          if (_isWindows) {
            _folders[folder.toLowerCase()] = maxSeverity;
          }
        }
        final parent = _paths.dirname(folder);
        if (parent == folder) break;
        folder = parent;
      }
    }
  }

  final p.Context _paths;
  final Map<String, (LspDiagnosticSeverity, int, String)> _files = {};
  final Map<String, LspDiagnosticSeverity> _folders = {};

  bool get _isWindows =>
      _paths.style == p.Style.windows || (!kIsWeb && Platform.isWindows);

  static String _canonicalize(String path, p.Context paths) {
    var norm = paths.normalize(path);
    if (paths.style == p.Style.windows) {
      norm = norm.replaceAll('/', '\\');
      if (norm.length >= 2 && norm[1] == ':') {
        norm = norm[0].toUpperCase() + norm.substring(1);
      }
    }
    return norm;
  }

  static String _tooltip(int errors, int warnings, int infos) {
    final parts = [
      if (errors > 0) errors == 1 ? '1 error' : '$errors errors',
      if (warnings > 0) warnings == 1 ? '1 warning' : '$warnings warnings',
      if (infos > 0 && errors == 0 && warnings == 0)
        infos == 1 ? '1 info' : '$infos infos',
    ];
    return parts.join(', ');
  }

  /// Returns [IdeGitDecoration] for [path] if it has problems, else null.
  IdeGitDecoration? file(String path) {
    final canon = _canonicalize(path, _paths);
    final match =
        _files[canon] ?? (_isWindows ? _files[canon.toLowerCase()] : null);
    if (match == null) return null;
    final (severity, count, tooltip) = match;
    final colorId = switch (severity) {
      LspDiagnosticSeverity.error => 'list.errorForeground',
      LspDiagnosticSeverity.warning => 'list.warningForeground',
      _ => 'problemsInfoIcon.foreground',
    };
    return IdeGitDecoration(
      colorId: colorId,
      letter: '$count',
      tooltip: tooltip,
    );
  }

  /// Returns [IdeGitDecoration] for [path] if any file under it has problems, else null.
  IdeGitDecoration? folder(String path) {
    final canon = _canonicalize(path, _paths);
    final severity =
        _folders[canon] ?? (_isWindows ? _folders[canon.toLowerCase()] : null);
    if (severity == null) return null;
    final colorId = switch (severity) {
      LspDiagnosticSeverity.error => 'list.errorForeground',
      LspDiagnosticSeverity.warning => 'list.warningForeground',
      _ => 'problemsInfoIcon.foreground',
    };
    final tooltip = switch (severity) {
      LspDiagnosticSeverity.error => 'Contains errors',
      LspDiagnosticSeverity.warning => 'Contains warnings',
      _ => 'Contains problems',
    };
    return IdeGitDecoration(
      colorId: colorId,
      letter: '•',
      tooltip: tooltip,
    );
  }
}
