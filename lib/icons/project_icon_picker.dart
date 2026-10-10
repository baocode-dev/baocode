import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/chat_models.dart';
import '../chat/composer/composer_files.dart';
import '../chat/composer/file_drop.dart';
import '../chat/floating/floating_placement.dart';
import '../chat/floating/floating_registry.dart';
import '../chat/widgets/hover_builder.dart';
import '../ide/ide_hover.dart';
import '../l10n/l10n.dart';
import '../platform/app_platform.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/window_controls.dart';
import '../workspace/workspace.dart';
import 'emoji_catalog.dart';
import 'emoji_sheet.dart';
import 'icon_library.dart';
import 'project_icon.dart';
import 'project_icon_view.dart';

enum IconPickerTab { emoji, icons, custom }

/// A project's icon picker, as Notion's: emoji, VS Code's icons in a theme
/// color, and pictures the user uploads. Floats under what opened it, in
/// an overlay entry of its own (not an OverlayPortal under the sidebar's
/// menus, which the desktop semantics bridge does not take).
class ProjectIconPicker extends StatefulWidget {
  const ProjectIconPicker({
    super.key,
    required this.workspace,
    required this.project,
    required this.onClose,
    this.onDisposed,
  });

  final Workspace workspace;
  final Project project;
  final VoidCallback onClose;

  /// Gone: closed, or its overlay with the app.
  final VoidCallback? onDisposed;

  /// Taps in [TapRegion]s of this group (what opens the picker) do not
  /// close it: they toggle it.
  static final Object tapRegion = Object();

  /// Asks for files to upload; replaceable under test.
  @visibleForTesting
  static Future<List<ComposerFile>> Function() pickFiles =
      WindowControls.pickFiles;

  /// The clipboard's images and files; replaceable under test.
  @visibleForTesting
  static Future<List<ImageAttachment>> Function() pasteboardImages =
      WindowControls.readPasteboardImages;
  @visibleForTesting
  static Future<List<ComposerFile>> Function() pasteboardFiles =
      WindowControls.readPasteboardFiles;

  static OverlayEntry? _entry;
  static Project? _shownFor;
  static final Object _owner = Object();

  /// The project whose picker shows; null when none does.
  static Project? get shownFor => _shownFor;

  /// Shows [project]'s picker under [anchor] (global), or closes it when it
  /// shows already.
  static void toggle(
    BuildContext context, {
    required Workspace workspace,
    required Project project,
    required Rect anchor,
  }) {
    if (_shownFor == project) return close();
    close();
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    // When the overlay goes (the app does) without closing it first.
    void gone() {
      if (!identical(_entry, entry)) return;
      _entry = null;
      _shownFor = null;
      FloatingRegistry.closePopover(_owner);
    }

    entry = _entry = OverlayEntry(
      builder: (context) => _PickerLayout(
        anchor: anchor,
        child: TapRegion(
          groupId: tapRegion,
          onTapOutside: (_) => close(),
          child: ProjectIconPicker(
            workspace: workspace,
            project: project,
            onClose: close,
            onDisposed: gone,
          ),
        ),
      ),
    );
    _shownFor = project;
    overlay.insert(entry);
    FloatingRegistry.openPopover(_owner, close);
  }

  static void close() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    _shownFor = null;
    FloatingRegistry.closePopover(_owner);
    entry
      ..remove()
      ..dispose();
  }

  /// The theme colors a codicon may be drawn in; null is the text's.
  static const colors = <String?>[
    null,
    'charts.red',
    'charts.orange',
    'charts.yellow',
    'charts.green',
    'terminal.ansiCyan',
    'charts.blue',
    'charts.purple',
    'terminal.ansiMagenta',
  ];

  static const width = 340.0;
  static const cell = 32.0;
  static const columns = 10;
  static const _gridHeight = 264.0;

  @override
  State<ProjectIconPicker> createState() => _ProjectIconPickerState();
}

/// Places the picker under its anchor, or above when there is no room,
/// inside the overlay.
class _PickerLayout extends StatelessWidget {
  const _PickerLayout({required this.anchor, required this.child});

