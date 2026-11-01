import 'dart:async';
import 'dart:convert';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/widgets/hover_builder.dart';
import '../../ide/ide_code_editor.dart';
import '../../l10n/l10n.dart';
import '../../theme/code_font.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../usage_ledger.dart';
import '../usage_record.dart';
import '../usage_trace.dart';
import 'usage_filters.dart';
import 'usage_style.dart';

/// A request's way, as it was kept while debugging: as Claude Code sent
/// it, as it went to the upstream, as the upstream answered and as Claude
/// Code was answered; each its line, its headers (their secrets cut down)
/// and its body.
class UsageTraceView extends StatefulWidget {
  const UsageTraceView({super.key, required this.call, this.ledger});

  final UsageCall call;

  /// The app's by default.
  final UsageLedger? ledger;

  @override
  State<UsageTraceView> createState() => _UsageTraceViewState();
}

enum _Leg { request, sent, received, answer }

class _UsageTraceViewState extends State<UsageTraceView> {
  late Future<UsageTrace?> _trace = _read();
  _Leg _leg = _Leg.request;
  int? _try;

  Future<UsageTrace?> _read() =>
      (widget.ledger ?? UsageLedger.current).traceOf(widget.call);

  @override
  void didUpdateWidget(UsageTraceView old) {
    super.didUpdateWidget(old);
    if (old.call.traceId != widget.call.traceId) {
      _trace = _read();
      _try = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<UsageTrace?>(
      future: _trace,
      builder: (context, snapshot) {
        final trace = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l10n.ustatTraceLoading, style: UsageText.faint),
          );
        }
        if (trace == null) {
          return Text(l10n.ustatTraceGone, style: UsageText.faint);
        }
        final tries = switch (_leg) {
          _Leg.sent => trace.sent.length,
          _Leg.received => trace.received.length,
          _ => 1,
        };
        final at = (_try ?? tries - 1).clamp(0, tries - 1);
        final message = switch (_leg) {
          _Leg.request => trace.request,
          _Leg.sent => trace.sent.elementAtOrNull(at),
          _Leg.received => trace.received.elementAtOrNull(at),
          _Leg.answer => trace.answer,
        };
        // Passed on as it came: the upstream's own answer.
        final same =
            _leg == _Leg.answer &&
            trace.passedOn &&
            (message?.body.isEmpty ?? true);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                UsageSegmented<_Leg>(
                  dense: true,
                  value: _leg,
                  onChanged: (leg) => setState(() {
                    _leg = leg;
                    _try = null;
                  }),
                  segments: [
                    (value: _Leg.request, label: l10n.ustatTraceRequest),
                    (value: _Leg.sent, label: l10n.ustatTraceSent),
                    (value: _Leg.received, label: l10n.ustatTraceReceived),
                    (value: _Leg.answer, label: l10n.ustatTraceAnswer),
                  ],
                ),
                if (tries > 1)
                  UsageSegmented<int>(
                    dense: true,
                    value: at,
                    onChanged: (i) => setState(() => _try = i),
                    segments: [
                      for (var i = 0; i < tries; i++)
                        (value: i, label: l10n.ustatTraceTry(i + 1)),
                    ],
                  ),
                _TextButton(
                  icon: Codicons.copy,
                  label: l10n.ustatTraceCopyAll,
                  onTap: () => unawaited(
                    Clipboard.setData(
                      ClipboardData(
                        text: const JsonEncoder.withIndent('  ')
                            .convert(trace.toJson()),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (message == null)
              Text(l10n.ustatTraceNone, style: UsageText.faint)
            else
              _MessageView(
                key: ValueKey('${_leg.name}/$at'),
                message: message,
                body: same
                    ? (trace.received.lastOrNull?.body ?? '')
                    : message.body,
                note: same ? l10n.ustatTracePassedOn : null,
              ),
          ],
        );
      },
    );
  }
}

/// A leg's line, headers and body.
class _MessageView extends StatefulWidget {
  const _MessageView({
    super.key,
    required this.message,
    required this.body,
    this.note,
  });

  final UsageTraceMessage message;
  final String body;
  final String? note;

  @override
  State<_MessageView> createState() => _MessageViewState();
}

class _MessageViewState extends State<_MessageView> {
  bool _headers = false;
  bool _raw = false;

  late final Future<String?> _pretty = _prettify(widget.body);

  static Future<String?> _prettify(String body) async {
    final text = body.trimLeft();
    if (text.isEmpty || text.length > 8 * 1024 * 1024) return null;
    if (!text.startsWith('{') && !text.startsWith('[')) return null;
    return compute(_indent, text);
  }

