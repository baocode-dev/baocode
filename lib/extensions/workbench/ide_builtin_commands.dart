// The built-in commands' ports on the IDE ([registerWorkbenchBuiltinCommands]):
// opening resources (files, untitled and virtual documents, diffs), the
// views, the settings, the active editor's typing and cursor commands,
// references and locations, and installing extensions; and the editor on
// screen typing through the `type` command while an extension overrides
// it (VSCodeVim).
//
// Follows VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/browser/parts/editor/editorCommands.ts (`_workbench.open`
// opening any resource the workbench can read, `_workbench.diff`),
// src/vs/editor/browser/coreCommands.ts (`EditorHandlerCommand`: the
// focused editor's `trigger`; `CursorMove` and `RevealLine` with their
// arguments), src/vs/editor/browser/widget/codeEditor/codeEditorWidget.ts
// (`_createView`'s command delegate: the keyboard's typing through the
// `type` command), src/vs/editor/contrib/gotoSymbol/browser/goToCommands.ts
// (`editor.action.goToLocations`: one location opens, several peek, none
// says [noResultsMessage]).
//
// Deviations:
// - A virtual document (a content provider's, a file system provider's)
//   opens read-only in a tab of its own; diffs of two of them too.
// - References and peeked locations show in the References panel (BaoCode
//   has no peek widget).
// - `cursorMove` moves by logical lines (`wrappedLine` is `line`) and
//   `viewPort*` targets use the lines on screen.
// - Only the keyboard's typing goes through `type`: an input method's
//   composition, paste and cut are the editor's.

import 'dart:async';
import 'dart:convert';

import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/services.dart' show TextSelection;
import 'package:path/path.dart' as p;

import '../../ide/ide_commands.dart';
import '../../ide/ide_editor_views.dart';
import '../../ide/ide_notifications.dart';
import '../../ide/ide_workspace.dart';
import '../../ide/lsp/lsp_protocol.dart';
import '../../l10n/l10n.dart';
import '../commands/command_arguments.dart';
import '../commands/extension_command_registry.dart';
import '../commands/type_command_interceptor.dart';
import '../commands/workbench_builtin_commands.dart';
import '../editors/editor_ports.dart';
import '../files/file_service.dart';
import '../gallery/extension_management_backend.dart';
import '../views/views_service.dart';
import 'ide_documents.dart';
import 'ide_text_editors.dart';

