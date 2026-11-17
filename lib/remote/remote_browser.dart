// Browsing a host for a folder (Open Remote Project…) or a file (Open
// File…), as Finder's and Explorer's open panels do: the host connected to,
// its places (home, its drives, the folders recently opened there), a
// folder's entries with the hidden ones left out until asked, and the path
// walked by. What the window shows of it is remote_browser_view.dart's.

import 'dart:async';

import 'package:bao_remote/client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show IconData;
import 'package:path/path.dart' as p;

/// How long reading a folder may take before the browser says it is
/// reading it: a fast one goes straight to its entries. Replaceable under
/// test.
@visibleForTesting
Duration remoteReadingDelay = const Duration(milliseconds: 200);

/// A host to browse, for a folder or a file, and how to reach it.
class RemoteBrowseRequest {
  const RemoteBrowseRequest({
    required this.host,
    required this.connect,
    this.files = false,
    this.directory,
    this.failureActions,
  });

  final String host;

  /// The host's connection: made (or the one made already), or why not.
  final Future<RemoteClient> Function() connect;

  /// For a file (folders walked into), not a folder.
  final bool files;

  /// Where to start: the host's home when null.
  final String? directory;

  /// What to offer as connecting failed with an error, beside Retry.
  final Future<List<RemoteBrowseAction>> Function(Object error)? failureActions;
}

/// Something to do about a connection that failed: [run], then connect
/// again if it says so; with [closes], the browser closes first (a form
/// shown in its place).
class RemoteBrowseAction {
  const RemoteBrowseAction(
    this.label, {
    required this.icon,
    required this.run,
    this.closes = false,
  });

  final String label;
  final IconData icon;
  final Future<bool> Function() run;
  final bool closes;
}

/// Shows the browser for a request: the path picked there, or null.
typedef RemoteBrowse = Future<String?> Function(RemoteBrowseRequest request);

/// What the browser shows of a folder, kept between runs: Explorer's
/// "Hidden items" and "Hide protected operating system files".
@immutable
class RemoteBrowserView {
  const RemoteBrowserView({this.hidden = false, this.system = false});

  factory RemoteBrowserView.fromJson(Map<String, Object?>? json) =>
      RemoteBrowserView(
        hidden: json?['hidden'] == true,
        system: json?['system'] == true,
      );

  /// Entries the system hides: a leading dot, Windows' hidden attribute.
  final bool hidden;

  /// Windows' protected files (hidden and system), with [hidden] only.
  final bool system;

  RemoteBrowserView copyWith({bool? hidden, bool? system}) => RemoteBrowserView(
    hidden: hidden ?? this.hidden,
    system: system ?? this.system,
  );

  Map<String, Object?> toJson() => {
    if (hidden) 'hidden': true,
    if (system) 'system': true,
  };
}

enum RemoteBrowserPhase { connecting, failed, ready }

/// The recent locations kept for a host, at most.
const remoteRecentLocationsKept = 20;

/// The browser's state: the connection, where it is, what is there and
/// what is selected, and the way back and forward.
class RemoteBrowserModel extends ChangeNotifier {
  RemoteBrowserModel(
    this.request, {
    this._view = const RemoteBrowserView(),
    List<String> locations = const [],
  }) : _locations = [...locations.take(remoteRecentLocationsKept)];

  final RemoteBrowseRequest request;

  RemoteBrowserPhase get phase => _phase;
  RemoteBrowserPhase _phase = RemoteBrowserPhase.connecting;

  /// Why connecting failed, and what may be done about it.
  Object? get connectError => _connectError;
  Object? _connectError;
  List<RemoteBrowseAction> get failureActions => _failureActions;
  List<RemoteBrowseAction> _failureActions = const [];

  RemoteClient? get client => _client;
  RemoteClient? _client;

  /// The host's home folder there.
  String get home => _home;
  String _home = '';

  /// Its drives (Windows), its root and volumes (elsewhere).
  List<BrowseRoot> get roots => _roots;
  List<BrowseRoot> _roots = const [];

  /// A Windows host: its paths `C:\…`, its drives above them.
  bool get isWindows => _client?.hello?.platform.os == 'win';
  p.Context get paths => isWindows ? p.windows : p.posix;

  /// Where it is; null: the drives (Explorer's This PC).
  String? get directory => _directory;
  String? _directory;

  /// The folders it was in there lately, the latest first (see
  /// [remember]).
  List<String> get locations => List.unmodifiable(_locations);
  final List<String> _locations;

  /// Keeps [path] first among the recent locations.
  void remember(String path) {
    _locations
      ..remove(path)
      ..insert(0, path);
    if (_locations.length > remoteRecentLocationsKept) {
      _locations.removeRange(remoteRecentLocationsKept, _locations.length);
    }
  }

  /// Its entries as read, every one.
  List<BrowseEntry> get entries => _entries;
  List<BrowseEntry> _entries = const [];

  /// Reading [directory], and whether it has taken long enough to say so.
  bool get reading => _reading;
  bool _reading = false;
  bool get readingShown => _readingShown;
  bool _readingShown = false;