  static String? _indent(String text) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  TextStyle get _mono => TextStyle(
    fontFamily: AppFonts.mono,
    fontFamilyFallback: AppFonts.monoFallbacks,
    fontSize: 11,
    height: 1.45,
    color: AppColors.text,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final message = widget.message;
    final line = [
      ?message.method,
      ?message.url,
      if (message.status case final status?) 'HTTP $status',
    ].join(' ');
    final facts = [
      UsageFormat.bytes(utf8.encode(widget.body).length),
      if (message.at case final at?) '+${UsageFormat.duration(at)}',
      if (message.truncated) l10n.ustatTraceTruncated,
      ?widget.note,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                line.isEmpty ? '—' : line,
                style: _mono.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(facts.join('  ·  '), style: UsageText.faint),
          ],
        ),
        if (message.headers.isNotEmpty) ...[
          const SizedBox(height: 4),
          _TextButton(
            icon: _headers ? Codicons.chevronDown : Codicons.chevronRight,
            label: l10n.ustatTraceHeaders(message.headers.length),
            onTap: () => setState(() => _headers = !_headers),
          ),
          if (_headers)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 0, 4),
              child: SelectableText.rich(
                TextSpan(
                  children: [
                    for (final MapEntry(:key, :value)
                        in message.headers.entries) ...[
                      TextSpan(
                        text: '$key: ',
                        style: _mono.copyWith(color: AppColors.textMuted),
                      ),
                      TextSpan(text: '$value\n', style: _mono),
                    ],
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 6),
        FutureBuilder<String?>(
          future: _pretty,
          builder: (context, snapshot) {
            final pretty = snapshot.data;
            final formatted = !_raw && pretty != null;
            final text = formatted ? pretty : widget.body;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(l10n.ustatTraceBody, style: UsageText.label),
                    const Spacer(),
                    if (pretty != null)
                      _TextButton(
                        icon: Codicons.json,
                        label: _raw
                            ? l10n.ustatTraceFormatted
                            : l10n.ustatTraceRaw,
                        onTap: () => setState(() => _raw = !_raw),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (text.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.code,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: UsagePalette.grid),
                    ),
                    child: Text(l10n.ustatTraceEmpty, style: UsageText.faint),
                  )
                else
                  _BodyEditor(
                    key: ValueKey(formatted),
                    text: text,
                    // Highlighted as what it is: JSON, else an event
                    // stream's lines as they came.
                    path: formatted || _isJson(widget.body)
                        ? 'body.json'
                        : 'body.txt',
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  static bool _isJson(String body) {
    final text = body.trimLeft();
    return text.startsWith('{') || text.startsWith('[');
  }
}

/// A body in the editor, read-only: highlighted, folded, searched and
/// selected as a file is; as tall as it is, up to [maxHeight], scrolled
/// past that.
class _BodyEditor extends StatefulWidget {
  const _BodyEditor({super.key, required this.text, required this.path});

  final String text;
  final String path;

  static const maxHeight = 420.0;

  @override
  State<_BodyEditor> createState() => _BodyEditorState();
}

class _BodyEditorState extends State<_BodyEditor> {
  // The document is handed in, so it is disposed here, not by the
  // controller.
  // An event stream's last blank line left out.
  late final _text = widget.text.trimRight();
  late final _document = EditorDocumentModel(_text);
  // Its caret at the top, where it is read from, not at the end.
  late final _controller = EditorSurfaceController(document: _document)
    ..select(0, 0);
  late final _lines = '\n'.allMatches(_text).length + 1;

  @override
  void dispose() {
    _controller.dispose();
    _document.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: (_lines * CodeFont.sized(12) * 1.5 + 16).clamp(
      56.0,
      _BodyEditor.maxHeight,
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: UsagePalette.grid),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: IdeCodeEditor(
          controller: _controller,
          path: widget.path,
          readOnly: true,
          interfaceSized: true,
          // Line numbers, folds, find and wrap (Alt+Z) as in a file; no
          // breakpoints.
          glyphMargin: false,
        ),
      ),
    ),
  );
}

/// A small action in text: an icon, a word.
class _TextButton extends StatelessWidget {
  const _TextButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    cursor: SystemMouseCursors.click,
    builder: (context, hovered) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: hovered ? AppColors.text : AppColors.textFaint,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: UsageText.faint.copyWith(
              color: hovered ? AppColors.text : null,
            ),
          ),
        ],
      ),
    ),
  );
}
