// Extensions of other editors that cannot come along: Microsoft's whose
// license allows them in Microsoft's products only (and which are not on
// Open VSX), with what to use instead; and editor-specific ones, skipped.
//
// Data: change the lists, not the code. A rule's [pattern] is an id, or a
// prefix ending in `*`; ids compare ignoring case. Importing asks Open VSX
// first: an extension of these publishers that is there (ms-toolsai.jupyter
// is) is reinstalled from it like any other.

/// Why an extension cannot be installed from Open VSX.
enum ProprietaryReason {
  /// Licensed for Microsoft's products only.
  license,

  /// Remote development: BaoCode has SSH remotes of its own.
  remoteDevelopment,

  /// An AI assistant: BaoCode has its own agents.
  aiAssistant,

  /// Needs notebooks, which BaoCode does not have.
  notebooks,
}

/// A proprietary extension (or a family of them).
class ProprietaryExtensionRule {
  const ProprietaryExtensionRule(
    this.pattern,
    this.reason, {
    this.alternatives = const [],
  });

  /// `publisher.name`, or `publisher.prefix*`.
  final String pattern;
  final ProprietaryReason reason;

  /// Open VSX extensions that do the same, best first.
  final List<String> alternatives;

  bool matches(String id) => _matches(pattern, id);
}

const proprietaryExtensionRules = <ProprietaryExtensionRule>[
  ProprietaryExtensionRule(
    'ms-python.vscode-pylance',
    ProprietaryReason.license,
    alternatives: ['detachhead.basedpyright'],
  ),
  ProprietaryExtensionRule(
    'ms-vscode.cpptools*',
    ProprietaryReason.license,
    alternatives: [
      'llvm-vs-code-extensions.vscode-clangd',
      'vadimcn.vscode-lldb',
    ],
  ),
  ProprietaryExtensionRule(
    'ms-dotnettools.*',
    ProprietaryReason.license,
    alternatives: ['muhammad-sammy.csharp'],
  ),
  ProprietaryExtensionRule(
    'ms-vscode-remote.*',
    ProprietaryReason.remoteDevelopment,
  ),
  ProprietaryExtensionRule(
    'ms-vscode.remote-*',
    ProprietaryReason.remoteDevelopment,
  ),
  ProprietaryExtensionRule('github.copilot*', ProprietaryReason.aiAssistant),
  ProprietaryExtensionRule('ms-vsliveshare.*', ProprietaryReason.license),
  ProprietaryExtensionRule('ms-toolsai.*', ProprietaryReason.notebooks),
];

/// Extensions skipped outright: another editor's own.
const skippedExtensionPatterns = <String>['anysphere.*'];

/// The rule for [id], if any.
ProprietaryExtensionRule? proprietaryRuleFor(String id) {
  for (final rule in proprietaryExtensionRules) {
    if (rule.matches(id)) return rule;
  }
  return null;
}

/// Whether [id] is skipped outright.
bool isSkippedExtension(String id) =>
    skippedExtensionPatterns.any((pattern) => _matches(pattern, id));

bool _matches(String pattern, String id) {
  final lowerPattern = pattern.toLowerCase();
  final lowerId = id.toLowerCase();
  return lowerPattern.endsWith('*')
      ? lowerId.startsWith(lowerPattern.substring(0, lowerPattern.length - 1))
      : lowerId == lowerPattern;
}
