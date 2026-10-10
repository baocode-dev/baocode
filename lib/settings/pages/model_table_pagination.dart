import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ide/ide_hover.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../models/model_providers.dart';
import '../../theme/codicons.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';

/// All model pickers share one page-size preference; selection remains owned
/// by each dialog, and select-all always uses that dialog's current page.
class ModelTablePage {
  ModelTablePage(this.providers);
  final ModelProviders providers;
  int index = 0;
  int get size => providers.modelPageSize;
  int pages(int count) => size == 0 ? 1 : math.max(1, (count / size).ceil());
  List<T> visible<T>(List<T> items) {
    index = index.clamp(0, pages(items.length) - 1);
    if (size == 0) return items;
    final start = index * size;
    return items.sublist(start, math.min(start + size, items.length));
  }
}

class ModelTablePagination extends StatelessWidget {
  const ModelTablePagination({
    super.key,
    required this.page,
    required this.count,
    required this.onChanged,
  });
  final ModelTablePage page;
  final int count;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(l10n.modelsPageRows, style: SettingsText.description),
        SettingsDropdown(
          current: page.size == 0 ? l10n.modelsPageUnlimited : '${page.size}',
          semanticLabel: l10n.modelsPageRows,
          entries: () => [
            for (final size in const [100, 1000, 10000, 0])
              IdeMenuAction(
                size == 0 ? l10n.modelsPageUnlimited : '$size',
                checked: size == page.size,
                onSelected: () async {
                  await page.providers.setModelPageSize(size);
                  page.index = 0;
                  onChanged();
                },
              ),
          ],
        ),
        Text(
          '${page.index + 1} / ${page.pages(count)} · $count',
          style: SettingsText.description,
        ),
        IdeActionButton(
          icon: Codicons.chevronLeft,
          tooltip: l10n.modelsPagePrevious,
          onPressed: page.index == 0
              ? null
              : () {
                  page.index--;
                  onChanged();
                },
        ),
        IdeActionButton(
          icon: Codicons.chevronRight,
          tooltip: l10n.modelsPageNext,
          onPressed: page.index + 1 >= page.pages(count)
              ? null
              : () {
                  page.index++;
                  onChanged();
                },
        ),
      ],
    );
  }
}
