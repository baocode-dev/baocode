import 'package:flutter/material.dart';

import '../../ide/ide_hover.dart';
import '../../ide/ide_input.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'model_dialogs.dart';

/// Shared quiet table surface for model selection and model benchmarks.
/// Selection is indicated by tint, not by heavy borders around every cell.
class ModelTableRow extends StatefulWidget {
  const ModelTableRow({
    super.key,
    required this.child,
    this.header = false,
    this.selected = false,
  });
  final Widget child;
  final bool header;
  final bool selected;

  @override
  State<ModelTableRow> createState() => _ModelTableRowState();
}

class _ModelTableRowState extends State<ModelTableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: Container(
      decoration: BoxDecoration(
        color: _hovered && !widget.header
            ? themeColors['list.hoverBackground'].withValues(alpha: .5)
            : widget.selected
            ? themeColors['list.activeSelectionBackground'].withValues(
                alpha: .18,
              )
            : widget.header
            ? themeColors['editorHoverWidget.background'].withValues(alpha: .45)
            : null,
        border: Border(
          bottom: BorderSide(
            color: themeColors['editorHoverWidget.border'].withValues(
              alpha: widget.header ? .55 : .18,
            ),
          ),
        ),
      ),
      child: widget.child,
    ),
  );
}

/// The top-level checkbox selects all models. Its visual box shares the row
/// checkbox center; the scope menu overlays the edge instead of shifting it.
class ModelTableSelection extends StatelessWidget {
  const ModelTableSelection({
    super.key,
    required this.checked,
    required this.onPageChanged,
    required this.onAllChanged,
    required this.allChecked,
    this.width = 42,
    this.height = 32,
  });
  final bool checked;
  final ValueChanged<bool>? onPageChanged;
  final ValueChanged<bool>? onAllChanged;
  final bool allChecked;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: Stack(
      children: [
        ModelCheckbox(
          checked: allChecked,
          hitSize: Size(width, height),
          semanticLabel: allChecked
              ? context.l10n.modelsFetchSelectNone
              : context.l10n.modelsFetchSelectAll,
          onChanged: onAllChanged,
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 12,
          child: Builder(
            builder: (context) => IdeActionButton(
              icon: Codicons.chevronDown,
              size: 12,
              iconSize: 10,
              tooltip: context.l10n.modelsSelectionScope,
              onPressed: onAllChanged == null
                  ? null
                  : () {
                      final box = context.findRenderObject()! as RenderBox;
                      showIdeMenu(
                        context,
                        anchor: box.localToGlobal(Offset.zero) & box.size,
                        entries: [
                          IdeMenuAction(
                            context.l10n.modelsSelectPage,
                            onSelected: () => onPageChanged?.call(true),
                          ),
                          IdeMenuAction(
                            context.l10n.modelsSelectAllPages,
                            checked: allChecked,
                            onSelected: () => onAllChanged?.call(true),
                          ),
                          const IdeMenuSeparator(),
                          IdeMenuAction(
                            context.l10n.modelsFetchSelectNone,
                            onSelected: () => onAllChanged?.call(false),
                          ),
                        ],
                      );
                    },
            ),
          ),
        ),
      ],
    ),
  );
}

/// The search and clear actions live in the field instead of a second toolbar.
class ModelTableSearch extends StatelessWidget {
  const ModelTableSearch({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
    this.onClear,
    this.autofocus = false,
  });
  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => IdeInputBox(
    controller: controller,
    autofocus: autofocus,
    semanticsLabel: label,
    placeholder: label,
    onChanged: onChanged,
    toggles: [
      if (controller.text.isNotEmpty || onClear != null)
        IdeActionButton(
          icon: Codicons.close,
          size: 24,
          iconSize: 12,
          tooltip: context.l10n.modelsTableClear,
          onPressed:
              onClear ??
              () {
                controller.clear();
                onChanged('');
              },
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Icon(
          Codicons.search,
          size: 13,
          color: themeColors['descriptionForeground'],
        ),
      ),
    ],
  );
}
