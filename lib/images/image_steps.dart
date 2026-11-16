import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../chat/chat_models.dart';
import '../chat/composer/composer_picker.dart';
import '../chat/widgets/content_image.dart';
import '../chat/widgets/copy_button.dart';
import '../chat/widgets/hover_builder.dart';
import '../chat/widgets/step_header.dart';
import '../chat/widgets/tool_call_row.dart' show toolVerb;
import '../ide/ide_button.dart';
import '../kernel/kernel_types.dart';
import '../l10n/l10n.dart';
import '../models/image_api.dart';
import '../models/model_icons.dart';
import '../models/model_provider.dart';
import '../models/model_providers.dart';
import '../theme/app_theme.dart';
import 'image_picks.dart';
import 'image_tools.dart';

/// A picture's icon (Remix Icon's image-line), an image step's.
const imageIcon = 'assets/icons/image-line.svg';

/// A call of `generate_image` (see image_tools.dart) as a step: its line,
/// then the pictures it made, whole, as the conversation's answer would
/// show them. While no image model is the default, it first asks which to
/// make them with ([ImagePicks]); while they are made, their places, as big
/// as they will be, a light sweeping across. Made with a model that is not
/// the default, its line offers to make it so; while the mouse is over it,
/// a faint button copies its prompt. It opens to what it answered (where
/// they were saved, or why it failed).
class ImageStep extends StatefulWidget {
  const ImageStep({
    super.key,
    required this.item,
    this.expanded = false,
    this.onToggle,
  });

  final ToolCallItem item;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  State<ImageStep> createState() => _ImageStepState();
}

class _ImageStepState extends State<ImageStep> {
  /// Made the default from this step: it says so.
  bool _madeDefault = false;

  /// Whether the mouse is over it: its prompt's copy button shows. Not a
  /// rebuild of it all, which would lose a selection in its line.
  final _hovered = ValueNotifier(false);

  ToolCallItem get item => widget.item;

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _hovered.value = true,
    onExit: (_) => _hovered.value = false,
    child: ListenableBuilder(
      listenable: Listenable.merge([
        ImagePicks.instance,
        ModelProviders.current,
      ]),
      builder: (context, _) => _build(context),
    ),
  );

  Widget _build(BuildContext context) {
    final l10n = context.l10n;
    final providers = ModelProviders.current;
    final running = item.status == ToolStatus.running;
    final picks = ImagePicks.instance;
    // Its input comes whole with the agent's message, after its line
    // shows: until then, what it will ask is not known, nor its shape.
    final known = callInputKnown(item);
    final asking = running && known && asksForModel(item, providers);
    // Declined before its call came: it fails as it does.
    final declined =
        picks.answered(item.callId) && picks.picked(item.callId) == null;
    final output = item.output?.trimRight() ?? '';
    final images = toolImages(item);
    final used = imageModelUsed(item);
    final Widget? action;
    if (used == null ||
        item.status == ToolStatus.failed ||
        item.status == ToolStatus.denied ||
        providers.imageModels.every(
          (entry) => modelRef(entry.provider.id, entry.model.id) != used,
        )) {
      action = null;
    } else if (used != providers.imageModel) {
      action = _DefaultButton(
        onTap: () {
          setState(() => _madeDefault = true);
          unawaited(providers.setImageModel(used));
        },
      );
    } else if (_madeDefault) {
      action = Text(
        l10n.imageDefaultSet,
        style: TextStyle(color: AppColors.textFaint, fontSize: 12),
      );
    } else {
      action = null;
    }
    final prompt = switch (item.input['prompt']) {
      final String text when text.trim().isNotEmpty => text.trim(),
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(
          verb:
              item.label ??
              (asking
                  ? l10n.toolImageWaiting
                  : toolVerb(item.kind, status: item.status, l10n: l10n)),
          object: item.target,
          running: running && !asking,
          expanded: widget.expanded,
          onToggle: output.isEmpty ? null : widget.onToggle,
          icon: SvgPicture.asset(
            imageIcon,
            width: 14,
            height: 14,
            colorFilter: ColorFilter.mode(AppColors.textMuted, BlendMode.srcIn),
          ),
          action: prompt == null || asking
              ? action
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (action case final action?) ...[
                      action,
                      const SizedBox(width: 4),
                    ],
                    _PromptCopy(prompt: prompt, hovered: _hovered),
                  ],
                ),
        ),
        if (widget.expanded && output.isNotEmpty)
          StepBody(child: Text(output, style: stepMono)),
        if (asking)
          _PickCard(callId: item.callId!, models: providers.imageModels)
        else if (running && known && !declined)
          _Making(count: imageCount(item.input), aspectRatio: _aspectRatio())
        else if (images.isNotEmpty)
          ToolImages(images: images),
      ],
    );
  }

  /// The shape the pictures will have: of the size asked of the model.
  double _aspectRatio() {
    final input = item.input;
    final ref =
        ImagePicks.instance.picked(item.callId) ??
        switch ((input['model'], ModelProviders.current.imageModels)) {
          (final String ref, _) => ref,
          (_, [(:final provider, :final model), ...]) => modelRef(
            provider.id,
            model.id,
          ),
          _ => null,
        };
    final model = parseModelRef(ref)?.model ?? ref;
    final size = imageSizeFor(
      model ?? '',
      ImageRequest(
        prompt: '',
        size: switch (input['size']) {
          final String size => size,
          _ => null,
        },
        aspectRatio: switch (input['aspect_ratio']) {
          final String aspect => aspect,
          _ => null,
        },
      ),
    );
    return switch (parseImageSize(size)) {
      (:final width, :final height) => width / height,
      null => 1,
    };
  }
}

