import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import '../chat/chat_models.dart';
import '../chat/widgets/hover_builder.dart';
import '../chat/widgets/content_image.dart';
import '../chat/widgets/step_header.dart';
import '../ide/ide_button.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../workspace/window_controls.dart';
import 'browser_tools.dart';

/// The browser's icon (Basil's chrome-solid), a browser step's.
const browserIcon = 'assets/icons/chrome-solid.svg';

/// What a call of a browser tool is about, in a few words: its step's
/// line after the verb, when the agent did not say it. From its input and,
/// once answered, what it answered (a page's title, an element's name).
String browserStepSummary(
  String tool,
  Map<String, Object?> input,
  String? output,
) {
  String? text(String key) => switch (input[key]) {
    final String value when value.trim().isNotEmpty => value.trim(),
    _ => null,
  };
  final answer = output ?? '';
  switch (tool) {
    case 'browser_open':
      return _address(text('url') ?? '');
    case 'browser_navigate':
      if (text('url') case final url?) return _address(url);
      // Where back, forward or a reload led: as browser_tabs lists a tab.
      return RegExp(r'^\[\d+\] (.*) — ').firstMatch(answer)?[1] ?? '';
    case 'browser_snapshot':
      return RegExp(r'^Title: (.*)$', multiLine: true).firstMatch(answer)?[1] ??
          '';
    case 'browser_click' || 'browser_type':
      // The element, as the tool found it.
      if (RegExp(r'^(?:Clicked|Typed into) (\S+)(?: "(.+?)")?(?: \[\d+\])?[.,]')
              .firstMatch(answer)
          case final match? when match[1] != 'at') {
        return match[2] == null ? match[1]! : '“${match[2]}”';
      }
      if (tool == 'browser_type') return '“${_clip(text('text') ?? '', 60)}”';
      return _aim(input);
    case 'browser_press':
      return text('key') ?? '';
    case 'browser_scroll':
      final dy = (input['deltaY'] as num?)?.round() ?? 0;
      final dx = (input['deltaX'] as num?)?.round() ?? 0;
      return [
        if (dy != 0) '${dy > 0 ? '↓' : '↑'} ${dy.abs()}',
        if (dx != 0) '${dx > 0 ? '→' : '←'} ${dx.abs()}',
      ].join(' ');
    case 'browser_evaluate':
      return _clip(text('expression')?.split('\n').first ?? '', 80);
    case 'browser_act':
      // A kept script: its name.
      final file = text('file');
      if (input['steps'] == null && file != null) return p.basename(file);
      // Each step's aim: “Reply” → “Great point” → Enter.
      return [
        for (final step
            in (input['steps'] as List? ?? const []).whereType<Map>())
          switch (step['action']) {
            'click' => _aim(step.cast()),
            'type' => '“${_clip('${step['text'] ?? ''}', 30)}”',
            'press' => '${step['key'] ?? ''}',
            'scroll' => '↕',
            'drag' => '${_aim(step.cast())} ⇢',
            'hover' => _aim(step.cast()),
            'wait' => '…',
            'navigate' => _address('${step['url'] ?? ''}'),
            _ => '',
          },
      ].where((s) => s.isNotEmpty).join(' → ');
    case 'browser_watch':
      return _clip(text('task')?.split('\n').first ?? '', 80);
    case 'browser_console':
      return switch (text('level')) {
        final level? when level != 'all' => level,
        _ => '',
      };
    case 'browser_network':
      return [
        ?text('url'),
        ?text('type'),
        if (input['failed'] == true) 'failed',
        if (text('save') case final save?) '→ ${save.split('/').last}',
      ].join(' · ');
    case 'browser_request':
      // Its first line: the method and the URL.
      if (RegExp(r'^(\S+) (\S+)').firstMatch(answer) case final match?) {
        return '${match[1]} ${_address(match[2]!)}';
      }
      return text('id') ?? '';
    case 'browser_performance':
      final vitals = PerformanceReport.parse(answer).vitals;
      return [
        for (final vital in vitals.take(2))
          if (vital.value != '—') '${vital.name} ${vital.value}',
      ].join(' · ');
    case 'browser_emulate':
      return [
        if (input['cpu'] case final num cpu when cpu > 1)
          'CPU ${cpu is int || cpu == cpu.roundToDouble() ? cpu.round() : cpu}×',
        if (text('network') case final network? when network != 'none') network,
        if (text('device') case final device? when device != 'none') device,
        if (text('colorScheme') case final scheme? when scheme != 'none')
          scheme,
        ?text('locale'),
        ?text('timezone'),
        if (input['cache'] == false) 'no cache',
        if (text('vision') case final vision? when vision != 'none') vision,
      ].join(' · ');
    case 'browser_inspect':
      return [
        if (text('selector') case final selector?) selector else _aim(input),
        if (input['parts'] case final List parts when parts.isNotEmpty)
          parts.join(', '),
      ].where((s) => s.isNotEmpty).join(' · ');
    case 'browser_sources':
      return [
        ?text('action'),
        ?text('url'),
        ?text('query'),
        ?text('filter'),
      ].join(' · ');
    case 'browser_breakpoints':
      final where = text('url') == null
          ? null
          : '${text('url')!.split('/').last}${input['line'] == null ? '' : ':${input['line']}'}';
      return [
        ?text('action'),
        ?where,
        if (text('exceptions') case final exceptions?)
          'exceptions: $exceptions',
        if (text('xhr') case final xhr?) 'xhr $xhr',
        ?text('event'),
        ?text('dom'),
        if (text('log') != null) 'logpoint',
        ?text('id'),
      ].join(' · ');
    case 'browser_debugger':
      // Where it is paused, as its first line says.
      final paused = RegExp(
        r'^Paused: (.*)$',
        multiLine: true,
      ).firstMatch(answer)?[1];
      return [
        ?text('action'),
        if (paused != null) _clip(paused, 80),
      ].join(' · ');
    case 'browser_intercept':
      return [?text('action'), ?text('url'), ?text('id')].join(' · ');
    case 'browser_storage':
      return [?text('kind'), ?text('action'), ?text('name')].join(' · ');
    case 'browser_dialog':
      return input['accept'] == true ? 'accept' : 'dismiss';
    case 'browser_history':
      return [
        ?text('since'),
        ?text('id'),
        ?text('url'),
        if (input['failed'] == true) 'failed',
      ].join(' · ');
    case 'browser_coverage':
      return text('action') ?? '';
    case 'browser_memory':
      return [?text('action'), ?text('of')].join(' · ');
  }
  return '';
}

