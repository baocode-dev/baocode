import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_input.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_spinning.dart';
import '../../l10n/l10n.dart';
import '../../models/model_provider.dart';
import '../../models/upstream.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'models_page.dart' show ModelsSettingsPage;
import 'settings_dropdown.dart';

/// Asks [provider]'s upstream for its models, with [key].
typedef ModelLister = Future<List<RemoteModel>> Function(
  ModelProvider provider,
  String? key,
);

/// A checkbox, as the dialogs draw theirs: [onChanged] null disables it.
class ModelCheckbox extends StatelessWidget {
  const ModelCheckbox({
    super.key,
    required this.checked,
    required this.onChanged,
    required this.semanticLabel,
  });

  final bool checked;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final onChanged = this.onChanged;
    return Semantics(
      checked: checked,
      enabled: onChanged != null,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onChanged == null ? null : () => onChanged(!checked),
      child: MouseRegion(
        cursor: onChanged == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged(!checked),
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: colors['checkbox.background'],
              border: Border.all(color: colors['checkbox.border']),
              borderRadius: BorderRadius.circular(3),
            ),
            child: checked
                ? Icon(
                    Codicons.check,
                    size: 14,
                    color: colors['checkbox.foreground'],
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// The dialogs' frame: [title] over [child], [actions] under it, as the
/// IDE's own dialogs look.
class ModelDialogFrame extends StatelessWidget {
  const ModelDialogFrame({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    this.onSubmit,
    this.maxWidth = 560,
  });

  final String title;

  /// The most it is wide, in a window wide enough; 440 at least.
  final double maxWidth;
  final Widget child;
  final List<Widget> actions;

  /// Enter, outside a field that takes it.
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final border = colors.get('widget.border');
    final shadow = colors.get('widget.shadow');
    final size = MediaQuery.sizeOf(context);
    final width = math.max(440.0, math.min(maxWidth, size.width * .9));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.enter): ?onSubmit,
      },
      child: FocusScope(
        autofocus: true,
        child: Align(
          alignment: const Alignment(0, -0.5),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: width,
              constraints: BoxConstraints(maxHeight: size.height * .85),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors['editorWidget.background'],
                border: border == null ? null : Border.all(color: border),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  const BoxShadow(color: Color(0x26000000), blurRadius: 20),
                  if (shadow != null) BoxShadow(color: shadow, blurRadius: 8),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12, top: 4),
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors['editorWidget.foreground'],
                            ),
                          ),
                        ),
                      ),
                      IdeActionButton(
                        icon: Codicons.close,
                        tooltip: context.l10n.dialogCloseDialog,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: child,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 8, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (final (i, action) in actions.indexed) ...[
                          if (i > 0) const SizedBox(width: 8),
                          action,
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _text(BuildContext context, {Color? color, double size = 13}) =>
    TextStyle(
      fontSize: size,
      height: 18 / 13,
      color: color ?? themeColors['editorWidget.foreground'],
    );

TextStyle _muted(BuildContext context) =>
    _text(context, color: themeColors['descriptionForeground'], size: 12);

// --- Fetching ---------------------------------------------------------------

/// Asks [provider]'s upstream for its models and lets the user check those
/// to offer; completes with its models merged with the list
/// ([mergeModelList]), or null when dismissed. [apply] is what its button
/// says; Apply when null. With [skip], what a button says that, where the
/// upstream lists none or cannot be asked, completes with its models as
/// they are. [loading] is what it says while it asks, under [loadingLead];
/// for at least [minLoading], however soon the upstream answers.
Future<List<ProviderModel>?> showFetchModelsDialog(
  BuildContext context, {
  required ModelProvider provider,
  required Future<String?> Function() key,
  required ModelLister list,
  String? apply,
  String? skip,
  String? loading,
  Widget? loadingLead,
  Duration minLoading = Duration.zero,
}) => showGeneralDialog<List<ProviderModel>>(
  context: context,
  // Closed by its buttons, Escape or the close button: a click beside it
  // would lose the models checked.
  barrierDismissible: false,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => FetchModelsDialog(
    provider: provider,
    keyOf: key,
    list: list,
    apply: apply,
    skip: skip,
    loading: loading,
    loadingLead: loadingLead,
    minLoading: minLoading,
  ),
);

class FetchModelsDialog extends StatefulWidget {
  const FetchModelsDialog({
    super.key,
    required this.provider,
    required this.keyOf,
    required this.list,
    this.apply,
    this.skip,
    this.loading,
    this.loadingLead,
    this.minLoading = Duration.zero,
  });

  final ModelProvider provider;
  final Future<String?> Function() keyOf;
  final ModelLister list;

  /// What the button that takes the checked ones says; Apply when null.
  final String? apply;

  /// What a button says that, where none are listed or they cannot be,
  /// takes the provider's models as they are; none when null.
  final String? skip;

  /// What it says while it asks the upstream; that it does when null.
  final String? loading;

  /// Above [loading], while it asks.
  final Widget? loadingLead;

  /// How long it says so at least.
  final Duration minLoading;

  @override
  State<FetchModelsDialog> createState() => _FetchModelsDialogState();
}

class _FetchModelsDialogState extends State<FetchModelsDialog> {
  final TextEditingController _search = TextEditingController();
  List<RemoteModel>? _listed;
  Object? _error;
  final Set<String> _checked = {};

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    // Those offered already stay checked.
    _checked.addAll([
      for (final model in widget.provider.models)
        if (model.enabled) model.id,
    ]);
    unawaited(_fetch());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _listed = null;
      _error = null;
    });
    final shown = Future<void>.delayed(widget.minLoading);
    try {
      final listed = [
        ...await widget.list(widget.provider, await widget.keyOf()),
      ]..sort((a, b) => compareModelNames(a.id, b.id));
      await shown;
      if (mounted) setState(() => _listed = listed);
    } on Object catch (error) {
      await shown;
      if (mounted) setState(() => _error = error);
    }
  }

  List<RemoteModel> get _shown {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final model in _listed ?? const <RemoteModel>[])
        if (query.isEmpty ||
            model.id.toLowerCase().contains(query) ||
            (model.label ?? '').toLowerCase().contains(query))
          model,
    ];
  }

  void _apply() {
    final listed = _listed;
    if (listed == null) return;
    final ids = {for (final model in listed) model.id};
    final merged = mergeModelList(
      widget.provider.models,
      listed,
      enable: _checked,
    );
    Navigator.pop(context, [
      for (final model in merged)
        if (ids.contains(model.id))
          model.copyWith(enabled: _checked.contains(model.id))
        else
          model,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final listed = _listed;
    final error = _error;
    final known = {for (final model in widget.provider.models) model.id};
    final Widget body;
    if (error != null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SelectableText(
          l10n.modelsFetchFailed('$error'),
          style: _text(context, color: themeColors['errorForeground']),
        ),
      );
    } else if (listed == null) {
      final saying = Row(
        children: [
          IdeSpinning(
            Icon(
              Codicons.loading,
              size: 14,
              color: themeColors['descriptionForeground'],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.loading ?? l10n.modelsFetchLoading,
              style: _muted(context),
            ),
          ),
        ],
      );
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: switch (widget.loadingLead) {
          final lead? => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [lead, const SizedBox(height: 12), saying],
          ),
          null => saying,
        },
      );
    } else if (listed.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(l10n.modelsFetchEmpty, style: _muted(context)),
      );
    } else {
      final shown = _shown;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdeInputBox(
            controller: _search,
            autofocus: true,
            placeholder: l10n.modelsSearch,
            semanticsLabel: l10n.modelsSearch,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.modelsFetchSelected(
                    listed.where((m) => _checked.contains(m.id)).length,
                    listed.length,
                  ),
                  style: _muted(context),
                ),
              ),
              _LinkButton(
                label: l10n.modelsFetchSelectAll,
                onPressed: () => setState(
                  () => _checked.addAll(shown.map((model) => model.id)),
                ),
              ),
              const SizedBox(width: 10),
              _LinkButton(
                label: l10n.modelsFetchSelectNone,
                onPressed: () => setState(
                  () => _checked.removeAll(shown.map((model) => model.id)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Flexible(
            child: shown.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(l10n.modelsNoMatch, style: _muted(context)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: shown.length,
                    itemExtent: 30,
                    itemBuilder: (context, index) {
                      final model = shown[index];
                      final checked = _checked.contains(model.id);
                      void toggle(bool value) => setState(
                        () => value
                            ? _checked.add(model.id)
                            : _checked.remove(model.id),
                      );
                      final detail = [
                        if (model.label case final label?
                            when label != model.id)
                          label,
                        if (model.contextWindow case final tokens?)
                          formatTokens(tokens),
                      ].join(' · ');
                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => toggle(!checked),
                          child: Row(
                            children: [
                              ModelCheckbox(
                                checked: checked,
                                semanticLabel: model.id,
                                onChanged: toggle,
                              ),
                              const SizedBox(width: 8),
                              // The id first: what follows it is cut short
                              // before it is (#246).
                              Flexible(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: model.id,
                                        style: _text(context).copyWith(
                                          fontFamily: AppFonts.mono,
                                          fontFamilyFallback:
                                              AppFonts.monoFallbacks,
                                        ),
                                      ),
                                      if (detail.isNotEmpty)
                                        TextSpan(
                                          text: '  $detail',
                                          style: _muted(context),
                                        ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!known.contains(model.id)) ...[
                                const SizedBox(width: 6),
                                ModelBadge(l10n.modelsFetchNew),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    }
    return ModelDialogFrame(
      title: l10n.modelsFetchTitle(widget.provider.name),
      // Room for the long ids some upstreams give theirs.
      maxWidth: 760,
      onSubmit: listed == null ? null : _apply,
      actions: [
        if (error != null)
          IdeButton(label: l10n.modelsRetry, onPressed: _fetch)
        else
          IdeButton(
            label: widget.apply ?? l10n.modelsFetchApply,
            onPressed: listed == null || listed.isEmpty ? null : _apply,
          ),
        if (widget.skip case final skip?
            when error != null || (listed != null && listed.isEmpty))
          IdeButton(
            label: skip,
            secondary: true,
            onPressed: () => Navigator.pop(context, widget.provider.models),
          ),
        IdeButton(
          label: l10n.commonCancel,
          secondary: true,
          onPressed: () => Navigator.pop(context),
        ),
      ],
      child: body,
    );
  }
}

/// A small tag after a model's name (New, Gone upstream…).
class ModelBadge extends StatelessWidget {
  const ModelBadge(this.label, {super.key, this.color, this.tooltip});

  final String label;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? AppColors.textMuted;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, height: 14 / 10.5, color: color),
      ),
    );
    if (tooltip case final message?) {
      return IdeHover(message: message, child: badge);
    }
    return badge;
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: themeColors['textLink.foreground'],
          ),
        ),
      ),
    ),
  );
}