  /// Why [directory] could not be read.
  Object? get readError => _readError;
  Object? _readError;

  /// The entry selected, by its name; a drive's path where the drives are.
  String? get selected => _selected;
  String? _selected;

  /// What the entries are narrowed to, by their names.
  String get filter => _filter;
  String _filter = '';

  RemoteBrowserView get view => _view;
  RemoteBrowserView _view;

  final List<String?> _back = [];
  final List<String?> _forward = [];
  bool get canGoBack => _back.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;

  /// Each read's, so that one finishing after another started is dropped.
  int _reads = 0;
  bool _disposed = false;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Connects (again), then reads where it starts.
  Future<void> connect() async {
    _phase = RemoteBrowserPhase.connecting;
    _connectError = null;
    _changed();
    final RemoteClient client;
    try {
      client = await request.connect();
    } on Object catch (error) {
      final actions = await request.failureActions?.call(error) ?? const [];
      if (_disposed) return;
      _phase = RemoteBrowserPhase.failed;
      _connectError = error;
      _failureActions = actions;
      _changed();
      return;
    }
    if (_disposed) return;
    _client = client;
    _home = client.hello?.home ?? '';
    try {
      _roots = await client.roots();
    } on Object {
      _roots = [BrowseRoot(isWindows ? 'C:\\' : '/')];
    }
    if (_disposed) return;
    _phase = RemoteBrowserPhase.ready;
    final start = request.directory;
    final fallback = _home.isEmpty ? _roots.first.path : _home;
    if (start != null && await goTo(start, record: false) == null) return;
    await open(fallback, record: false);
  }

  /// Walks to [directory] (null: the drives), read anew; the way back
  /// kept unless not [record].
  Future<void> open(String? directory, {bool record = true}) async {
    if (record && directory != _directory) {
      _back.add(_directory);
      _forward.clear();
    }
    final from = _directory;
    _directory = directory;
    // Back up a level: the folder come from is selected, as Finder has it.
    _selected =
        from != null && directory != null && paths.dirname(from) == directory
        ? paths.basename(from)
        : from != null && directory == null
        ? _rootOf(from)
        : null;
    _filter = '';
    _entries = const [];
    await refresh();
  }

  /// Reads [directory] again: one made in a terminal since.
  Future<void> refresh() async {
    final client = _client;
    final directory = _directory;
    if (client == null) return;
    final read = ++_reads;
    _readError = null;
    if (directory == null) {
      try {
        _roots = await client.roots();
      } on Object {
        // As they were.
      }
      if (read != _reads) return;
      _reading = _readingShown = false;
      _changed();
      return;
    }
    _reading = true;
    _changed();
    final timer = Timer(remoteReadingDelay, () {
      if (read != _reads || !_reading) return;
      _readingShown = true;
      _changed();
    });
    try {
      final entries = await client.browse(directory);
      if (read != _reads || _disposed) return;
      _entries = entries
        ..sort((a, b) {
          if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
          return compareNames(a.name, b.name);
        });
      if (_selected != null && !_entries.any((e) => e.name == _selected)) {
        _selected = null;
      }
    } on Object catch (error) {
      if (read != _reads || _disposed) return;
      _entries = const [];
      _readError = error;
    } finally {
      timer.cancel();
      if (read == _reads) _reading = _readingShown = false;
    }
    _changed();
  }

  /// The entries shown: folders only for a folder, the hidden ones as the
  /// view says, those the filter leaves.
  List<BrowseEntry> get visible {
    final filter = _filter.toLowerCase();
    return [
      for (final entry in _entries)
        if ((request.files || entry.isDirectory) &&
            _shows(entry) &&
            (filter.isEmpty || entry.name.toLowerCase().contains(filter)))
          entry,
    ];
  }

  bool _shows(BrowseEntry entry) =>
      (!entry.hidden || _view.hidden) && (!entry.system || _view.system);

  /// How many of the entries the view hides (the filter aside).
  int get hiddenCount => [
    for (final entry in _entries)
      if ((request.files || entry.isDirectory) && !_shows(entry)) entry,
  ].length;

  /// The drives shown where the drives are, the filter leaving them.
  List<BrowseRoot> get visibleRoots {
    final filter = _filter.toLowerCase();
    return [
      for (final root in _roots)
        if (filter.isEmpty ||
            root.path.toLowerCase().contains(filter) ||
            root.label.toLowerCase().contains(filter))
          root,
    ];
  }

  /// The selectable rows' keys, in order: the entries' names, or the
  /// drives' paths.
  List<String> get _keys => _directory == null
      ? [for (final root in visibleRoots) root.path]
      : [for (final entry in visible) entry.name];

  set filter(String value) {
    if (value == _filter) return;
    _filter = value;
    final keys = _keys;
    // The first match, so that Enter takes it.
    if (value.isNotEmpty) {
      _selected = keys.isEmpty ? null : keys.first;
    } else if (_selected != null && !keys.contains(_selected)) {
      _selected = null;
    }
    _changed();
  }

