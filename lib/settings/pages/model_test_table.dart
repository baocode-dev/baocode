import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/model_provider.dart';
import '../../models/model_test.dart';
import '../../theme/app_theme.dart';
import 'model_test_result_view.dart';
import 'settings_widgets.dart';

enum ModelTestColumn {
  model,
  status,
  firstEvent,
  firstText,
  duration,
  tokens,
  speed,
  output;

  bool get numeric => index >= firstEvent.index && index <= speed.index;
  bool get time => this == firstEvent || this == firstText || this == duration;

  String label(AppLocalizations l10n) => switch (this) {
    model => l10n.modelsBenchmarkModel,
    status => l10n.modelsBenchmarkStatus,
    firstEvent => l10n.modelsBenchmarkFirstEvent,
    firstText => l10n.modelsBenchmarkFirstText,
    duration => l10n.modelsBenchmarkDuration,
    tokens => l10n.modelsBenchmarkTokens,
    speed => l10n.modelsBenchmarkSpeed,
    output => l10n.modelsBenchmarkOutput,
  };
}

/// Snapshot the values once per refresh so filters and comparators use the
/// same stream state. Formatting is shared with the result hover, not copied.
class ModelTestTableRow {
  ModelTestTableRow(this.model, ModelTestResult? result, AppLocalizations l10n)
    : cells = [
        model.displayName,
        modelTestStatusText(l10n, result?.status),
        modelTestDuration(result?.firstEvent),
        modelTestDuration(result?.firstText),
        result == null ? '—' : modelTestDuration(result.elapsed),
        modelTestOutputTokens(result),
        modelTestSpeed(result),
        modelTestOutputPreview(
          result?.output.isNotEmpty == true
              ? result!.output
              : modelTestErrorText(l10n, result?.error) ?? '',
        ),
      ],
      values = [
        model.displayName.toLowerCase(),
        result?.status.index ?? -1,
        _seconds(result?.firstEvent),
        _seconds(result?.firstText),
        result == null ? null : _seconds(result.elapsed),
        result == null || result.output.isEmpty ? null : result.outputTokens,
        result?.tokensPerSecond,
        (result?.output ?? '').toLowerCase(),
      ],
      searchableOutput = [
        result?.output ?? '',
        result?.thinking ?? '',
        modelTestErrorText(l10n, result?.error) ?? '',
      ].join('\n').toLowerCase();

  final ProviderModel model;
  final List<String> cells;
  final List<Object?> values;
  final String searchableOutput;

  static double? _seconds(Duration? value) =>
      value == null ? null : value.inMicroseconds / 1000000;

  String searchValue(ModelTestColumn column) => switch (column) {
    ModelTestColumn.model => '${model.id}\n${model.displayName}'.toLowerCase(),
    ModelTestColumn.output => searchableOutput,
    _ => cells[column.index].toLowerCase(),
  };
}

class ModelTestColumnFilter {
  const ModelTestColumnFilter({this.text = '', this.minimum, this.maximum});
  final String text;
  final double? minimum;
  final double? maximum;
  bool get active =>
      text.trim().isNotEmpty || minimum != null || maximum != null;

  bool matches(ModelTestTableRow row, ModelTestColumn column) {
    if (!row.searchValue(column).contains(text.trim().toLowerCase())) {
      return false;
    }
    if (minimum == null && maximum == null) return true;
    final value = row.values[column.index];
    return value is num &&
        (minimum == null || value >= minimum!) &&
        (maximum == null || value <= maximum!);
  }

  /// Time thresholds accept either s or ms; metric display units are not used
  /// as sorting keys. Tokens and throughput accept their displayed suffixes.
  static double? parseNumber(String text, ModelTestColumn column) {
    final value = text.trim().toLowerCase();
    if (value.isEmpty) return null;
    final match = RegExp(
      r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*(ms|s|token/s|tokens?|)?$',
    ).firstMatch(value);
    if (match == null) return null;
    final number = double.tryParse(match[1]!);
    if (number == null || !number.isFinite) return null;
    final unit = match[2] ?? '';
    if (column.time) {
      if (unit != '' && unit != 's' && unit != 'ms') return null;
      return unit == 'ms' ? number / 1000 : number;
    }
    if (column == ModelTestColumn.tokens &&
        !const ['', 'token', 'tokens'].contains(unit)) {
      return null;
    }
    if (column == ModelTestColumn.speed &&
        !const ['', 'token/s'].contains(unit)) {
      return null;
    }
    return number;
  }
}

/// Filter/sort the complete dataset before pagination. Missing measurements
/// stay last in either direction; equal values keep a deterministic ID order.
class ModelTestTableState {
  String query = '';
  ModelTestColumn? sortColumn;
  bool ascending = true;
  final filters = <ModelTestColumn, ModelTestColumnFilter>{};
  final widths = <ModelTestColumn, double>{};

  void toggleSort(ModelTestColumn column) {
    ascending = sortColumn != column || !ascending;
    sortColumn = column;
  }

  List<ModelTestTableRow> apply(List<ModelTestTableRow> rows) {
    final search = query.trim().toLowerCase();
    final result = rows
        .where(
          (row) =>
              (search.isEmpty ||
                  ModelTestColumn.values.any(
                    (c) => row.searchValue(c).contains(search),
                  )) &&
              filters.entries.every(
                (entry) => entry.value.matches(row, entry.key),
              ),
        )
        .toList();
    final column = sortColumn;
    if (column == null) return result;
    result.sort((a, b) {
      final av = a.values[column.index];
      final bv = b.values[column.index];
      if (av == null || bv == null) {
        if (av != bv) return av == null ? 1 : -1;
      } else {
        final compared = av is num && bv is num
            ? av.compareTo(bv)
            : '$av'.compareTo('$bv');
        if (compared != 0) return ascending ? compared : -compared;
      }
      return a.model.id.compareTo(b.model.id);
    });
    return result;
  }

  /// Measure all rows, not only the current page. Outlier model IDs have an
  /// auto-width cap; manual resizing can exceed that cap.
  List<double> autoWidths(
    BuildContext context,
    List<ModelTestTableRow> rows, {
    ModelTestColumn? fitColumn,
  }) {
    final l10n = context.l10n;
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    double measure(String text, TextStyle style) {
      // Native text inherits theme letter spacing and fallback fonts too.
      painter.text = TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      );
      painter.layout();
      return painter.width.ceilToDouble();
    }

    final result = <double>[];
    for (final column in ModelTestColumn.values) {
      var width = measure(column.label(l10n), SettingsText.label) + 62;
      if (column != ModelTestColumn.output) {
        final style = SettingsText.description;
        // Layout repeated status/metric text only once per refresh.
        final values = rows.map((row) => row.cells[column.index]).toSet();
        for (final value in values) {
          width = math.max(
            width,
            measure(
                  value,
                  style.copyWith(
                    fontFamily: column.numeric ? AppFonts.mono : null,
                    fontFamilyFallback: column.numeric
                        ? AppFonts.monoFallbacks
                        : null,
                  ),
                ) +
                24,
          );
        }
      }
      final min = column == ModelTestColumn.model ? 150.0 : 72.0;
      final max = column == ModelTestColumn.model && fitColumn != column
          ? 420.0
          : 1400.0;
      result.add(width.clamp(min, max));
    }
    painter.dispose();
    return result;
  }
}
