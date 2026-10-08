import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'review_store.dart';

/// A Git command that failed.
class GitReviewError implements Exception {
  const GitReviewError(this.arguments, this.exitCode, this.stderr);

  final List<String> arguments;
  final int exitCode;
  final String stderr;

  @override
  String toString() =>
      'git ${arguments.first} failed ($exitCode): ${stderr.trim()}';
}

class _Output {
  const _Output(this.exitCode, this.bytes);

  final int exitCode;
  final Uint8List bytes;

  String get text => utf8.decode(bytes, allowMalformed: true);

  /// The NUL-separated records of a `-z` listing.
  List<String> get records => [
    for (final record in text.split('\x00'))
      if (record.isNotEmpty) record,
  ];
}

/// [ReviewStore] over a bare repository of the app's own, whose work tree
/// is the project: the project's `.git` (if it has one) is never read or
/// written, nor its index, HEAD or refs. Its `.gitignore` files are
/// followed. Line endings, filters and encodings are left as they are on
/// disk (`info/attributes`), so that what is put back is byte for byte
/// what was there.
class GitReviewStore implements ReviewStore {
  GitReviewStore._(this.root, this.gitDir, this._own);

  /// The store for [root], its repository under [checkpoints] (made the
  /// first time); null when Git cannot run or [root] is not a folder.
  static Future<GitReviewStore?> open(
    String root, {
    required String checkpoints,
  }) async {
    root = p.normalize(p.absolute(root));
    checkpoints = p.normalize(p.absolute(checkpoints));
    if (!await Directory(root).exists() || !await _gitUsable) return null;
    final gitDir = p.join(checkpoints, _folderName(root));
    final own = p.isWithin(root, checkpoints)
        ? p.relative(checkpoints, from: root)
        : null;
    final store = GitReviewStore._(root, gitDir, own);
    try {
      if (!await File(p.join(gitDir, 'HEAD')).exists()) {
        await _initialize(gitDir, root);
      } else if (own != null) {
        // Taken by snapshots before they left it out.
        await store._locked(
          () => store._git([
            'rm',
            '--cached',
            // Whatever is staged there: only the index changes.
            '-f',
            '-r',
            '-q',
            '--ignore-unmatch',
            '--',
            ':(literal)$own',
          ]),
        );
      }
    } on Object {
      return null;
    }
    return store;
  }

  @override
  final String root;

  /// The repository: `checkpoints/<folder name>-<hash of its path>`.
  final String gitDir;

  /// The checkpoints folder relative to the root, where the project holds
  /// it (a home folder, say): left out of the snapshots, which would
  /// otherwise take in what they write there.
  final String? _own;

  bool _isOwn(String path) {
    final own = _own;
    return own != null && (path == own || p.isWithin(own, path));
  }

  /// Past this size a file is left out of the snapshots.
  static int maxFileBytes = 10 * 1024 * 1024;

  /// Past this many new or changed files at once, the project is too large
  /// to snapshot (a first snapshot of a home folder, say).
  static int maxFiles = 100000;

  /// Folders left out even where no `.gitignore` says so: what tools
  /// download or build, not what an agent edits.
  static const _excluded = [
    '.DS_Store',
    'node_modules/',
    '.venv/',
    '__pycache__/',
    '.dart_tool/',
    '.gradle/',
    '.next/',
    '.nuxt/',
    'Pods/',
    'DerivedData/',
  ];

  static Future<void> _initialize(String gitDir, String root) async {
    await Directory(gitDir).create(recursive: true);
    final result = await Process.run('git', [
      'init',
      '-q',
      '--bare',
      // No hooks or other files from the user's template.
      '--template=',
      gitDir,
    ]);
    if (result.exitCode != 0) {
      throw GitReviewError(const ['init'], result.exitCode, '${result.stderr}');
    }
    final info = await Directory(p.join(gitDir, 'info')).create();
    // Above the project's own `.gitattributes`: no conversions.
    await File(p.join(info.path, 'attributes'))
        .writeAsString('* -text !eol -filter -ident !working-tree-encoding\n');
    await File(p.join(info.path, 'exclude'))
        .writeAsString('${_excluded.join('\n')}\n');
    await File(p.join(gitDir, 'description'))
        .writeAsString('Snapshots of $root, for reviewing agents\' changes.\n');
  }

