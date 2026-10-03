import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_dialog.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_input.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../models/model_provider.dart';
import '../../models/model_providers.dart';
import '../../models/model_runtime.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'model_dialogs.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';

/// Settings → Models: Claude Code as set up on this machine, and the
/// upstreams added ([ModelProviders]), the model new sessions start with;
/// an upstream's own page when one is opened.
class ModelsSettingsPage extends StatefulWidget {
  const ModelsSettingsPage({
    super.key,
    required this.providers,
    this.listModels = listUpstreamModels,
  });

  final ModelProviders providers;
  final ModelLister listModels;

  /// The protocol's name, as the list and the detail show it.
  static String protocolName(BuildContext context, ProviderProtocol value) {
    final l10n = context.l10n;
    return switch (value) {
      ProviderProtocol.anthropic => l10n.modelsProtocolAnthropic,
      ProviderProtocol.openaiChat => 'OpenAI Chat Completions',
      ProviderProtocol.openaiResponses => 'OpenAI Responses',
    };
  }

  @override
  State<ModelsSettingsPage> createState() => _ModelsSettingsPageState();
}

class _ModelsSettingsPageState extends State<ModelsSettingsPage> {
  /// The upstream whose page shows; the list when null.
  String? _open;

  ModelProviders get _providers => widget.providers;