  set view(RemoteBrowserView value) {
    _view = value;
    final keys = _keys;
    if (_selected != null && !keys.contains(_selected)) _selected = null;
    _changed();
  }

  void select(String? key) {
    if (key == _selected) return;
    _selected = key;
    _changed();
  }

  /// Selects the row [by] rows from the one selected (the first or the
  /// last when none is).
  void moveSelection(int by) {
    final keys = _keys;
    if (keys.isEmpty) return;
    final at = _selected == null ? -1 : keys.indexOf(_selected!);
    final next = at < 0
        ? (by > 0 ? 0 : keys.length - 1)
        : (at + by).clamp(0, keys.length - 1);
    select(keys[next]);
  }

  /// The row selected's index among those shown; -1 for none.
  int get selectedIndex => _selected == null ? -1 : _keys.indexOf(_selected!);

  /// The entry selected, if one is (not a drive).
  BrowseEntry? get selectedEntry {
    if (_directory == null || _selected == null) return null;
    for (final entry in _entries) {
      if (entry.name == _selected) return entry;
    }
    return null;
  }

  /// The path of [name] where it is.
  String pathOf(String name) =>
      _directory == null ? name : paths.join(_directory!, name);

  /// Where Open goes: for a folder, the one selected, else where it is;
  /// for a file, the one selected. Null: nothing to open.
  String? get target {
    if (_phase != RemoteBrowserPhase.ready) return null;
    if (_directory == null) {
      return request.files || _selected == null ? null : _selected;
    }
    final entry = selectedEntry;
    if (request.files) {
      return entry == null || entry.isDirectory ? null : pathOf(entry.name);
    }
    return entry != null && entry.isDirectory ? pathOf(entry.name) : _directory;
  }

  /// Whether there is a level above: the drives above a drive's root.
  bool get canGoUp =>
      _directory != null &&
      (isWindows || paths.dirname(_directory!) != _directory);

  Future<void> up() async {
    if (!canGoUp) return;
    final directory = _directory!;
    final parent = paths.dirname(directory);
    await open(parent == directory ? null : parent);
  }

  Future<void> back() async {
    if (_back.isEmpty) return;
    _forward.add(_directory);
    await open(_back.removeLast(), record: false);
  }

  Future<void> forward() async {
    if (_forward.isEmpty) return;
    _back.add(_directory);
    await open(_forward.removeLast(), record: false);
  }

  /// The drive [path] is on (`C:\`).
  String _rootOf(String path) => paths.rootPrefix(path).isEmpty
      ? path
      : paths.rootPrefix(path).toUpperCase().replaceAll('/', '\\');

  /// [typed] as a path there: a drive's letter alone its root, a relative
  /// one under where it is; `~` left for the host to spell out.
  String resolveTyped(String typed) {
    var path = typed.trim();
    if (isWindows) {
      if (RegExp(r'^[A-Za-z]:$').hasMatch(path)) return '$path\\'.toUpperCase();
      if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
        path = path[0].toUpperCase() + path.substring(1);
      }
    }
    if (path.startsWith('~') || paths.isAbsolute(path)) return path;
    final directory = _directory ?? _home;
    return paths.join(directory, path);
  }

  /// Goes to [typed] (see [resolveTyped]): a folder walked into; a file
  /// the path to open when browsing for one, else its folder walked into
  /// with it selected. Why not, when it cannot be gone to.
  Future<String?> goTo(String typed, {bool record = true}) async {
    final client = _client;
    if (client == null) return null;
    final path = resolveTyped(typed);
    final String real;
    final String? type;
    try {
      real = await client.realPath(path);
      type = await client.stat(real);
    } on Object {
      return path;
    }
    if (type == null) return path;
    if (type == 'directory') {
      await open(real, record: record);
      return null;
    }
    await open(paths.dirname(real), record: record);
    select(paths.basename(real));
    return null;
  }

  /// Makes a folder [name] where it is, then selects it; throws as the
  /// host refuses.
  Future<void> makeFolder(String name) async {
    final client = _client;
    final directory = _directory;
    if (client == null || directory == null) return;
    await client.create(
      directory,
      paths.join(directory, name),
      directory: true,
    );
    await refresh();
    select(name);
  }

  /// A name for a new folder not taken there: [base], then `base 2`, ….
  String freeName(String base) {
    final taken = {for (final entry in _entries) entry.name.toLowerCase()};
    if (!taken.contains(base.toLowerCase())) return base;
    for (var i = 2; ; i++) {
      final name = '$base $i';
      if (!taken.contains(name.toLowerCase())) return name;
    }
  }
}

/// [a] before [b] as Finder sorts names: case aside, numbers by their
/// value (`file2` before `file10`).
int compareNames(String a, String b) {
  final digits = RegExp(r'\d+|\D+');
  final left = digits.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final right = digits.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = left[i], y = right[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final order = nx != null && ny != null && nx != ny
        ? nx.compareTo(ny)
        : x.compareTo(y);
    if (order != 0) return order;
  }
  final order = left.length.compareTo(right.length);
  return order != 0 ? order : a.compareTo(b);
}