// --- A model ----------------------------------------------------------------

/// Edits [model] of [provider], or adds one when null, filled in as
/// [template] (a copy of it) if given; completes with it, or null when
/// dismissed.
Future<ProviderModel?> showModelEditDialog(
  BuildContext context, {
  required ModelProvider provider,
  ProviderModel? model,
  ProviderModel? template,
}) => showGeneralDialog<ProviderModel>(
  context: context,
  barrierDismissible: true,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) =>
      ModelEditDialog(provider: provider, model: model, template: template),
);

class ModelEditDialog extends StatefulWidget {
  const ModelEditDialog({
    super.key,
    required this.provider,
    this.model,
    this.template,
  });

  final ModelProvider provider;
  final ProviderModel? model;

  /// What a model added is filled in as: one it is a copy of.
  final ProviderModel? template;

  @override
  State<ModelEditDialog> createState() => _ModelEditDialogState();
}

class _ModelEditDialogState extends State<ModelEditDialog> {
  /// What the fields start as.
  late final ProviderModel? _start = widget.model ?? widget.template;

  late final TextEditingController _id = TextEditingController(
    text: _start?.id,
  );
  late final TextEditingController _label = TextEditingController(
    text: _start?.label,
  );
  late final TextEditingController _context = TextEditingController(
    text: switch (_start?.contextWindow) {
      final tokens? => formatTokens(tokens),
      null => '',
    },
  );
  late bool _images = _start?.images ?? true;

