// A markdown file's front matter, as its properties: a key and its value
// a row, a list's items as tags. A value on a line of its own is edited in
// its field, written back as YAML; the rest in the file's source.

import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../ide_input.dart';

/// One of front matter's keys: its text, or its list's items; [inline]
/// when its text is on its own line, quoted or not (to be edited there).
typedef FrontMatterProperty = ({
  String key,
  String? text,
  List<String> items,
  bool inline,
});

/// [yaml]'s keys at the top, in order, each with its value: a scalar's
/// text unquoted, a block's lines joined, a list's items (`- item`, or
/// `[a, b]`). Null where a line is not that (it shows as YAML instead).
List<FrontMatterProperty>? parseFrontMatterProperties(String yaml) {
  final properties = <FrontMatterProperty>[];
  String? key;
  String? text;
  var items = <String>[];
  final more = <String>[];
  var inline = false;

  void close() {
    final current = key;
    if (current == null) return;
    final rest = more.join(' ').trim();
    final joined = [?text, if (rest.isNotEmpty) rest].join(' ').trim();
    properties.add((
      key: current,
      text: items.isEmpty ? joined : null,
      items: items,
      inline: inline && items.isEmpty && more.isEmpty,
    ));
    key = null;
    text = null;
    items = [];
    more.clear();
    inline = false;
  }

  final top = RegExp(r'^([^\s#:][^:]*):(?:\s+(.*))?$');
  for (final line in yaml.split(RegExp('\r\n|\r|\n'))) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    if (!line.startsWith(RegExp(r'\s')) && !line.startsWith('-')) {
      final match = top.firstMatch(line);
      if (match == null) return null;
      close();
      key = match[1]!.trim();
      final value = match[2]?.trim() ?? '';
      if (value.startsWith('[') && value.endsWith(']')) {
        items = [
          for (final item in value.substring(1, value.length - 1).split(','))
            if (_unquoted(item.trim()) case final item when item.isNotEmpty)
              item,
        ];
      } else if (!value.startsWith('|') && !value.startsWith('>')) {
        if (value.isNotEmpty) text = _unquoted(value);
        inline = true;
      }
      continue;
    }
    if (key == null) return null;
    final trimmed = line.trim();
    if (trimmed.startsWith('- ') || trimmed == '-') {
      items.add(_unquoted(trimmed.substring(1).trim()));
    } else {
      more.add(trimmed);
    }
  }
  close();
  return properties.isEmpty ? null : properties;
}

/// [source], front matter with its fences (`---`), with [key]'s value
/// (on its own line) [value]: quoted as it was, else only where YAML needs
/// it. As it was when [key] is not there.
String setFrontMatterValue(String source, String key, String value) {
  final lines = source.split('\n');
  final pattern = RegExp('^${RegExp.escape(key)}:(?:\\s+(.*))?\$');
  for (final (i, line) in lines.indexed) {
    final match = pattern.firstMatch(line.trimRight());
    if (match == null) continue;
    final old = match[1]?.trim() ?? '';
    lines[i] = '$key: ${_quoted(value, like: old)}';
    return lines.join('\n');
  }
  return source;
}

/// [value] as YAML writes it: quoted as [like] was, else bare where it can
/// be read back as the same text.
String _quoted(String value, {required String like}) {
  String double() =>
      '"${value.replaceAll('\\', r'\\').replaceAll('"', r'\"')}"';
  if (like.startsWith('"')) return double();
  if (like.startsWith("'")) return "'${value.replaceAll("'", "''")}'";
  final bare =
      value.isNotEmpty &&
      value.trim() == value &&
      !RegExp(r'''^[-?:,\[\]{}#&*!|>'"%@`]''').hasMatch(value) &&
      !value.contains(': ') &&
      !value.contains(' #') &&
      !value.endsWith(':') &&
      !RegExp(
        r'^(true|false|yes|no|on|off|null|~|[-+]?[\d.]+)$',
        caseSensitive: false,
      ).hasMatch(value);
  return bare ? value : double();
}

/// [value] as YAML reads it quoted: `"…"` with its escapes, `'…'` with
/// `''` for a quote.
String _unquoted(String value) {
  if (value.length < 2) return value;
  final inner = value.substring(1, value.length - 1);
  if (value.startsWith('"') && value.endsWith('"')) {
    return inner.replaceAllMapped(
      RegExp(r'\\(.)'),
      (match) => switch (match[1]!) {
        'n' => '\n',
        't' => '\t',
        final other => other,
      },
    );
  }
  if (value.startsWith("'") && value.endsWith("'")) {
    return inner.replaceAll("''", "'");
  }
  return value;
}

/// Front matter's [properties] ([parseFrontMatterProperties]), a rule
/// under them: each value on its own line in a field, [onChanged] told it
/// when its field is left (or Enter pressed); shown, not edited, without.
class MarkdownFrontMatter extends StatelessWidget {
  const MarkdownFrontMatter({
    super.key,
    required this.properties,
    this.onChanged,
  });

  final List<FrontMatterProperty> properties;
  final void Function(String key, String value)? onChanged;

  @override
  Widget build(BuildContext context) {
    final separator = themeColors['textSeparator.foreground'];
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: separator.withValues(alpha: separator.a * 0.33),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final property in properties)
            _Row(
              key: ValueKey(property.key),
              property: property,
              onChanged: property.inline ? onChanged : null,
            ),
        ],
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({super.key, required this.property, this.onChanged});

  final FrontMatterProperty property;
  final void Function(String key, String value)? onChanged;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  late final TextEditingController _text = TextEditingController(
    text: widget.property.text ?? '',
  );
  final FocusNode _focus = FocusNode(debugLabel: 'front matter value');

  FrontMatterProperty get _property => widget.property;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_Row oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Changed in its source meanwhile.
    final text = _property.text ?? '';
    if (!_focus.hasFocus && text != _text.text) _text.text = text;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final value = _text.text.trim();
    if (value != (_property.text ?? '')) {
      widget.onChanged?.call(_property.key, value);
    }
  }

  /// A line break typed: the value is one line, so it is done.
  void _changed(String text) {
    if (!text.contains('\n')) return;
    _text.text = text.replaceAll(RegExp(r'\s*\n\s*'), ' ');
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final property = _property;
    final value = TextStyle(
      color: AppColors.textPrimary,
      fontSize: 13,
      height: 1.5,
    );
    final editable = widget.onChanged != null;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: editable ? 4 : 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Padding(
              // On its field's first line.
              padding: EdgeInsets.only(top: editable ? 4 : 1, right: 12),
              child: Text(
                property.key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ),
          ),
          Expanded(
            child: property.items.isNotEmpty
                ? Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [for (final item in property.items) _Tag(item)],
                  )
                : editable
                ? IdeInputBox(
                    controller: _text,
                    focusNode: _focus,
                    // Long ones wrap (a skill's description), one line all
                    // the same.
                    maxLines: 8,
                    lineHeight: 20,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    onChanged: _changed,
                    onSubmitted: (_) => _focus.unfocus(),
                  )
                : Text(
                    property.text?.isEmpty ?? true ? '—' : property.text!,
                    style: property.text?.isEmpty ?? true
                        ? value.copyWith(color: AppColors.textFaint)
                        : value,
                  ),
          ),
        ],
      ),
    );
  }
}

/// A list's item.
class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(
      color: AppColors.inlineCodeBackground,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: AppFonts.uiCodeStyle(12)
          .copyWith(color: AppColors.textMuted, height: 1.6),
    ),
  );
}