  /// `<name>-<FNV-1a of the path>`: readable, and one per path.
  static String _folderName(String root) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(root)) {
      hash ^= byte;
      hash *= 0x100000001b3;
    }
    // Ints are signed: the two halves, unsigned.
    String half(int bits) => bits.toRadixString(16).padLeft(8, '0');
    final name = p.basename(root).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '${name.isEmpty ? 'root' : name}-'
        '${half(hash >>> 32)}${half(hash & 0xFFFFFFFF)}';
  }

  /// Whether `git` runs. On macOS, where `/usr/bin/git` without the
  /// command line tools would ask the user to install them, only once they
  /// are (or another Git comes first on the PATH).
  static final Future<bool> _gitUsable = () async {
    try {
      if (Platform.isMacOS && _onPath('git') == '/usr/bin/git') {
        final tools = await Process.run('xcode-select', ['-p']);
        if (tools.exitCode != 0) return false;
      }
      return (await Process.run('git', ['--version'])).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }();

  static String? _onPath(String name) {
    final path = Platform.environment['PATH'] ?? '';
    for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
      if (directory.isEmpty) continue;
      final candidate = p.join(directory, name);
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  // --- Running Git -----------------------------------------------------------

  /// Operations on the repository's own index, one at a time (conversations
  /// in the same project share it).
  static final Map<String, Future<void>> _locks = {};

  Future<T> _locked<T>(Future<T> Function() body) {
    final result = (_locks[gitDir] ?? Future.value()).then((_) => body());
    _locks[gitDir] = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  static int _scratch = 0;

  /// Runs `git` on the repository and the project, with the index at
  /// [index] (by default its own); fails unless the exit code is in [ok]
  /// (null: any).
  Future<_Output> _git(
    List<String> arguments, {
    List<int>? input,
    String? index,
    Map<String, String> environment = const {},
    Set<int>? ok = const {0},
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final Process process;
    try {
      process = await Process.start(
        'git',
        [
          '--git-dir=$gitDir',
          '--work-tree=$root',
          for (final setting in const [
            'core.autocrlf=false',
            'core.safecrlf=false',
            'core.fsmonitor=false',
            'core.quotePath=false',
            'core.longpaths=true',
          ]) ...['-c', setting],
          ...arguments,
        ],
        workingDirectory: root,
        environment: {
          'GIT_TERMINAL_PROMPT': '0',
          'GIT_OPTIONAL_LOCKS': '0',
          'GIT_INDEX_FILE': index ?? p.join(gitDir, 'index'),
          ...environment,
        },
      );
    } on ProcessException catch (error) {
      throw ReviewUnavailable('Git could not be started: ${error.message}');
    }
    final stdout = BytesBuilder(copy: false);
    final stderr = StringBuffer();
    final reading = Future.wait([
      process.stdout.listen(stdout.add).asFuture<void>(),
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(stderr.write)
          .asFuture<void>(),
    ]);
    // Git may be done before it read it all.
    unawaited(process.stdin.done.catchError((Object _) {}));
    if (input != null) process.stdin.add(input);
    unawaited(process.stdin.close().catchError((Object _) {}));
    final code = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    await reading;
    if (ok != null && !ok.contains(code)) {
      throw GitReviewError(arguments, code, stderr.toString());
    }
    return _Output(code, stdout.takeBytes());
  }

  String _full(String path) => p.join(root, path);

  bool _exists(String path) =>
      FileSystemEntity.typeSync(_full(path), followLinks: false) !=
      FileSystemEntityType.notFound;

  bool _tooLarge(String path) {
    try {
      final file = File(_full(path));
      return FileSystemEntity.typeSync(file.path, followLinks: false) ==
              FileSystemEntityType.file &&
          file.lengthSync() > maxFileBytes;
    } on FileSystemException {
      return false;
    }
  }

  // --- Snapshots -------------------------------------------------------------

  @override
  Future<String> snapshot({Iterable<String>? paths}) => _locked(() async {
    final specs = <String>[];
    if (paths == null) {
      final everything = [
        '.',
        if (_own case final own?) ':(exclude,literal)$own',
      ];
      final changed = (await _git([
        'ls-files',
        '-z',
        '--others',
        '--modified',
        '--exclude-standard',
        '--',
        ...everything,
      ], timeout: const Duration(minutes: 5))).records;
      if (changed.length > maxFiles) {
        throw ReviewUnavailable(
          'The project has too many files to snapshot (${changed.length}).',
        );
      }
      specs.addAll(everything);
      for (final path in changed) {
        if (_tooLarge(path)) specs.add(':(exclude,literal)$path');
      }
    } else {
      final wanted = {
        for (final path in paths)
          if (!_isOwn(path)) path,
      };
      final missing = [
        for (final path in wanted)
          if (!_exists(path)) path,
      ];
      // A file gone counts where the snapshot had it.
      final tracked = missing.isEmpty
          ? const <String>{}
          : (await _git([
              'ls-files',
              '-z',
              '--',
              for (final path in missing) ':(literal)$path',
            ])).records.toSet();
      for (final path in wanted) {
        if (_exists(path) ? !_tooLarge(path) : tracked.contains(path)) {
          specs.add(':(literal)$path');
        }
      }
    }
    if (specs.isNotEmpty) await _add(specs);
    return (await _git(['write-tree'])).text.trim();
  });

  Future<void> _add(List<String> specs) async {
    Future<void> add() => _git(
      [
        'add',
        '-A',
        // A file that cannot be read is left as it was, not the rest.
        '--ignore-errors',
        '--pathspec-from-file=-',
        '--pathspec-file-nul',
      ],
      input: utf8.encode(specs.join('\x00')),
      ok: const {0, 1},
      timeout: const Duration(minutes: 5),
    );
    try {
      await add();
    } on GitReviewError catch (error) {
      // Left by a Git that was killed (one here would have finished; one
      // of another run of the app, long since).
      final lock = File(p.join(gitDir, 'index.lock'));
      if (!error.stderr.contains('index.lock') ||
          !await lock.exists() ||
          DateTime.now().difference(await lock.lastModified()) <
              const Duration(minutes: 5)) {
        rethrow;
      }
      await lock.delete();
      await add();
    }
  }

  static final _rawRecord = RegExp(
    r'^:(\d{6}) (\d{6}) ([0-9a-f]+) ([0-9a-f]+) ',
  );

  @override
  Future<List<ReviewTreeChange>> diff(String from, String to) async {
    if (from == to) return const [];
    final records = (await _git([
      'diff-tree',
      '-r',
      '-z',
      '--no-renames',
      from,
      to,
    ])).records;
    ReviewBlob? blob(String mode, String oid) =>
        mode == '000000' ? null : ReviewBlob(mode, oid);
    return [
      for (var i = 0; i + 1 < records.length; i += 2)
        if (_rawRecord.firstMatch(records[i]) case final match?)
          ReviewTreeChange(
            records[i + 1],
            blob(match[1]!, match[3]!),
            blob(match[2]!, match[4]!),
          ),
    ];
  }

  @override
  Future<Map<String, ({int added, int removed})?>> lineCounts(
    String from,
    String to,
  ) async {
    if (from == to) return const {};
    final records = (await _git([
      'diff-tree',
      '-r',
      '-z',
      '--numstat',
      '--no-renames',
      from,
      to,
    ])).records;
    return {
      for (final record in records)
        if (record.split('\t') case [final added, final removed, ...final path])
          path.join('\t'): switch ((
            int.tryParse(added),
            int.tryParse(removed),
          )) {
            (final added?, final removed?) => (added: added, removed: removed),
            _ => null,
          },
    };
  }

  @override
  Future<String> overlay(String tree, Map<String, ReviewBlob?> entries) async {
    if (entries.isEmpty) return tree;
    final index = p.join(gitDir, 'overlay-$pid-${_scratch++}');
    try {
      await _git(['read-tree', tree], index: index);
      final none = '0' * tree.length;
      await _git(
        ['update-index', '-z', '--add', '--replace', '--index-info'],
        index: index,
        input: utf8.encode(
          [
            for (final MapEntry(key: path, value: blob) in entries.entries)
              blob == null
                  ? '0 $none\t$path\x00'
                  : '${blob.mode} ${blob.oid}\t$path\x00',
          ].join(),
        ),
      );
      return (await _git(['write-tree'], index: index)).text.trim();
    } finally {
      for (final file in [index, '$index.lock']) {
        try {
          await File(file).delete();
        } on FileSystemException {
          // Not there.
        }
      }
    }
  }

  @override
  Future<bool> contains(String tree, String path) async =>
      (await _git(['cat-file', '-e', '$tree:$path'], ok: null)).exitCode == 0;

  // --- Files -----------------------------------------------------------------

  @override
  Future<bool> exists(String path) async => _exists(path);

  @override
  Future<ReviewBlob?> current(String path) async {
    final full = _full(path);
    switch (FileSystemEntity.typeSync(full, followLinks: false)) {
      case FileSystemEntityType.notFound || FileSystemEntityType.directory:
        return null;
      case FileSystemEntityType.link:
        final target = await Link(full).target();
        final hashed = await _git([
          'hash-object',
          '--stdin',
        ], input: utf8.encode(target));
        return ReviewBlob('120000', hashed.text.trim());
      default:
        final hashed = await _git(['hash-object', '--no-filters', '--', path]);
        final executable =
            !Platform.isWindows && File(full).statSync().mode & 0x49 != 0;
        return ReviewBlob(executable ? '100755' : '100644', hashed.text.trim());
    }
  }

  @override
  Future<Uint8List> read(ReviewBlob blob) async =>
      (await _git(['cat-file', 'blob', blob.oid])).bytes;

  @override
  Future<void> restore(String path, ReviewBlob? blob) async {
    final full = _full(path);
    final type = FileSystemEntity.typeSync(full, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      throw ReviewUnavailable('$path is a folder now.');
    }
    if (blob == null) {
      if (type != FileSystemEntityType.notFound) await File(full).delete();
      await _removeEmpty(p.dirname(full));
      return;
    }
    final bytes = await read(blob);
    if (type == FileSystemEntityType.link ||
        (blob.isLink && type != FileSystemEntityType.notFound)) {
      await File(full).delete();
    }
    await Directory(p.dirname(full)).create(recursive: true);
    if (blob.isLink) {
      await Link(full).create(utf8.decode(bytes, allowMalformed: true));
      return;
    }
    await File(full).writeAsBytes(bytes, flush: true);
    if (blob.mode == '100755' && !Platform.isWindows) {
      await Process.run('chmod', ['+x', full]);
    }
  }

  /// Deletes [directory] and those above it while empty, up to the root.
  Future<void> _removeEmpty(String directory) async {
    while (p.isWithin(root, directory)) {
      final folder = Directory(directory);
      try {
        if (!await folder.exists() || !await folder.list().isEmpty) return;
        await folder.delete();
      } on FileSystemException {
        return;
      }
      directory = p.dirname(directory);
    }
  }

  @override
  Future<Uint8List?> merge(String path, ReviewBlob from, ReviewBlob to) async {
    final temp = await Directory.systemTemp.createTemp('baocode-review-');
    try {
      final ours = p.join(temp.path, 'current');
      final base = p.join(temp.path, 'base');
      final theirs = p.join(temp.path, 'other');
      await File(_full(path)).copy(ours);
      await File(base).writeAsBytes(await read(from));
      await File(theirs).writeAsBytes(await read(to));
      final merged = await _git([
        'merge-file',
        '-p',
        '-q',
        ours,
        base,
        theirs,
      ], ok: null);
      // The number of conflicts, or an error (a binary file).
      return merged.exitCode == 0 ? merged.bytes : null;
    } finally {
      await temp.delete(recursive: true);
    }
  }

  @override
  Future<void> write(String path, Uint8List bytes) =>
      File(_full(path)).writeAsBytes(bytes, flush: true);

  // --- Sessions --------------------------------------------------------------

  static final _safeName = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]*$');

  String _ref(String session) {
    if (!_safeName.hasMatch(session) || session.endsWith('.lock')) {
      session = 'h${_folderName(session).split('-').last}';
    }
    return 'refs/baocode/sessions/$session';
  }

  int _saves = 0;

  @override
  Future<String?> load(String session) async {
    final resolved = await _git([
      'rev-parse',
      '-q',
      '--verify',
      '${_ref(session)}^{commit}',
    ], ok: null);
    if (resolved.exitCode != 0) return null;
    final commit = (await _git(['cat-file', 'commit', resolved.text.trim()]))
        .text;
    final body = commit.indexOf('\n\n');
    return body < 0 ? '' : commit.substring(body + 2);
  }

  @override
  Future<void> save(
    String session,
    String data, {
    required Iterable<String> trees,
    required Iterable<ReviewBlob> blobs,
  }) async {
    final entries = [
      for (final (i, tree) in trees.toSet().indexed)
        '040000 tree $tree\tt$i\x00',
      for (final (i, oid) in {for (final blob in blobs) blob.oid}.indexed)
        '100644 blob $oid\tb$i\x00',
    ];
    final tree = (await _git([
      'mktree',
      '-z',
    ], input: utf8.encode(entries.join()))).text.trim();
    const identity = {
      'GIT_AUTHOR_NAME': 'baocode',
      'GIT_AUTHOR_EMAIL': 'baocode@localhost',
      'GIT_COMMITTER_NAME': 'baocode',
      'GIT_COMMITTER_EMAIL': 'baocode@localhost',
    };
    final commit = (await _git(
      ['commit-tree', '--no-gpg-sign', '-F', '-', tree],
      input: utf8.encode(data),
      environment: identity,
    )).text.trim();
    await _git(['update-ref', _ref(session), commit]);
    // Snapshots no session keeps go after Git's grace period.
    if (++_saves % 50 == 0) {
      unawaited(
        _git([
          'gc',
          '--auto',
          '--quiet',
        ], ok: null).then((_) {}, onError: (Object _) {}),
      );
    }
  }

  @override
  Future<void> forget(String session) =>
      _git(['update-ref', '-d', _ref(session)], ok: null);
}
