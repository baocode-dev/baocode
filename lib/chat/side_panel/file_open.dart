import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../ide/file_service.dart';
import '../../ide/file_views.dart';
import '../../workspace/window_controls.dart';
import '../chat_models.dart';
import 'file_link.dart';
import 'file_link_menu.dart';
import '../widgets/image_thumbnails.dart' show showImagePreview;
import 'shown_files.dart';

/// A file to show: at [range], or as its changes ([diff]) against
/// [original], its text before (the agent's edit, or Git's HEAD or index).
@immutable
class FileOpenRequest {
  const FileOpenRequest(
    this.path, {
    this.range,
    this.diff = false,
    this.change,
    this.original,
    this.modified,
    this.plan = false,
    this.local = false,
    this.readOnly = false,
    this.preview = false,
    this.agentChange = false,
  });

  /// Absolute, on the project's host (on this machine when [local]).
  final String path;

  /// On this machine whatever the project's host: something shown as a
  /// file (see [FileOpenScope.showText]).
  final bool local;

  /// Shown, not to edit: text sent already, a picture.
  final bool readOnly;

  /// In the tab that shows what was looked at last, which the next look
  /// takes over, as VS Code's preview editor: kept once it is pinned.
  final bool preview;

  /// The agent's plan, written in plan mode: shown on a page of its own
  /// where there is one (the side panel's), else as any file.
  final bool plan;
  final FileLineRange? range;

  /// Its changes rather than its text, where they are known.
  final bool diff;

  /// The agent's change pending in the file, shown in its text (each part
  /// to keep or undo) rather than as its changes: scrolled to, the part at
  /// [range] (else the first), the lines not marked.
  final bool agentChange;

  /// The change [diff] shows, when the session lists it.
  final FileChange? change;

  /// Reads [path]'s text before it changed; null when unknown.
  final Future<String> Function()? original;

  /// Reads [path]'s text after it changed (a staged change's, the index's);
  /// the file's when null.
  final Future<String> Function()? modified;

  FileOpenRequest copyWith({
    FileLineRange? range,
    FileChange? change,
    Future<String> Function()? original,
  }) => FileOpenRequest(
    path,
    range: range ?? this.range,
    diff: diff,
    change: change ?? this.change,
    original: original ?? this.original,
    modified: modified,
    plan: plan,
    local: local,
    readOnly: readOnly,
    preview: preview,
    agentChange: agentChange,
  );

  @override
  String toString() =>
      'FileOpenRequest($path${range == null ? '' : ', $range'}'
      '${diff ? ', diff' : ''}${plan ? ', plan' : ''}'
      '${local ? ', local' : ''}${readOnly ? ', read-only' : ''}'
      '${preview ? ', preview' : ''}${agentChange ? ', agent change' : ''})';
}

/// Where a chat's files open (the agent window's side panel, the IDE's
/// editor), and how it learns which exist.
class FileLinkTarget {
  const FileLinkTarget({
    required this.open,
    this.exists,
    this.readBytes,
    this.sizeOf,
    this.paths,
    this.roots,
    this.home,
    this.inPanel = false,
    this.openInIde,
    this.openFolder,
  });

  final ValueChanged<FileOpenRequest> open;

  /// The home folder of the project's host, where `~` goes; null while it
  /// is not known (a remote host not reached yet).
  final String? Function()? home;

  /// Shows a folder the chat names (absolute, on the project's host) in
  /// the side panel's tree; none where there is no such tree.
  final ValueChanged<String>? openFolder;

  /// Whether [open] shows them in the side panel (the agent window's).
  final bool inPanel;

  /// Opens one in the IDE of the project, where [open] does not.
  final ValueChanged<FileOpenRequest>? openInIde;

  /// Reads the file at an absolute path (on the project's host): an image
  /// the chat names, to show; none, and images open as other files.
  final Future<Uint8List> Function(String path)? readBytes;

  /// How many bytes the file at an absolute path takes (on the project's
  /// host): an image too big to show small is not read for it.
  final Future<int> Function(String path)? sizeOf;

  /// A multi-folder workspace's folders as they are now: its files are
  /// theirs (see [FileOpenScope.roots]).
  final List<String> Function()? roots;

  /// Whether the file at an absolute path is there; inline code naming a
  /// file is a link only once it is known to be. None: never a link.
  final Future<bool> Function(String path)? exists;

  /// How the project's host spells paths; this machine's when null.
  final p.Context? paths;
}

