import 'package:flutter/widgets.dart';

/// A kind of file shown as something of its own rather than its text: a
/// stash as the Stash page shows it (see docs/stash.md); later, say, a web
/// page or a spreadsheet. What shows it registers it ([FileViews.register])
/// while it can.
@immutable
class FileView {
  const FileView({
    required this.id,
    required this.matches,
    required this.build,
  });

  /// Tells it from the others (one registered again takes its place).
  final String id;

  /// Whether the file at [path] (absolute, on this machine) is one.
  final bool Function(String path) matches;

  /// It, for the file at [path], in place of an editor. In the IDE its tab
  /// has a [PageStorage] of its own: a list it keeps there (`KeptScrolling`,
  /// a [PageStorageKey]) is where it was when the tab shows again.
  final Widget Function(BuildContext context, String path) build;
}

/// A kind of file a chat's link opens outside the app rather than in it:
/// a web page on this machine, in the browser. Registered as [FileView]s
/// are ([FileViews.registerOpener]); the IDE's editor still shows its text.
@immutable
class FileOpener {
  const FileOpener({
    required this.id,
    required this.matches,
    required this.label,
    required this.open,
  });

  /// Tells it from the others (one registered again takes its place).
  final String id;

  /// Whether the file at [path] (absolute, on this machine) is one.
  final bool Function(String path) matches;

  /// Its item in the link's menu ("Open in Browser").
  final String Function(BuildContext context) label;

  /// Opens the file at [path] there.
  final Future<void> Function(String path) open;
}

/// The [FileView]s: where a file opens (the side panel's tabs, the IDE's
/// editor) asks [of] first, before it reads the file as text; and the
/// [FileOpener]s, which a chat's link asks [openerOf] first.
abstract final class FileViews {
  static final List<FileView> _views = [];
  static final List<FileOpener> _openers = [];

  static void registerOpener(FileOpener opener) => _openers
    ..removeWhere((other) => other.id == opener.id)
    ..add(opener);

  static void unregisterOpener(String id) =>
      _openers.removeWhere((opener) => opener.id == id);

  /// What opens the file at [path] outside the app; null to open it in it.
  static FileOpener? openerOf(String path) {
    for (final opener in _openers) {
      if (opener.matches(path)) return opener;
    }
    return null;
  }

  static void register(FileView view) => _views
    ..removeWhere((other) => other.id == view.id)
    ..add(view);

  static void unregister(String id) =>
      _views.removeWhere((view) => view.id == id);

  /// The view of the file at [path]; null to show its text.
  static FileView? of(String path) {
    for (final view in _views) {
      if (view.matches(path)) return view;
    }
    return null;
  }

  static FileView? byId(String id) {
    for (final view in _views) {
      if (view.id == id) return view;
    }
    return null;
  }
}