/// What a click aims at: its words, else its ref, else its point.
String _aim(Map<String, Object?> input) =>
    switch ((input['text'], input['ref'], input['x'], input['y'])) {
      (final String text, _, _, _) when text.isNotEmpty => '“$text”',
      (_, final int ref, _, _) => '[$ref]',
      (_, _, final num x, final num y) => '(${x.round()}, ${y.round()})',
      _ => '',
    };

/// A URL as a step shows it: without its scheme, nor a lone slash.
String _address(String url) {
  final bare = url.replaceFirst(RegExp(r'^https?://(www\.)?'), '');
  return _clip(
    bare.endsWith('/') ? bare.substring(0, bare.length - 1) : bare,
    80,
  );
}

String _clip(String text, int max) =>
    text.length > max ? '${text.substring(0, max)}…' : text;

/// What a browser step did ([tool], as its [input] says), or does while
/// running; in [l10n]'s language.
String browserVerb(
  String? tool,
  Map<String, Object?> input, {
  ToolStatus status = ToolStatus.succeeded,
  required AppLocalizations l10n,
}) {
  final action = switch (tool) {
    'browser_navigate' when input['url'] == null => switch (input['action']) {
      final String action => action,
      _ => 'navigate',
    },
    'browser_performance' => switch (input['action']) {
      'start' => 'recordStart',
      'stop' => 'recordStop',
      _ => 'performance',
    },
    final String tool => tool.replaceFirst('browser_', ''),
    null => '',
  };
  return status == ToolStatus.running
      ? l10n.browserStepRunning(action)
      : l10n.browserStepDone(action);
}

/// Whether [item] answered with something to read: a page's text, the
/// console, a screenshot; not an action's "Clicked." (unless it failed).
bool _readable(ToolCallItem item) {
  if (item.images.isNotEmpty) return true;
  if (item.output?.trim().isEmpty ?? true) return false;
  if (item.status == ToolStatus.failed) return true;
  return switch (item.tool) {
    'browser_tabs' ||
    'browser_snapshot' ||
    'browser_evaluate' ||
    'browser_console' ||
    'browser_network' ||
    'browser_request' ||
    'browser_performance' ||
    'browser_emulate' ||
    'browser_inspect' ||
    'browser_sources' ||
    'browser_breakpoints' ||
    'browser_debugger' ||
    'browser_intercept' ||
    'browser_storage' ||
    'browser_dialog' ||
    'browser_coverage' ||
    'browser_memory' ||
    'browser_history' ||
    'browser_watch' => true,
    // An action's answer says what it changed, past its first line.
    _ => item.output!.trim().contains('\n'),
  };
}

/// A browser tool's call as a step: "Clicked “Sign in”", or what the agent
/// said it does. It opens to what it found, each its own way: a
/// screenshot (small after its line while it is closed), the console's
/// lines by level, the requests as a table, a performance report's Web
/// Vitals; its right click shows the tab in the side panel. While it watches the user (browser_watch),
/// it shows what they are asked and do, and their buttons to finish.
class BrowserStep extends StatelessWidget {
  const BrowserStep({
    super.key,
    required this.item,
    this.expanded = false,
    this.onToggle,
  });

