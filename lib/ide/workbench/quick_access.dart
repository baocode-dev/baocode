// What the quick input lists for its text: the provider of its prefix
// (upstream `IQuickAccessRegistry` and `IQuickAccessProvider`,
// src/vs/platform/quickinput/common/quickAccess.ts), each registered by
// the feature it is of (files, commands, a line, a symbol, the editors).

import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../ide_quick_input.dart';

/// One kind of quick access: what the quick input lists while its text
/// starts with [prefix].
@immutable
class QuickAccessProvider {
  const QuickAccessProvider({
    required this.prefix,
    required this.picks,
    this.placeholder,
    this.contextKey,
    this.onShow,
    this.refresh,
  });

  /// `>` for the commands, `:` for a line…; the files' is empty, the
  /// default (upstream `defaultProvider`).
  final String prefix;

  /// The rows for [filter], the text after [prefix].
  final List<IdeQuickPickItem> Function(BuildContext context, String filter)
  picks;

  /// What the input says while empty; nothing without.
  final String Function(AppLocalizations l10n)? placeholder;

  /// The context key true while it lists (upstream's
  /// `contextKey`: `inFilesPicker`, `inEditorsPicker`).
  final String? contextKey;

  /// As the quick input opens with it (the files listed again).
  final VoidCallback? onShow;

  /// What its rows follow while they show (the files' index, the
  /// symbols).
  final Listenable? Function()? refresh;
}

/// The providers, by prefix: a text's is the longest prefix it starts
/// with (upstream `QuickAccessRegistry.getQuickAccessProvider`).
class QuickAccessRegistry {
  final List<QuickAccessProvider> _providers = [];

  List<QuickAccessProvider> get providers => List.unmodifiable(_providers);

  /// Adds [provider] until the returned callback runs.
  VoidCallback register(QuickAccessProvider provider) {
    _providers.add(provider);
    return () => _providers.remove(provider);
  }

  /// The provider for [text]; null without one (no default registered).
  QuickAccessProvider? providerFor(String text) {
    QuickAccessProvider? found;
    for (final provider in _providers) {
      if (text.startsWith(provider.prefix) &&
          (found == null || provider.prefix.length > found.prefix.length)) {
        found = provider;
      }
    }
    return found;
  }
}