  final Rect anchor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final overlay = context.findAncestorRenderObjectOfType<RenderBox>();
    final origin = overlay != null && overlay.hasSize
        ? overlay.localToGlobal(Offset.zero)
        : Offset.zero;
    return CustomSingleChildLayout(
      delegate: _Below(anchor.shift(-origin), top: _titleBar - origin.dy),
      child: child,
    );
  }

  /// What the window's top takes, not to be covered: macOS's title bar
  /// (its traffic lights), Windows' header.
  static double get _titleBar => AppPlatform.isMacOS
      ? AppMetrics.titleBarHeight
      : AppPlatform.isWindows
      ? AppMetrics.headerHeight
      : 0;
}

class _Below extends SingleChildLayoutDelegate {
  const _Below(this.anchor, {required double top}) : top = top < 0 ? 0 : top;

  final Rect anchor;

  /// Where the room for it starts: under the title bar.
  final double top;
  static const _margin = 8.0;

  EdgeInsets get _insets =>
      const EdgeInsets.all(_margin).copyWith(top: top + _margin);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(_insets.deflateSize(constraints.biggest));

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      computeFloatingPosition(
        anchor: anchor,
        size: childSize,
        bounds: _insets.deflateRect(Offset.zero & size),
        placement: (side: FloatingSide.bottom, align: FloatingAlign.start),
        gap: 4,
      ).offset;

  @override
  bool shouldRelayout(_Below oldDelegate) =>
      oldDelegate.anchor != anchor || oldDelegate.top != top;
}

/// One choice of the grid: [icon], or uploading one when null.
@immutable
class _Cell {
  const _Cell(this.icon, this.label);

  final ProjectIcon? icon;
  final String label;
}

class _Section {
  const _Section(this.title, this.cells);

  final String? title;
  final List<_Cell> cells;

  int get rows => (cells.length / ProjectIconPicker.columns).ceil();
}

/// A codicon once: its name, and those of its aliases to search by.
typedef _Codicon = ({String name, String keywords});

