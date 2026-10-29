import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_dialog.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_input.dart';
import '../../ide/ide_menu.dart';
import '../../icons/project_icon.dart';
import '../../icons/project_icon_picker.dart';
import '../../kernel/claude_code/claude_haiku.dart';
import '../../l10n/l10n.dart';
import '../../models/codex/codex_api.dart' show codexClientVersion;
import '../../models/codex/codex_quota_format.dart';
import '../../models/codex/codex_service.dart';
import '../../models/codex/codex_usage.dart';
import '../../models/auxiliary_model_menu.dart';
import '../../models/featured_upstreams.dart';
import '../../models/model_icons.dart';
import '../../models/model_provider.dart';
import '../../models/model_providers.dart';
import '../../models/model_runtime.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../chat/widgets/hover_builder.dart';
import '../../chat/widgets/pixel_loader.dart';
import '../../workspace/workspace.dart';
import 'featured_upstreams_strip.dart';
import 'model_dialogs.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';
import '../../ide/ide_back_button.dart';

/// Asks [model] of [provider] [modelTestPrompt]; its reply, timed.
/// Completing [cancel] stops it.
typedef ModelTester = Future<ClaudeTimedAnswer> Function(
  ModelProvider provider,
  ProviderModel model, {
  Future<void>? cancel,
});

/// What a model is tested with: long enough an answer to show it streams.
const modelTestPrompt =
    'Output the numbers 1 through 120 separated by a single space. '
    'No commas, no newlines, no explanation.';

/// Tests [model] through Claude Code, as a session reaches it: the
/// provider's environment, the proxy, the upstream.
Future<ClaudeTimedAnswer> testModelThroughClaudeCode(
  ModelProvider provider,
  ProviderModel model, {
  Future<void>? cancel,
}) => timeClaudeAnswer(
  'Do exactly as asked.',
  modelTestPrompt,
  model: modelRef(provider.id, model.id),
  cancel: cancel,
);

/// Settings → Models: Claude Code as set up on this machine, and the
/// upstreams added ([ModelProviders]), the model new sessions start with;
/// an upstream's own page when one is opened.
class ModelsSettingsPage extends StatefulWidget {
  const ModelsSettingsPage({
    super.key,
    required this.providers,
    this.listModels = listUpstreamModels,
    this.testModel = testModelThroughClaudeCode,
    this.codex,
    this.workspace,
    this.featured,
  });

  final ModelProviders providers;
  final ModelLister listModels;
  final ModelTester testModel;

  /// The ChatGPT (Codex) providers' accounts; the app's when null.
  final CodexService? codex;

  /// Whose icon picker an upstream's icon is picked in (its pictures, the
  /// icons picked last); none picked when null.
  final Workspace? workspace;

  /// The upstreams shown cards of; the app's when null (see
  /// [FeaturedUpstreamsStrip]).
  final Future<List<FeaturedUpstream>>? featured;

  /// An upstream to open the page of, as the page shows next (or now, if
  /// it does): one just imported. Taken as it is opened.
  static final ValueNotifier<String?> reveal = ValueNotifier(null);

  /// Adds an upstream named [name], to be filled in: its id.
  static Future<String> addUpstream(
    ModelProviders providers,
    String name,
  ) async {
    final id = providers.newId(name);
    await providers.save(
      ModelProvider(id: id, name: name, disableNonessentialTraffic: true),
    );
    return id;
  }

  /// The protocol's name, as the list and the detail show it.
  static String protocolName(BuildContext context, ProviderProtocol value) {
    final l10n = context.l10n;
    return switch (value) {
      ProviderProtocol.anthropic => l10n.modelsProtocolAnthropic,
      ProviderProtocol.openaiChat => 'OpenAI Chat Completions',
      ProviderProtocol.openaiResponses => 'OpenAI Responses',
      ProviderProtocol.codex => 'ChatGPT (Codex)',
    };
  }

  @override
  State<ModelsSettingsPage> createState() => _ModelsSettingsPageState();
}

class _ModelsSettingsPageState extends State<ModelsSettingsPage> {
  /// The upstream whose page shows; the list when null.
  String? _open;

  ModelProviders get _providers => widget.providers;

  /// The sites listed (see [ModelsSettingsPage.featured]).
  late final Future<List<FeaturedUpstream>> _featured =
      widget.featured ?? FeaturedUpstream.load();

  /// The hosts of [_featured], once got, then of the list got again behind
  /// it as it answers: their upstreams lead the list.
  Set<String> _listedHosts = const {};
  bool _relisted = false;

  /// Whether [_featured] is the app's, got again behind it.
  bool get _follows => widget.featured == null;

  @override
  void initState() {
    super.initState();
    _reveal();
    ModelsSettingsPage.reveal.addListener(_reveal);
    if (_follows) FeaturedUpstream.known.addListener(_relist);
    unawaited(
      _featured.then((listed) {
        // Not where the new list answered before it.
        if (mounted && !_relisted) _takeHosts(listed);
      }),
    );
  }

  void _takeHosts(List<FeaturedUpstream> listed) {
    setState(() => _listedHosts = {for (final u in listed) ...u.hosts});
  }

  /// The list [FeaturedUpstream.load] got again; an empty one changes
  /// nothing.
  void _relist() {
    final listed = FeaturedUpstream.known.value;
    if (listed.isEmpty || !mounted) return;
    _relisted = true;
    _takeHosts(listed);
  }

  @override
  void dispose() {
    ModelsSettingsPage.reveal.removeListener(_reveal);
    if (_follows) FeaturedUpstream.known.removeListener(_relist);
    super.dispose();
  }

  void _reveal() {
    final id = ModelsSettingsPage.reveal.value;
    if (id == null) return;
    ModelsSettingsPage.reveal.value = null;
    if (mounted) setState(() => _open = id);
  }

  Future<void> _add() async {
    final id = await ModelsSettingsPage.addUpstream(
      _providers,
      context.l10n.modelsNewProviderName,
    );
    if (mounted) setState(() => _open = id);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _providers,
    builder: (context, _) {
      final open = _providers.provider(_open);
      if (open != null) {
        return ProviderSettingsPage(
          key: ValueKey(open.id),
          providers: _providers,
          provider: open,
          listModels: widget.listModels,
          testModel: widget.testModel,
          codex: widget.codex ?? codexService,
          workspace: widget.workspace,
          onBack: () => setState(() => _open = null),
          onOpen: (id) => setState(() => _open = id),
        );
      }
      return _list(context);
    },
  );

  String _defaultName(BuildContext context, String? value) {
    final l10n = context.l10n;
    if (value == null) return l10n.modelsDefaultLast;
    if (_providers.resolve(value) case (final provider, final model)) {
      return '${provider.name} · ${model.displayName}';
    }
    if (value == 'default') return l10n.modelsBuiltinDefault;
    return value;
  }

  String _auxiliaryName(BuildContext context, String? value) {
    final l10n = context.l10n;
    if (value == null) return l10n.modelsAuxiliaryAuto;
    if (value == builtinProviderId) {
      // Not there on BaoCode's own core: automatic in its place.
      return _providers.builtinAvailable
          ? l10n.modelsAuxiliaryBuiltin
          : l10n.modelsAuxiliaryAuto;
    }
    return _defaultName(context, value);
  }

