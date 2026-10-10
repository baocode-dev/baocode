// The editor features extensions drive, one set per open document: what a
// future extension host's `vscode.window`/`languages` calls paint through.
// The workbench creates them (see [IdeEditorFeaturesRegistry]) and gives
// them to the editor surface; nothing here depends on the host.

import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:bao_editor/monaco/flutter/editor_decorations.dart'
    show EditorGutterIcon;

import 'package:bao_editor/monaco/flutter/editor_code_lens.dart';
// The features' public types, for the workbench that drives them.
export 'package:bao_editor/monaco/flutter/editor_code_lens.dart'
    show EditorCodeLens, EditorCodeLensColors, EditorCommand;
export 'package:bao_editor/monaco/flutter/editor_decoration_types.dart'
    show
        EditorDecorationsController,
        EditorDecorationTheme,
        EditorDecorationTypeRegistry;
export 'package:bao_editor/monaco/flutter/editor_inlay_hints.dart'
    show EditorInlayHint, EditorInlayHintKind, EditorInlayHintsController;
export 'package:bao_editor/monaco/flutter/editor_inline_suggest.dart'
    show EditorInlineSuggestController, EditorInlineSuggestion;
import 'package:bao_editor/monaco/flutter/editor_decoration_types.dart';
import 'package:bao_editor/monaco/flutter/editor_inlay_hints.dart';
import 'package:bao_editor/monaco/flutter/editor_inline_suggest.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';

import '../platform/svg_file.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart';
import 'ide_editor_colors.dart';
import 'ide_editor_links.dart';
import 'ide_workspace.dart';

/// Where the workbench keeps [IdeEditorFeatures] for its open documents,
/// reached by the extension host as `vscode.window.activeTextEditor`'s
/// decoration/inlay/CodeLens features.
class IdeEditorFeaturesRegistry {
  /// [types] given is the workspace's (kept on dispose); otherwise the
  /// registry has its own.
  IdeEditorFeaturesRegistry({EditorDecorationTypeRegistry? types})
    : _types = types,
      _ownsTypes = types == null;

  final Map<IdeDocument, IdeEditorFeatures> _features = {};
  EditorDecorationTypeRegistry? _types;
  final bool _ownsTypes;
  EditorDecorationTheme? _theme;

  /// All open documents' features (the theme's type registry is shared).
  Iterable<IdeEditorFeatures> get all => _features.values;

  /// [document]'s features, created on first use.
  IdeEditorFeatures of(
    IdeDocument document,
    EditorSurfaceController controller,
  ) {
    _types ??= EditorDecorationTypeRegistry();
    return _features[document] ??= IdeEditorFeatures(
      controller: controller,
      types: _types!,
      theme: _theme,
    );
  }

  /// The features [document] already has, if any.
  IdeEditorFeatures? ofDocument(IdeDocument document) => _features[document];

  /// The shared decoration-type registry (`registerTextEditorDecorationType`
  /// keys are the host's, so they are the same across editors).
  EditorDecorationTypeRegistry get types =>
      _types ??= EditorDecorationTypeRegistry();

  /// The workbench's theme changed.
  void setTheme(EditorDecorationTheme theme) {
    if (theme == _theme) return;
    _theme = theme;
    for (final features in _features.values) {
      features.setTheme(theme);
    }
  }

  /// [document]'s editor is gone (its features go with it).
  void release(IdeDocument document) {
    final features = _features.remove(document);
    if (features == null) return;
    features.dispose();
  }

  void dispose() {
    for (final features in _features.values) {
      features.dispose();
    }
    _features.clear();
    if (_ownsTypes) _types?.dispose();
    _types = null;
  }
}

/// One document's editor features: the decoration types its editors paint
/// (`registerTextEditorDecorationType` + `setDecorations`), its inlay hints,
/// its CodeLenses and its inline completion's ghost text.
class IdeEditorFeatures {
  IdeEditorFeatures({
    required EditorSurfaceController controller,
    required this.types,
    EditorDecorationTheme? theme,
  }) : decorations = EditorDecorationsController(
         document: controller.document,
         types: types,
         theme:
             theme ??
             const EditorDecorationTheme(isDark: true, colors: _noColors),
       ),
       inlayHints = EditorInlayHintsController(controller.document),
       codeLens = EditorCodeLensController(controller.document),
       inlineSuggest = EditorInlineSuggestController(controller),
       colors = EditorDocumentColors(controller);