class _ProjectIconPickerState extends State<ProjectIconPicker>
    implements FileDropDelegate {
  IconPickerTab _tab = IconPickerTab.emoji;
  final TextEditingController _query = TextEditingController();
  late final FocusNode _search = FocusNode(onKeyEvent: _key);
  final ScrollController _scroll = ScrollController();

  /// The color codicons are picked in.
  String? _color;

  /// The highlighted cell, by its index in [_cells]: the one Enter picks,
  /// and the one the footer names.
  final ValueNotifier<int?> _active = ValueNotifier(null);

  List<_Section> _sections = const [];
  List<_Cell> _cells = const [];

  bool _dropping = false;
  bool _uploading = false;
  String? _error;

  /// A right click on an uploaded picture: where, and which.
  ({Offset at, IconImage image})? _menu;

  Workspace get _workspace => widget.workspace;
  IconLibrary get _library => _workspace.icons;

  static final List<_Codicon> _codicons = () {
    final byGlyph = <int, ({String name, List<String> names})>{};
    for (final MapEntry(key: name, value: icon) in Codicons.byName.entries) {
      (byGlyph[icon.codePoint] ??= (name: name, names: [])).names.add(name);
    }
    return [
      for (final glyph in byGlyph.values)
        (
          name: glyph.name,
          keywords: glyph.names.join(' ').replaceAll('-', ' ').toLowerCase(),
        ),
    ];
  }();

  @override
  void initState() {
    super.initState();
    if (_workspace.iconOf(widget.project) case final CodiconIcon icon) {
      _tab = IconPickerTab.icons;
      _color = icon.color;
    } else if (_workspace.iconOf(widget.project) is LibraryIcon) {
      _tab = IconPickerTab.custom;
    } else if (EmojiSheet.loaded.value == null) {
      _tab = IconPickerTab.icons;
    }
    _query.addListener(_queryChanged);
    _workspace.addListener(_changed);
    EmojiSheet.loaded.addListener(_changed);
    EmojiSheet.fetched.addListener(_changed);
    EmojiSheet.style.addListener(_changed);
    unawaited(EmojiSheet.request());
    if (EmojiCatalog.loaded == null) {
      unawaited(
        EmojiCatalog.load().then((_) {
          if (mounted) _changed();
        }),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _search.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _build();
  }

  @override
  void dispose() {
    widget.onDisposed?.call();
    _workspace.removeListener(_changed);
    EmojiSheet.loaded.removeListener(_changed);
    EmojiSheet.fetched.removeListener(_changed);
    EmojiSheet.style.removeListener(_changed);
    _query.dispose();
    _search.dispose();
    _scroll.dispose();
    _active.dispose();
    super.dispose();
  }

  void _changed() => setState(_build);

  void _queryChanged() {
    setState(() {
      _build();
      _active.value = _query.text.trim().isEmpty || _cells.isEmpty ? null : 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _setTab(IconPickerTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _error = null;
      _menu = null;
      _build();
      _active.value = _query.text.trim().isEmpty || _cells.isEmpty ? null : 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _search.requestFocus();
  }

  // --- What shows ----------------------------------------------------------

  void _build() {
    final l10n = context.l10n;
    final query = _query.text.trim().toLowerCase();
    _sections = switch (_tab) {
      IconPickerTab.emoji => _emojiSections(l10n, query),
      IconPickerTab.icons => _iconSections(l10n, query),
      IconPickerTab.custom => _customSections(l10n, query),
    };
    _cells = [for (final section in _sections) ...section.cells];
    final active = _active.value;
    if (active != null && active >= _cells.length) _active.value = null;
  }

  List<_Cell> _recent<T extends ProjectIcon>(String Function(T) label) => [
    for (final icon in _workspace.recentIcons)
      if (icon is T) _Cell(icon, label(icon)),
  ];

  List<_Section> _emojiSections(AppLocalizations l10n, String query) {
    final catalog = EmojiCatalog.loaded;
    final sheet = EmojiSheet.loaded.value;
    if (catalog == null || sheet == null) return const [];
    // Only those the sheet has a picture of.
    bool drawn(Emoji emoji) => sheet.cell(emoji.emoji) != null;
    _Cell cell(Emoji emoji) =>
        _Cell(EmojiIcon(emoji.emoji), _emojiLabel(emoji));
    if (query.isNotEmpty) {
      return [
        _Section(null, [
          for (final e in catalog.search(query))
            if (drawn(e)) cell(e),
        ]),
      ];
    }
    final names = {
      for (final emoji in catalog.all) emoji.emoji: _emojiLabel(emoji),
    };
    final recent = _recent<EmojiIcon>((icon) => names[icon.emoji] ?? '');
    final groups = <int, List<_Cell>>{};
    for (final emoji in catalog.all) {
      if (drawn(emoji)) (groups[emoji.group] ??= []).add(cell(emoji));
    }
    return [
      if (recent.isNotEmpty) _Section(l10n.iconPickerRecent, recent),
      for (final group in EmojiCatalog.groups)
        if (groups[group] case final cells?)
          _Section(_groupName(l10n, group), cells),
    ];
  }

  String _emojiLabel(Emoji emoji) =>
      Localizations.localeOf(context).languageCode == 'zh' &&
          emoji.chineseName.isNotEmpty
      ? emoji.chineseName
      : emoji.name;

  static String _groupName(AppLocalizations l10n, int group) => switch (group) {
    0 => l10n.emojiGroupSmileys,
    1 => l10n.emojiGroupPeople,
    3 => l10n.emojiGroupAnimals,
    4 => l10n.emojiGroupFood,
    5 => l10n.emojiGroupTravel,
    6 => l10n.emojiGroupActivities,
    7 => l10n.emojiGroupObjects,
    8 => l10n.emojiGroupSymbols,
    _ => l10n.emojiGroupFlags,
  };

  List<_Section> _iconSections(AppLocalizations l10n, String query) {
    final words = query.split(RegExp(r'\s+'))..removeWhere((w) => w.isEmpty);
    final cells = [
      for (final codicon in _codicons)
        if (words.every(codicon.keywords.contains))
          _Cell(CodiconIcon(codicon.name, color: _color), codicon.name),
    ];
    if (query.isNotEmpty) return [_Section(null, cells)];
    final recent = _recent<CodiconIcon>((icon) => icon.name);
    return [
      if (recent.isNotEmpty) _Section(l10n.iconPickerRecent, recent),
      _Section(l10n.iconPickerIcons, cells),
    ];
  }

  List<_Section> _customSections(AppLocalizations l10n, String query) {
    final images = [
      for (final image in _library.images)
        if (image.name.toLowerCase().contains(query))
          _Cell(LibraryIcon(image.id), image.name),
    ];
    if (query.isNotEmpty) return [_Section(null, images)];
    return [
      _Section(l10n.iconPickerUploaded, [
        _Cell(null, l10n.iconPickerUpload),
        ...images,
      ]),
    ];
  }

  // --- Picking -------------------------------------------------------------

  void _pick(_Cell cell) {
    final icon = cell.icon;
    if (icon == null) {
      unawaited(_uploadPicked());
      return;
    }
    _workspace.setIcon(widget.project, icon);
    widget.onClose();
  }

  void _remove() {
    _workspace.setIcon(widget.project, null);
    widget.onClose();
  }

  /// Gives the project one of the tab's choices (those found, when
  /// searching) at random; the picker stays, to try another.
  void _random() {
    final cells = [
      for (final section in _sections)
        if (section.title != context.l10n.iconPickerRecent)
          for (final cell in section.cells)
            if (cell.icon != null) cell,
    ];
    if (cells.isEmpty) return;
    final cell = cells[math.Random().nextInt(cells.length)];
    _workspace.setIcon(widget.project, cell.icon, remember: false);
  }

  // --- Uploading -----------------------------------------------------------

  Future<void> _uploadPicked() async {
    final files = await ProjectIconPicker.pickFiles();
    await _upload([
      for (final file in files)
        if (!file.directory) () => _library.addFile(file.path),
    ]);
  }

  /// Runs [uploads]; the project takes the first picture uploaded and the
  /// picker closes, or it says why one was not taken.
  Future<void> _upload(List<Future<IconImage> Function()> uploads) async {
    if (uploads.isEmpty) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    IconImage? first;
    IconUploadError? error;
    for (final upload in uploads) {
      try {
        first ??= await upload();
      } on IconUploadException catch (e) {
        error ??= e.error;
      }
    }
    if (!mounted) return;
    if (first != null) {
      _workspace.setIcon(widget.project, LibraryIcon(first.id));
      widget.onClose();
      return;
    }
    final l10n = context.l10n;
    setState(() {
      _uploading = false;
      _tab = IconPickerTab.custom;
      _build();
      _error = switch (error) {
        IconUploadError.tooLarge => l10n.iconUploadTooLarge,
        IconUploadError.unreadable => l10n.iconUploadUnreadable,
        _ => l10n.iconUploadUnsupported,
      };
    });
  }

  /// ⌘V: the clipboard's image, or image files; text goes in the search.
  Future<void> _paste() async {
    final images = await ProjectIconPicker.pasteboardImages();
    if (images.isNotEmpty) {
      return _upload([
        for (final image in images)
          () => _library.add(image.bytes, name: image.name ?? ''),
      ]);
    }
    final files = await ProjectIconPicker.pasteboardFiles();
    final pictures = [
      for (final file in files)
        if (!file.directory) file,
    ];
    if (pictures.isNotEmpty) {
      return _upload([
        for (final file in pictures) () => _library.addFile(file.path),
      ]);
    }
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.isEmpty || !mounted) return;
    final value = _query.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    _query.value = value.replaced(selection, text.replaceAll('\n', ' '));
  }

  @override
  void fileDragOver(Offset position, List<ComposerFile> files) {
    if (!_dropping) setState(() => _dropping = true);
  }

  @override
  void fileDragLeave() {
    if (_dropping) setState(() => _dropping = false);
  }

  @override
  void fileDrop(Offset position, List<ComposerFile> files) {
    setState(() => _dropping = false);
    unawaited(
      _upload([
        for (final file in files)
          if (!file.directory) () => _library.addFile(file.path),
      ]),
    );
  }

  // --- Keys ----------------------------------------------------------------

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_menu != null) {
        setState(() => _menu = null);
      } else {
        widget.onClose();
      }
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    final command = AppPlatform.isMacOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    if (command && key == LogicalKeyboardKey.keyV) {
      unawaited(_paste());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final active = _active.value ?? (_cells.isEmpty ? null : 0);
      if (active != null) _pick(_cells[active]);
      return KeyEventResult.handled;
    }
    // Left and right move the caret until a cell is highlighted.
    if (_active.value == null &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      return KeyEventResult.ignored;
    }
    final move = switch (key) {
      LogicalKeyboardKey.arrowLeft => _moveBy(-1),
      LogicalKeyboardKey.arrowRight => _moveBy(1),
      LogicalKeyboardKey.arrowUp => _moveRow(-1),
      LogicalKeyboardKey.arrowDown => _moveRow(1),
      _ => null,
    };
    if (move == null) return KeyEventResult.ignored;
    if (_cells.isNotEmpty) {
      _active.value = move.clamp(0, _cells.length - 1);
      _reveal(_active.value!);
    }
    return KeyEventResult.handled;
  }

  int _moveBy(int step) => switch (_active.value) {
    null => 0,
    final active => active + step,
  };

  /// The cell a row up or down: in the same column, of the section before
  /// or after past its first or last row.
  int _moveRow(int step) {
    final active = _active.value;
    if (active == null) return 0;
    final (section, index) = _locate(active);
    const columns = ProjectIconPicker.columns;
    final column = index % columns;
    final row = index ~/ columns + step;
    final start = _start(section);
    if (row >= 0 && row < _sections[section].rows) {
      return start +
          math.min(row * columns + column, _sections[section].cells.length - 1);
    }
    final next = section + step;
    if (next < 0) return active;
    if (next >= _sections.length) return _cells.length - 1;
    final cells = _sections[next].cells.length;
    final to = step > 0
        ? column
        : (_sections[next].rows - 1) * columns + column;
    return _start(next) + math.min(to, cells - 1);
  }

  int _start(int section) =>
      [for (var i = 0; i < section; i++) _sections[i].cells.length]
          .fold(0, (a, b) => a + b);

  (int, int) _locate(int index) {
    var start = 0;
    for (final (i, section) in _sections.indexed) {
      if (index < start + section.cells.length) return (i, index - start);
      start += section.cells.length;
    }
    return (_sections.length - 1, 0);
  }

  static const _headerHeight = 28.0;
  static const _gridPadding = 4.0;

  /// Scrolls the grid so that cell [index] shows.
  void _reveal(int index) {
    if (!_scroll.hasClients) return;
    final (section, at) = _locate(index);
    var top = _gridPadding;
    for (var i = 0; i < section; i++) {
      if (_sections[i].title != null) top += _headerHeight;
      top += _sections[i].rows * ProjectIconPicker.cell;
    }
    if (_sections[section].title != null) top += _headerHeight;
    top += at ~/ ProjectIconPicker.columns * ProjectIconPicker.cell;
    final position = _scroll.position;
    final bottom = top + ProjectIconPicker.cell;
    if (top < position.pixels) {
      _scroll.jumpTo(top - (at < ProjectIconPicker.columns ? 28 : 0));
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(bottom - position.viewportDimension + _gridPadding);
    }
  }

  // --- Building ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final current = _workspace.iconOf(widget.project);
    final panel = Container(
      width: ProjectIconPicker.width,
      decoration: BoxDecoration(
        color: colors['menu.background'],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _dropping ? colors['focusBorder'] : colors['menu.border'],
        ),
        boxShadow: [
          BoxShadow(
            color: colors['widget.shadow'],
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTabs(l10n, current),
          _buildSearch(l10n),
          if (_tab == IconPickerTab.icons) _buildColors(l10n),
          if (_tab == IconPickerTab.emoji) _buildStyles(),
          SizedBox(
            height: ProjectIconPicker._gridHeight,
            child: _buildGrid(l10n, current),
          ),
          _buildFooter(l10n),
        ],
      ),
    );
    return FileDropRegion(
      delegate: this,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              panel,
              if (_menu case final menu?) ..._buildMenu(l10n, menu),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabs(AppLocalizations l10n, ProjectIcon? current) {
    Widget tab(IconPickerTab tab, String label) =>
        _Tab(label: label, selected: _tab == tab, onTap: () => _setTab(tab));
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: themeColors['menu.border'])),
      ),
      child: Row(
        children: [
          // Scrolled rather than cut where the names are long.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Not until there are pictures of them.
                  if (EmojiSheet.loaded.value != null)
                    tab(IconPickerTab.emoji, l10n.iconPickerEmoji),
                  tab(IconPickerTab.icons, l10n.iconPickerIcons),
                  tab(IconPickerTab.custom, l10n.iconPickerCustom),
                ],
              ),
            ),
          ),
          if (current != null)
            _TextButton(label: l10n.iconPickerRemove, onTap: _remove),
        ],
      ),
    );
  }

  Widget _buildSearch(AppLocalizations l10n) {
    final colors = themeColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _query,
                focusNode: _search,
                style: TextStyle(
                  color: colors['input.foreground'],
                  fontSize: 12.5,
                ),
                cursorColor: AppColors.text,
                cursorHeight: 14,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.iconPickerSearch,
                  hintStyle: TextStyle(
                    color: colors['input.placeholderForeground'],
                    fontSize: 12.5,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 15,
                    color: AppColors.textFaint,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 28),
                  contentPadding: const EdgeInsets.symmetric(vertical: 7),
                  filled: true,
                  fillColor: colors['input.background'],
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: AppColors.borderStrong),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors['focusBorder']),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _IconButton(
            icon: Icons.shuffle_rounded,
            label: l10n.iconPickerRandom,
            onTap: _random,
          ),
        ],
      ),
    );
  }

  Widget _buildColors(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
    child: Row(
      children: [
        for (final color in ProjectIconPicker.colors)
          _ColorDot(
            color: color == null
                ? AppColors.text
                : codiconColor(color) ?? Colors.transparent,
            label: color ?? l10n.iconPickerDefaultColor,
            selected: color == _color,
            onTap: () => setState(() {
              _color = color;
              _build();
            }),
          ),
      ],
    ),
  );

  /// Whose pictures of the emoji: those fetched can be picked.
  Widget _buildStyles() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
    child: Row(
      children: [
        for (final style in EmojiStyle.values)
          _StyleButton(
            label: style.label,
            selected: style == EmojiSheet.style.value,
            onTap: EmojiSheet.fetched.value.contains(style)
                ? () => _workspace.setEmojiStyle(style)
                : null,
          ),
      ],
    ),
  );

  Widget _buildGrid(AppLocalizations l10n, ProjectIcon? current) {
    if (_tab == IconPickerTab.emoji && EmojiCatalog.loaded == null) {
      return const SizedBox.shrink();
    }
    if (_cells.isEmpty) {
      return Center(
        child: Text(
          l10n.iconPickerNoResults,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      );
    }
    var start = 0;
    final slivers = <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: _gridPadding)),
    ];
    for (final section in _sections) {
      final first = start;
      start += section.cells.length;
      if (section.title case final title?) {
        slivers.add(
          SliverToBoxAdapter(
            child: Container(
              height: _headerHeight,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                title,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }
      slivers.add(
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: ProjectIconPicker.columns,
            mainAxisExtent: ProjectIconPicker.cell,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _CellView(
              cell: section.cells[i],
              index: first + i,
              active: _active,
              current: current,
              library: _library,
              onTap: _pick,
              onSecondaryTap: _openMenu,
            ),
            childCount: section.cells.length,
          ),
        ),
      );
    }
    slivers.add(
      const SliverToBoxAdapter(child: SizedBox(height: _gridPadding)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: CustomScrollView(controller: _scroll, slivers: slivers),
    );
  }

  Widget _buildFooter(AppLocalizations l10n) {
    final colors = themeColors;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors['menu.border'])),
      ),
      child: ValueListenableBuilder(
        valueListenable: _active,
        builder: (context, active, _) {
          final style = TextStyle(color: AppColors.textMuted, fontSize: 11.5);
          if (_error case final error?) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                error,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(color: colors['errorForeground']),
              ),
            );
          }
          if (_uploading) {
            return const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            );
          }
          final cell = active == null || active >= _cells.length
              ? null
              : _cells[active];
          final text = _dropping
              ? l10n.iconPickerDropHere
              : cell?.label ??
                    (_tab == IconPickerTab.custom
                        ? l10n.iconPickerUploadHint
                        : '');
          return Row(
            children: [
              if (cell?.icon case final icon? when !_dropping) ...[
                ProjectIconView(
                  icon: icon,
                  library: _library,
                  size: 20,
                  color: AppColors.text,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openMenu(_Cell cell, Offset globalPosition) {
    if (cell.icon case LibraryIcon(:final id)) {
      final image = _library[id];
      final box = context.findRenderObject() as RenderBox?;
      if (image == null || box == null) return;
      final at = box.globalToLocal(globalPosition);
      // Inside the panel, where it can be clicked.
      setState(
        () => _menu = (
          at: Offset(at.dx, math.min(at.dy, box.size.height - 40)),
          image: image,
        ),
      );
    }
  }

  List<Widget> _buildMenu(
    AppLocalizations l10n,
    ({Offset at, IconImage image}) menu,
  ) {
    final colors = themeColors;
    const menuWidth = 170.0;
    return [
      // A click anywhere else closes it.
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _menu = null),
          onSecondaryTap: () => setState(() => _menu = null),
        ),
      ),
      Positioned(
        left: math.min(menu.at.dx, ProjectIconPicker.width - menuWidth - 4),
        top: menu.at.dy,
        child: Container(
          width: menuWidth,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colors['menu.background'],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors['menu.border']),
            boxShadow: [
              BoxShadow(color: colors['widget.shadow'], blurRadius: 12),
            ],
          ),
          child: HoverBuilder(
            cursor: SystemMouseCursors.click,
            builder: (context, hovered) => GestureDetector(
              onTap: () {
                setState(() => _menu = null);
                unawaited(_library.remove(menu.image.id));
              },
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: hovered
                      ? colors['menu.selectionBackground']
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 14,
                      color: colors['errorForeground'],
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        l10n.iconPickerDeleteFromLibrary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors['errorForeground'],
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

class _CellView extends StatelessWidget {
  const _CellView({
    required this.cell,
    required this.index,
    required this.active,
    required this.current,
    required this.library,
    required this.onTap,
    required this.onSecondaryTap,
  });

  final _Cell cell;
  final int index;
  final ValueNotifier<int?> active;
  final ProjectIcon? current;
  final IconLibrary library;
  final ValueChanged<_Cell> onTap;
  final void Function(_Cell cell, Offset globalPosition) onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final icon = cell.icon;
    final glyph = switch (icon) {
      null => Icon(Icons.add_rounded, size: 20, color: AppColors.textMuted),
      _ => ProjectIconView(
        icon: icon,
        library: library,
        size: 28,
        color: AppColors.text,
      ),
    };
    return Semantics(
      button: true,
      selected: icon != null && icon == current,
      label: cell.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => active.value = index,
        child: GestureDetector(
          onTap: () => onTap(cell),
          onSecondaryTapUp: (details) =>
              onSecondaryTap(cell, details.globalPosition),
          child: ValueListenableBuilder(
            valueListenable: active,
            builder: (context, value, child) => Container(
              margin: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: value == index
                    ? themeColors['toolbar.hoverBackground']
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: icon != null && icon == current
                    ? Border.all(color: themeColors['focusBorder'])
                    : null,
              ),
              alignment: Alignment.center,
              child: child,
            ),
            child: ExcludeSemantics(child: glyph),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: selected
                    ? themeColors['focusBorder']
                    : Colors.transparent,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: selected || hovered ? AppColors.text : AppColors.textMuted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    ),
  );
}

class _TextButton extends StatelessWidget {
  const _TextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered
                ? themeColors['toolbar.hoverBackground']
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
      ),
    ),
  );
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IdeHover(
    message: label,
    excludeFromSemantics: true,
    child: Semantics(
      button: true,
      label: label,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: hovered
                  ? themeColors['toolbar.hoverBackground']
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 16, color: AppColors.textMuted),
          ),
        ),
      ),
    ),
  );
}

/// An emoji set to pick; [onTap] null while it is not fetched yet.
class _StyleButton extends StatelessWidget {
  const _StyleButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    selected: selected,
    child: HoverBuilder(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? themeColors['toolbar.activeBackground']
                : hovered && onTap != null
                ? themeColors['toolbar.hoverBackground']
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: onTap == null
                  ? AppColors.textFaint
                  : selected
                  ? AppColors.text
                  : AppColors.textMuted,
            ),
          ),
        ),
      ),
    ),
  );
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? themeColors['focusBorder'] : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    ),
  );
}