  /// The auxiliary model: what titles and commit messages ask.
  Widget _auxiliaryRow(BuildContext context) {
    final l10n = context.l10n;
    final current = _providers.auxiliaryModel;
    final shown = _auxiliaryName(context, current);
    void set(String? model) => unawaited(_providers.setAuxiliaryModel(model));
    return SettingsRow(
      label: l10n.modelsAuxiliary,
      description: l10n.modelsAuxiliaryDescription,
      trailing: SettingsDropdown(
        current: shown,
        semanticLabel: l10n.modelsChoiceLabel(l10n.modelsAuxiliary, shown),
        entries: () => auxiliaryModelEntries(
          l10n,
          _providers,
          current: current,
          onPick: set,
        ),
      ),
    );
  }

  /// The image model: what the agents make pictures with.
  Widget _imageRow(BuildContext context) {
    final l10n = context.l10n;
    final current = _providers.imageModel;
    final models = _providers.imageModels;
    // The default first among them, where it is still there.
    final shown = switch ((current, models.firstOrNull)) {
      (_, null) => l10n.modelsImageNone,
      (final String picked, (:final provider, :final model))
          when modelRef(provider.id, model.id) == picked =>
        '${provider.name} · ${model.displayName}',
      _ => l10n.modelsImageFirst,
    };
    void set(String? model) => unawaited(_providers.setImageModel(model));
    final providers = <ModelProvider>[];
    for (final (:provider, model: _) in models) {
      if (!providers.contains(provider)) providers.add(provider);
    }
    return SettingsRow(
      label: l10n.modelsImage,
      description: l10n.modelsImageDescription,
      trailing: SettingsDropdown(
        current: shown,
        semanticLabel: l10n.modelsChoiceLabel(l10n.modelsImage, shown),
        entries: () => [
          IdeMenuAction(
            l10n.modelsImageFirst,
            checked: current == null,
            enabled: models.isNotEmpty,
            onSelected: () => set(null),
          ),
          if (providers.isNotEmpty) const IdeMenuSeparator(),
          for (final provider in providers)
            IdeMenuAction(
              provider.name,
              checked: parseModelRef(current)?.provider == provider.id,
              submenu: [
                for (final model in provider.imageModels)
                  IdeMenuAction(
                    model.displayName,
                    checked: current == modelRef(provider.id, model.id),
                    onSelected: () => set(modelRef(provider.id, model.id)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context) {
    final l10n = context.l10n;
    // The newest such: one imported later takes the place of one before.
    final providers = _providers.providers;
    ModelProvider? pinned;
    for (final provider in providers) {
      if (_listedHosts.contains(provider.host.toLowerCase())) pinned = provider;
    }
    final current = _providers.defaultModel;
    final shown = _defaultName(context, current);
    return SettingsPage(
      title: l10n.modelsTitle,
      lead: FeaturedUpstreamsStrip(
        upstreams: _featured,
        follow: _follows,
        hosts: [for (final provider in _providers.providers) provider.host],
      ),
      children: [
        SettingsCard(
          children: [
            SettingsRow(
              label: l10n.modelsDefault,
              description: l10n.modelsDefaultDescription,
              trailing: SettingsDropdown(
                current: shown,
                semanticLabel: l10n.modelsChoiceLabel(
                  l10n.modelsDefault,
                  shown,
                ),
                entries: () => [
                  IdeMenuAction(
                    l10n.modelsDefaultLast,
                    checked: current == null,
                    onSelected: () =>
                        unawaited(_providers.setDefaultModel(null)),
                  ),
                  const IdeMenuSeparator(),
                  if (_providers.builtinOffered)
                    IdeMenuAction(
                      l10n.modelsBuiltinDefault,
                      checked: current == 'default',
                      onSelected: () =>
                          unawaited(_providers.setDefaultModel('default')),
                    ),
                  for (final provider in _providers.enabled)
                    IdeMenuAction(
                      provider.name,
                      checked: parseModelRef(current)?.provider == provider.id,
                      submenu: [
                        for (final model in provider.enabledModels)
                          IdeMenuAction(
                            model.displayName,
                            checked: current == modelRef(provider.id, model.id),
                            onSelected: () => unawaited(
                              _providers.setDefaultModel(
                                modelRef(provider.id, model.id),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            _auxiliaryRow(context),
            _imageRow(context),
          ],
        ),
        SettingsGroup(
          title: l10n.modelsProviders,
          children: [
            // Claude Code as set up on this machine: the CLI's alone, not
            // BaoCode's own core's.
            if (_providers.builtinAvailable)
              _ProviderRow(
                icon: const ProviderIcon(builtinProviderId, size: 16),
                name: l10n.modelsBuiltinName,
                badge: l10n.modelsBuiltinBadge,
                detail: l10n.modelsBuiltinDescription,
                status: _providers.builtinHidden ? _Status.off : _Status.ready,
                enabled: !_providers.builtinHidden,
                switchLabel: l10n.modelsEnableProvider(l10n.modelsBuiltinName),
                onEnabled: (value) =>
                    unawaited(_providers.setBuiltinHidden(!value)),
              ),
            // The newest at a site BaoCode lists first (one imported later
            // takes the place of one before); the rest in their order.
            for (final provider in [
              ?pinned,
              ...providers.where((provider) => provider != pinned),
            ])
              _ProviderRow(
                icon: ProviderIconView(
                  icon: providerIconOf(provider),
                  site: providerSite(provider),
                  size: 16,
                ),
                name: provider.name,
                badge: ModelsSettingsPage.protocolName(
                  context,
                  provider.protocol,
                ),
                detail: [
                  if (provider.protocol.usesAccounts)
                    l10n.modelsAccountCount(provider.accounts.length)
                  else if (provider.host.isEmpty)
                    l10n.modelsProviderNoUrl
                  else
                    provider.host,
                  l10n.modelsModelCount(provider.enabledModels.length),
                ].join(' · '),
                status: !provider.enabled
                    ? _Status.off
                    : _providers.error(provider.id) != null
                    ? _Status.failed
                    : provider.enabledModels.isEmpty || !provider.connected
                    ? _Status.incomplete
                    : _Status.ready,
                error: _providers.error(provider.id),
                enabled: provider.enabled,
                switchLabel: l10n.modelsEnableProvider(provider.name),
                onEnabled: (value) => unawaited(
                  _providers.save(provider.copyWith(enabled: value)),
                ),
                onOpen: () => setState(() => _open = provider.id),
              ),
            SettingsRow(
              label: l10n.modelsAddProvider,
              trailing: IdeButton(
                label: l10n.modelsAddProvider,
                icon: Codicons.add,
                onPressed: () => unawaited(_add()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _Status { ready, incomplete, failed, off }

/// An upstream in the list: its status, name, protocol and where it is,
/// and whether the picker offers it; a click opens it.
class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.icon,
    required this.name,
    required this.badge,
    required this.detail,
    required this.status,
    required this.enabled,
    required this.switchLabel,
    required this.onEnabled,
    this.error,
    this.onOpen,
  });

  /// What the picker heads its models with.
  final Widget icon;
  final String name;
  final String badge;
  final String detail;
  final _Status status;
  final String? error;
  final bool enabled;
  final String switchLabel;
  final ValueChanged<bool> onEnabled;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final onOpen = this.onOpen;
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (status) {
          _Status.ready => AppColors.added,
          _Status.incomplete => AppColors.caution,
          _Status.failed => colors['errorForeground'],
          _Status.off => SettingsColors.textQuaternary,
        },
      ),
    );
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          if (error case final error?)
            IdeHover(message: error, child: dot)
          else
            dot,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconTheme.merge(
                      data: IconThemeData(color: SettingsColors.textSecondary),
                      child: DefaultTextStyle.merge(
                        style: TextStyle(color: SettingsColors.textSecondary),
                        child: icon,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SettingsText.label,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ModelBadge(badge),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SettingsText.description,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SettingsSwitch(
            value: enabled,
            semanticLabel: switchLabel,
            onChanged: onEnabled,
          ),
          if (onOpen != null) ...[
            const SizedBox(width: 8),
            Icon(
              Codicons.chevronRight,
              size: 14,
              color: SettingsColors.textSecondary,
            ),
          ],
        ],
      ),
    );
    if (onOpen == null) return row;
    return Semantics(
      button: true,
      label: name,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: row,
        ),
      ),
    );
  }
}

// --- An upstream ------------------------------------------------------------

/// An upstream's page: where it is and its key, its models, which of them
/// Claude Code uses for what, and the rest.
class ProviderSettingsPage extends StatefulWidget {
  const ProviderSettingsPage({
    super.key,
    required this.providers,
    required this.provider,
    required this.listModels,
    required this.onBack,
    this.onOpen,
    this.testModel = testModelThroughClaudeCode,
    this.codex,
    this.workspace,
  });

  final ModelProviders providers;
  final ModelProvider provider;
  final ModelLister listModels;
  final VoidCallback onBack;

  /// Opens upstream [id]'s page in its place: a copy of it, made.
  final ValueChanged<String>? onOpen;
  final ModelTester testModel;

  /// The ChatGPT (Codex) providers' accounts; the app's when null.
  final CodexService? codex;

  /// See [ModelsSettingsPage.workspace].
  final Workspace? workspace;

  @override
  State<ProviderSettingsPage> createState() => _ProviderSettingsPageState();
}

class _ProviderSettingsPageState extends State<ProviderSettingsPage> {
  final TextEditingController _search = TextEditingController();
  bool _showKey = false;

  /// All the upstream's models listed, not only those checked.
  bool _showAll = false;
  bool _rolesOpen = true;
  bool _advancedOpen = false;

  /// What the key was read as, once it is.
  String? _key;
  bool _keyRead = false;
  String? _keyError;

  bool _testing = false;
  String? _testResult;
  bool _testFailed = false;

  /// The models tested since the page opened, by id.
  final Map<String, _ModelTest> _modelTests = {};

  /// Completed as the page closes: the tests under way stop.
  final Completer<void> _closed = Completer();

  /// Signing in to an account, while it is under way.
  CodexLogin? _login;
  String? _loginError;
  bool _refreshingQuota = false;

  ModelProviders get _providers => widget.providers;
  ModelProvider get _provider => widget.provider;
  CodexService get _codex => widget.codex ?? codexService;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    unawaited(_readKey());
    if (_provider.protocol.usesAccounts && _provider.accounts.isNotEmpty) {
      unawaited(_refreshQuota());
    }
  }

  @override
  void dispose() {
    if (ProjectIconPicker.showsFor(_iconOwner)) ProjectIconPicker.close();
    _login?.cancel();
    _closed.complete();
    _search.dispose();
    super.dispose();
  }

  Future<void> _addAccount() async {
    setState(() => _loginError = null);
    try {
      final login = await _codex.login(_provider.id);
      if (!mounted) {
        login.cancel();
        return;
      }
      setState(() => _login = login);
      await login.result;
    } on CodexCancelled {
      // As asked.
    } on Object catch (error) {
      if (mounted) setState(() => _loginError = '$error');
    } finally {
      if (mounted) setState(() => _login = null);
    }
  }

  Future<void> _refreshQuota() async {
    setState(() => _refreshingQuota = true);
    try {
      await _codex.refreshUsage(_providerNow);
    } finally {
      if (mounted) setState(() => _refreshingQuota = false);
    }
  }

  Future<void> _removeAccount(ProviderAccount account) async {
    final l10n = context.l10n;
    final choice = await showIdeDialog(
      context,
      message: l10n.modelsAccountRemoveConfirm(account.displayName),
      detail: l10n.modelsAccountRemoveDetail,
      buttons: [l10n.modelsAccountRemove],
    );
    if (choice != 0) return;
    await _codex.removeAccount(_provider.id, account.id);
  }

  Future<void> _readKey() async {
    final key = await _providers.key(_provider.id);
    if (mounted) {
      setState(() {
        _key = key;
        _keyRead = true;
      });
    }
  }

  Future<void> _save(ModelProvider provider) => _providers.save(provider);

  /// Whose icon picker it is: the upstream's.
  (String, String) get _iconOwner => ('provider', _provider.id);

  /// Shows the icon picker under [anchor] (global), or closes it.
  void _toggleIconPicker(Workspace workspace, Rect anchor) {
    final site = providerSite(_providerNow);
    ProjectIconPicker.toggleFor(
      context,
      workspace: workspace,
      target: IconPickerTarget(
        icon: () => _providerNow.icon,
        setIcon: (icon) =>
            unawaited(_save(_providerNow.copyWith(icon: () => icon))),
        changes: _providers,
        site: site,
        brands: true,
      ),
      of: _iconOwner,
      anchor: anchor,
    );
  }

  Future<void> _setKey(String key) async {
    try {
      await _providers.setKey(_provider.id, key);
      if (mounted) setState(() => _keyError = null);
    } on Object catch (error) {
      if (mounted) setState(() => _keyError = '$error');
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final l10n = context.l10n;
    try {
      final models = await widget.listModels(
        _provider,
        await _providers.key(_provider.id),
      );
      _providers.reportError(_provider.id, null);
      if (!mounted) return;
      setState(() {
        _testFailed = false;
        _testResult = l10n.modelsTestOk(models.length);
      });
    } on Object catch (error) {
      _providers.reportError(_provider.id, '$error');
      if (!mounted) return;
      setState(() {
        _testFailed = true;
        _testResult = l10n.modelsTestFailed('$error');
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _fetch() async {
    final models = await showFetchModelsDialog(
      context,
      provider: _provider,
      key: () => _providers.key(_provider.id),
      list: widget.listModels,
    );
    if (models != null) await _save(_providerNow.copyWith(models: models));
  }

  /// Tests [models], three at a time; those under test already are left.
  Future<void> _testModels(List<ProviderModel> models) async {
    final queue = [
      for (final model in models)
        if (_modelTests[model.id]?.running != true) model,
    ];
    setState(() {
      for (final model in queue) {
        _modelTests[model.id] = const _ModelTest();
      }
    });
    Future<void> next() async {
      while (queue.isNotEmpty && !_closed.isCompleted) {
        final model = queue.removeAt(0);
        _ModelTest test;
        try {
          final answer = await widget.testModel(
            _providerNow,
            model,
            cancel: _closed.future,
          );
          test = _ModelTest(answer: answer);
        } on ClaudeHaikuCancelled {
          return;
        } on Object catch (error) {
          test = _ModelTest(error: '$error');
        }
        if (mounted) setState(() => _modelTests[model.id] = test);
      }
    }

    await Future.wait([for (var i = 0; i < 3; i++) next()]);
  }

  /// The provider as kept now: changed since this page was built, maybe.
  ModelProvider get _providerNow =>
      _providers.provider(_provider.id) ?? _provider;

  /// Edits [model], or adds one: filled in as [template], when a copy.
  Future<void> _editModel([
    ProviderModel? model,
    ProviderModel? template,
  ]) async {
    final edited = await showModelEditDialog(
      context,
      provider: _provider,
      model: model,
      template: template,
    );
    if (edited != null) await _save(_providerNow.withModel(edited));
  }

  Future<void> _removeModel(ProviderModel model) => _removeModels({model.id});

  /// Removes the models [ids] name, and the roles they had, here and on
  /// the other upstreams.
  Future<void> _removeModels(Set<String> ids) async {
    final provider = _providerNow;
    var roles = provider.roles.without(provider.id, ids);
    for (final role in ProviderRoles.keys) {
      if (ids.contains(roles[role])) roles = roles.copyWith(role, null);
    }
    await _save(
      provider.copyWith(
        models: [
          for (final m in provider.models)
            if (!ids.contains(m.id)) m,
        ],
        roles: roles,
      ),
    );
    await _providers.forgetRoles(provider.id, ids);
  }

  /// Removes, once confirmed, the models the upstream no longer lists.
  Future<void> _removeMissing() async {
    final l10n = context.l10n;
    final missing = [
      for (final model in _providerNow.sortedModels)
        if (model.missing) model,
    ];
    if (missing.isEmpty) return;
    final choice = await showIdeDialog(
      context,
      message: l10n.modelsRemoveMissingConfirm(missing.length),
      detail: [
        for (final model in missing.take(12)) model.displayName,
        if (missing.length > 12) '…',
      ].join('\n'),
      buttons: [l10n.modelsRemove],
    );
    if (choice != 0 || !mounted) return;
    await _removeModels({for (final model in missing) model.id});
  }

  /// A copy of it, its key with it, opened in its place.
  Future<void> _duplicate() async {
    final name = context.l10n.modelsDuplicateName(_providerNow.name);
    final id = await _providers.duplicate(_provider.id, name);
    if (id != null) widget.onOpen?.call(id);
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final choice = await showIdeDialog(
      context,
      message: l10n.modelsDeleteConfirm(_provider.name),
      detail: l10n.modelsDeleteDetail,
      buttons: [l10n.commonDelete],
    );
    if (choice != 0) return;
    widget.onBack();
    await _providers.remove(_provider.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final provider = _provider;
    return SettingsColumn(
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          // Its arrow level with the title under it.
          child: Transform.translate(
            offset: const Offset(-10, 0),
            child: IdeBackButton(label: l10n.modelsTitle, onTap: widget.onBack),
          ),
        ),
        const SizedBox(height: 8),
        Text(provider.name, style: SettingsText.title),
        const SizedBox(height: 16),
        _connection(context),
        if (provider.protocol.usesAccounts) ...[
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: _codex,
            builder: (context, _) => _accounts(context),
          ),
        ],
        const SizedBox(height: 16),
        _models(context),
        const SizedBox(height: 16),
        _Folding(
          title: l10n.modelsRoles,
          description: l10n.modelsRolesDescription,
          open: _rolesOpen,
          onToggle: () => setState(() => _rolesOpen = !_rolesOpen),
          children: _roles(context),
        ),
        const SizedBox(height: 16),
        _Folding(
          title: l10n.modelsAdvanced,
          open: _advancedOpen,
          onToggle: () => setState(() => _advancedOpen = !_advancedOpen),
          children: _advanced(context),
        ),
      ],
    );
  }

  /// Speaks [protocol] from now on: a new provider's name, left as it was
  /// made, becomes ChatGPT's when it is that.
  Future<void> _setProtocol(ProviderProtocol protocol) {
    var provider = _providerNow.copyWith(protocol: protocol);
    if (protocol == ProviderProtocol.codex &&
        provider.name == context.l10n.modelsNewProviderName) {
      provider = provider.copyWith(name: 'ChatGPT');
    }
    return _save(provider);
  }

  Widget _accounts(BuildContext context) {
    final l10n = context.l10n;
    final provider = _provider;
    final login = _login;
    String balanceName(AccountBalance value) => switch (value) {
      AccountBalance.roundRobin => l10n.modelsBalanceRoundRobin,
      AccountBalance.fillFirst => l10n.modelsBalanceFillFirst,
      AccountBalance.mostRemaining => l10n.modelsBalanceMostRemaining,
    };
    final balance = balanceName(provider.balance);
    return SettingsGroup(
      title: l10n.modelsAccounts,
      description: l10n.modelsAccountsDescription,
      children: [
        if (provider.accounts.isEmpty)
          SettingsRow(label: l10n.modelsAccountsNone)
        else
          for (final account in provider.accounts)
            _AccountRow(
              account: account,
              usage: _codex.usage(provider.id, account.id),
              error: _codex.error(provider.id, account.id),
              limitedUntil: _codex.limitedUntil(provider.id, account.id),
              onEnabled: (value) => unawaited(
                _save(
                  _providerNow.withAccount(account.copyWith(enabled: value)),
                ),
              ),
              onRemove: () => unawaited(_removeAccount(account)),
            ),
        if (provider.accounts.length > 1)
          SettingsRow(
            label: l10n.modelsBalance,
            description: switch (provider.balance) {
              AccountBalance.roundRobin =>
                l10n.modelsBalanceRoundRobinDescription,
              AccountBalance.fillFirst =>
                l10n.modelsBalanceFillFirstDescription,
              AccountBalance.mostRemaining =>
                l10n.modelsBalanceMostRemainingDescription,
            },
            trailing: SettingsDropdown(
              current: balance,
              semanticLabel: l10n.modelsChoiceLabel(
                l10n.modelsBalance,
                balance,
              ),
              entries: () => [
                for (final value in AccountBalance.values)
                  IdeMenuAction(
                    balanceName(value),
                    checked: value == provider.balance,
                    onSelected: () =>
                        unawaited(_save(_providerNow.copyWith(balance: value))),
                  ),
              ],
            ),
          ),
        SettingsRow(
          label: login != null
              ? l10n.modelsAccountSigningIn
              : l10n.modelsAddAccount,
          description: switch (login) {
            null => l10n.modelsAddAccountDescription,
            CodexLogin(listening: false) => l10n.modelsAccountPortBusy,
            _ => l10n.modelsAccountSigningInDetail,
          },
          below: [
            if (_loginError case final error?)
              SelectableText(
                l10n.modelsAccountSignInFailed(error),
                style: SettingsText.description.copyWith(
                  color: themeColors['errorForeground'],
                ),
              ),
          ],
          trailing: SettingsButtons(
            children: [
              if (login != null) ...[
                IdeButton(
                  label: l10n.modelsAccountCopyLink,
                  icon: Codicons.copy,
                  secondary: true,
                  onPressed: () => unawaited(
                    Clipboard.setData(ClipboardData(text: '${login.url}')),
                  ),
                ),
                IdeButton(
                  label: l10n.commonCancel,
                  secondary: true,
                  onPressed: login.cancel,
                ),
              ] else ...[
                if (provider.accounts.isNotEmpty)
                  IdeButton(
                    label: l10n.modelsRefreshQuota,
                    icon: Codicons.refresh,
                    secondary: true,
                    onPressed: _refreshingQuota
                        ? null
                        : () => unawaited(_refreshQuota()),
                  ),
                IdeButton(
                  label: l10n.modelsAddAccount,
                  icon: Codicons.add,
                  onPressed: () => unawaited(_addAccount()),
                ),
              ],
            ],
          ),
        ),
        if (login != null)
          SettingsRow(
            label: l10n.modelsAccountCallback,
            description: l10n.modelsAccountCallbackDetail,
            trailing: _Field(
              // Made anew for each sign-in.
              key: ObjectKey(login),
              value: '',
              label: l10n.modelsAccountCallback,
              placeholder: 'http://localhost:1455/auth/callback?code=…',
              onCommit: (text) {
                if (text.trim().isEmpty) return;
                String? error;
                try {
                  login.submit(text);
                } on CodexException catch (e) {
                  error = e.message;
                }
                // Also written as the field goes, maybe with the page.
                if (mounted) setState(() => _loginError = error);
              },
            ),
          ),
      ],
    );
  }

  Widget _connection(BuildContext context) {
    final l10n = context.l10n;
    final provider = _provider;
    final protocol = ModelsSettingsPage.protocolName(
      context,
      provider.protocol,
    );
    final workspace = widget.workspace;
    return SettingsGroup(
      title: l10n.modelsConnection,
      children: [
        SettingsRow(
          label: l10n.modelsIcon,
          description: l10n.modelsIconDescription,
          trailing: _IconButton(
            icon: providerIconOf(provider),
            site: providerSite(provider),
            label: l10n.modelsIconChange,
            onTap: workspace == null
                ? null
                : (anchor) => _toggleIconPicker(workspace, anchor),
          ),
        ),
        SettingsRow(
          label: l10n.modelsName,
          trailing: _Field(
            value: provider.name,
            label: l10n.modelsName,
            onCommit: (name) {
              if (name.trim().isEmpty) return;
              unawaited(_save(_providerNow.copyWith(name: name.trim())));
            },
          ),
        ),
        SettingsRow(
          label: l10n.modelsProtocol,
          description: l10n.modelsProtocolDescription,
          trailing: SettingsDropdown(
            current: protocol,
            semanticLabel: l10n.modelsChoiceLabel(
              l10n.modelsProtocol,
              protocol,
            ),
            entries: () => [
              for (final value in ProviderProtocol.values)
                IdeMenuAction(
                  ModelsSettingsPage.protocolName(context, value),
                  checked: value == provider.protocol,
                  onSelected: () => unawaited(_setProtocol(value)),
                ),
            ],
          ),
        ),
        if (!provider.protocol.usesAccounts) ...[
          SettingsRow(
            label: l10n.modelsBaseUrl,
            description: provider.protocol.proxied
                ? l10n.modelsBaseUrlOpenAIHint
                : l10n.modelsBaseUrlAnthropicHint,
            trailing: _Field(
              value: provider.baseUrl,
              label: l10n.modelsBaseUrl,
              placeholder: provider.protocol.proxied
                  ? 'https://api.openai.com/v1'
                  : 'https://api.anthropic.com',
              onCommit: (url) =>
                  unawaited(_save(_providerNow.copyWith(baseUrl: url.trim()))),
            ),
          ),
          SettingsRow(
            label: l10n.modelsApiKey,
            description: l10n.modelsApiKeyDescription,
            below: [
              if (_keyError case final error?)
                SelectableText(
                  l10n.modelsApiKeyError(error),
                  style: SettingsText.description.copyWith(
                    color: themeColors['errorForeground'],
                  ),
                ),
            ],
            trailing: _keyRead
                ? _Field(
                    value: _key ?? '',
                    label: l10n.modelsApiKey,
                    obscure: !_showKey,
                    toggles: [
                      IdeInputToggle(
                        icon: _showKey ? Codicons.eyeClosed : Codicons.eye,
                        tooltip: _showKey
                            ? l10n.modelsApiKeyHide
                            : l10n.modelsApiKeyShow,
                        checked: false,
                        onChanged: (_) => setState(() => _showKey = !_showKey),
                      ),
                    ],
                    onCommit: (key) {
                      _key = key.trim();
                      unawaited(_setKey(key));
                    },
                  )
                : const SizedBox(width: _Field.width, height: 26),
          ),
        ],
        SettingsRow(
          label: l10n.modelsTest,
          below: [
            if (_testing)
              Text(l10n.modelsTesting, style: SettingsText.description)
            else if (_testResult case final result?)
              SelectableText(
                result,
                style: SettingsText.description.copyWith(
                  color: _testFailed
                      ? themeColors['errorForeground']
                      : AppColors.added,
                ),
              ),
          ],
          trailing: IdeButton(
            label: l10n.modelsTest,
            icon: Codicons.plug,
            secondary: true,
            onPressed: _testing || !provider.connected
                ? null
                : () => unawaited(_test()),
          ),
        ),
      ],
    );
  }

  Widget _models(BuildContext context) {
    final l10n = context.l10n;
    final provider = _provider;
    final query = _search.text.trim().toLowerCase();
    // Those checked, unless all are shown, or searched.
    final all = _showAll || query.isNotEmpty;
    final shown = [
      for (final model in provider.sortedModels)
        if ((all || model.enabled) &&
            (query.isEmpty ||
                model.id.toLowerCase().contains(query) ||
                model.displayName.toLowerCase().contains(query)))
          model,
    ];
    final missing = provider.models.where((model) => model.missing).length;
    return SettingsGroup(
      title: l10n.modelsModelsGroup,
      description: l10n.modelsModelsDescription,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          // The search above the buttons, which wrap when the page is narrow.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (provider.models.length > 8) ...[
                IdeInputBox(
                  controller: _search,
                  placeholder: l10n.modelsSearch,
                  semanticsLabel: l10n.modelsSearch,
                ),
                const SizedBox(height: 8),
              ],
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (shown.isNotEmpty)
                    IdeButton(
                      label: l10n.modelsTestModels,
                      secondary: true,
                      onPressed: () => unawaited(
                        _testModels([
                          // Not the image models': a picture costs.
                          for (final model in shown)
                            if (!model.kind.generatesImages) model,
                        ]),
                      ),
                    ),
                  if (provider.models.isNotEmpty)
                    IdeButton(
                      label: _showAll
                          ? l10n.modelsShowChecked
                          : l10n.modelsShowAll(provider.models.length),
                      secondary: true,
                      onPressed: () => setState(() => _showAll = !_showAll),
                    ),
                  if (missing > 0)
                    IdeButton(
                      label: l10n.modelsRemoveMissing(missing),
                      secondary: true,
                      onPressed: () => unawaited(_removeMissing()),
                    ),
                  IdeButton(
                    label: l10n.modelsFetch,
                    icon: Codicons.cloudDownload,
                    onPressed: !provider.connected
                        ? null
                        : () => unawaited(_fetch()),
                  ),
                  IdeButton(
                    label: l10n.modelsAddModel,
                    icon: Codicons.add,
                    secondary: true,
                    onPressed: () => unawaited(_editModel()),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (provider.models.isEmpty)
          SettingsRow(label: l10n.modelsNone)
        else if (shown.isEmpty)
          SettingsRow(label: all ? l10n.modelsNoMatch : l10n.modelsNoneChecked)
        else
          for (final model in shown)
            _ModelRow(
              model: model,
              endpoint: switch (provider.protocolOf(model)) {
                final protocol when protocol != provider.protocol => protocol,
                _ => null,
              },
              test: _modelTests[model.id],
              onEnabled: (value) => unawaited(
                _save(_providerNow.withModel(model.copyWith(enabled: value))),
              ),
              onTest: () => unawaited(_testModels([model])),
              onEdit: () => unawaited(_editModel(model)),
              onDuplicate: () => unawaited(_editModel(null, model)),
              onRemove: () => unawaited(_removeModel(model)),
            ),
      ],
    );
  }

  List<Widget> _roles(BuildContext context) {
    final l10n = context.l10n;
    final provider = _provider;
    // The other upstreams whose models a role may pick (all but the main
    // model): through the proxy, any that can be reached (not Claude
    // Code's own, whose key is not the app's).
    final others = [
      for (final other in _providers.enabled)
        if (other.id != provider.id && other.connected) other,
    ];
    Widget role(
      String role,
      String label,
      String description, {
      String? warning,
    }) {
      final elsewhere = ProviderRoles.crossUpstream.contains(role);
      final current = provider.roles[role];
      final picked = parseModelRef(current);
      final pickedProvider = picked == null
          ? null
          : _providers.provider(picked.provider);
      final pickedModel = picked == null
          ? null
          : pickedProvider?.model(picked.model);
      final missing = picked != null && pickedModel == null;
      final shown = switch (current) {
        _ when pickedModel != null =>
          '${pickedProvider!.name} · ${pickedModel.displayName}',
        _ when picked != null => picked.model,
        final id? => provider.model(id)?.displayName ?? id,
        null => l10n.modelsRoleUnset,
      };
      Widget caution(String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 4),
            child: Icon(Codicons.warning, size: 13, color: AppColors.caution),
          ),
          Expanded(
            child: Text(
              text,
              style: SettingsText.description.copyWith(
                color: AppColors.caution,
              ),
            ),
          ),
        ],
      );
      IdeMenuAction pick(String label, String value) => IdeMenuAction(
        label,
        checked: current == value,
        onSelected: () => unawaited(
          _save(
            _providerNow.copyWith(
              roles: _providerNow.roles.copyWith(role, value),
            ),
          ),
        ),
      );
      return SettingsRow(
        label: label,
        description: description,
        below: [
          if (warning != null && current == null) caution(warning),
          if (missing) caution(l10n.modelsRoleMissing),
        ],
        trailing: SettingsDropdown(
          current: shown,
          semanticLabel: l10n.modelsChoiceLabel(label, shown),
          entries: () => [
            IdeMenuAction(
              l10n.modelsRoleUnset,
              checked: current == null,
              onSelected: () => unawaited(
                _save(
                  _providerNow.copyWith(
                    roles: _providerNow.roles.copyWith(role, null),
                  ),
                ),
              ),
            ),
            const IdeMenuSeparator(),
            for (final model in provider.enabledModels)
              pick(model.displayName, model.id),
            if (elsewhere && others.isNotEmpty) ...[
              const IdeMenuSeparator(),
              for (final other in others)
                IdeMenuAction(
                  other.name,
                  checked: picked?.provider == other.id,
                  submenu: [
                    for (final model in other.enabledModels)
                      pick(model.displayName, modelRef(other.id, model.id)),
                  ],
                ),
            ],
          ],
        ),
      );
    }

    return [
      role('main', l10n.modelsRoleMain, l10n.modelsRoleMainDescription),
      role('opus', l10n.modelsRoleOpus, l10n.modelsRoleOpusDescription),
      role('sonnet', l10n.modelsRoleSonnet, l10n.modelsRoleSonnetDescription),
      role(
        'haiku',
        l10n.modelsRoleHaiku,
        l10n.modelsRoleHaikuDescription,
        warning: l10n.modelsRoleHaikuWarning,
      ),
      role(
        'subagent',
        l10n.modelsRoleSubagent,
        l10n.modelsRoleSubagentDescription,
      ),
    ];
  }

  String _authName(BuildContext context, ProviderAuth value) {
    final l10n = context.l10n;
    return switch (value) {
      ProviderAuth.auto => l10n.modelsAuthAuto,
      ProviderAuth.bearer => 'Bearer (ANTHROPIC_AUTH_TOKEN)',
      ProviderAuth.apiKey => 'x-api-key (ANTHROPIC_API_KEY)',
    };
  }

  List<Widget> _advanced(BuildContext context) {
    final l10n = context.l10n;
    final provider = _provider;
    final auth = _authName(context, provider.auth);
    final protocols = provider.protocols;
    return [
      if (protocols.contains(ProviderProtocol.anthropic))
        SettingsRow(
          label: l10n.modelsAuth,
          description: l10n.modelsAuthDescription,
          trailing: SettingsDropdown(
            current: auth,
            semanticLabel: l10n.modelsChoiceLabel(l10n.modelsAuth, auth),
            entries: () => [
              for (final value in ProviderAuth.values)
                IdeMenuAction(
                  _authName(context, value),
                  checked: value == provider.auth,
                  onSelected: () =>
                      unawaited(_save(_providerNow.copyWith(auth: value))),
                ),
            ],
          ),
        ),
      SettingsSwitchRow(
        label: l10n.modelsNonessential,
        description: l10n.modelsNonessentialDescription,
        value: provider.disableNonessentialTraffic,
        onChanged: (value) => unawaited(
          _save(_providerNow.copyWith(disableNonessentialTraffic: value)),
        ),
      ),
      if (protocols.contains(ProviderProtocol.openaiChat))
        SettingsSwitchRow(
          label: l10n.modelsPreserveThinking,
          description: l10n.modelsPreserveThinkingDescription,
          value: provider.preserveThinking,
          onChanged: (value) =>
              unawaited(_save(_providerNow.copyWith(preserveThinking: value))),
        ),
      if (protocols.any((protocol) => protocol.proxied))
        SettingsSwitchRow(
          label: l10n.modelsPromptCacheKey,
          description: l10n.modelsPromptCacheKeyDescription,
          value: provider.promptCacheKey,
          onChanged: (value) =>
              unawaited(_save(_providerNow.copyWith(promptCacheKey: value))),
        ),
      if (provider.protocol == ProviderProtocol.codex)
        SettingsRow(
          label: l10n.modelsCodexVersion,
          description: l10n.modelsCodexVersionDescription,
          trailing: _Field(
            value: provider.clientVersion ?? '',
            label: l10n.modelsCodexVersion,
            placeholder: codexClientVersion,
            onCommit: (text) {
              final version = text.trim();
              // Not one: left as it was.
              if (version.isNotEmpty &&
                  !ModelProvider.isClientVersion(version)) {
                return;
              }
              unawaited(
                _save(
                  _providerNow.copyWith(
                    clientVersion: () => version.isEmpty ? null : version,
                  ),
                ),
              );
            },
          ),
        ),
      SettingsRow(
        label: l10n.modelsEnv,
        description: l10n.modelsEnvDescription,
        below: [
          const SizedBox(height: 4),
          _Field(
            value: formatEnvironment(provider.env),
            label: l10n.modelsEnv,
            placeholder: 'API_TIMEOUT_MS=600000',
            lines: 6,
            onCommit: (text) => unawaited(
              _save(_providerNow.copyWith(env: parseEnvironment(text))),
            ),
          ),
        ],
      ),
      SettingsRow(
        label: l10n.modelsHeaders,
        description: l10n.modelsHeadersDescription,
        below: [
          const SizedBox(height: 4),
          _Field(
            value: formatHeaders(provider.headers),
            label: l10n.modelsHeaders,
            placeholder: l10n.modelsHeadersPlaceholder,
            lines: 6,
            onCommit: (text) => unawaited(
              _save(_providerNow.copyWith(headers: parseHeaders(text))),
            ),
          ),
        ],
      ),
      SettingsRow(
        label: l10n.modelsDuplicateProvider,
        description: l10n.modelsDuplicateProviderDescription,
        trailing: IdeButton(
          label: l10n.modelsDuplicateProvider,
          icon: Codicons.copy,
          secondary: true,
          onPressed: () => unawaited(_duplicate()),
        ),
      ),
      SettingsRow(
        label: l10n.modelsDelete,
        description: l10n.modelsDeleteDescription,
        trailing: IdeButton(
          label: l10n.modelsDelete,
          icon: Codicons.trash,
          secondary: true,
          onPressed: () => unawaited(_delete()),
        ),
      ),
    ];
  }
}

/// [env] as the Extra Environment field shows it: `KEY=VALUE` a line.
String formatEnvironment(Map<String, String> env) =>
    [for (final MapEntry(:key, :value) in env.entries) '$key=$value']
        .join('\n');

/// The Extra Environment field's [text]: `KEY=VALUE` a line, blank lines
/// and `#` comments skipped, a line without `=` too.
Map<String, String> parseEnvironment(String text) => {
  for (final line in text.split('\n'))
    if (line.trim() case final line
        when line.isNotEmpty && !line.startsWith('#') && line.contains('='))
      if (line.substring(0, line.indexOf('=')).trim() case final key
          when RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key))
        key: line.substring(line.indexOf('=') + 1).trim(),
};

/// [headers] as the Custom Headers field shows it: `Name: Value` a line.
String formatHeaders(Map<String, String> headers) =>
    [for (final MapEntry(:key, :value) in headers.entries) '$key: $value']
        .join('\n');

/// The Custom Headers field's [text]: `Name: Value` a line, blank lines and
/// `#` comments skipped, a name that may not be set ([isSettableHeader], an
/// auth header among them) dropped.
Map<String, String> parseHeaders(String text) => {
  for (final line in text.split('\n'))
    if (line.trim() case final line
        when line.isNotEmpty && !line.startsWith('#') && line.contains(':'))
      if (line.substring(0, line.indexOf(':')).trim() case final name
          when isSettableHeader(name))
        name: line.substring(line.indexOf(':') + 1).trim(),
};

/// A model in its upstream's list: whether it is offered, its names and
/// what it can do, and its menu.
class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    this.endpoint,
    required this.test,
    required this.onEnabled,
    required this.onTest,
    required this.onEdit,
    required this.onDuplicate,
    required this.onRemove,
  });

  final ProviderModel model;

  /// The endpoint it is spoken to at, when not its upstream's.
  final ProviderProtocol? endpoint;
  final _ModelTest? test;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onTest;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          ModelCheckbox(
            checked: model.enabled,
            semanticLabel: l10n.modelsEnableModel(model.displayName),
            onChanged: onEnabled,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        model.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SettingsText.label.copyWith(
                          color: model.enabled
                              ? null
                              : SettingsColors.textSecondary,
                        ),
                      ),
                    ),
                    if (model.missing) ...[
                      const SizedBox(width: 6),
                      ModelBadge(
                        l10n.modelsMissing,
                        color: AppColors.caution,
                        tooltip: l10n.modelsMissingTooltip,
                      ),
                    ],
                    if (model.custom) ...[
                      const SizedBox(width: 6),
                      ModelBadge(l10n.modelsCustom),
                    ],
                    if (endpoint case final endpoint?) ...[
                      const SizedBox(width: 6),
                      ModelBadge(
                        switch (endpoint) {
                          ProviderProtocol.openaiChat => 'Chat Completions',
                          ProviderProtocol.openaiResponses => 'Responses',
                          _ => 'Anthropic',
                        },
                        tooltip:
                            '${l10n.modelsEndpoint}: '
                            '${ModelsSettingsPage.protocolName(context, endpoint)}',
                      ),
                    ],
                    if (model.kind.generatesImages) ...[
                      const SizedBox(width: 6),
                      ModelBadge(
                        l10n.modelsImageBadge,
                        tooltip: l10n.modelsKindDescription,
                      ),
                    ] else if (!model.images) ...[
                      const SizedBox(width: 6),
                      ModelBadge(l10n.modelsNoImages),
                    ],
                  ],
                ),
                if (model.label != null && model.displayName != model.id)
                  Text(
                    model.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SettingsText.description.copyWith(
                      fontFamily: AppFonts.mono,
                      fontFamilyFallback: AppFonts.monoFallbacks,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          if (test case final test?) ...[
            const SizedBox(width: 8),
            _ModelTestResult(test),
          ],
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              switch (model.contextWindow) {
                final tokens? => formatTokens(tokens),
                null => '—',
              },
              textAlign: TextAlign.end,
              style: SettingsText.description,
            ),
          ),
          const SizedBox(width: 10),
          const SizedBox(width: 4),
          Builder(
            builder: (context) => IdeActionButton(
              icon: Codicons.ellipsis,
              tooltip: l10n.modelsMore,
              onPressed: () {
                final box = context.findRenderObject()! as RenderBox;
                unawaited(
                  showIdeMenu(
                    context,
                    anchor: box.localToGlobal(Offset.zero) & box.size,
                    alignRight: true,
                    entries: [
                      IdeMenuAction(l10n.modelsEdit, onSelected: onEdit),
                      IdeMenuAction(
                        l10n.modelsDuplicate,
                        onSelected: onDuplicate,
                      ),
                      IdeMenuAction(l10n.modelsRemove, onSelected: onRemove),
                      IdeMenuAction(
                        l10n.modelsTestModel,
                        enabled:
                            test?.running != true &&
                            !model.kind.generatesImages,
                        onSelected: onTest,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A model's test, under way until it has the [answer] it got, or the
/// [error] it got instead.
class _ModelTest {
  const _ModelTest({this.answer, this.error});

  final ClaudeTimedAnswer? answer;
  final String? error;

  bool get running => answer == null && error == null;
}

/// How soon a model's first text came and how fast the rest, or that it
/// failed; the reply, or the error, on hover.
class _ModelTestResult extends StatelessWidget {
  const _ModelTestResult(this.test);

  final _ModelTest test;

  static String _seconds(Duration time) =>
      (time.inMilliseconds / 1000).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final answer = test.answer;
    if (test.error case final error?) {
      return IdeHover(
        message: error,
        child: Text(
          l10n.modelsTestModelFailed,
          style: SettingsText.description,
        ),
      );
    }
    if (answer == null) {
      return PixelLoader.agent(size: 11, color: SettingsColors.textSecondary);
    }
    final speed = answer.tokensPerSecond;
    return IdeHover(
      message:
          '${l10n.modelsTestTotal(_seconds(answer.lastText))}\n\n'
          '${answer.text.trim()}',
      child: Text(
        [
          l10n.modelsTestFirstText(_seconds(answer.firstText)),
          if (speed != null) '${speed.round()} tok/s',
        ].join(' · '),
        style: SettingsText.description,
      ),
    );
  }
}

/// An account of a ChatGPT (Codex) provider: who it is, its plan, how
/// much of its quota is used; whether it takes requests, and its removal.
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.usage,
    required this.error,
    required this.limitedUntil,
    required this.onEnabled,
    required this.onRemove,
  });

  final ProviderAccount account;
  final CodexUsage? usage;
  final String? error;
  final DateTime? limitedUntil;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final usage = this.usage;
    final plan = usage?.plan ?? account.plan;
    final error = this.error;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        account.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SettingsText.label.copyWith(
                          color: account.enabled
                              ? null
                              : SettingsColors.textSecondary,
                        ),
                      ),
                    ),
                    if (plan != null && plan.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      ModelBadge(plan[0].toUpperCase() + plan.substring(1)),
                    ],
                    if (limitedUntil != null) ...[
                      const SizedBox(width: 6),
                      ModelBadge(
                        l10n.modelsAccountLimited,
                        color: AppColors.caution,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                if (usage == null || usage.windows.isEmpty)
                  if (error == null)
                    Text(
                      l10n.modelsAccountQuotaUnknown,
                      style: SettingsText.description,
                    )
                  else
                    const SizedBox.shrink()
                else ...[
                  for (final window in usage.windows) _QuotaLine(window),
                  if (usage.credits case final credits?)
                    Text(
                      l10n.modelsQuotaCredits(credits),
                      style: SettingsText.description,
                    ),
                ],
                if (error != null)
                  SelectableText(
                    error,
                    maxLines: 3,
                    style: SettingsText.description.copyWith(
                      color: themeColors['errorForeground'],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SettingsSwitch(
            value: account.enabled,
            semanticLabel: l10n.modelsAccountEnable(account.displayName),
            onChanged: onEnabled,
          ),
          const SizedBox(width: 8),
          IdeActionButton(
            icon: Codicons.trash,
            tooltip: l10n.modelsAccountRemove,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// A window of an account's quota: how long it is, a bar of how much of
/// it is used, and when it starts over.
class _QuotaLine extends StatelessWidget {
  const _QuotaLine(this.window);

  final CodexWindow window;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final used = window.usedPercent.clamp(0, 100).toDouble();
    final color = used >= 90
        ? themeColors['errorForeground']
        : used >= 70
        ? AppColors.caution
        : AppColors.added;
    final detail = [
      l10n.modelsQuotaUsed(used.round()),
      if (window.resetsAt case final at?)
        quotaResets(l10n, at, DateTime.now()),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              quotaWindowName(l10n, window.minutes),
              style: SettingsText.description,
            ),
          ),
          Container(
            width: 96,
            height: 4,
            alignment: AlignmentDirectional.centerStart,
            decoration: BoxDecoration(
              color: AppColors.textFaint.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              widthFactor: used / 100,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SettingsText.description,
            ),
          ),
        ],
      ),
    );
  }
}

/// A group whose heading folds it.
/// An upstream's [icon], as large as a field is high; a click opens the
/// icon picker under it ([onTap] with where it is), none when null.
class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.site,
    required this.label,
    required this.onTap,
  });

  final ProjectIcon? icon;

  /// Whose icon shows without [icon].
  final Uri? site;
  final String label;
  final ValueChanged<Rect>? onTap;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    final colors = themeColors;
    return IdeHover(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        // A press on it toggles the picker, not closes it as one outside.
        child: TapRegion(
          groupId: ProjectIconPicker.tapRegion,
          child: HoverBuilder(
            cursor: onTap == null
                ? MouseCursor.defer
                : SystemMouseCursors.click,
            builder: (context, hovered) => GestureDetector(
              onTap: onTap == null
                  ? null
                  : () {
                      final box = context.findRenderObject() as RenderBox?;
                      if (box == null || !box.hasSize) return;
                      onTap(box.localToGlobal(Offset.zero) & box.size);
                    },
              child: Container(
                width: 32,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hovered && onTap != null
                      ? colors['toolbar.hoverBackground']
                      : colors['input.background'],
                  border: Border.all(color: colors['input.border']),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ProviderIconView(
                  icon: icon,
                  site: site,
                  size: 16,
                  color: SettingsColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Folding extends StatelessWidget {
  const _Folding({
    required this.title,
    required this.open,
    required this.onToggle,
    required this.children,
    this.description,
  });

  final String title;
  final String? description;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        button: true,
        expanded: open,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.only(left: 8, top: 8, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        open ? Codicons.chevronDown : Codicons.chevronRight,
                        size: 13,
                        color: SettingsColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(title, style: SettingsText.heading),
                    ],
                  ),
                  if (description case final description? when open) ...[
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.only(left: 17),
                      child: Text(
                        description,
                        style: SettingsText.headingDescription,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      if (open) SettingsCard(children: children),
    ],
  );
}

/// A text setting, written when it loses focus or Enter is pressed (not
/// as each key is typed).
class _Field extends StatefulWidget {
  const _Field({
    super.key,
    required this.value,
    required this.label,
    required this.onCommit,
    this.placeholder,
    this.obscure = false,
    this.lines = 1,
    this.toggles = const [],
  });

  static const width = 300.0;

  final String value;
  final String label;
  final ValueChanged<String> onCommit;
  final String? placeholder;
  final bool obscure;
  final int lines;
  final List<Widget> toggles;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();
  late String _committed = widget.value;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_Field oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Changed elsewhere (settings.json): shown, unless being edited.
    if (widget.value != oldWidget.value && !_focus.hasFocus) {
      _controller.text = widget.value;
      _committed = widget.value;
    }
  }

  @override
  void dispose() {
    // A change not yet written is not lost as the page goes: written once
    // the tree is done with it.
    final text = _controller.text;
    if (text != _committed) {
      final commit = widget.onCommit;
      scheduleMicrotask(() => commit(text));
    }
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final text = _controller.text;
    if (text == _committed) return;
    _committed = text;
    widget.onCommit(text);
  }

  @override
  Widget build(BuildContext context) {
    final multiline = widget.lines > 1;
    final input = IdeInputBox(
      controller: _controller,
      focusNode: _focus,
      placeholder: widget.placeholder,
      semanticsLabel: widget.label,
      obscureText: widget.obscure && !multiline,
      minLines: multiline ? 3 : 1,
      maxLines: widget.lines,
      toggles: widget.toggles,
      onSubmitted: multiline ? null : (_) => _commit(),
    );
    if (multiline) return input;
    return SizedBox(width: _Field.width, child: input);
  }
}
