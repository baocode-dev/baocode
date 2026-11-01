import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_input.dart';
import '../../l10n/l10n.dart';
import '../../models/model_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../workspace/editor_launcher.dart' show openExternal;
import '../usage_prices.dart';
import '../usage_query.dart';
import '../usage_record.dart';
import 'usage_charts.dart';
import 'usage_filters.dart';
import 'usage_style.dart';

/// Settings → Usage's prices: the models called in the time shown and
/// those priced, a row each, their prices a million tokens typed in place
/// (kept as a field is left), what they came to in that time; and that
/// BaoCode can keep them (the baocode-usage skill).
class UsagePricesCard extends StatelessWidget {
  const UsagePricesCard({super.key, required this.summary, this.prices});

  final UsageSummary summary;

  /// The app's by default.
  final UsagePrices? prices;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final prices = this.prices ?? UsagePrices.current;
    return ListenableBuilder(
      listenable: prices,
      builder: (context, _) {
        final rows = <_Row>[];
        final seen = <String>{};
        // By upstream and model: the same model on two is priced apart.
        final called = <(String, String), List<UsageCall>>{};
        for (final call in summary.calls) {
          (called[(call.provider, call.model)] ??= []).add(call);
        }
        final ranked = called.entries.toList()
          ..sort(
            (a, b) => b.value
                .fold(0, (sum, call) => sum + call.total)
                .compareTo(a.value.fold(0, (sum, call) => sum + call.total)),
          );
        for (final MapEntry(key: (upstream, model), value: calls) in ranked) {
          // Its own price, else any upstream's, else one to be its own.
          final own = UsagePrices.key(upstream, model);
          final any = UsagePrices.key(null, model);
          final key =
              prices.all.containsKey(own) || !prices.all.containsKey(any)
              ? own
              : any;
          if (!seen.add(key)) continue;
          rows.add(
            _Row(
              key: key,
              upstream: upstream,
              model: model,
              upstreamName: key == any
                  ? l10n.ustatPriceAnyUpstream
                  : calls.last.providerName ?? upstream,
              spent: prices.costOf([
                for (final MapEntry(key: (u, m), value: calls) in ranked)
                  // Any upstream's: those it prices, none of their own.
                  if (m == model &&
                      (u == upstream ||
                          (key == any &&
                              !prices.all.containsKey(UsagePrices.key(u, m)))))
                    ...calls,
              ]),
            ),
          );
        }
        for (final key in prices.all.keys) {
          if (seen.contains(key)) continue;
          final (:upstream, :model) = UsagePrices.parseKey(key);
          rows.add(
            _Row(
              key: key,
              upstream: upstream ?? '',
              model: model,
              upstreamName: upstream ?? l10n.ustatPriceAnyUpstream,
            ),
          );
        }
        return UsageCard(
          title: l10n.ustatPrices,
          subtitle: l10n.ustatPricesDetail,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Header(),
              for (final row in rows)
                _PriceRow(key: ValueKey(row.key), row: row, prices: prices),
              const SizedBox(height: 10),
              if (rows.any(
                (row) =>
                    row.upstream == ClaudePrices.upstream &&
                    !prices.all.containsKey(row.key) &&
                    ClaudePrices.of(row.model) != null,
              )) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: Text(
                    l10n.ustatPriceClaudeDefault,
                    style: UsageText.faint,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Codicons.sparkle,
                      size: 12,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.ustatPricesAgentHint,
                      style: UsageText.faint,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Row {
  const _Row({
    required this.key,
    required this.upstream,
    required this.model,
    required this.upstreamName,
    this.spent,
  });

  final String key;
  final String upstream;
  final String model;
  final String upstreamName;
  final UsageCost? spent;
}

/// The columns' widths.
abstract final class _Columns {
  static const price = 64.0;
  static const currency = 52.0;
  static const spent = 76.0;
  static const actions = 56.0;
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget cell(String text, double width) => SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: UsageText.faint,
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: UsagePalette.grid)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(l10n.ustatFieldModel, style: UsageText.faint)),
          cell(l10n.ustatTokenInput, _Columns.price),
          cell(l10n.ustatTokenCacheRead, _Columns.price),
          cell(l10n.ustatTokenCacheWrite, _Columns.price),
          cell(l10n.ustatTokenOutput, _Columns.price),
          cell(l10n.ustatPriceCurrency, _Columns.currency),
          cell(l10n.ustatPriceSpent, _Columns.spent),
          const SizedBox(width: _Columns.actions),
        ],
      ),
    );
  }
}

/// A model's prices, each typed in place; kept once a field is left with
/// both the input's and the output's in, cleared once all are emptied.
class _PriceRow extends StatefulWidget {
  const _PriceRow({super.key, required this.row, required this.prices});

  final _Row row;
  final UsagePrices prices;

  @override
  State<_PriceRow> createState() => _PriceRowState();
}

class _PriceRowState extends State<_PriceRow> {
  late final _input = TextEditingController();
  late final _cacheRead = TextEditingController();
  late final _cacheWrite = TextEditingController();
  late final _output = TextEditingController();
  late final _currency = TextEditingController();
  bool _incomplete = false;
  ModelPrice? _shown;