/// Whether [item]'s input has come: the streamed start of its call has
/// none, the agent's whole message all of it (its prompt among it).
bool callInputKnown(ToolCallItem item) => item.input.containsKey('prompt');

/// Whether [item], a call under way, asks the user for its model: it
/// names none, and no default is picked ([ImageTools]'s choice). From the
/// moment its input is known, not once its call has come to the tool (the
/// agent's message comes first), until answered.
bool asksForModel(ToolCallItem item, ModelProviders providers) {
  final picks = ImagePicks.instance;
  final id = item.callId;
  if (id == null || picks.answered(id)) return false;
  if (picks.waiting(id)) return true;
  if (item.input['model'] case final String named when named.isNotEmpty) {
    return false;
  }
  final models = providers.imageModels;
  if (models.isEmpty) return false;
  final picked = providers.imageModel;
  return !models.any(
    (entry) => modelRef(entry.provider.id, entry.model.id) == picked,
  );
}

/// The image model (a model ref) [item] was made with: as picked in its
/// step, else as its answer says; null while not known.
String? imageModelUsed(ToolCallItem item) =>
    ImagePicks.instance.picked(item.callId) ??
    _usedModel.firstMatch(item.output ?? '')?[1];

/// The model ref in the tool's answer's first line ([describeSaved]).
final _usedModel = RegExp(r'^Generated .*? with .*\((@[^()\s]+/[^()\s]+)\)');

/// How many pictures a call asks for.
int imageCount(Map<String, Object?> input) => switch (input['count']) {
  final num count => count.toInt().clamp(1, 4),
  _ => 1,
};

/// The image models [models] as the model picker lists them: under their
/// upstreams, each with its maker's logo.
List<KernelOption> imageModelOptions(List<ImageModel> models) => [
  for (final (:provider, :model) in models)
    KernelOption(
      modelRef(provider.id, model.id),
      model.displayName,
      Icons.image_outlined,
      model.id,
      group: KernelOptionGroup(
        provider.id,
        provider.name,
        iconBuilder: (size, color) =>
            ProviderIcon(provider.id, size: size, color: color),
      ),
      iconBuilder: (size, color) => ModelIcon(
        provider: provider.id,
        model: model.id,
        size: size,
        color: color,
      ),
    ),
];

/// Asks which image model to make the pictures of call [callId] with: the
/// model picker's dropdown, then Generate (or not).
class _PickCard extends StatefulWidget {
  const _PickCard({required this.callId, required this.models});

  final String callId;
  final List<ImageModel> models;

  @override
  State<_PickCard> createState() => _PickCardState();
}

class _PickCardState extends State<_PickCard> {
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final options = imageModelOptions(widget.models);
    if (options.isEmpty) return const SizedBox.shrink();
    final selected =
        options.where((option) => option.id == _picked).firstOrNull ??
        options.first;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: contentImageMaxWidth),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: AppColors.code,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.partBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.imagePickTitle,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Flexible(
                    child: ComposerPicker(
                      options: options,
                      selected: selected,
                      label: '${selected.group?.label} · ${selected.label}',
                      describes: false,
                      menuWidth: 260,
                      searchPlaceholder: l10n.modelsSearch,
                      onSelected: (option) =>
                          setState(() => _picked = option.id),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IdeButton(
                    label: l10n.imagePickDecline,
                    secondary: true,
                    onPressed: () => ImagePicks.instance.decline(widget.callId),
                  ),
                  const SizedBox(width: 6),
                  IdeButton(
                    label: l10n.imagePickGenerate,
                    onPressed: () =>
                        ImagePicks.instance.pick(widget.callId, selected.id),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Copies a step's prompt: there while the mouse is over the step, kept in
/// place (and its "copied" with it) while not.
class _PromptCopy extends StatelessWidget {
  const _PromptCopy({required this.prompt, required this.hovered});

  final String prompt;
  final ValueListenable<bool> hovered;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: hovered,
    builder: (context, shown, child) => IgnorePointer(
      ignoring: !shown,
      child: AnimatedOpacity(
        opacity: shown ? 1 : 0,
        duration: const Duration(milliseconds: 120),
        child: child,
      ),
    ),
    child: SelectionContainer.disabled(
      child: CopyButton(text: prompt, tooltip: context.l10n.imageCopyPrompt),
    ),
  );
}

/// Makes the model a step's pictures were made with the default.
class _DefaultButton extends StatelessWidget {
  const _DefaultButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: hovered ? AppColors.hover : null,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: Text(
              context.l10n.imageSetDefault,
              style: TextStyle(color: AppColors.text, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}

/// The places of [count] pictures being made.
class _Making extends StatelessWidget {
  const _Making({required this.count, required this.aspectRatio});

  final int count;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            ContentImagePlaceholder(aspectRatio: aspectRatio),
          ],
        ],
      ),
    );
  }
}
