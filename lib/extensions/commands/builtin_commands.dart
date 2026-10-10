// Built-in commands extensions may call (`vscode.open`, `setContext`,
// `_executeHoverProvider`…): handlers other areas register by id.

import 'dart:async';

/// Runs a built-in command with the extension's (revived) arguments; what
/// it returns goes back to the extension.
typedef BuiltinCommandHandler = FutureOr<Object?> Function(List<Object?> args);

/// Runs every command whose id starts with a prefix
/// (`workbench.view.extension.`): [id] is the whole id.
typedef BuiltinPrefixHandler =
    FutureOr<Object?> Function(String id, List<Object?> args);

/// The built-in commands by id (upstream's `CommandsRegistry` for the
/// commands the workbench itself registers). Areas register theirs:
///
/// ```dart
/// final stop = registry.builtins.register('_executeHoverProvider', (args) => …);
/// ```
///
/// The language features area registers the `_execute*Provider` commands
/// of extHostApiCommands.ts here; the SCM, debug and view areas theirs.
final class BuiltinCommands {
  final _handlers = <String, List<BuiltinCommandHandler>>{};
  final _prefixes = <(String, BuiltinPrefixHandler)>[];
  final _onDidRegister = StreamController<String>.broadcast(sync: true);

  /// Ids as they are registered.
  Stream<String> get onDidRegister => _onDidRegister.stream;

  /// Registers [handler] for [id]; a later registration of the same id
  /// wins until it is removed (as `CommandsRegistry`). Returns what
  /// removes it.
  void Function() register(String id, BuiltinCommandHandler handler) {
    final list = _handlers.putIfAbsent(id, () => []);
    list.add(handler);
    _onDidRegister.add(id);
    return () {
      list.remove(handler);
      if (list.isEmpty && identical(_handlers[id], list)) _handlers.remove(id);
    };
  }

  /// Registers [handler] for every id starting with [prefix].
  void Function() registerPrefix(String prefix, BuiltinPrefixHandler handler) {
    final entry = (prefix, handler);
    _prefixes.add(entry);
    return () => _prefixes.remove(entry);
  }

  /// The handler of [id]: its own, else a prefix's; null when none.
  BuiltinCommandHandler? lookup(String id) {
    final list = _handlers[id];
    if (list != null && list.isNotEmpty) return list.last;
    for (final (prefix, handler) in _prefixes.reversed) {
      if (id.startsWith(prefix) && id.length > prefix.length) {
        return (args) => handler(id, args);
      }
    }
    return null;
  }

  bool has(String id) => lookup(id) != null;

  /// The registered ids (not prefixes).
  Iterable<String> get ids => _handlers.keys;

  void dispose() => unawaited(_onDidRegister.close());
}