/// Whether a file is in [files], as the listing of its folder says: on a
/// remote project's host as well as here. A folder listed is kept a few
/// seconds, for the paths asked together.
Future<bool> Function(String path) fileExistsIn(
  IdeFileService files, {
  p.Context? paths,
}) {
  final context = paths ?? p.context;
  final listings = <String, ({DateTime at, Future<Set<String>> names})>{};
  return (path) async {
    final folder = context.dirname(path);
    final now = DateTime.now();
    var listing = listings[folder];
    if (listing == null || now.difference(listing.at).inSeconds >= 5) {
      listing = (
        at: now,
        names: files
            .list(folder)
            .then(
              (entries) => {
                for (final entry in entries)
                  if (!entry.isDirectory) entry.name,
              },
            ),
      );
      listings[folder] = listing;
    }
    try {
      return (await listing.names).contains(context.basename(path));
    } catch (_) {
      return false;
    }
  };
}

/// Which files exist, as [check] finds, asked once each: a listener is
/// told (once for those found together) as answers come.
class FileExistence extends ChangeNotifier {
  FileExistence(this.check);

  final Future<bool> Function(String path)? check;

  final Map<String, bool> _known = {};
  final Set<String> _asking = {};
  bool _notifying = false;
  bool _disposed = false;

  /// Whether [path] exists: null until known, asked then.
  bool? known(String path) {
    if (_known[path] case final known?) return known;
    final check = this.check;
    if (check == null) return false;
    if (_asking.add(path)) {
      unawaited(
        check(path).then((found) => found, onError: (_) => false).then((found) {
          _asking.remove(path);
          _known[path] = found;
          if (found) _notifySoon();
        }),
      );
    }
    return null;
  }

