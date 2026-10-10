import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;

import '../../ide/ide_button.dart';
import '../../ide/ide_drag_selection.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_input.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_spinning.dart';
import '../../l10n/l10n.dart';
import '../../models/model_provider.dart';
import '../../models/model_providers.dart';
import '../../models/model_test.dart';
import 'model_test_preset_dialog.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'model_dialogs.dart';
import 'model_table_pagination.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';
import 'model_test_result_view.dart';
import 'model_test_table.dart';
import 'model_test_filter_dialog.dart';

/// The action itself becomes a green check after a successful generation.
class ModelTestButton extends StatelessWidget {
  const ModelTestButton({
    super.key,
    required this.service,
    required this.provider,
    required this.model,
    this.preferences,
  });

  final ModelTestService service;
  final ModelProvider provider;
  final ProviderModel model;
  final ModelProviders? preferences;

  @override
  Widget build(BuildContext context) => provider.id == builtinProviderId
      ? const SizedBox.shrink()
      : ListenableBuilder(
          listenable: service,
          builder: (context, _) {
            final l10n = context.l10n;
            final result = service.result(provider.id, model.id);
            final status = result?.status;
            final button = IdeActionButton(
              icon: switch (status) {
                ModelTestStatus.passed => Codicons.check,
                ModelTestStatus.failed => Codicons.error,
                ModelTestStatus.running ||
                ModelTestStatus.queued => Codicons.sync,
                _ => Codicons.play,
              },
              color: modelTestStatusColor(status),
              label: status == ModelTestStatus.passed
                  ? modelTestSpeed(result)
                  : null,
              tooltipContent: result == null
                  ? null
                  : ModelTestHoverDetails(service: service, result: result),
              tooltip: [
                '${l10n.modelsBenchmark}: ${model.displayName}',
                if (status != null) modelTestStatusText(l10n, status),
                ?modelTestErrorText(l10n, result?.error),
              ].join('\n'),
              onPressed: !provider.connected || result?.active == true
                  ? null
                  : () => service.start(
                      provider,
                      [model],
                      prompt: (preferences ?? ModelProviders.current)
                          .selectedTestPreset
                          .prompt,
                    ),
            );
            return status == ModelTestStatus.running
                ? IdeSpinning(button)
                : button;
          },
        );
}