final class IdeBuiltinCommands
    implements
        WorkbenchCommandsPort,
        EditorCommandsPort,
        ExtensionManagementCommandsPort {
  IdeBuiltinCommands({
    required this.workspace,
    required this.editors,
    required this.documents,
    required this.files,
    required this.views,
    required this.commands,
    required this.management,
    required this.openUri,
    this.appScheme,
  }) : _typing = TypeCommandInterceptor(commands) {
    workspace.editorViews.addListener(_shownChanged);
    _shownChanged();
  }

  final IdeWorkspace workspace;
  final IdeTextEditors editors;
  final IdeDocumentsPort documents;
  final FileService files;
  final ExtensionViewsService views;
  final ExtensionCommandRegistry commands;
  final ExtensionManagementBackend management;

  /// Opens an `http(s):`, `mailto:` or the app's own URI outside the
  /// editor.
  final Future<void> Function(String target) openUri;

  /// The app's own URI scheme (`baocode`), opened by its URL handler.
  final String? appScheme;

  /// Shows locations in the References panel, titled (the workbench sets
  /// it while it shows).
  void Function(String title, List<CommandLocation> locations)?
  onShowReferences;

  /// Reveals a path in the Explorer (the workbench sets it).
  void Function(String path)? onRevealInExplorer;

  /// Opens a folder, or asks for one (the workbench sets it).
  Future<void> Function(String? path, {required bool forceNewWindow})?
  onOpenFolder;

  /// Highlights the focused editor's occurrences again (the extensions'
  /// editor features set it).
  void Function()? onTriggerWordHighlight;

  /// Whether an installed extension runs only once the extensions restart
  /// (the extension host sets it).
  bool Function(InstalledExtension installed)? needsRestart;

  /// Restarts the extensions (the extension host sets it).
  Future<void> Function()? restartExtensions;

  /// The app's strings.
  AppLocalizations Function() l10n = () => englishLocalizations;

  final TypeCommandInterceptor _typing;
  IdeEditorView? _shown;

  // --- the keyboard's typing through `type`

  void _shownChanged() {
    final view = workspace.editorViews.active;
    if (identical(view, _shown)) return;
    _shown?.controller.typeOverride = null;
    _shown = view;
    view?.controller.typeOverride = _typing.type;
  }

  /// A BaoCode command by id (not the built-in registered over it).
  IdeCommand? _app(String id) => commands.appCommands?.call()[id];

  /// The focused editor (`getFocusedCodeEditor`), when it can be edited.
  IdeEditorView? get _focused {
    final view = workspace.editorViews.active;
    if (view == null || !view.hasFocus()) return null;
    return view;
  }

  IdeEditorView? get _editable {
    final view = _focused;
    return view == null || view.document.readRevision != null ? null : view;
  }

  // --- WorkbenchCommandsPort

  /// The local path of [resource], when it is a file here.
  String? _localPath(VsUri resource) => switch (resource.scheme) {
    'file' || 'vscode-userdata' => resource.fsPath(),
    _ => null,
  };

  /// The text of [resource]: a file's, a content provider's or a file
  /// system provider's.
  Future<String> _read(VsUri resource) async {
    if (_localPath(resource) case final path?) {
      return workspace.files.read(path);
    }
    final virtual = await documents.readVirtual(resource);
    if (virtual != null) return virtual;
    if (await files.canHandleResource(resource)) {
      return utf8.decode(await files.readFile(resource), allowMalformed: true);
    }
    throw StateError('Unable to resolve resource $resource');
  }

  String _title(VsUri resource) => p.posix.basename(resource.path);

  @override
  Future<void> openEditor(
    VsUri resource, {
    int? column,
    EditorOpenOptions? options,
    String? label,
  }) async {
    final preserveFocus = options?.preserveFocus ?? options?.inactive ?? false;
    final selection = switch (options?.selection) {
      final r? => EditorSelectionValue(
        anchorLine: r.startLineNumber,
        anchorColumn: r.startColumn,
        activeLine: r.endLineNumber,
        activeColumn: r.endColumn,
      ),
      null => null,
    };
    if (_localPath(resource) case final path?) {
      await editors.showTextDocument(
        path,
        preserveFocus: preserveFocus,
        selection: selection,
      );
      return;
    }
    if (resource.scheme == 'untitled') {
      final open = workspace.documents.any(
        (d) => d.isUntitled && d.path == resource.path,
      );
      if (open) {
        workspace.select(resource.path);
      } else {
        workspace.newUntitled();
      }
      return;
    }
    await workspace.openRevision(
      resource.path,
      label: label ?? '${_title(resource)} (${resource.scheme})',
      read: () => _read(resource),
    );
  }

  @override
  Future<void> openExternal(String target) => openUri(target);

  @override
  bool isExternal(VsUri resource) => resource.scheme == appScheme;

  @override
  Future<void> openDiff(
    VsUri left,
    VsUri right, {
    String? label,
    String? description,
    int? column,
    EditorOpenOptions? options,
  }) async {
    final title = label ?? '${_title(left)} ↔ ${_title(right)}';
    final rightPath = _localPath(right);
    await workspace.openDiff(
      rightPath ?? right.path,
      label: title,
      original: () => _read(left),
      modified: rightPath == null ? () => _read(right) : null,
    );
  }

  @override
  Future<void> openFolder(VsUri? folder, {bool forceNewWindow = false}) async {
    final open = onOpenFolder;
    if (open != null) {
      await open(
        folder == null ? null : _localPath(folder) ?? folder.path,
        forceNewWindow: forceNewWindow,
      );
    } else {
      _app('workbench.action.files.openFolder')?.run();
    }
  }

  @override
  Future<void> openSettings({String? query}) async =>
      _app('workbench.action.openSettings')?.run();

  @override
  Future<void> showViewContainer(String id) async {
    if (views.contributions.container(id) != null) {
      await views.openViewContainer(id, focus: true);
    } else {
      _app(id)?.run();
    }
  }

  @override
  void focusActiveEditorGroup() => workspace.editorViews.active?.focus();

  @override
  Future<void> revealInExplorer(VsUri resource) async {
    final path = _localPath(resource);
    if (path != null) onRevealInExplorer?.call(path);
  }

  // --- EditorCommandsPort

  @override
  void type(String text) {
    if (text.isEmpty) return;
    _editable?.controller.typeDefault(text);
  }

  @override
  void replacePreviousChar(String text, int replaceCharCnt) => _editable
      ?.controller
      .compositionType(text, replacePrevCharCnt: replaceCharCnt);

  @override
  void compositionType(
    String text, {
    int replacePrevCharCnt = 0,
    int replaceNextCharCnt = 0,
    int positionDelta = 0,
  }) => _editable?.controller.compositionType(
    text,
    replacePrevCharCnt: replacePrevCharCnt,
    replaceNextCharCnt: replaceNextCharCnt,
    positionDelta: positionDelta,
  );

  @override
  void cursorMove(Map<String, Object?> args) {
    final view = _focused;
    if (view == null) return;
    final to = '${args['to'] ?? ''}';
    final by = '${args['by'] ?? 'line'}';
    final value = switch (args['value']) {
      final num n when n > 0 => n.toInt(),
      _ => 1,
    };
    final select = args['select'] == true;
    final controller = view.controller;
    final snapshot = view.document.model.snapshot;
    final lines = snapshot.lineCount;
    String lineText(int line) {
      final start = snapshot.offsetAtPosition(Position(line, 1));
      final end = line < lines
          ? snapshot.offsetAtPosition(Position(line + 1, 1))
          : view.document.text.length;
      return view.document.text
          .substring(start, end)
          .replaceAll(RegExp(r'\r?\n$'), '');
    }

    final visible = view.visibleLines();
    final halfPage = visible == null
        ? 10
        : ((visible.last - visible.first + 1) / 2).floor().clamp(1, lines);
    Position target(Position from) {
      final line = from.lineNumber;
      switch (to) {
        case 'left':
          final n = by == 'halfLine'
              ? (lineText(line).length / 2).floor() * value
              : value;
          return snapshot.positionAtOffset(
            (snapshot.offsetAtPosition(from) - n).clamp(
              0,
              view.document.text.length,
            ),
          );
        case 'right':
          final n = by == 'halfLine'
              ? (lineText(line).length / 2).floor() * value
              : value;
          return snapshot.positionAtOffset(
            (snapshot.offsetAtPosition(from) + n).clamp(
              0,
              view.document.text.length,
            ),
          );
        case 'up' || 'down':
          final rows = by == 'halfLine' ? halfPage * value : value;
          final next = (line + (to == 'up' ? -rows : rows)).clamp(1, lines);
          return Position(
            next,
            from.column.clamp(1, lineText(next).length + 1),
          );
        case 'prevBlankLine' || 'nextBlankLine':
          final step = to == 'prevBlankLine' ? -1 : 1;
          var next = line;
          for (var i = 0; i < value; i++) {
            do {
              next += step;
            } while (next > 1 &&
                next < lines &&
                lineText(next).trim().isNotEmpty);
          }
          return Position(next.clamp(1, lines), 1);
        case 'wrappedLineStart':
          return Position(line, 1);
        case 'wrappedLineEnd':
          return Position(line, lineText(line).length + 1);
        case 'wrappedLineColumnCenter':
          return Position(line, (lineText(line).length / 2).floor() + 1);
        case 'wrappedLineFirstNonWhitespaceCharacter':
          final text = lineText(line);
          final first = text.indexOf(RegExp(r'\S'));
          return Position(line, (first < 0 ? text.length : first) + 1);
        case 'wrappedLineLastNonWhitespaceCharacter':
          final text = lineText(line);
          final last = text.lastIndexOf(RegExp(r'\S'));
          return Position(line, (last < 0 ? 0 : last) + 1);
        case 'viewPortTop':
          return Position(
            ((visible?.first ?? 1) + value - 1).clamp(1, lines),
            1,
          );
        case 'viewPortBottom':
          return Position(
            ((visible?.last ?? lines) - value + 1).clamp(1, lines),
            1,
          );
        case 'viewPortCenter':
          return Position(
            visible == null
                ? line
                : ((visible.first + visible.last) / 2).floor().clamp(1, lines),
            1,
          );
        case 'viewPortIfOutside':
          if (visible == null ||
              (line >= visible.first && line <= visible.last)) {
            return from;
          }
          return Position(
            line < visible.first ? visible.first : visible.last,
            1,
          );
      }
      return from;
    }

    controller.setSelections([
      for (final s in controller.selections)
        () {
          final active = snapshot.positionAtOffset(s.extentOffset);
          final offset = snapshot.offsetAtPosition(target(active));
          return TextSelection(
            baseOffset: select ? s.baseOffset : offset,
            extentOffset: offset,
          );
        }(),
    ]);
    controller.revealSelection();
  }

  @override
  void revealLine(int lineNumber, String at) {
    final view = workspace.editorViews.active;
    if (view == null) return;
    final snapshot = view.document.model.snapshot;
    final line = (lineNumber + 1).clamp(1, snapshot.lineCount);
    final offset = snapshot.offsetAtPosition(Position(line, 1));
    view.reveal(offset, offset, center: at == 'center');
  }

  @override
  Future<void> showReferences(
    VsUri uri,
    CommandPosition position,
    List<CommandLocation> locations,
  ) async {
    onShowReferences?.call(
      locations.length == 1 ? '1 reference' : '${locations.length} references',
      locations,
    );
  }

  @override
  Future<void> goToLocations(
    VsUri uri,
    CommandPosition position,
    List<CommandLocation> locations, {
    String? multiple,
    String? noResultsMessage,
  }) async {
    if (locations.isEmpty) {
      if (noResultsMessage != null) {
        workspace.notifications.notify(IdeSeverity.info, noResultsMessage);
      }
      return;
    }
    if (locations.length == 1 || multiple == 'goto') {
      final first = locations.first;
      final path = _localPath(first.uri);
      if (path != null) {
        await workspace.openAt(
          path,
          LspRange(
            LspPosition(
              first.range.startLineNumber - 1,
              first.range.startColumn - 1,
            ),
            LspPosition(
              first.range.endLineNumber - 1,
              first.range.endColumn - 1,
            ),
          ),
        );
      } else {
        await openEditor(first.uri);
      }
      if (multiple != 'gotoAndPeek' || locations.length == 1) return;
    }
    await showReferences(uri, position, locations);
  }

  @override
  void triggerSuggest() => _app('editor.action.triggerSuggest')?.run();

  @override
  void triggerParameterHints() =>
      _app('editor.action.triggerParameterHints')?.run();

  @override
  void triggerWordHighlight() => onTriggerWordHighlight?.call();

  // --- ExtensionManagementCommandsPort

  @override
  Future<void> install({
    String? id,
    VsUri? vsix,
    Map<String, Object?>? options,
  }) async {
    if (vsix != null) {
      await management.install(_localPath(vsix) ?? vsix.path);
      return;
    }
    if (id == null) return;
    final at = id.lastIndexOf('@');
    await management.installFromGallery(
      at > 0 ? id.substring(0, at) : id,
      version: at > 0 ? id.substring(at + 1) : null,
      preRelease: options?['installPreReleaseVersion'] == true,
    );
  }

  @override
  Future<void> uninstall(String id) => management.uninstall(id);

  @override
  Future<void> installVsixs(List<VsUri> vsixs) async {
    // All of them, then the first failure (`Promise.allSettled`).
    final installed = await Future.wait([
      for (final vsix in vsixs)
        management.install(
          _localPath(vsix) ?? vsix.path,
          options: const ExtensionInstallOptions(installGivenVersion: true),
        ),
    ]);
    final restart = installed.any((e) => needsRestart?.call(e) ?? false);
    final strings = l10n();
    final several = vsixs.length > 1;
    if (restart) {
      workspace.notifications.notify(
        IdeSeverity.info,
        several
            ? strings.extInstallVsixsRestart
            : strings.extInstallVsixRestart,
        primary: [
          IdeNotificationAction(
            strings.extRestartExtensions,
            () => unawaited(restartExtensions?.call()),
          ),
        ],
      );
    } else {
      workspace.notifications.notify(
        IdeSeverity.info,
        several ? strings.extInstallVsixsDone : strings.extInstallVsixDone,
      );
    }
  }

  void dispose() {
    workspace.editorViews.removeListener(_shownChanged);
    _shown?.controller.typeOverride = null;
    _shown = null;
    _typing.dispose();
  }
}