  void _notifySoon() {
    if (_notifying || _disposed) return;
    _notifying = true;
    scheduleMicrotask(() {
      _notifying = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// What the file links under it open: those in [root] (on the project's
/// host, spelled as [paths]), or a workspace's [roots], through [onOpen].
class FileOpenScope extends InheritedWidget {
  const FileOpenScope({
    super.key,
    required this.root,
    required this.onOpen,
    required this.existence,
    this.paths,
    this.roots = const [],
    this.seen = const [],
    this.home,
    this.local = true,
    this.readBytes,
    this.sizeOf,
    this.inPanel = false,
    this.onOpenInIde,
    this.onOpenFolder,
    required super.child,
  });

  /// See [FileLinkTarget.openFolder].
  final ValueChanged<String>? onOpenFolder;

  /// See [FileLinkTarget.inPanel].
  final bool inPanel;

  /// See [FileLinkTarget.openInIde].
  final ValueChanged<FileOpenRequest>? onOpenInIde;

  /// See [FileLinkTarget.readBytes].
  final Future<Uint8List> Function(String path)? readBytes;

  /// See [FileLinkTarget.sizeOf].
  final Future<int> Function(String path)? sizeOf;

  final String root;

  /// Whether the files are this machine's (not a remote project's): their
  /// menu then shows them in the file manager, and opens them in apps.
  final bool local;
  final ValueChanged<FileOpenRequest> onOpen;
  final FileExistence existence;
  final p.Context? paths;

  /// A multi-folder workspace's folders, its files' ([root], the agent's
  /// directory, only holds its settings): a relative path is looked for in
  /// each, in order.
  final List<String> roots;

  /// The files the agent read or changed (absolute, wherever they are):
  /// the one a path names when that is not where the path says, as an
  /// agent that read `/Users/me/a/lib/b.dart` from `/Users/me/Desktop` may
  /// name it `a/lib/b.dart`.
  final List<String> seen;

  /// See [FileLinkTarget.home].
  final String? home;

  static FileOpenScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FileOpenScope>();

  /// The scope over [context], for what a click does (not depended on).
  static FileOpenScope? find(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FileOpenScope>();

  /// [path] absolute (see [FileLink.resolvePath]): relative to [root], or
  /// in a workspace the first of its folders' found to have it (until one
  /// is, the first's); the file the agent saw that it names, where that is
  /// the one found.
  String? resolve(String path) {
    final candidates = _candidates(path);
    if (candidates.length < 2) return candidates.firstOrNull;
    for (final candidate in candidates) {
      if (existence.known(candidate) == true) return candidate;
    }
    return candidates.first;
  }

  /// [resolve]d, where it is read with no click asking for it (an image
  /// the chat shows): in [root] or one of [roots], or a file the agent
  /// saw; null elsewhere.
  String? resolveShown(String path) {
    final full = resolve(path);
    if (full == null) return null;
    final context = paths ?? p.context;
    final inside = [...roots, root].any(
      (folder) => folder == full || context.isWithin(folder, full),
    );
    if (inside) return full;
    final seenFile = _seen(path);
    return seenFile != null && context.equals(seenFile, full) ? full : null;
  }

  /// Where [path] may be: in each of [roots], then in [root], then the
  /// file of those [seen] it names.
  List<String> _candidates(String path) {
    final found = <String>{};
    for (final folder in [...roots, root]) {
      if (FileLink.resolvePath(path, folder, paths: paths, home: home)
          case final full?) {
        found.add(full);
      }
    }
    if (_seen(path) case final file?) found.add(file);
    return [...found];
  }

  /// The file of [seen] that [path] names: that one (absolute, or relative
  /// to [root]), or the one it ends with (as whole names, `b.dart` not
  /// `ab.dart`); the last read of those.
  String? _seen(String path) {
    final context = paths ?? p.context;
    if (path.isEmpty || path.startsWith('~')) return null;
    final normalized = context.normalize(path);
    final index = _SeenIndex.of(seen, context);
    final full = context.normalize(context.join(root, path));
    if (index.byPath[context.canonicalize(full)] case final file?) return file;
    final parts = context.split(normalized);
    if (context.isAbsolute(normalized) || parts.contains('..')) return null;
    for (final (:file, :names)
        in index.byName[parts.last] ?? const <_SeenFile>[]) {
      if (names.length <= parts.length) continue;
      var same = true;
      for (var i = 1; i <= parts.length && same; i++) {
        same = names[names.length - i] == parts[parts.length - i];
      }
      if (same) return file;
    }
    return null;
  }

  /// Opens [link] if it is in [root]; false if it is not. In a workspace,
  /// once it is found in one of its folders, if that is not known yet.
  bool openLink(FileLink link, {bool diff = false}) {
    final path = resolve(link.path);
    if (path == null) return false;
    void open(String path) =>
        onOpen(FileOpenRequest(path, range: link.range, diff: diff));
    final check = existence.check;
    final candidates = _candidates(link.path);
    if (candidates.length < 2 ||
        check == null ||
        existence.known(path) == true) {
      open(path);
      return true;
    }
    unawaited(() async {
      for (final candidate in candidates) {
        final found = await check(candidate)
            .then((found) => found, onError: (_) => false);
        if (found) return open(candidate);
      }
      open(path);
    }());
    return true;
  }

  /// What a click on a markdown link to [href] does: opens the file it goes
  /// to, when that is in [root]; null for any other. A right click has its
  /// menu (see [FileLinkMenu]). An image shows enlarged, over [context]'s
  /// window, and a web page here opens in the browser (see [activate]).
  GestureRecognizer? linkRecognizer(String? href, {BuildContext? context}) {
    final link = FileLink.parseHref(href);
    if (link == null) return null;
    final path = resolve(link.path);
    if (path == null) return null;
    return FileLinkRecognizer(
      menuFor(path, () => openLink(link), context: context),
    )..onTap = () => activate(link, path, context);
  }

  /// What a click on inline [code] does: opens the file it names, once
  /// that is known to exist in [root]; null until then, and for any other.
  GestureRecognizer? codeRecognizer(String code, {BuildContext? context}) {
    final link = FileLink.parseText(code);
    if (link == null) return null;
    final path = resolve(link.path);
    if (path == null || existence.known(path) != true) return null;
    return FileLinkRecognizer(
      menuFor(path, () => openLink(link), context: context),
    )..onTap = () => activate(link, path, context);
  }

  /// A click on [link], to the file at [path]: one opened outside the app
  /// opens there ([openerOf], a web page here in the browser); an image
  /// shows enlarged over [context]'s window ([preview]); anything else
  /// opens (see [openLink]).
  void activate(FileLink link, String path, BuildContext? context) {
    if (context != null && link.range == null && showsImage(path)) {
      unawaited(preview(context, path, orElse: () => openLink(link)));
    } else if (link.range == null ? openerOf(path) : null case final opener?) {
      unawaited(opener.open(path));
    } else {
      openLink(link);
    }
  }

  /// Whether a click on the image at [path] shows it enlarged: one the
  /// window draws, which can be read.
  bool showsImage(String path) =>
      readBytes != null &&
      _imageTypes.containsKey(
        (paths ?? p.context).extension(path).toLowerCase(),
      );

  /// What a click on [path] opens it with outside the app (see
  /// [FileViews.openerOf]): only a file on this machine; null to open it in
  /// the app.
  FileOpener? openerOf(String path) => local ? FileViews.openerOf(path) : null;

  static const _imageTypes = {
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.bmp': 'image/bmp',
  };

  /// Shows the file at [path] on this machine (whatever the project's
  /// host), read-only, in the tab of what was looked at last: where the
  /// chat's files open (the side panel, the IDE).
  void showLocal(String path, {FileLineRange? range}) => onOpen(
    FileOpenRequest(
      path,
      range: range,
      local: true,
      readOnly: true,
      preview: true,
    ),
  );

  /// Shows [text] as a file named [name] (see [ShownFiles.text]), as
  /// [showLocal] does; false where it cannot be one.
  bool showText(String text, {required String name}) {
    final path = ShownFiles.text(text, name: name);
    if (path == null) return false;
    showLocal(path);
    return true;
  }

  /// The image at [path], read; null when it cannot be, or (where its
  /// size can be known) takes more than [maxBytes].
  Future<ImageAttachment?> image(String path, {int? maxBytes}) async {
    final read = readBytes;
    if (read == null) return null;
    try {
      if ((maxBytes, sizeOf) case (final most?, final sizeOf?)
          when await sizeOf(path) > most) {
        return null;
      }
      return ImageAttachment(
        bytes: await read(path),
        mediaType:
            _imageTypes[(paths ?? p.context).extension(path).toLowerCase()] ??
            'image/png',
        name: (paths ?? p.context).basename(path),
      );
    } on Object {
      return null;
    }
  }

  /// Shows the image at [path] enlarged over [context]'s window, with the
  /// file's menu; [orElse] where it cannot be read.
  Future<void> preview(
    BuildContext context,
    String path, {
    VoidCallback? orElse,
  }) async {
    final image = await this.image(path);
    if (!context.mounted) return;
    if (image == null) return orElse?.call();
    showImagePreview(
      context,
      image,
      menu: menuFor(
        path,
        orElse ?? () => onOpen(FileOpenRequest(path)),
        context: context,
        previewing: true,
      ),
    );
  }

  /// The right click's menu of the file at [path] (absolute), [open]
  /// opening it (in the side panel, or the IDE: see [inPanel]); in the
  /// IDE too ([onOpenInIde]). An image also shows enlarged over
  /// [context]'s window (unless it is [previewing]), and copies.
  FileLinkMenu menuFor(
    String path,
    VoidCallback open, {
    BuildContext? context,
    bool previewing = false,
  }) {
    final image = context != null && showsImage(path);
    return FileLinkMenu(
      path: path,
      root: root,
      paths: paths,
      local: local,
      onOpen: open,
      inPanel: inPanel,
      onOpenInIde: switch (onOpenInIde) {
        final inIde? => () => inIde(FileOpenRequest(path)),
        null => null,
      },
      onPreview: image && !previewing
          ? () => unawaited(preview(context, path))
          : null,
      onCopyImage: image
          ? () => unawaited(() async {
              if (await this.image(path) case final image?) {
                await WindowControls.writePasteboardImage(image);
              }
            }())
          : null,
      opener: openerOf(path),
    );
  }

  @override
  bool updateShouldNotify(FileOpenScope oldWidget) =>
      root != oldWidget.root ||
      onOpen != oldWidget.onOpen ||
      existence != oldWidget.existence ||
      paths != oldWidget.paths ||
      home != oldWidget.home ||
      local != oldWidget.local ||
      readBytes != oldWidget.readBytes ||
      inPanel != oldWidget.inPanel ||
      onOpenInIde != oldWidget.onOpenInIde ||
      onOpenFolder != oldWidget.onOpenFolder ||
      !listEquals(roots, oldWidget.roots) ||
      !listEquals(seen, oldWidget.seen);
}

/// [FileOpenScope.seen] looked up by path, made once for each list: every
/// path in the chat's text (a code span, a link) is looked for in it, as
/// the chat is built, and a long session's has thousands of files.
class _SeenIndex {
  _SeenIndex(List<String> seen, this.context) {
    // The last read first, as the files are looked for.
    for (final file in seen.reversed) {
      byPath.putIfAbsent(context.canonicalize(file), () => file);
      final names = context.split(context.normalize(file));
      if (names.isEmpty) continue;
      (byName[names.last] ??= <_SeenFile>[]).add((file: file, names: names));
    }
  }

  static final _made = Expando<_SeenIndex>();

  static _SeenIndex of(List<String> seen, p.Context context) {
    final made = _made[seen];
    if (made != null && made.context == context) return made;
    return _made[seen] = _SeenIndex(seen, context);
  }

  final p.Context context;

  /// The files, by their canonical path.
  final byPath = <String, String>{};

  /// The files and their names, by the last of those, the last read first.
  final byName = <String, List<_SeenFile>>{};
}

/// A file of [FileOpenScope.seen], and its names (its folders' and its own).
typedef _SeenFile = ({String file, List<String> names});