  Future<void> _add() async {
    final name = context.l10n.modelsNewProviderName;
    final id = _providers.newId(name);
    await _providers.save(
      ModelProvider(id: id, name: name, disableNonessentialTraffic: true),
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
          onBack: () => setState(() => _open = null),
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
    if (value == builtinProviderId) return l10n.modelsAuxiliaryBuiltin;
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
        entries: () => [
          IdeMenuAction(
            l10n.modelsAuxiliaryAuto,
            checked: current == null,
            onSelected: () => set(null),
          ),
          const IdeMenuSeparator(),
          IdeMenuAction(
            l10n.modelsAuxiliaryBuiltin,
            checked: current == builtinProviderId,
            onSelected: () => set(builtinProviderId),
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
    final current = _providers.defaultModel;
    final shown = _defaultName(context, current);
    return SettingsPage(
      title: l10n.modelsTitle,
      description: l10n.modelsDescription,
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
                  if (!_providers.builtinHidden)
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
          ],
        ),
        SettingsGroup(
          title: l10n.modelsProviders,
          children: [
            _ProviderRow(
              name: l10n.modelsBuiltinName,
              badge: l10n.modelsBuiltinBadge,
              detail: l10n.modelsBuiltinDescription,
              status: _providers.builtinHidden ? _Status.off : _Status.ready,
              enabled: !_providers.builtinHidden,
              switchLabel: l10n.modelsEnableProvider(l10n.modelsBuiltinName),
              onEnabled: (value) =>
                  unawaited(_providers.setBuiltinHidden(!value)),
            ),
            for (final provider in _providers.providers)
              _ProviderRow(
                name: provider.name,
                badge: ModelsSettingsPage.protocolName(
                  context,
                  provider.protocol,
                ),
                detail: [
                  if (provider.host.isEmpty)
                    l10n.modelsProviderNoUrl
                  else
                    provider.host,
                  l10n.modelsModelCount(provider.enabledModels.length),
                ].join(' · '),
                status: !provider.enabled
                    ? _Status.off
                    : _providers.error(provider.id) != null
                    ? _Status.failed
                    : provider.enabledModels.isEmpty || provider.host.isEmpty
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
          _Status.ready => SettingsSwitch.onColor,
          _Status.incomplete => AppColors.caution,
          _Status.failed => colors['errorForeground'],
          _Status.off => AppColors.textFaint,
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
            Icon(Codicons.chevronRight, size: 14, color: AppColors.textMuted),
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
  });

  final ModelProviders providers;
  final ModelProvider provider;
  final ModelLister listModels;
  final VoidCallback onBack;

  @override
  State<ProviderSettingsPage> createState() => _ProviderSettingsPageState();
}

class _ProviderSettingsPageState extends State<ProviderSettingsPage> {
  final TextEditingController _search = TextEditingController();
  bool _showKey = false;
  bool _rolesOpen = true;
  bool _advancedOpen = false;

  /// What the key was read as, once it is.
  String? _key;
  bool _keyRead = false;
  String? _keyError;

  bool _testing = false;
  String? _testResult;
  bool _testFailed = false;

  ModelProviders get _providers => widget.providers;
  ModelProvider get _provider => widget.provider;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    unawaited(_readKey());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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

  /// The provider as kept now: changed since this page was built, maybe.
  ModelProvider get _providerNow =>
      _providers.provider(_provider.id) ?? _provider;

  Future<void> _editModel([ProviderModel? model]) async {
    final edited = await showModelEditDialog(
      context,
      provider: _provider,
      model: model,
    );
    if (edited != null) await _save(_providerNow.withModel(edited));
  }

  Future<void> _removeModel(ProviderModel model) async {
    final provider = _providerNow;
    var roles = provider.roles;
    for (final role in const ['main', 'opus', 'sonnet', 'haiku', 'subagent']) {
      if (roles[role] == model.id) roles = roles.copyWith(role, null);
    }
    await _save(
      provider.copyWith(
        models: [
          for (final m in provider.models)
            if (m.id != model.id) m,
        ],
        roles: roles,
      ),
    );
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
          child: _BackLink(label: l10n.modelsTitle, onTap: widget.onBack),
        ),
        const SizedBox(height: 8),
        Text(provider.name, style: SettingsText.title),
        const SizedBox(height: 16),
        _connection(context),
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

  Widget _connection(BuildContext context) {
    final l10n = context.l10n;
    final provider = _provider;
    final protocol = ModelsSettingsPage.protocolName(
      context,
      provider.protocol,
    );
    return SettingsGroup(
      title: l10n.modelsConnection,
      children: [
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
                  onSelected: () =>
                      unawaited(_save(_providerNow.copyWith(protocol: value))),
                ),
            ],
          ),
        ),
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
                      : SettingsSwitch.onColor,
                ),
              ),
          ],
          trailing: IdeButton(
            label: l10n.modelsTest,
            icon: Codicons.plug,
            secondary: true,
            onPressed: _testing || provider.host.isEmpty
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
    final shown = [
      for (final model in provider.models)
        if (query.isEmpty ||
            model.id.toLowerCase().contains(query) ||
            model.displayName.toLowerCase().contains(query))
          model,
    ];
    return SettingsGroup(
      title: l10n.modelsModelsGroup,
      description: l10n.modelsModelsDescription,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: provider.models.length > 8
                    ? IdeInputBox(
                        controller: _search,
                        placeholder: l10n.modelsSearch,
                        semanticsLabel: l10n.modelsSearch,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              SettingsButtons(
                children: [
                  IdeButton(
                    label: l10n.modelsFetch,
                    icon: Codicons.cloudDownload,
                    onPressed: provider.host.isEmpty
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
          SettingsRow(label: l10n.modelsNoMatch)
        else
          for (final model in shown)
            _ModelRow(
              model: model,
              onEnabled: (value) => unawaited(
                _save(_providerNow.withModel(model.copyWith(enabled: value))),
              ),
              onEdit: () => unawaited(_editModel(model)),
              onRemove: () => unawaited(_removeModel(model)),
            ),
      ],
    );
  }

  List<Widget> _roles(BuildContext context) {
    final l10n = context.l10n;
    final provider = _provider;
    Widget role(
      String role,
      String label,
      String description, {
      String? warning,
    }) {
      final current = provider.roles[role];
      final shown = switch (current) {
        final id? => provider.model(id)?.displayName ?? id,
        null => l10n.modelsRoleUnset,
      };
      return SettingsRow(
        label: label,
        description: description,
        below: [
          if (warning != null && current == null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 4),
                  child: Icon(
                    Codicons.warning,
                    size: 13,
                    color: AppColors.caution,
                  ),
                ),
                Expanded(
                  child: Text(
                    warning,
                    style: SettingsText.description.copyWith(
                      color: AppColors.caution,
                    ),
                  ),
                ),
              ],
            ),
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
              IdeMenuAction(
                model.displayName,
                checked: current == model.id,
                onSelected: () => unawaited(
                  _save(
                    _providerNow.copyWith(
                      roles: _providerNow.roles.copyWith(role, model.id),
                    ),
                  ),
                ),
              ),
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
    return [
      if (!provider.protocol.proxied)
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
      if (provider.protocol == ProviderProtocol.openaiChat)
        SettingsSwitchRow(
          label: l10n.modelsPreserveThinking,
          description: l10n.modelsPreserveThinkingDescription,
          value: provider.preserveThinking,
          onChanged: (value) =>
              unawaited(_save(_providerNow.copyWith(preserveThinking: value))),
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

/// A model in its upstream's list: whether it is offered, its names and
/// what it can do, and its menu.
class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.onEnabled,
    required this.onEdit,
    required this.onRemove,
  });

  final ProviderModel model;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final muted = AppColors.textMuted;
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
                          color: model.enabled ? null : AppColors.textMuted,
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
                  ],
                ),
                if (model.label != null && model.displayName != model.id)
                  Text(
                    model.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SettingsText.description.copyWith(
                      fontFamily: AppFonts.mono,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
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
          SizedBox(
            width: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (model.thinking)
                  IdeHover(
                    message: l10n.modelsThinking,
                    child: Icon(Codicons.lightbulb, size: 14, color: muted),
                  ),
                if (model.images) ...[
                  const SizedBox(width: 4),
                  IdeHover(
                    message: l10n.modelsImages,
                    child: Icon(Codicons.fileMedia, size: 14, color: muted),
                  ),
                ],
              ],
            ),
          ),
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
                      IdeMenuAction(l10n.modelsRemove, onSelected: onRemove),
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

/// A group whose heading folds it.
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
              padding: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        open ? Codicons.chevronDown : Codicons.chevronRight,
                        size: 13,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(title, style: SettingsText.heading),
                    ],
                  ),
                  if (description case final description? when open) ...[
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.only(left: 17),
                      child: Text(description, style: SettingsText.description),
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

class _BackLink extends StatelessWidget {
  const _BackLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = themeColors['textLink.foreground'];
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Codicons.chevronLeft, size: 14, color: color),
              const SizedBox(width: 2),
              Text(label, style: TextStyle(fontSize: 12.5, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A text setting, written when it loses focus or Enter is pressed (not
/// as each key is typed).
class _Field extends StatefulWidget {
  const _Field({
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