  final ToolCallItem item;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final opens = _readable(item);
    final running = item.status == ToolStatus.running;
    final shot = item.status == ToolStatus.failed
        ? null
        : item.images.firstOrNull;
    final header = StepHeader(
      verb:
          item.label ??
          browserVerb(item.tool, item.input, status: item.status, l10n: l10n),
      object: item.target,
      running: running,
      expanded: expanded,
      onToggle: opens ? onToggle : null,
      icon: SvgPicture.asset(
        browserIcon,
        width: 14,
        height: 14,
        colorFilter: ColorFilter.mode(AppColors.textMuted, BlendMode.srcIn),
      ),
      trailingGap: 0,
      trailing: shot == null
          ? null
          : StepThumbnails(images: toolImages(item), shown: !expanded),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        if (running && item.tool == 'browser_watch')
          const _WatchCard()
        else if (expanded && opens)
          _body(context),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final output = item.output?.trimRight() ?? '';
    if (item.status != ToolStatus.failed) {
      if (item.images.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A request's headers before its picture.
            if (output.isNotEmpty)
              StepBody(child: Text(output, style: stepMono)),
            ToolImages(images: toolImages(item)),
          ],
        );
      }
      switch (item.tool) {
        case 'browser_console':
          return StepBody(child: _ConsoleLines(output));
        case 'browser_network':
          return StepBody(child: _NetworkTable(output));
        case 'browser_performance' when output.contains('Web Vitals'):
          return StepBody(
            maxHeight: 420,
            child: _PerformanceView(PerformanceReport.parse(output)),
          );
      }
    }
    return StepBody(child: Text(output, style: stepMono));
  }
}

/// What BaoCode watches the user do (see [BrowserWatching]): the task they
/// were given, their steps so far, and their buttons: done, or give up.
class _WatchCard extends StatelessWidget {
  const _WatchCard();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: BrowserWatching.current,
      builder: (context, watching, _) => watching == null
          ? const SizedBox.shrink()
          : ListenableBuilder(
              listenable: watching,
              builder: (context, _) => _card(context, watching),
            ),
    );
  }

  Widget _card(BuildContext context, BrowserWatching watching) {
    final l10n = context.l10n;
    // Where it began is not theirs.
    final steps = watching.steps.where((s) => s.kind != 'page').toList();
    final shown = steps.length > 5 ? steps.sublist(steps.length - 5) : steps;
    final muted = TextStyle(color: AppColors.textMuted, fontSize: 12);
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Recording, as the browser's badge says.
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.removed,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.browserWatchTitle,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (watching.task.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              watching.task,
              style: TextStyle(color: AppColors.text, fontSize: 13),
            ),
          ],
          const SizedBox(height: 6),
          Text(l10n.browserWatchHint, style: muted),
          if (shown.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final step in shown)
              Text(
                _watchedLine(step, l10n),
                style: stepMono,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(l10n.browserWatchSteps(steps.length), style: muted),
              ),
              IdeButton(
                label: l10n.browserWatchCancel,
                secondary: true,
                onPressed: watching.cancel,
              ),
              const SizedBox(width: 8),
              IdeButton(
                label: l10n.browserWatchDone,
                onPressed: watching.finish,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A step the user took, as the card lists it: "Clicked button “Go”".
  static String _watchedLine(WatchedStep step, AppLocalizations l10n) {
    final what = switch (step.kind) {
      'input' => '${step.target} = ${step.value ?? ''}',
      'key' => step.value ?? '',
      'navigate' => _address(step.value ?? ''),
      _ => step.target,
    };
    return '${l10n.browserWatchedStep(step.kind)} $what';
  }
}

/// The level's color: an error's, a warning's, else the step's.
Color? _levelColor(String level) => switch (level) {
  'error' => AppColors.removed,
  'warning' => AppColors.caution,
  _ => null,
};

/// browser_console's lines (`[time] level: text (where)`), each in its
/// level's color.
class _ConsoleLines extends StatelessWidget {
  const _ConsoleLines(this.output);

  final String output;

  static final _line = RegExp(r'^\[([\d:.]+)\] (\w+): ');

  @override
  Widget build(BuildContext context) {
    final faint = TextStyle(color: AppColors.textFaint);
    return Text.rich(
      TextSpan(
        children: [
          for (final (i, line) in output.split('\n').indexed) ...[
            if (i > 0) const TextSpan(text: '\n'),
            if (_line.firstMatch(line) case final match?) ...[
              TextSpan(text: '${match[1]} ', style: faint),
              TextSpan(
                text: line.substring(match.end),
                style: TextStyle(color: _levelColor(match[2]!)),
              ),
            ] else
              TextSpan(text: line),
          ],
        ],
      ),
      style: stepMono,
    );
  }
}