Future<void> showModelTestDialog(
  BuildContext context, {
  required ModelProvider provider,
  required ModelTestService service,
  ModelProviders? preferences,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => ModelTestDialog(
    provider: provider,
    service: service,
    preferences: preferences,
  ),
);

class ModelTestDialog extends StatefulWidget {
  const ModelTestDialog({
    super.key,
    required this.provider,
    required this.service,
    this.preferences,
  });

  final ModelProviders? preferences;
  final ModelProvider provider;
  final ModelTestService service;

  @override
  State<ModelTestDialog> createState() => _ModelTestDialogState();
}

class _ModelTestDialogState extends State<ModelTestDialog> {
  ModelProviders get _preferences =>
      widget.preferences ?? ModelProviders.current;
  late final _page = ModelTablePage(_preferences);
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  final Set<String> _selected = {};
  final _tableState = ModelTestTableState();
  final _search = TextEditingController();
  List<ModelTestTableRow> _allRows = [];
  List<ModelTestTableRow> _viewRows = [];
  List<ModelTestTableRow>? _strokeRows;
  List<double> _autoWidths = [];
  int? _widthSignature;
  double _selectionWidth = 36;
  String? _hoveredModel;

  @override
  void dispose() {
    // Only view resources: the process-level service keeps running.
    _search.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  void _start() => widget.service.start(
    widget.provider,
    _page
        .visible(_viewRows)
        .map((row) => row.model)
        .where((model) => _selected.contains(model.id)),
    prompt: _preferences.selectedTestPreset.prompt,
  );

  Future<void> _editPreset({required bool adding}) async {
    final saved = await showModelTestPresetDialog(
      context,
      source: _preferences.selectedTestPreset,
      adding: adding,
    );
    if (saved != null) await _preferences.saveTestPreset(saved);
  }

  void _resetPage() {
    _page.index = 0;
    _hoveredModel = null;
    if (_vertical.hasClients) _vertical.jumpTo(0);
  }

  Future<void> _filterColumn(ModelTestColumn column) async {
    final filter = await showModelTestFilterDialog(
      context,
      column: column,
      filter: _tableState.filters[column] ?? const ModelTestColumnFilter(),
    );
    if (!mounted || filter == null) return;
    setState(() {
      if (filter.active) {
        _tableState.filters[column] = filter;
      } else {
        _tableState.filters.remove(column);
      }
      _resetPage();
    });
  }

  void _resize(int index, double delta, double width) => setState(() {
    if (index == 0) {
      _selectionWidth = (width + delta).clamp(28, 80);
    } else {
      _tableState.widths[ModelTestColumn.values[index - 1]] = (width + delta)
          .clamp(64, 2000);
    }
  });

  Widget _header(ModelTestColumn column) => Row(
    children: [
      Expanded(
        child: IdeHover(
          message: column.label(context.l10n),
          child: GestureDetector(
            key: ValueKey('model-test-sort-${column.name}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              _tableState.toggleSort(column);
              _resetPage();
            }),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    column.label(context.l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SettingsText.label,
                  ),
                ),
                if (_tableState.sortColumn == column)
                  Icon(
                    _tableState.ascending
                        ? Codicons.arrowUp
                        : Codicons.arrowDown,
                    size: 12,
                    color: AppColors.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
      IdeActionButton(
        icon: Codicons.filter,
        iconSize: 12,
        size: 18,
        color: _tableState.filters.containsKey(column)
            ? themeColors['textLink.foreground']
            : null,
        tooltip:
            '${context.l10n.modelsTableFilter}: ${column.label(context.l10n)}',
        onPressed: () => unawaited(_filterColumn(column)),
      ),
    ],
  );

  Widget _textCell(
    String text, {
    Color? color,
    bool numeric = false,
    int maxLines = 1,
  }) => Text(
    text,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    textAlign: numeric ? TextAlign.right : TextAlign.left,
    style: SettingsText.description.copyWith(
      color: color,
      fontFamily: numeric ? AppFonts.mono : null,
      fontFamilyFallback: numeric ? AppFonts.monoFallbacks : null,
    ),
  );

  Widget _gridRow(
    List<Widget> cells, {
    bool header = false,
    bool alternate = false,
    required List<double> widths,
  }) {
    final border = themeColors['editorHoverWidget.border'];
    return Semantics(
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: header
              ? themeColors['editorHoverWidget.background']
              : alternate
              ? themeColors['list.hoverBackground'].withValues(alpha: .25)
              : null,
          border: Border(bottom: BorderSide(color: border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, cell) in cells.indexed)
              Stack(
                children: [
                  Container(
                    width: widths[index],
                    padding: EdgeInsets.symmetric(
                      horizontal: index == 0 ? 0 : 10,
                    ),
                    alignment: index >= 3 && index <= 7
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    decoration: BoxDecoration(
                      border: index == cells.length - 1
                          ? null
                          : Border(right: BorderSide(color: border)),
                    ),
                    child: cell,
                  ),
                  if (header)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      child: Semantics(
                        label: index == 0
                            ? context.l10n.modelsTableSelection
                            : '${context.l10n.modelsTableResize}: ${ModelTestColumn.values[index - 1].label(context.l10n)}',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            key: ValueKey('model-test-resize-$index'),
                            dragStartBehavior: DragStartBehavior.down,
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragUpdate: (event) => _resize(
                              index,
                              event.delta.dx,
                              index == 0
                                  ? _selectionWidth
                                  : _tableState.widths[ModelTestColumn
                                            .values[index - 1]] ??
                                        widths[index],
                            ),
                            child: SizedBox(
                              width: 6,
                              child: Center(
                                child: Container(width: 1, color: border),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _table(BuildContext context) {
    final l10n = context.l10n;
    final rows = _page.visible(_viewRows);
    final models = rows.map((row) => row.model).toList();
    final hovered = _hoveredModel == null
        ? null
        : widget.service.result(widget.provider.id, _hoveredModel!);
    // Keep the shared result portal outside the scroll clips; row-local portals
    // can detach their semantics when the rich overlay extends past the cell.
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = [
          _selectionWidth,
          for (final column in ModelTestColumn.values)
            _tableState.widths[column] ?? _autoWidths[column.index],
        ];
        final minimum = widths.fold<double>(0, (sum, width) => sum + width);
        final tableWidth = math.max(minimum, constraints.maxWidth);
        // Manual widths never get silently stretched again. Fill only columns
        // whose width is still automatic, preserving both handles and alignment.
        final free = [
          for (final i in [1, 8])
            if (!_tableState.widths.containsKey(ModelTestColumn.values[i - 1]))
              i,
        ];
        if (free.isNotEmpty) {
          for (final i in free) {
            widths[i] += (tableWidth - minimum) / free.length;
          }
        }
        return IdeHover(
          message: l10n.modelsBenchmarkView,
          enabled: hovered != null,
          followMouse: true,
          content: hovered == null
              ? Text(l10n.modelsBenchmarkUntested)
              : ModelTestHoverDetails(service: widget.service, result: hovered),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: themeColors['editorHoverWidget.border'],
              ),
            ),
            child: Scrollbar(
              controller: _horizontal,
              thumbVisibility: true,
              notificationPredicate: (notification) => notification.depth == 0,
              child: SingleChildScrollView(
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 36,
                        child: _gridRow(
                          [
                            Center(
                              child: ModelCheckbox(
                                hitSize: Size(widths[0], 36),
                                checked:
                                    models.isNotEmpty &&
                                    models.every(
                                      (m) => _selected.contains(m.id),
                                    ),
                                semanticLabel:
                                    models.isNotEmpty &&
                                        models.every(
                                          (m) => _selected.contains(m.id),
                                        )
                                    ? l10n.modelsFetchSelectNone
                                    : l10n.modelsFetchSelectAll,
                                onChanged: (checked) => setState(() {
                                  _selected.removeAll(models.map((m) => m.id));
                                  if (checked) {
                                    _selected.addAll(models.map((m) => m.id));
                                  }
                                }),
                              ),
                            ),
                            for (final column in ModelTestColumn.values)
                              _header(column),
                          ],
                          header: true,
                          widths: widths,
                        ),
                      ),
                      Expanded(
                        child: IdeDragSelection(
                          scrollController: _vertical,
                          onStart: () => _strokeRows = _viewRows,
                          onEnd: () => setState(() => _strokeRows = null),
                          child: ListView.builder(
                            controller: _vertical,
                            itemExtent: 38,
                            itemCount: models.length,
                            itemBuilder: (context, index) {
                              final row = rows[index];
                              final model = row.model;
                              final result = widget.service.result(
                                widget.provider.id,
                                model.id,
                              );
                              final error = modelTestErrorText(
                                l10n,
                                result?.error,
                              );
                              final preview =
                                  row.cells[ModelTestColumn.output.index];
                              return KeyedSubtree(
                                key: ValueKey(model.id),
                                child: _gridRow(
                                  [
                                    Center(
                                      child: ModelCheckbox(
                                        hitSize: Size(widths[0], 38),
                                        checked: _selected.contains(model.id),
                                        dragSelect: true,
                                        semanticLabel: model.displayName,
                                        onChanged: (checked) => setState(
                                          () => checked
                                              ? _selected.add(model.id)
                                              : _selected.remove(model.id),
                                        ),
                                      ),
                                    ),
                                    IdeHover(
                                      message: model.id,
                                      child: _textCell(model.displayName),
                                    ),
                                    _textCell(
                                      modelTestStatusText(l10n, result?.status),
                                      color: modelTestStatusColor(
                                        result?.status,
                                      ),
                                    ),
                                    _textCell(
                                      modelTestDuration(result?.firstEvent),
                                      numeric: true,
                                    ),
                                    _textCell(
                                      modelTestDuration(result?.firstText),
                                      numeric: true,
                                    ),
                                    _textCell(
                                      result == null
                                          ? '—'
                                          : modelTestDuration(result.elapsed),
                                      numeric: true,
                                    ),
                                    _textCell(
                                      modelTestOutputTokens(result),
                                      numeric: true,
                                    ),
                                    _textCell(
                                      modelTestSpeed(result),
                                      numeric: true,
                                    ),
                                    MouseRegion(
                                      onEnter: (_) => setState(
                                        () => _hoveredModel = model.id,
                                      ),
                                      child: SizedBox.expand(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: _textCell(
                                            preview,
                                            color: error != null
                                                ? themeColors['errorForeground']
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  alternate: index.isOdd,
                                  widths: widths,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.service, _preferences]),
    builder: (context, _) {
      final l10n = context.l10n;
      final provider = widget.provider;
      final preset = _preferences.selectedTestPreset;
      _allRows = [
        for (final model in provider.models)
          ModelTestTableRow(
            model,
            widget.service.result(provider.id, model.id),
            l10n,
          ),
      ];
      _viewRows = _strokeRows ?? _tableState.apply(_allRows);
      _page.visible(_viewRows);
      final signature = Object.hash(
        l10n.localeName,
        MediaQuery.textScalerOf(context),
        Object.hashAll(_allRows.expand((row) => row.cells.take(8))),
      );
      if (signature != _widthSignature) {
        _widthSignature = signature;
        _autoWidths = _tableState.autoWidths(context, _allRows);
      }
      final active = provider.models.any(
        (model) => widget.service.result(provider.id, model.id)?.active == true,
      );
      return ModelDialogFrame(
        title: '${l10n.modelsBenchmarkTitle} · ${provider.name}',
        maxWidth: 1120,
        actionsLeading: ModelTablePagination(
          page: _page,
          count: _viewRows.length,
          onChanged: () {
            if (mounted) {
              setState(() {
                _hoveredModel = null;
                if (_vertical.hasClients) _vertical.jumpTo(0);
              });
            }
          },
        ),
        actions: [
          if (active)
            IdeButton(
              label: l10n.modelsBenchmarkStop,
              secondary: true,
              onPressed: () => widget.service.cancel(provider.id),
            ),
          IdeButton(
            label: l10n.modelsBenchmarkStart,
            icon: Codicons.play,
            onPressed:
                !provider.connected ||
                    !_page
                        .visible(_viewRows)
                        .any((row) => _selected.contains(row.model.id)) ||
                    preset.prompt.trim().isEmpty
                ? null
                : _start,
          ),
          IdeButton(
            label: l10n.commonClose,
            secondary: true,
            onPressed: () => Navigator.pop(context),
          ),
        ],
        child: SizedBox(
          height: math.min(
            MediaQuery.sizeOf(context).height * .85 - 110,
            202 + 38.0 * math.max(1, _page.visible(_viewRows).length),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Text(l10n.modelsBenchmarkPrompt, style: SettingsText.label),
                  SettingsDropdown(
                    current: modelTestPresetName(l10n, preset),
                    semanticLabel: l10n.modelsBenchmarkPrompt,
                    entries: () => [
                      for (final item in _preferences.testPresets)
                        IdeMenuAction(
                          modelTestPresetName(l10n, item),
                          checked: item.id == preset.id,
                          onSelected: () =>
                              unawaited(_preferences.selectTestPreset(item.id)),
                        ),
                      const IdeMenuSeparator(),
                      IdeMenuAction(
                        l10n.modelsPresetAdd,
                        onSelected: () => unawaited(_editPreset(adding: true)),
                      ),
                    ],
                  ),
                  IdeActionButton(
                    icon: Codicons.add,
                    tooltip: l10n.modelsPresetAdd,
                    onPressed: () => unawaited(_editPreset(adding: true)),
                  ),
                  IdeActionButton(
                    icon: Codicons.edit,
                    tooltip: l10n.modelsPresetEdit,
                    onPressed: preset.builtin
                        ? null
                        : () => unawaited(_editPreset(adding: false)),
                  ),
                  IdeActionButton(
                    icon: Codicons.trash,
                    tooltip: l10n.modelsPresetDelete,
                    onPressed: preset.builtin
                        ? null
                        : () => unawaited(
                            _preferences.deleteTestPreset(preset.id),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                color: themeColors['input.background'],
                child: SelectableText(
                  preset.prompt,
                  maxLines: 3,
                  style: SettingsText.description.copyWith(
                    fontFamily: AppFonts.mono,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: IdeInputBox(
                      controller: _search,
                      placeholder: l10n.modelsTableSearch,
                      semanticsLabel: l10n.modelsTableSearch,
                      onChanged: (value) => setState(() {
                        _tableState.query = value;
                        _resetPage();
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IdeButton(
                    label: l10n.modelsTableClear,
                    secondary: true,
                    onPressed: () => setState(() {
                      _search.clear();
                      _tableState.query = '';
                      _tableState.filters.clear();
                      _tableState.sortColumn = null;
                      _resetPage();
                    }),
                  ),
                  const SizedBox(width: 6),
                  IdeButton(
                    label: l10n.modelsTableAutoWidth,
                    secondary: true,
                    onPressed: () => setState(() {
                      _tableState.widths.clear();
                      _selectionWidth = 36;
                      if (_horizontal.hasClients) _horizontal.jumpTo(0);
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(child: _table(context)),
            ],
          ),
        ),
      );
    },
  );
}
