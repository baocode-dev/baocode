import 'dart:async';

import 'package:flutter/foundation.dart';

import '../channel/channel_setup.dart' show ChannelSetup;
import '../kernel/claude_code/claude_core_setting.dart';
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
  static const actionsKey = 'models.actions';
  static const imageKey = 'models.image';

  /// [actionsModel]'s value for the auxiliary model, whatever it is.
  static const followAuxiliary = 'auxiliary';

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
  /// the provider's main model when the one picked is gone, or is an image
  /// model (not one to converse with).
  (ModelProvider, ProviderModel)? resolve(String? ref) {
    final parsed = parseModelRef(ref);
    if (parsed == null) return null;
    final provider = this.provider(parsed.provider);
    if (provider == null) return null;
    ProviderModel? chat(String id) => switch (provider.model(id)) {
      final model? when !model.kind.generatesImages => model,
      _ => null,
    };
    final model =
        chat(parsed.model) ??
        switch (provider.roles.main) {
          final main? => chat(main),
          null => null,
        };
    if (model == null) return null;
    return (provider, model);
  }

  /// Whether Claude Code as set up on this machine is left out of the
  /// picker.
  bool get builtinHidden => _read(builtinHiddenKey) == true;

  /// Whether there is Claude Code as set up on this machine (its login,
  /// its models, its settings') to run on: only for the CLI. BaoCode's own
  /// core runs on the upstreams here alone, and the channel build on its
  /// account's (lib/channel/): never on this machine's.
  bool get builtinAvailable =>
      !ChannelSetup.channelBuild && ClaudeCore.current() == ClaudeCore.cli;

  /// Whether Claude Code as set up on this machine is in the picker.
  bool get builtinOffered => builtinAvailable && !builtinHidden;

  /// The model a session on BaoCode's own core starts on when the one
  /// picked is no upstream's: the first of the first upstream turned on;
  /// null without one.
  String? get firstModel => switch (enabled.firstOrNull) {
    final provider? => modelRef(provider.id, provider.enabledModels.first.id),
    null => null,
  };

  /// The model new sessions start with (a [modelRef], or a model of the
  /// built-in provider while it is [builtinAvailable]); null for the last
  /// one picked.
  String? get defaultModel => switch (_read(defaultKey)) {
    final String model
        when model.isNotEmpty &&
            (builtinAvailable || parseModelRef(model) != null) =>
      model,
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
  /// Code's own Haiku; picked while it is not [builtinAvailable], it is
  /// automatic.
  ({String? model, bool exact}) auxiliary(String? model) =>
      switch (auxiliaryModel) {
        builtinProviderId when builtinAvailable => (model: null, exact: true),
        null || builtinProviderId => (model: model, exact: false),
        final String picked => (model: picked, exact: true),
      };

  Future<void> setAuxiliaryModel(String? model) => _write(auxiliaryKey, model);

  /// The model the AI actions a user asks for ask (a stash said clearly,
  /// polished, searched by meaning), picked beside them and shared: a
  /// [modelRef], [builtinProviderId] for Claude Code's own Haiku, or
  /// [followAuxiliary]; null while none is picked (they ask first).
  String? get actionsModel => switch (_read(actionsKey)) {
    final String model when model.isNotEmpty => model,
    _ => null,
  };

  /// What an AI action is asked of ([actionsModel], as [auxiliary] gives
  /// one); the auxiliary model while none is picked (or Claude Code's own
  /// Haiku is, while it is not [builtinAvailable]).
  ({String? model, bool exact}) get actions => switch (actionsModel) {
    builtinProviderId when builtinAvailable => (model: null, exact: true),
    null || followAuxiliary || builtinProviderId => auxiliary(null),
    final String picked => (model: picked, exact: true),
  };

  Future<void> setActionsModel(String? model) => _write(actionsKey, model);

  /// The image model the agents make pictures with unless they name
  /// another (a [modelRef]); null for the first turned on.
  String? get imageModel => switch (_read(imageKey)) {
    final String model when model.isNotEmpty => model,
    _ => null,
  };

  Future<void> setImageModel(String? model) => _write(imageKey, model);

  /// The image models the agents make pictures with: those turned on of the
  /// upstreams turned on, [imageModel] first, the others in order.
  List<({ModelProvider provider, ProviderModel model})> get imageModels {
    final all = [
      for (final provider in providers)
        if (provider.enabled && provider.connected)
          for (final model in provider.imageModels)
            (provider: provider, model: model),
    ];
    final picked = imageModel;
    final index = all.indexWhere(
      (entry) => modelRef(entry.provider.id, entry.model.id) == picked,
    );
    if (index <= 0) return all;
    return [all[index], ...all.take(index), ...all.skip(index + 1)];
  }

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

  /// Adds a copy of provider [id] named [name], its key with it; not its
  /// accounts, signed in to anew. Its id; null without [id].
  Future<String?> duplicate(String id, String name) async {
    final source = provider(id);
    if (source == null) return null;
    final copy = newId(name);
    final json = {...source.toJson(), 'id': copy, 'name': name}
      ..remove('accounts');
    await save(ModelProvider.fromJson(json)!);
    if (await key(id) case final key? when key.isNotEmpty) {
      await setKey(copy, key);
    }
    return copy;
  }

  /// Unsets the other providers' roles that pick a model of provider
  /// [id] ([ProviderRoles.without]), of its [models] only when given:
  /// they, or it, gone.
  Future<void> forgetRoles(String id, [Set<String>? models]) async {
    final list = providers;
    final kept = [
      for (final provider in list)
        provider.id == id
            ? provider
            : provider.copyWith(roles: provider.roles.without(id, models)),
    ];
    if (Iterable<int>.generate(list.length)
        .every((i) => kept[i].roles == list[i].roles)) {
      return;
    }
    await _writeProviders(kept);
  }

  /// Removes provider [id], and its key (its accounts' tokens); the other
  /// providers' roles on its models with it.
  Future<void> remove(String id) async {
    final accounts = provider(id)?.accounts ?? const [];
    await _writeProviders([
      for (final provider in providers)
        if (provider.id != id)
          provider.copyWith(roles: provider.roles.without(id)),
    ]);
    if (parseModelRef(defaultModel)?.provider == id) {
      await setDefaultModel(null);
    }
    if (parseModelRef(auxiliaryModel)?.provider == id) {
      await setAuxiliaryModel(null);
    }
    if (parseModelRef(actionsModel)?.provider == id) {
      await setActionsModel(null);
    }
    if (parseModelRef(imageModel)?.provider == id) {
      await setImageModel(null);
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

  final Map<String, Future<String?>> _keys = {};

  /// Provider [id]'s key, from the keychain (read once: the requests that
  /// arrive while the read is under way wait for that same read).
  Future<String?> key(String id) {
    if (_keys[id] case final read?) return read;
    late final Future<String?> read;
    read = secrets.read(ModelProvider.keyRefFor(id)).catchError((
      Object error,
      StackTrace stack,
    ) {
      // A failure, whatever it is, is not kept: the keychain may read it the
      // next time. Until that read answers them all, none of the requests
      // that arrive starts one of its own (one PowerShell for each was the
      // hang). A key set meanwhile stays.
      if (identical(_keys[id], read)) _keys.remove(id);
      if (error is! SecretStoreException) {
        Error.throwWithStackTrace(error, stack);
      }
      debugPrint('Key of $id not read: $error');
      return null;
    });
    return _keys[id] = read;
  }

  /// Keeps [key] for provider [id]; empty removes it.
  Future<void> setKey(String id, String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await secrets.delete(ModelProvider.keyRefFor(id));
      _keys[id] = Future.value();
    } else {
      await secrets.write(ModelProvider.keyRefFor(id), trimmed);
      _keys[id] = Future.value(trimmed);
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