/// browser_network's lines (`id method status type size time url`) as a
/// table, those that failed in red.
class _NetworkTable extends StatelessWidget {
  const _NetworkTable(this.output);

  final String output;

  static final _row = RegExp(
    r'^(\S+) ([A-Z]+) (\S+) (\S+) (\(cache\)|\?|[\d.]+ [kM]?B) (\d+ ms|…) (.*)$',
  );

  @override
  Widget build(BuildContext context) {
    final rows = <List<String>>[];
    final rest = <String>[];
    for (final line in output.split('\n')) {
      if (_row.firstMatch(line) case final m?) {
        rows.add([m[2]!, m[3]!, m[4]!, m[5]!, m[6]!, m[7]!]);
      } else {
        rest.add(line);
      }
    }
    if (rows.isEmpty) return Text(output, style: stepMono);
    final faint = stepMono.copyWith(color: AppColors.textFaint);
    Widget cell(String text, {TextStyle? style, bool end = false}) => Padding(
      padding: const EdgeInsets.only(right: 12, bottom: 2),
      child: Text(
        text,
        style: style ?? stepMono,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: end ? TextAlign.end : TextAlign.start,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in rest) Text(line, style: faint),
        Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          columnWidths: const {5: FlexColumnWidth()},
          children: [
            for (final [method, status, type, size, time, url] in rows)
              TableRow(
                children: [
                  cell(method),
                  cell(
                    status,
                    style: switch (int.tryParse(status)) {
                      final code? when code < 400 => null,
                      _ => stepMono.copyWith(color: AppColors.removed),
                    },
                  ),
                  cell(type, style: faint),
                  cell(size, style: faint, end: true),
                  cell(time, style: faint, end: true),
                  cell(url),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// A Web Vital: its name, value and rating (`good`, `needs improvement`,
/// `poor`; none when not measured).
typedef WebVital = ({String name, String value, String? rating});

/// browser_performance's report, read back: its Web Vitals, the rest of
/// its lines, and the trace it saved.
class PerformanceReport {
  const PerformanceReport({
    required this.vitals,
    required this.lines,
    this.trace,
  });

  factory PerformanceReport.parse(String output) {
    final vitals = <WebVital>[];
    final lines = <String>[];
    String? trace;
    final vital = RegExp(
      r'^  (LCP|CLS|INP|FCP|TTFB): (.+?)(?: \((good|needs improvement|poor)\))?(?: — .*)?$',
    );
    final traced = RegExp(r'^Trace: (\S+)');
    for (final line in output.split('\n')) {
      if (vital.firstMatch(line) case final m?) {
        vitals.add((name: m[1]!, value: _seconds(m[2]!), rating: m[3]));
      } else if (traced.firstMatch(line) case final m?) {
        trace = m[1];
      } else if (!line.startsWith('Web Vitals')) {
        lines.add(line);
      }
    }
    // Blank lines at the ends, left by those taken out.
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    return PerformanceReport(vitals: vitals, lines: lines, trace: trace);
  }

  final List<WebVital> vitals;
  final List<String> lines;
  final String? trace;

  /// A time from a second up in seconds, as Web Vitals are read.
  static String _seconds(String value) {
    final ms = RegExp(r'^(\d+) ms$').firstMatch(value);
    if (ms == null) return value;
    final n = int.parse(ms[1]!);
    return n >= 1000 ? '${(n / 1000).toStringAsFixed(2)} s' : value;
  }
}

class _PerformanceView extends StatelessWidget {
  const _PerformanceView(this.report);

  final PerformanceReport report;

  static Color _rated(String? rating) => switch (rating) {
    'good' => AppColors.added,
    'needs improvement' => AppColors.caution,
    'poor' => AppColors.removed,
    _ => AppColors.textFaint,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final trace = report.trace;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final vital in report.vitals)
              Container(
                width: 104,
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: _rated(vital.rating),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          vital.name,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      vital.value,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(report.lines.join('\n'), style: stepMono),
        if (trace != null) ...[
          const SizedBox(height: 8),
          _TraceLink(
            label: l10n.browserTraceReveal(l10n.fileManager),
            onTap: () => WindowControls.revealInFileManager(trace),
          ),
        ],
      ],
    );
  }
}

/// The trace saved: shown in the file manager, to drop into DevTools.
class _TraceLink extends StatelessWidget {
  const _TraceLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: TextStyle(
            color: hovered ? AppColors.text : AppColors.accent,
            fontSize: 12,
            decoration: hovered ? TextDecoration.underline : null,
          ),
        ),
      ),
    );
  }
}