  /// What it is for, as picked; null to go by its name.
  late ModelKind? _kind = _start?.kindSet;

  /// What it is for: as picked, else as its name tells.
  ModelKind get _shownKind => _kind ?? guessModelKind(_id.text.trim());

  /// [_shownKind] as kept: null where its name tells it.
  ModelKind? get _keptKind {
    final kind = _shownKind;
    return kind == guessModelKind(_id.text.trim()) ? null : kind;
  }

  /// The endpoint it is spoken to at, as picked; null for its upstream's.
  late ProviderProtocol? _protocol = _start?.protocol;

  /// The model's own efforts and contexts; null for the defaults.
  late List<String>? _efforts = _start?.efforts;
  late List<int>? _contexts = _start?.contexts;
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [_id, _context]) {
      controller.addListener(() {
        if (_tried) setState(() {});
      });
    }
    // What it is for, as the name typed tells, until one is picked.
    _id.addListener(() {
      if (_kind == null && !_tried) setState(() {});
    });
  }

  @override
  void dispose() {
    _id.dispose();
    _label.dispose();
    _context.dispose();
    super.dispose();
  }

  bool get _adding => widget.model == null;

  /// [_protocol] as kept: none for a picture's model, or on an upstream
  /// signed in to (Codex), whose models all go as it does.
  ProviderProtocol? get _keptProtocol =>
      _shownKind.generatesImages || widget.provider.protocol.usesAccounts
      ? null
      : _protocol;

  /// What the Endpoint choice shows [protocol] as; the upstream's for
  /// null.
  String _endpointName(ProviderProtocol? protocol) => protocol == null
      ? context.l10n.modelsEndpointUpstream(
          ModelsSettingsPage.protocolName(context, widget.provider.protocol),
        )
      : ModelsSettingsPage.protocolName(context, protocol);

  /// [options], or null when they are [defaults]: the model then follows
  /// the defaults as they change.
  static List<T>? _sameAs<T>(List<T>? options, List<T> defaults) =>
      options == null ||
          options.length == defaults.length &&
              Iterable<int>.generate(options.length)
                  .every((i) => options[i] == defaults[i])
      ? null
      : options;

  /// An effort as typed: as the picker names it (`X-High`, `Disable`),
  /// or as it goes to the upstream (`xhigh`, `none`).
  static String? _parseEffort(String text) {
    final level = text.trim().toLowerCase();
    return switch (level) {
      'disable' || 'disabled' || 'off' => 'none',
      'x-high' => 'xhigh',
      _ when RegExp(r'^[a-z0-9][a-z0-9_-]*$').hasMatch(level) => level,
      _ => null,
    };
  }

  String? _idError(AppLocalizations l10n) {
    final id = _id.text.trim();
    if (id.isEmpty) return l10n.modelsModelIdHint;
    if (_adding && widget.provider.model(id) != null) {
      return l10n.modelsModelIdTaken;
    }
    return null;
  }

  void _save() {
    final l10n = context.l10n;
    final tokens = parseTokens(_context.text);
    if (_idError(l10n) != null || tokens == -1) {
      setState(() => _tried = true);
      return;
    }
    final label = _label.text.trim();
    final model = widget.model;
    Navigator.pop(
      context,
      model == null
          ? ProviderModel(
              id: _id.text.trim(),
              label: label.isEmpty ? null : label,
              contextWindow: tokens,
              efforts: _efforts,
              contexts: _contexts,
              images: _images,
              custom: true,
              kind: _keptKind,
              protocol: _keptProtocol,
            )
          : model.copyWith(
              label: () => label.isEmpty ? null : label,
              contextWindow: () => tokens,
              efforts: () => _efforts,
              contexts: () => _contexts,
              images: _images,
              kind: () => _keptKind,
              protocol: () => _keptProtocol,
            ),
    );
  }

  Widget _field(String label, Widget input) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: _text(context, size: 12)),
        const SizedBox(height: 4),
        input,
      ],
    ),
  );

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) =>
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                ModelCheckbox(
                  checked: value,
                  semanticLabel: label,
                  onChanged: onChanged,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: _text(context))),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final idError = _tried ? _idError(l10n) : null;
    final contextError = _tried && parseTokens(_context.text) == -1
        ? l10n.modelsContextInvalid
        : null;
    return ModelDialogFrame(
      title: _adding ? l10n.modelsAddTitle : l10n.modelsEditTitle,
      onSubmit: _save,
      actions: [
        IdeButton(label: l10n.modelsSave, onPressed: _save),
        IdeButton(
          label: l10n.commonCancel,
          secondary: true,
          onPressed: () => Navigator.pop(context),
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(
              l10n.modelsModelId,
              _adding
                  ? IdeInputBox(
                      controller: _id,
                      autofocus: true,
                      placeholder: l10n.modelsModelIdHint,
                      semanticsLabel: l10n.modelsModelId,
                      onSubmitted: (_) => _save(),
                      validation: idError == null
                          ? null
                          : IdeInputValidation(idError),
                    )
                  : SelectableText(
                      _id.text,
                      style: _text(context).copyWith(
                        fontFamily: AppFonts.mono,
                        fontFamilyFallback: AppFonts.monoFallbacks,
                      ),
                    ),
            ),
            _field(
              l10n.modelsModelLabel,
              IdeInputBox(
                controller: _label,
                autofocus: !_adding,
                placeholder: l10n.modelsModelLabelHint,
                semanticsLabel: l10n.modelsModelLabel,
                onSubmitted: (_) => _save(),
              ),
            ),
            _field(
              l10n.modelsKind,
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SettingsDropdown(
                  current: _kindName(l10n, _shownKind),
                  semanticLabel:
                      '${l10n.modelsKind}: ${_kindName(l10n, _shownKind)}',
                  entries: () => [
                    for (final kind in ModelKind.values)
                      IdeMenuAction(
                        _kindName(l10n, kind),
                        checked: kind == _shownKind,
                        onSelected: () => setState(() => _kind = kind),
                      ),
                  ],
                ),
              ),
            ),
            if (_shownKind.generatesImages)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  l10n.modelsKindDescription,
                  style: _text(
                    context,
                    size: 12,
                  ).copyWith(color: AppColors.textMuted),
                ),
              )
            else ...[
              if (!widget.provider.protocol.usesAccounts)
                _field(
                  l10n.modelsEndpoint,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SettingsDropdown(
                        current: _endpointName(_protocol),
                        semanticLabel:
                            '${l10n.modelsEndpoint}: ${_endpointName(_protocol)}',
                        entries: () => [
                          IdeMenuAction(
                            _endpointName(null),
                            checked: _protocol == null,
                            onSelected: () => setState(() => _protocol = null),
                          ),
                          const IdeMenuSeparator(),
                          for (final protocol in ProviderProtocol.forModels)
                            IdeMenuAction(
                              _endpointName(protocol),
                              checked: protocol == _protocol,
                              onSelected: () =>
                                  setState(() => _protocol = protocol),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.modelsEndpointDescription,
                        style: _text(
                          context,
                          size: 12,
                        ).copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              _field(
                l10n.modelsContextWindow,
                IdeInputBox(
                  controller: _context,
                  placeholder: l10n.modelsContextWindowHint,
                  semanticsLabel: l10n.modelsContextWindow,
                  onSubmitted: (_) => _save(),
                  validation: contextError == null
                      ? null
                      : IdeInputValidation(contextError),
                ),
              ),
              _field(
                l10n.modelsEffortOptions,
                _OptionList<String>(
                  options: _efforts ?? ProviderModel.defaultEfforts,
                  description: l10n.modelsEffortOptionsDescription,
                  label: effortLabel,
                  parse: _parseEffort,
                  addHint: l10n.modelsEffortAddHint,
                  invalid: l10n.modelsEffortInvalid,
                  onChanged: (efforts) => setState(
                    () => _efforts = _sameAs(
                      efforts,
                      ProviderModel.defaultEfforts,
                    ),
                  ),
                ),
              ),
              _field(
                l10n.modelsContextOptions,
                _OptionList<int>(
                  options: _contexts ?? ProviderModel.defaultContexts,
                  description: l10n.modelsContextOptionsDescription,
                  label: formatTokens,
                  parse: (text) => switch (parseTokens(text)) {
                    final tokens? when tokens > 0 => tokens,
                    _ => null,
                  },
                  addHint: l10n.modelsContextAddHint,
                  invalid: l10n.modelsContextInvalid,
                  sorted: true,
                  onChanged: (contexts) => setState(
                    () => _contexts = _sameAs(
                      contexts,
                      ProviderModel.defaultContexts,
                    ),
                  ),
                ),
              ),
              _check(
                l10n.modelsNoImages,
                !_images,
                (value) => setState(() => _images = !value),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _kindName(AppLocalizations l10n, ModelKind kind) => switch (kind) {
  ModelKind.chat => l10n.modelsKindChat,
  ModelKind.image => l10n.modelsKindImage,
  ModelKind.imageChat => l10n.modelsKindImageChat,
};

/// Options a model offers in the picker, each removed by its ×, others
/// added by typing them; back to the defaults with Reset.
class _OptionList<T> extends StatefulWidget {
  const _OptionList({
    required this.options,
    required this.description,
    required this.label,
    required this.parse,
    required this.addHint,
    required this.invalid,
    required this.onChanged,
    this.sorted = false,
  });

  final List<T> options;
  final String description;
  final String Function(T option) label;

  /// An option as typed; null when it is not one.
  final T? Function(String text) parse;
  final String addHint;
  final String invalid;

  /// The options with one removed or added; null for the defaults.
  final ValueChanged<List<T>?> onChanged;

  /// Kept in order (contexts), else as added.
  final bool sorted;

  @override
  State<_OptionList<T>> createState() => _OptionListState<T>();
}

class _OptionListState<T> extends State<_OptionList<T>> {
  final TextEditingController _input = TextEditingController();
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      if (_invalid) setState(() => _invalid = false);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    final option = widget.parse(text);
    if (option == null) {
      setState(() => _invalid = true);
      return;
    }
    _input.clear();
    if (widget.options.contains(option)) return;
    final options = [...widget.options, option];
    if (widget.sorted) options.sort();
    widget.onChanged(options);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final border = themeColors['input.border'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.description, style: _muted(context)),
        const SizedBox(height: 6),
        if (widget.options.isEmpty)
          Text(l10n.modelsOptionsNone, style: _muted(context))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in widget.options)
                Container(
                  padding: const EdgeInsets.only(left: 7, right: 1),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label(option),
                        style: _text(context, size: 12),
                      ),
                      IdeActionButton(
                        icon: Codicons.close,
                        iconSize: 12,
                        size: 20,
                        tooltip: l10n.modelsOptionRemove(widget.label(option)),
                        onPressed: () => widget.onChanged([
                          for (final o in widget.options)
                            if (o != option) o,
                        ]),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 160,
              child: IdeInputBox(
                controller: _input,
                placeholder: widget.addHint,
                semanticsLabel: widget.addHint,
                onSubmitted: (_) => _add(),
                validation: _invalid
                    ? IdeInputValidation(widget.invalid)
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            IdeButton(
              label: l10n.modelsOptionAdd,
              secondary: true,
              onPressed: _add,
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _LinkButton(
                label: l10n.modelsOptionsReset,
                onPressed: () => widget.onChanged(null),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
