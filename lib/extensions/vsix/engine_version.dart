/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Whether an extension's `engines.vscode` accepts the VS Code version the
// extension host is.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/extensions/common/extensionValidator.ts (`IParsedVersion`,
// `INormalizedVersion`, `isValidVersionStr`, `parseVersion`,
// `normalizeVersion`, `isValidVersion`, `isValidExtensionVersion`,
// `isEngineValid`, `isVersionValid`).
//
// Deviations: notices are [EngineNotice]s (a kind and its values) for the
// UI to word; the product date is a [DateTime].

/// The VS Code version the extension host runtime is (VSCodium REH
/// 1.135.06055 is upstream 1.135.0; see docs/extensions/PROGRESS.md).
const extensionHostEngineVersion = '1.135.0';

/// `IParsedVersion`.
class ParsedEngineVersion {
  const ParsedEngineVersion({
    required this.hasCaret,
    required this.hasGreaterEquals,
    required this.majorBase,
    required this.majorMustEqual,
    required this.minorBase,
    required this.minorMustEqual,
    required this.patchBase,
    required this.patchMustEqual,
    required this.preRelease,
  });

  final bool hasCaret;
  final bool hasGreaterEquals;
  final int majorBase;
  final bool majorMustEqual;
  final int minorBase;
  final bool minorMustEqual;
  final int patchBase;
  final bool patchMustEqual;
  final String? preRelease;
}

/// `INormalizedVersion`.
class NormalizedEngineVersion {
  const NormalizedEngineVersion({
    required this.majorBase,
    required this.majorMustEqual,
    required this.minorBase,
    required this.minorMustEqual,
    required this.patchBase,
    required this.patchMustEqual,
    required this.notBefore,
    required this.isMinimum,
  });

  final int majorBase;
  final bool majorMustEqual;
  final int minorBase;
  final bool minorMustEqual;
  final int patchBase;
  final bool patchMustEqual;

  /// Milliseconds since the epoch, or 0.
  final int notBefore;
  final bool isMinimum;
}

final _versionRegExp = RegExp(
  r'^(\^|>=)?((\d+)|x)\.((\d+)|x)\.((\d+)|x)(\-.*)?$',
);
final _notBeforeRegExp = RegExp(r'^-(\d{4})(\d{2})(\d{2})(\d{2})?(\d{2})?$');

/// `isValidVersionStr`.
bool isValidEngineVersionString(String version) {
  version = version.trim();
  return version == '*' || _versionRegExp.hasMatch(version);
}

/// `parseVersion`.
ParsedEngineVersion? parseEngineVersion(String version) {
  if (!isValidEngineVersionString(version)) return null;
  version = version.trim();
  if (version == '*') {
    return const ParsedEngineVersion(
      hasCaret: false,
      hasGreaterEquals: false,
      majorBase: 0,
      majorMustEqual: false,
      minorBase: 0,
      minorMustEqual: false,
      patchBase: 0,
      patchMustEqual: false,
      preRelease: null,
    );
  }
  final m = _versionRegExp.firstMatch(version);
  if (m == null) return null;
  return ParsedEngineVersion(
    hasCaret: m[1] == '^',
    hasGreaterEquals: m[1] == '>=',
    majorBase: m[2] == 'x' ? 0 : int.parse(m[2]!),
    majorMustEqual: m[2] != 'x',
    minorBase: m[4] == 'x' ? 0 : int.parse(m[4]!),
    minorMustEqual: m[4] != 'x',
    patchBase: m[6] == 'x' ? 0 : int.parse(m[6]!),
    patchMustEqual: m[6] != 'x',
    preRelease: (m[8]?.isEmpty ?? true) ? null : m[8],
  );
}

/// `normalizeVersion`.
NormalizedEngineVersion? normalizeEngineVersion(ParsedEngineVersion? version) {
  if (version == null) return null;
  var minorMustEqual = version.minorMustEqual;
  var patchMustEqual = version.patchMustEqual;
  if (version.hasCaret) {
    if (version.majorBase == 0) {
      patchMustEqual = false;
    } else {
      minorMustEqual = false;
      patchMustEqual = false;
    }
  }
  var notBefore = 0;
  if (version.preRelease case final preRelease?) {
    final match = _notBeforeRegExp.firstMatch(preRelease);
    if (match != null) {
      notBefore = DateTime.utc(
        int.parse(match[1]!),
        int.parse(match[2]!),
        int.parse(match[3]!),
        int.tryParse(match[4] ?? '') ?? 0,
        int.tryParse(match[5] ?? '') ?? 0,
      ).millisecondsSinceEpoch;
    }
  }
  return NormalizedEngineVersion(
    majorBase: version.majorBase,
    majorMustEqual: version.majorMustEqual,
    minorBase: version.minorBase,
    minorMustEqual: minorMustEqual,
    patchBase: version.patchBase,
    patchMustEqual: patchMustEqual,
    isMinimum: version.hasGreaterEquals,
    notBefore: notBefore,
  );
}

/// `isValidVersion`: whether the product's [version] (released on
/// [productDate]) satisfies [desired].
bool isValidEngineVersion(
  String version,
  DateTime? productDate,
  String desired,
) {
  final current = normalizeEngineVersion(parseEngineVersion(version));
  final wanted = normalizeEngineVersion(parseEngineVersion(desired));
  if (current == null || wanted == null) return false;
  return _isValidVersion(current, productDate, wanted);
}

