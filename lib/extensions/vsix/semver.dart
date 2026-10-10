// Extension versions (`1.2.3`, `1.2.3-next.4`) compared as semver does
// (VS Code compares them with the `semver` package): numerically, a
// pre-release before its release, its identifiers one by one.

/// Negative when [a] is older than [b], positive when newer, 0 when the
/// same. A part that is not a number counts as 0; build metadata (`+…`)
/// is ignored.
int compareExtensionVersions(String a, String b) {
  final (coreA, preA) = _split(a);
  final (coreB, preB) = _split(b);
  for (var i = 0; i < 3; i++) {
    final diff = (i < coreA.length ? coreA[i] : 0).compareTo(
      i < coreB.length ? coreB[i] : 0,
    );
    if (diff != 0) return diff.sign;
  }
  if (preA == null) return preB == null ? 0 : 1;
  if (preB == null) return -1;
  final (partsA, partsB) = (preA.split('.'), preB.split('.'));
  for (var i = 0; i < partsA.length && i < partsB.length; i++) {
    final (x, y) = (partsA[i], partsB[i]);
    final (nx, ny) = (int.tryParse(x), int.tryParse(y));
    final int diff;
    if (nx != null && ny != null) {
      diff = nx.compareTo(ny);
    } else if (nx != null) {
      diff = -1;
    } else if (ny != null) {
      diff = 1;
    } else {
      diff = x.compareTo(y);
    }
    if (diff != 0) return diff.sign;
  }
  return partsA.length.compareTo(partsB.length).sign;
}

/// Whether [version] is `major.minor.patch` with an optional pre-release
/// and build (`semver.valid`, loosely).
bool isSemver(String version) => _semver.hasMatch(version.trim());

final _semver = RegExp(
  r'^v?\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$',
);

(List<int>, String?) _split(String version) {
  var text = version.trim();
  if (text.startsWith('v')) text = text.substring(1);
  final plus = text.indexOf('+');
  if (plus >= 0) text = text.substring(0, plus);
  final dash = text.indexOf('-');
  final core = dash >= 0 ? text.substring(0, dash) : text;
  final pre = dash >= 0 ? text.substring(dash + 1) : null;
  return ([for (final part in core.split('.')) int.tryParse(part) ?? 0], pre);
}
