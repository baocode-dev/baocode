// Plain Dart, no Flutter: tool/release_manifest.dart imports it too.

/// A version as pubspec.yaml writes it: `1.2.0+12`, semver's
/// `major.minor.patch`, an optional pre-release (`1.2.0-beta.1`), and the
/// build number after `+`. Ordered by semver, then by build number (none
/// is 0): `1.2.0+12` is newer than `1.2.0+11`, and `1.2.0-beta.1` older
/// than `1.2.0`.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease = const [],
    this.build = 0,
  });

  final int major;
  final int minor;
  final int patch;

  /// The dot-separated identifiers after `-`; none for a release.
  final List<String> preRelease;

  /// The number after `+`.
  final int build;

  static final _pattern = RegExp(
    r'^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?(?:\+(\d+))?$',
  );

  /// [text] as a version; null when it is not one. `1.2` and `1` are read
  /// as `1.2.0` and `1.0.0`; a leading `v` is allowed.
  static AppVersion? tryParse(String text) {
    final match = _pattern.firstMatch(text.trim());
    if (match == null) return null;
    final preRelease = match.group(4)?.split('.') ?? const <String>[];
    if (preRelease.any((part) => part.isEmpty)) return null;
    int part(int group) => int.parse(match.group(group) ?? '0');
    return AppVersion(
      part(1),
      part(2),
      part(3),
      preRelease: preRelease,
      build: part(5),
    );
  }

  /// [text] as a version; throws a [FormatException] when it is not one.
  static AppVersion parse(String text) =>
      tryParse(text) ?? (throw FormatException('Not a version: "$text"'));

  /// `1.2.0`: without the build number, as the user is shown it.
  String get marketing => [
    '$major.$minor.$patch',
    if (preRelease.isNotEmpty) '-${preRelease.join('.')}',
  ].join();

  @override
  int compareTo(AppVersion other) {
    for (final (a, b) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      if (a != b) return a.compareTo(b);
    }
    final pre = _comparePreRelease(preRelease, other.preRelease);
    if (pre != 0) return pre;
    return build.compareTo(other.build);
  }

  /// Semver's precedence: a release is above its pre-releases; identifiers
  /// compared in turn, numbers numerically and below words.
  static int _comparePreRelease(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return b.length.compareTo(a.length).sign;
    for (var i = 0; i < a.length && i < b.length; i++) {
      final x = int.tryParse(a[i]);
      final y = int.tryParse(b[i]);
      final order = switch ((x, y)) {
        (final x?, final y?) => x.compareTo(y),
        (_?, null) => -1,
        (null, _?) => 1,
        _ => a[i].compareTo(b[i]),
      };
      if (order != 0) return order.sign;
    }
    return a.length.compareTo(b.length).sign;
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode =>
      Object.hash(major, minor, patch, Object.hashAll(preRelease), build);

  /// As pubspec.yaml writes it: `1.2.0+12` (`1.2.0` with no build number).
  @override
  String toString() => build == 0 ? marketing : '$marketing+$build';
}

/// The version this app is: pubspec.yaml's `version`, which
/// test/update/version_test.dart keeps this in step with.
const appVersionString = '1.0.7+8';

final AppVersion currentAppVersion = AppVersion.parse(appVersionString);
