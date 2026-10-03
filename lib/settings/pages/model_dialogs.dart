import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_input.dart';
import '../../l10n/l10n.dart';
import '../../models/model_provider.dart';
import '../../models/upstream.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;

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
class _ModelDialogFrame extends StatelessWidget {
  const _ModelDialogFrame({
    required this.title,
    required this.child,
    required this.actions,
    this.onSubmit,
  });

  final String title;
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
    final width = math.max(440.0, math.min(560.0, size.width * .9));
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
/// ([mergeModelList]), or null when dismissed.
Future<List<ProviderModel>?> showFetchModelsDialog(
  BuildContext context, {
  required ModelProvider provider,
  required Future<String?> Function() key,
  required ModelLister list,
}) => showGeneralDialog<List<ProviderModel>>(
  context: context,
  barrierDismissible: true,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) =>
      FetchModelsDialog(provider: provider, keyOf: key, list: list),
);

class FetchModelsDialog extends StatefulWidget {
  const FetchModelsDialog({
    super.key,
    required this.provider,
    required this.keyOf,
    required this.list,
  });

  final ModelProvider provider;
  final Future<String?> Function() keyOf;
  final ModelLister list;

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
    try {
      final listed = [
        ...await widget.list(widget.provider, await widget.keyOf()),
      ]..sort((a, b) => a.id.compareTo(b.id));
      if (mounted) setState(() => _listed = listed);
    } on Object catch (error) {
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
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(l10n.modelsFetchLoading, style: _muted(context)),
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
                              Flexible(
                                child: Text(
                                  model.id,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _text(context)
                                      .copyWith(fontFamily: AppFonts.mono),
                                ),
                              ),
                              if (detail.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    detail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _muted(context),
                                  ),
                                ),
                              ],
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
    return _ModelDialogFrame(
      title: l10n.modelsFetchTitle(widget.provider.name),
      onSubmit: listed == null ? null : _apply,
      actions: [
        if (error != null)
          IdeButton(label: l10n.modelsRetry, onPressed: _fetch)
        else
          IdeButton(
            label: l10n.modelsFetchApply,
            onPressed: listed == null || listed.isEmpty ? null : _apply,
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

/// Edits [model] of [provider], or adds one when null; completes with it,
/// or null when dismissed.
Future<ProviderModel?> showModelEditDialog(
  BuildContext context, {
  required ModelProvider provider,
  ProviderModel? model,
}) => showGeneralDialog<ProviderModel>(
  context: context,
  barrierDismissible: true,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) =>
      ModelEditDialog(provider: provider, model: model),
);

/// [text] as a number of tokens (`200000`, `200K`, `1M`, `1.5m`); null
/// when empty, -1 when it is not one.
int? parseTokens(String text) {
  final value = text.trim().replaceAll(RegExp(r'[,_\s]'), '').toLowerCase();
  if (value.isEmpty) return null;
  final match = RegExp(r'^(\d+(?:\.\d+)?)([km]?)$').firstMatch(value);
  if (match == null) return -1;
  final number = double.parse(match.group(1)!);
  final tokens = switch (match.group(2)) {
    'k' => number * 1000,
    'm' => number * 1000000,
    _ => number,
  }.round();
  return tokens > 0 ? tokens : -1;
}

class ModelEditDialog extends StatefulWidget {
  const ModelEditDialog({super.key, required this.provider, this.model});

  final ModelProvider provider;
  final ProviderModel? model;

  @override
  State<ModelEditDialog> createState() => _ModelEditDialogState();
}

class _ModelEditDialogState extends State<ModelEditDialog> {
  late final TextEditingController _id = TextEditingController(
    text: widget.model?.id,
  );
  late final TextEditingController _label = TextEditingController(
    text: widget.model?.label,
  );
  late final TextEditingController _context = TextEditingController(
    text: switch (widget.model?.contextWindow) {
      final tokens? => formatTokens(tokens),
      null => '',
    },
  );
  late bool _thinking = widget.model?.thinking ?? false;
  late bool _images = widget.model?.images ?? false;
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [_id, _context]) {
      controller.addListener(() {
        if (_tried) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _id.dispose();
    _label.dispose();
    _context.dispose();
    super.dispose();
  }

  bool get _adding => widget.model == null;

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
              thinking: _thinking,
              images: _images,
              custom: true,
            )
          : model.copyWith(
              label: () => label.isEmpty ? null : label,
              contextWindow: () => tokens,
              thinking: _thinking,
              images: _images,
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
    return _ModelDialogFrame(
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
                      style: _text(context).copyWith(fontFamily: AppFonts.mono),
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
            _check(
              l10n.modelsSupportsThinking,
              _thinking,
              (value) => setState(() => _thinking = value),
            ),
            _check(
              l10n.modelsSupportsImages,
              _images,
              (value) => setState(() => _images = value),
            ),
          ],
        ),
      ),
    );
  }
}
