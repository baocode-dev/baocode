import 'dart:async';

import 'package:flutter/foundation.dart';

import '../settings/user_settings.dart';
import 'model_provider.dart';
import 'secret_store.dart';

/// The upstreams Settings → Models keeps, read from settings.json and
/// written back to it; their keys in the keychain ([SecretStore]).
///
/// Also what the app learned of them while it ran (a failed connection),
/// which the picker marks; not kept.
class ModelProviders extends ChangeNotifier {
  ModelProviders({
    required this._read,
    required this._write,
    Listenable? changes,
    this._secrets,
  }) : _changes = changes {
    changes?.addListener(_changed);
  }

  /// Kept in [settings].
  factory ModelProviders.settings(
    UserSettings settings, {
    SecretStore? secrets,
  }) => ModelProviders(
    read: (key) => settings[key],
    write: settings.update,
    changes: settings,
    secrets: secrets,
  );

  /// Kept in memory, e.g. under test.
  factory ModelProviders.memory({
    List<ModelProvider> providers = const [],
    SecretStore? secrets,
  }) {
    final values = <String, Object?>{
      providersKey: [for (final provider in providers) provider.toJson()],
    };
    late final ModelProviders store;
    store = ModelProviders(
      read: (key) => values[key],
      write: (key, value) async {
        if (value == null) {
          values.remove(key);
        } else {
          values[key] = value;
        }
        store._changed();
      },
      secrets: secrets ?? MemorySecretStore(),
    );
    return store;
  }

  /// The app's; main() points it at settings.json.
  static ModelProviders current = ModelProviders.memory();

  static const providersKey = 'models.providers';
  static const builtinHiddenKey = 'models.builtin.hidden';
  static const defaultKey = 'models.default';
  static const auxiliaryKey = 'models.auxiliary';

  final Object? Function(String key) _read;
  final Future<void> Function(String key, Object? value) _write;
  final Listenable? _changes;
  final SecretStore? _secrets;

  SecretStore get secrets => _secrets ?? SecretStore.instance;

  List<ModelProvider>? _cache;

  void _changed() {
    _cache = null;
    notifyListeners();
  }

  /// All of them, in the order they were added.
  List<ModelProvider> get providers => _cache ??= [
    for (final json in switch (_read(providersKey)) {
      final List list => list,
      _ => const [],
    })
      ?ModelProvider.fromJson(json),
  ];

  /// Those offered in the picker.
  List<ModelProvider> get enabled => [
    for (final provider in providers)
      if (provider.enabled && provider.enabledModels.isNotEmpty) provider,
  ];

  ModelProvider? provider(String? id) =>
      providers.where((provider) => provider.id == id).firstOrNull;

  /// The provider and model [ref] (a [modelRef]) picks, if both are there;
  /// the provider's main model when the one picked is gone.
  (ModelProvider, ProviderModel)? resolve(String? ref) {
    final parsed = parseModelRef(ref);
    if (parsed == null) return null;
    final provider = this.provider(parsed.provider);
    if (provider == null) return null;
    final model =
        provider.model(parsed.model) ??
        switch (provider.roles.main) {
          final main? => provider.model(main),
          null => null,
        };
    if (model == null) return null;
    return (provider, model);
  }

  /// Whether Claude Code as set up on this machine is left out of the
  /// picker.
  bool get builtinHidden => _read(builtinHiddenKey) == true;

  /// The model new sessions start with (a [modelRef], or a model of the
  /// built-in provider); null for the last one picked.
  String? get defaultModel => switch (_read(defaultKey)) {
    final String model when model.isNotEmpty => model,
    _ => null,
  };

  /// The auxiliary model, as kept: what the app's own small jobs ask
  /// (agents' titles, commit messages). A [modelRef], or
  /// [builtinProviderId] for Claude Code's own Haiku; null for automatic.
  String? get auxiliaryModel => switch (_read(auxiliaryKey)) {
    final String model when model.isNotEmpty => model,
    _ => null,
  };

  /// What a small job is asked of: the auxiliary model, as it is
  /// ([exact]); automatic, [model] (the session's, or new sessions'
  /// default), by its provider's Haiku tier. A null model is Claude
  /// Code's own Haiku.
  ({String? model, bool exact}) auxiliary(String? model) =>
      switch (auxiliaryModel) {
        builtinProviderId => (model: null, exact: true),
        final String picked => (model: picked, exact: true),
        null => (model: model, exact: false),
      };

  Future<void> setAuxiliaryModel(String? model) => _write(auxiliaryKey, model);

  /// Adds [provider], or replaces the one of its id.
  Future<void> save(ModelProvider provider) async {
    final list = [...providers];
    final index = list.indexWhere((p) => p.id == provider.id);
    if (index < 0) {
      list.add(provider);
    } else {
      list[index] = provider;
    }
    await _writeProviders(list);
  }

  /// Removes provider [id], and its key (its accounts' tokens).
  Future<void> remove(String id) async {
    final accounts = provider(id)?.accounts ?? const [];
    await _writeProviders([
      for (final provider in providers)
        if (provider.id != id) provider,
    ]);
    if (parseModelRef(defaultModel)?.provider == id) {
      await setDefaultModel(null);
    }
    if (parseModelRef(auxiliaryModel)?.provider == id) {
      await setAuxiliaryModel(null);
    }
    _errors.remove(id);
    try {
      await secrets.delete(ModelProvider.keyRefFor(id));
      for (final account in accounts) {
        await secrets.delete(ModelProvider.accountRefFor(id, account.id));
      }
    } on SecretStoreException catch (error) {
      debugPrint('Key of $id not removed: $error');
    }
  }

  Future<void> _writeProviders(List<ModelProvider> list) async {
    _cache = list;
    notifyListeners();
    await _write(providersKey, [
      for (final provider in list) provider.toJson(),
    ]);
  }

  Future<void> setBuiltinHidden(bool hidden) =>
      _write(builtinHiddenKey, hidden ? true : null);

  Future<void> setDefaultModel(String? model) => _write(defaultKey, model);

  /// A fresh id for a new provider, from its [name].
  String newId(String name) {
    final base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stem = base.isEmpty || base == builtinProviderId ? 'provider' : base;
    var id = stem;
    for (var n = 2; provider(id) != null; n++) {
      id = '$stem-$n';
    }
    return id;
  }

  // --- Keys -------------------------------------------------------------------------

  final Map<String, String?> _keys = {};

  /// Provider [id]'s key, from the keychain (read once).
  Future<String?> key(String id) async {
    if (_keys.containsKey(id)) return _keys[id];
    try {
      return _keys[id] = await secrets.read(ModelProvider.keyRefFor(id));
    } on SecretStoreException catch (error) {
      debugPrint('Key of $id not read: $error');
      return null;
    }
  }

  /// Keeps [key] for provider [id]; empty removes it.
  Future<void> setKey(String id, String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await secrets.delete(ModelProvider.keyRefFor(id));
      _keys[id] = null;
    } else {
      await secrets.write(ModelProvider.keyRefFor(id), trimmed);
      _keys[id] = trimmed;
    }
    notifyListeners();
  }

  // --- What went wrong ---------------------------------------------------------------

  final Map<String, String> _errors = {};

  /// Why provider [id] last failed, while it is not known to work again.
  String? error(String id) => _errors[id];

  void reportError(String id, String? error) {
    if (_errors[id] == error) return;
    if (error == null) {
      _errors.remove(id);
    } else {
      _errors[id] = error;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _changes?.removeListener(_changed);
    super.dispose();
  }
}