  static Color? _noColors(String id) => null;

  final EditorDecorationTypeRegistry types;

  /// `createTextEditorDecorationType` + `TextEditor.setDecorations`.
  final EditorDecorationsController decorations;

  /// `registerInlayHintsProvider`.
  final EditorInlayHintsController inlayHints;

  /// `registerCodeLensProvider`.
  final EditorCodeLensController codeLens;

  /// `registerInlineCompletionItemProvider`.
  final EditorInlineSuggestController inlineSuggest;

  /// Document links under the editor's modifier-click gesture.
  final EditorDocumentLinks links = EditorDocumentLinks();

  /// `registerColorProvider`: color swatches and their picker.
  final EditorDocumentColors colors;

  /// The colors the last [setTheme] resolved (`theme.colors`).
  EditorDecorationTheme get theme => decorations.theme;

  /// The workbench's theme changed: every feature re-resolves its colors.
  void setTheme(EditorDecorationTheme value) {
    decorations.theme = value;
    inlayHints.colors = EditorInlayHintColors.from(value.colors);
    inlineSuggest.colors = EditorGhostTextColors.from(value.colors);
    links.setColor(value.colors('editorLink.activeForeground'));
    colors.setDark(value.isDark);
    // CodeLens zones take their colors where they are built.
  }

  /// The CodeLens zone colors of [theme].
  EditorCodeLensColors get codeLensColors =>
      EditorCodeLensColors.from(decorations.theme.colors);

  void addListener(VoidCallback listener) {
    decorations.addListener(listener);
    inlayHints.addListener(listener);
    codeLens.addListener(listener);
    inlineSuggest.addListener(listener);
    links.addListener(listener);
    colors.addListener(listener);
  }

  void removeListener(VoidCallback listener) {
    decorations.removeListener(listener);
    inlayHints.removeListener(listener);
    codeLens.removeListener(listener);
    inlineSuggest.removeListener(listener);
    links.removeListener(listener);
    colors.removeListener(listener);
  }

  void dispose() {
    decorations.dispose();
    inlayHints.dispose();
    codeLens.dispose();
    inlineSuggest.dispose();
    links.dispose();
    colors.dispose();
  }
}

/// The workbench's theme as a decoration theme: `colors.get` resolves the
/// theme's color registry, and [colors] keys the resolution cache (a theme,
/// or the colors extensions contribute, changing makes new ones).
EditorDecorationTheme ideDecorationTheme(WorkbenchColors colors) =>
    EditorDecorationTheme(isDark: colors.dark, colors: colors.get, key: colors);

/// The image of a decoration's `gutterIconPath` (a file path or `file:` URI):
/// an SVG through flutter_svg, anything else through the platform's codecs,
/// nothing when it cannot be read or decoded. A `codicon:` one is a glyph
/// margin codicon (`debugGlyph`, upstream's `glyphMarginClassName`).
Widget ideGutterIconBuilder(BuildContext context, EditorGutterIcon icon) {
  final value = Uri.tryParse(icon.path);
  if (value != null && value.scheme == 'codicon') {
    final codePoint = int.tryParse(value.path, radix: 16);
    if (codePoint == null) return const SizedBox.shrink();
    final color = int.tryParse(value.queryParameters['color'] ?? '', radix: 16);
    // Text, not an `IconData`, whose code point must be a constant.
    return Text(
      String.fromCharCode(codePoint),
      style: TextStyle(
        fontFamily: Codicons.fontFamily,
        fontSize: 14,
        height: 1,
        color: color == null ? null : Color(color),
      ),
    );
  }
  final path = value != null && value.scheme == 'file'
      ? value.toFilePath()
      : icon.path;
  final file = File(path);
  if (!file.existsSync()) return const SizedBox.shrink();
  return icon.isSvg
      ? svgFile(path)
      : Image.file(
          file,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
}
