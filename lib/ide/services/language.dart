// The workspace's language servers as the workbench shows them (upstream's
// language features with `LanguageStatusService` and the extension
// recommendations, `FileBasedRecommendations`): the active file's symbols
// (the outline, the breadcrumbs, Go to Symbol), the servers' edits applied,
// their missing ones recommended and started once installed.

import 'dart:async';

import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import '../ide_notifications.dart';
import '../ide_status_bar.dart' show IdeLanguageNames;
import '../ide_workspace.dart';
import '../lsp/language_features.dart';
import '../lsp/lsp_protocol.dart';
import '../lsp_ui/document_symbols.dart';
import '../lsp_ui/lsp_convert.dart';
import '../workbench/contributions.dart';

class LanguageService extends ChangeNotifier {
  LanguageService({
    required this.host,
    required this._caret,
    required this._applyEdit,
    required this._ignored,
    this.onIgnore,
  });

  final WorkbenchHost host;

  /// Where the active editor's caret is.
  final Position Function() _caret;

  /// [edit] applied, as a rename's: in the editor where it is open.
  final Future<bool> Function(LspWorkspaceEdit edit) _applyEdit;

  /// The servers not to recommend.
  final Set<String> Function() _ignored;

  /// A server not to recommend again.
  final void Function(String id)? onIgnore;

  IdeWorkspace? _workspace;
  LanguageFeatures? _languages;
  IdeDocumentSymbols? _symbols;
  StreamSubscription<LspApplyEditRequest>? _editRequests;

  /// The servers recommended this session.
  final Set<String> _recommended = {};

  /// Whether the display language can be read: recommendations wait for
  /// it.
  bool _localized = false;

  /// The workspace's language features; none where it has no servers.
  LanguageFeatures? get languages => _languages;

  /// The active file's symbols.
  IdeDocumentSymbols? get symbols => _symbols;

  /// Follows [workspace]'s servers.
  void attach(IdeWorkspace workspace) {
    _workspace = workspace;
    final languages = _languages = workspace.languages;
    _symbols = languages == null ? null : IdeDocumentSymbols(languages)
      ?..addListener(notifyListeners);
    languages?.addListener(_languagesChanged);
    _editRequests = languages?.workspaceEdits.listen(_applyEditRequest);
  }

  void detach() {
    _languages?.removeListener(_languagesChanged);
    unawaited(_editRequests?.cancel());
    _editRequests = null;
    _symbols
      ?..removeListener(notifyListeners)
      ..dispose();
    _symbols = null;
    _languages = null;
    _workspace = null;
  }

  void _languagesChanged() {
    if (host.context == null) return;
    recommendServers();
    final symbols = _symbols;
    if (symbols != null && !symbols.loaded) symbols.refresh();
    notifyListeners();
  }

  /// The active document, or its text, changed: its symbols follow.
  void documentChanged() => _symbols?.update(_workspace?.active);

  /// The display language can be read: what waited for it is done.
  void localized() {
    if (_localized) return;
    _localized = true;
    recommendServers();
  }

  /// `workspace/applyEdit` from a server: applied like a rename.
  Future<void> _applyEditRequest(LspApplyEditRequest request) async {
    try {
      request.complete(await _applyEdit(request.edit));
    } catch (error) {
      request.complete(false);
      host.report(error);
    }
  }

  /// The caret's place, as the servers count.
  LspPosition get caret {
    final caret = _caret();
    return LspPosition(caret.lineNumber - 1, caret.column - 1);
  }

  /// The symbols around the caret, outermost first (the breadcrumbs').
  List<LspDocumentSymbol> get symbolPath {
    final symbols = _symbols;
    final active = _workspace?.active;
    if (symbols == null || active == null || symbols.path != active.path) {
      return const [];
    }
    return ideSymbolPathAt(symbols.symbols, caret);
  }

  /// [symbol] of the active file shown.
  void revealSymbol(LspDocumentSymbol symbol) {
    final path = _workspace?.active?.path;
    if (path == null) return;
    unawaited(host.openLocation(IdeLocation(path, symbol.selectionRange)));
  }

  /// Recommends installing the active file's missing language servers,
  /// once a session each, as VS Code recommends a language's extension
  /// (`FileBasedRecommendations`): a notification with Install.
  void recommendServers() {
    final languages = _languages;
    final path = _workspace?.active?.path;
    if (!_localized || languages == null || path == null) return;
    for (final status in languages.statusFor(path)) {
      if (status.state == LanguageServerState.missing &&
          status.installable &&
          status.missingRuntime == null &&
          !_ignored().contains(status.serverId) &&
          _recommended.add(status.serverId)) {
        // Only in the notification center: a toast for every file opened
        // is too much.
        _recommendServer(status, path);
      }
    }
  }

  void _recommendServer(LanguageServerStatus status, String path) {
    final context = host.context;
    final workspace = _workspace;
    if (context == null || workspace == null) return;
    final id = status.serverId;
    final language = IdeLanguageNames.forPath(path);
    final l10n = context.l10n;
    workspace.notifications.notify(
      IdeSeverity.info,
      l10n.wbRecommendServer(id, language),
      sticky: true,
      silent: true,
      primary: [
        IdeNotificationAction(
          l10n.extInstall,
          () => unawaited(install(id, path)),
        ),
      ],
      secondary: [
        IdeNotificationAction(
          l10n.wbDontShowAgainServer,
          () => onIgnore?.call(id),
        ),
      ],
    );
  }

  /// Installs the server [id] that [path] wants.
  Future<void> install(String id, String path) async {
    try {
      await _languages?.install(id, path: path);
    } catch (error) {
      host.report(error);
    }
  }

  /// Starts the open files' servers named [id], and those limited to some
  /// of its features (`ruff#only=format`), now that it is installed.
  void startServer(String id) {
    final languages = _languages;
    final workspace = _workspace;
    if (languages == null || workspace == null) return;
    final ids = {
      id,
      for (final doc in workspace.documents)
        for (final status in languages.statusFor(doc.path))
          if (status.serverId.split('#').first == id) status.serverId,
    };
    ids.forEach(languages.retry);
  }

  /// The servers the open files want and could install, less those not to
  /// recommend: the Extensions view's Recommended pane.
  Set<String> recommendedServers() {
    final languages = _languages;
    final workspace = _workspace;
    if (languages == null || workspace == null) return const {};
    return {
      for (final doc in workspace.documents)
        for (final status in languages.statusFor(doc.path))
          if (status.state == LanguageServerState.missing &&
              status.installable &&
              !_ignored().contains(status.serverId))
            status.serverId.split('#').first,
    };
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }
}