bool _isValidVersion(
  NormalizedEngineVersion version,
  DateTime? productDate,
  NormalizedEngineVersion desiredVersion,
) {
  final productTs = productDate?.millisecondsSinceEpoch;
  final majorBase = version.majorBase;
  final minorBase = version.minorBase;
  final patchBase = version.patchBase;

  var desiredMajorBase = desiredVersion.majorBase;
  var desiredMinorBase = desiredVersion.minorBase;
  var desiredPatchBase = desiredVersion.patchBase;
  final desiredNotBefore = desiredVersion.notBefore;

  var majorMustEqual = desiredVersion.majorMustEqual;
  var minorMustEqual = desiredVersion.minorMustEqual;
  var patchMustEqual = desiredVersion.patchMustEqual;

  if (desiredVersion.isMinimum) {
    if (majorBase > desiredMajorBase) return true;
    if (majorBase < desiredMajorBase) return false;
    if (minorBase > desiredMinorBase) return true;
    if (minorBase < desiredMinorBase) return false;
    if (productTs != null && productTs != 0 && productTs < desiredNotBefore) {
      return false;
    }
    return patchBase >= desiredPatchBase;
  }

  // Anything < 1.0.0 is compatible with >= 1.0.0, except exact matches
  if (majorBase == 1 &&
      desiredMajorBase == 0 &&
      (!majorMustEqual || !minorMustEqual || !patchMustEqual)) {
    desiredMajorBase = 1;
    desiredMinorBase = 0;
    desiredPatchBase = 0;
    majorMustEqual = true;
    minorMustEqual = false;
    patchMustEqual = false;
  }

  if (majorBase < desiredMajorBase) return false;
  if (majorBase > desiredMajorBase) return !majorMustEqual;
  if (minorBase < desiredMinorBase) return false;
  if (minorBase > desiredMinorBase) return !minorMustEqual;
  if (patchBase < desiredPatchBase) return false;
  if (patchBase > desiredPatchBase) return !patchMustEqual;
  if (productTs != null && productTs != 0 && productTs < desiredNotBefore) {
    return false;
  }
  return true;
}

/// Why an `engines.vscode` was not accepted.
enum EngineNoticeKind {
  /// `versionSyntax`: it does not parse.
  syntax,

  /// `versionSpecificity1`/`2`: too loose (`*`, `x.x.x`, `0.x.y`).
  notSpecific,

  /// `versionMismatch`: it wants another version.
  mismatch,

  /// `engines.vscode` is missing or not a string.
  missing,
}

/// A notice of [isEngineCompatible]: its [kind], the [requested] range and
/// the [current] version, to word in the UI.
class EngineNotice {
  const EngineNotice(this.kind, this.requested, this.current);

  final EngineNoticeKind kind;
  final String requested;
  final String current;

  /// Upstream's English wording.
  String get message => switch (kind) {
    EngineNoticeKind.syntax =>
      'Could not parse `engines.vscode` value $requested. Please use, for '
          'example: ^1.22.0, ^1.22.x, etc.',
    EngineNoticeKind.notSpecific =>
      'Version specified in `engines.vscode` ($requested) is not specific '
          'enough.',
    EngineNoticeKind.mismatch =>
      'Extension is not compatible with Code $current. Extension requires: '
          '$requested.',
    EngineNoticeKind.missing =>
      'property `engines.vscode` is mandatory and must be of type `string`',
  };

  @override
  String toString() => message;
}

/// `isVersionValid`: whether [requested] (an `engines.vscode`) accepts
/// [currentVersion]; why not is added to [notices].
bool isEngineCompatible(
  String requested, {
  String currentVersion = extensionHostEngineVersion,
  DateTime? productDate,
  List<EngineNotice>? notices,
}) {
  final desiredVersion = normalizeEngineVersion(parseEngineVersion(requested));
  if (desiredVersion == null) {
    notices?.add(
      EngineNotice(EngineNoticeKind.syntax, requested, currentVersion),
    );
    return false;
  }
  // enforce that a breaking API version is specified.
  // for 0.X.Y, that means up to 0.X must be specified
  // otherwise for Z.X.Y, that means Z must be specified
  if (desiredVersion.majorBase == 0) {
    if (!desiredVersion.majorMustEqual || !desiredVersion.minorMustEqual) {
      notices?.add(
        EngineNotice(EngineNoticeKind.notSpecific, requested, currentVersion),
      );
      return false;
    }
  } else if (!desiredVersion.majorMustEqual) {
    notices?.add(
      EngineNotice(EngineNoticeKind.notSpecific, requested, currentVersion),
    );
    return false;
  }
  final current = normalizeEngineVersion(parseEngineVersion(currentVersion));
  if (current == null ||
      !_isValidVersion(current, productDate, desiredVersion)) {
    notices?.add(
      EngineNotice(EngineNoticeKind.mismatch, requested, currentVersion),
    );
    return false;
  }
  return true;
}

/// `isEngineValid`: `*` is valid too (galleries' engine checks).
bool isEngineValid(
  String engine, {
  String version = extensionHostEngineVersion,
  DateTime? productDate,
}) =>
    engine == '*' ||
    isEngineCompatible(
      engine,
      currentVersion: version,
      productDate: productDate,
    );

/// `isValidExtensionVersion`: built-in and declarative extensions (no
/// `main`, no `browser`) are not checked.
bool isValidExtensionVersion({
  required String? engine,
  required bool hasCode,
  bool builtin = false,
  String version = extensionHostEngineVersion,
  DateTime? productDate,
  List<EngineNotice>? notices,
}) {
  if (builtin || !hasCode) return true;
  if (engine == null) {
    notices?.add(EngineNotice(EngineNoticeKind.missing, '', version));
    return false;
  }
  return isEngineCompatible(
    engine,
    currentVersion: version,
    productDate: productDate,
    notices: notices,
  );
}
