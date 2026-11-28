import 'acp_connection.dart';

/// Google's Antigravity CLI (`agy`) as BaoCode runs it: installed from
/// Google's own release feed, its conversations kept in a folder of
/// BaoCode's (`--gemini-dir`), apart from the user's terminal; signed in
/// as agy is.
///
/// Only the Agent Client Protocol is spoken to it ([AcpConnection]).
abstract interface class AgyRuntime {
  /// The version installed; null when none is.
  Future<String?> version();

  /// The version Google's feed offers for this machine. Throws
  /// [AgyUnavailable] when it could not be asked.
  Future<String> latestVersion();

  /// Downloads Google's build for this machine and installs it, telling
  /// [onProgress] how far it got (0 to 1). The one before stays until the
  /// new one starts; sessions under way keep theirs.
  Future<void> install({void Function(double progress)? onProgress});

  /// Starts `agy acp` for one conversation in [cwd]: one booted ahead
  /// ([warm]) when there is one, its backend up. Throws [AgyUnavailable].
  Future<AcpTransport> start(String cwd);

  /// Boots an agy ahead, for the next [start] to be at once: its backend
  /// asks Google for the account and its models first, seconds that
  /// sending a message would otherwise wait out.
  void warm();

  /// The models the account has, as `agy models` lists them. Throws
  /// [AgyUnavailable] (with [AgyUnavailable.signIn] when not signed in).
  Future<List<AgyModel>> models();

  /// Signs in with a Google account in the browser (ACP `authenticate`);
  /// completes once signed in. Given up once [cancel] completes.
  Future<void> signIn({Future<void>? cancel});

  /// Signs out (ACP `logout`): the terminal's agy too, whose sign-in it is.
  Future<void> signOut();

  /// Deletes what agy keeps of conversation [sessionId], for good. Its
  /// process is to be ended first.
  Future<void> deleteSession(String sessionId);

  /// Ends every agy started (as the process quits).
  Future<void> stopAll();
}

/// A model of the account's, as the picker offers it: thinking levels
/// listed apart (`gemini-3.8-flash` with low, medium and high), as ACP
/// picks them (`thought_level`).
class AgyModel {
  const AgyModel(this.id, this.label, {this.efforts = const []});

  factory AgyModel.fromJson(Map<String, Object?> json) => AgyModel(
    '${json['id'] ?? ''}',
    '${json['label'] ?? ''}',
    efforts: [for (final e in json['efforts'] as List? ?? const []) '$e'],
  );

  final String id;
  final String label;

  /// Its thinking levels, least first; none when it has no choice of them.
  final List<String> efforts;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (efforts.isNotEmpty) 'efforts': efforts,
  };

  @override
  bool operator ==(Object other) =>
      other is AgyModel &&
      other.id == id &&
      other.label == label &&
      _listEquals(other.efforts, efforts);

  @override
  int get hashCode => Object.hash(id, label, Object.hashAll(efforts));

  @override
  String toString() => 'AgyModel($id, $label, $efforts)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What this app tells agy of itself as it connects (`initialize`): no
/// files or terminals of its own to offer (agy reads and runs them itself);
/// forms to put to the user (`elicitation/create`, its questions: without
/// them, agy's ask_question is never put to the user, the turn ended).
const agyHello = {
  'protocolVersion': 1,
  'clientCapabilities': {
    'fs': {'readTextFile': false, 'writeTextFile': false},
    'terminal': false,
    'elicitation': {'form': <String, Object?>{}},
  },
  'clientInfo': {'name': 'baocode', 'title': 'BaoCode', 'version': '1'},
};

/// The thinking levels agy names its models with (`-high`), least first.
const agyEfforts = ['low', 'medium', 'high'];

/// `agy models`' lines (`<id>\t<label>`) as models: those that differ only
/// by a thinking level (`gemini-3.8-flash-high`, `…-low`) as one, its
/// levels its efforts, its label without the level.
List<AgyModel> parseAgyModels(String output) {
  final rows = <(String, String)>[];
  for (final line in output.split('\n')) {
    final parts = line.split('\t');
    if (parts.length < 2) continue;
    final id = parts[0].trim();
    if (id.isEmpty || id.contains(' ')) continue;
    rows.add((id, parts.sublist(1).join('\t').trim()));
  }
  final levels = RegExp('-(${agyEfforts.join('|')})\$');
  final byBase = <String, List<(String, String, String)>>{};
  for (final (id, label) in rows) {
    final match = levels.firstMatch(id);
    if (match == null) continue;
    byBase.putIfAbsent(id.substring(0, match.start), () => []).add((
      id,
      label,
      match.group(1)!,
    ));
  }
  final models = <AgyModel>[];
  final done = <String>{};
  for (final (id, label) in rows) {
    final match = levels.firstMatch(id);
    final base = match == null ? null : id.substring(0, match.start);
    if (base != null && (byBase[base]?.length ?? 0) > 1) {
      if (!done.add(base)) continue;
      final variants = byBase[base]!;
      models.add(
        AgyModel(
          base,
          label.replaceFirst(RegExp(r'\s*\((Low|Medium|High)\)$'), ''),
          efforts: [
            for (final level in agyEfforts)
              if (variants.any((v) => v.$3 == level)) level,
          ],
        ),
      );
      continue;
    }
    if (done.add(id)) models.add(AgyModel(id, label));
  }
  return models;
}

/// agy could not be run: not installed, not signed in, or failing.
class AgyUnavailable implements Exception {
  const AgyUnavailable(
    this.message, {
    this.notInstalled = false,
    this.signIn = false,
    this.detail,
  });

  final String message;
  final bool notInstalled;

  /// Whether signing in is what it takes.
  final bool signIn;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message\n$detail';
}