  ModelPrice? get _price => widget.prices.all[widget.row.key];

  List<TextEditingController> get _fields => [
    _input,
    _cacheRead,
    _cacheWrite,
    _output,
    _currency,
  ];

  @override
  void initState() {
    super.initState();
    _fill();
  }

  @override
  void didUpdateWidget(_PriceRow old) {
    super.didUpdateWidget(old);
    // Set elsewhere (by an agent, in settings.json): shown as it is now.
    if (_price != _shown) _fill();
  }

  static String _number(double? value) {
    if (value == null) return '';
    final text = value.toStringAsFixed(4);
    return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
  }

  void _fill() {
    final price = _shown = _price;
    String number(double? value) => _number(value);
    _input.text = number(price?.input);
    _cacheRead.text = number(price?.cacheRead);
    _cacheWrite.text = number(price?.cacheWrite);
    _output.text = number(price?.output);
    _currency.text = price?.currency ?? '';
    _incomplete = false;
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  void _commit() {
    double? number(TextEditingController field) =>
        double.tryParse(field.text.trim().replaceAll(',', ''));
    final input = number(_input);
    final output = number(_output);
    final empty = _fields.take(4).every((field) => field.text.trim().isEmpty);
    final old = _price;
    if (empty) {
      setState(() => _incomplete = false);
      if (old != null) unawaited(widget.prices.update({widget.row.key: null}));
      return;
    }
    if (input == null || output == null) {
      setState(() => _incomplete = true);
      return;
    }
    final currency = _currency.text.trim().toUpperCase();
    final next = ModelPrice(
      input: input,
      output: output,
      cacheRead: number(_cacheRead),
      cacheWrite: number(_cacheWrite),
      cacheWriteLong: old?.cacheWriteLong,
      currency: currency.isEmpty ? old?.currency ?? 'USD' : currency,
      source: old?.source,
      updated: old?.updated,
    );
    setState(() => _incomplete = false);
    if (next == old) return;
    _shown = ModelPrice(
      input: next.input,
      output: next.output,
      cacheRead: next.cacheRead,
      cacheWrite: next.cacheWrite,
      cacheWriteLong: next.cacheWriteLong,
      currency: next.currency,
      source: next.source,
      updated: DateTime.now(),
    );
    unawaited(widget.prices.update({widget.row.key: _shown}));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final row = widget.row;
    final price = _price;
    final spent = row.spent?.text;
    // Claude Code's own, unset: priced at Anthropic's, shown in its place.
    final fallback = price == null && row.upstream == ClaudePrices.upstream
        ? ClaudePrices.of(row.model)
        : null;
    String shown(double? value, String text) =>
        fallback == null ? text : _number(value);
    Widget field(TextEditingController controller, double width, String hint) =>
        SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Focus(
              onFocusChange: (focused) {
                if (!focused) _commit();
              },
              child: IdeInputBox(
                controller: controller,
                placeholder: hint,
                fontSize: 12,
                lineHeight: 16,
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                semanticsLabel: '${row.model} $hint',
                onSubmitted: (_) => _commit(),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ModelIcon(provider: row.upstream, model: row.model, size: 12),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: row.model, style: UsageText.body),
                      TextSpan(
                        text: '  ${row.upstreamName}',
                        style: UsageText.faint,
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              field(
                _input,
                _Columns.price,
                shown(fallback?.input, l10n.ustatTokenInput),
              ),
              field(
                _cacheRead,
                _Columns.price,
                shown(fallback?.cacheRead, '='),
              ),
              field(
                _cacheWrite,
                _Columns.price,
                shown(fallback?.cacheWrite, '='),
              ),
              field(
                _output,
                _Columns.price,
                shown(fallback?.output, l10n.ustatTokenOutput),
              ),
              field(_currency, _Columns.currency, 'USD'),
              SizedBox(
                width: _Columns.spent,
                child: Text(
                  spent ?? '—',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: UsageText.tabular.copyWith(
                    color: spent == null ? AppColors.textFaint : null,
                  ),
                ),
              ),
              SizedBox(
                width: _Columns.actions,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (price?.source case final source?)
                      UsageIconButton(
                        icon: Codicons.linkExternal,
                        tooltip: [
                          '${l10n.ustatPriceSource}: $source',
                          if (price?.updated case final updated?)
                            l10n.ustatPriceUpdated(
                              UsageFormat.when(updated.toLocal()),
                            ),
                        ].join('\n'),
                        onPressed: () => unawaited(openExternal(source)),
                      ),
                    if (price != null)
                      UsageIconButton(
                        icon: Codicons.close,
                        tooltip: l10n.ustatPriceClear,
                        onPressed: () =>
                            unawaited(widget.prices.update({row.key: null})),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (_incomplete)
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 2),
              child: Text(
                l10n.ustatPriceIncomplete,
                style: UsageText.faint.copyWith(color: UsagePalette.error),
              ),
            ),
        ],
      ),
    );
  }
}
