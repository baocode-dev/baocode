// What of an extension BaoCode uses: its color themes and file icon themes
// (and the colors and icons they refer to). No extension code runs, so the
// rest of it does nothing here. Told from its manifest alone, before it is
// installed (a .vsix, a folder, a gallery entry) or after.
//
// - Supported: themes and nothing else of note.
// - Partly supported: themes, and code or contributions that will not run
//   (settings or commands of an icon theme that generates its own).
// - Not supported: no theme: it cannot be installed.

import '../vsix/extension_manifest.dart';
import '../vsix/vsix_reader.dart';

/// The verdict.
enum ExtensionCapabilityLevel { full, partial, unsupported }

/// What will not run.
enum CapabilityFindingKind {
  /// Its `main` or `browser` code.
  code,

  /// A `contributes` key ([CapabilityFinding.detail]) other than themes.
  contribution,
}

/// One reason for the verdict: its [kind] and what it is about ([detail]:
/// a contribution's key).
class CapabilityFinding {
  const CapabilityFinding(this.kind, [this.detail]);

  final CapabilityFindingKind kind;
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is CapabilityFinding &&
      other.kind == kind &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, detail);

  @override
  String toString() =>
      'CapabilityFinding(${kind.name}${detail == null ? '' : ', $detail'})';
}

/// The verdict and its reasons.
class CapabilityReport {
  const CapabilityReport({required this.level, this.findings = const []});

  static const fullyUsable = CapabilityReport(
    level: ExtensionCapabilityLevel.full,
  );

  final ExtensionCapabilityLevel level;
  final List<CapabilityFinding> findings;

  /// Whether it may be installed: it has a theme.
  bool get installable => level != ExtensionCapabilityLevel.unsupported;

  @override
  String toString() => 'CapabilityReport(${level.name}, $findings)';
}

/// The contributions BaoCode applies.
const themeContributions = {'themes', 'iconThemes'};

/// What goes with them: the colors and icons themes refer to, and what
/// only describes the extension.
const _usedContributions = {...themeContributions, 'colors', 'icons'};

/// Whether [manifest] contributes a color or file icon theme.
bool hasThemes(ExtensionManifestInfo manifest) =>
    switch (manifest.manifest['contributes']) {
      final Map<Object?, Object?> contributes => themeContributions.any(
        (key) => _present(contributes[key]),
      ),
      _ => false,
    };

/// Classifies the extension whose manifest is [manifest].
CapabilityReport analyzeExtensionCapabilities(ExtensionManifestInfo manifest) {
  final findings = <CapabilityFinding>[
    if (manifest.hasCode) const CapabilityFinding(CapabilityFindingKind.code),
    if (manifest.manifest['contributes'] case final Map<Object?, Object?> c)
      for (final MapEntry(:key, :value) in c.entries)
        if (key is String &&
            !_usedContributions.contains(key) &&
            _present(value))
          CapabilityFinding(CapabilityFindingKind.contribution, key),
  ];
  return CapabilityReport(
    level: !hasThemes(manifest)
        ? ExtensionCapabilityLevel.unsupported
        : findings.isEmpty
        ? ExtensionCapabilityLevel.full
        : ExtensionCapabilityLevel.partial,
    findings: List.unmodifiable(findings),
  );
}

/// [analyzeExtensionCapabilities] of an open package.
CapabilityReport analyzeExtensionPackage(ExtensionPackage package) =>
    analyzeExtensionCapabilities(package.manifest);

bool _present(Object? value) => switch (value) {
  null => false,
  final List list => list.isNotEmpty,
  final Map map => map.isNotEmpty,
  _ => true,
};
