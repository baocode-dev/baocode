/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/base/common/iconLabels.ts (`parseLabelWithIcons`,
// `matchesFuzzyIconAware`), src/vs/base/common/linkedText.ts
// (`parseLinkedText`), src/vs/base/browser/ui/iconLabel/iconLabels.ts
// (`labelWithIconsRegex`) and src/vs/platform/quickinput/browser/
// quickInputList.ts (`compareEntries`).
//
// Deviations: fuzzy matching is lib/ide/ide_quick_input.dart's
// `ideMatchesFuzzy` (upstream `matchesFuzzy` without separate substring
// matching, which `matchesFuzzyIconAware` does not ask for), and comparing
// is its `ideCompareAnything`.

import '../../../ide/ide_quick_input.dart'
    show IdeMatch, ideCompareAnything, ideMatchesFuzzy;

/// A label without its `$(icon)`s, and for each of its characters the
/// length of the icons before it in the label (`IParsedLabelWithIcons`).
typedef ParsedLabelWithIcons = ({String text, List<int> iconOffsets});

final _parseIcons = RegExp(r'\$\([A-Za-z0-9~-]+\)');

/// Upstream `parseLabelWithIcons`: `abc $(icon)xyz` is `abc xyz` with the
/// offsets `[0, 0, 0, 0, 7, 7, 7]`.
ParsedLabelWithIcons parseLabelWithIcons(String input) {
  final text = StringBuffer();
  final offsets = <int>[];
  var iconsOffset = 0;
  var pos = 0;
  for (final match in _parseIcons.allMatches(input)) {
    final chars = input.substring(pos, match.start);
    text.write(chars);
    for (var i = 0; i < chars.length; i++) {
      offsets.add(iconsOffset);
    }
    iconsOffset += match.end - match.start;
    pos = match.end;
  }
  final chars = input.substring(pos);
  text.write(chars);
  for (var i = 0; i < chars.length; i++) {
    offsets.add(iconsOffset);
  }
  return (text: text.toString(), iconOffsets: offsets);
}

/// Upstream `matchesFuzzyIconAware`: [query] matched fuzzily against the
/// label's text, the matches given as ranges of the label with its icons.
List<IdeMatch>? matchesFuzzyIconAware(
  String query,
  ParsedLabelWithIcons target,
) {
  final (:text, :iconOffsets) = target;
  if (iconOffsets.isEmpty) return ideMatchesFuzzy(query, text);
  // The text may start with white space where the label started with an
  // icon.
  final trimmed = text.replaceFirst(RegExp(r'^ +'), '');
  final leading = text.length - trimmed.length;
  final matches = ideMatchesFuzzy(query, trimmed);
  if (matches == null) return null;
  return [
    for (final match in matches)
      () {
        final offset = iconOffsets[match.start + leading] + leading;
        return (start: match.start + offset, end: match.end + offset);
      }(),
  ];
}

/// The character positions [matches] cover.
List<int> matchPositions(List<IdeMatch>? matches) => [
  for (final match in matches ?? const <IdeMatch>[])
    for (var i = match.start; i < match.end; i++) i,
];

/// Upstream `compareEntries`: rows whose label matched first, then by
/// `compareAnything` on their labels without icons (`saneSortLabel`).
/// [lookFor] is the query, lowercased.
int compareQuickPickEntries(
  ({String sortLabel, bool labelMatched}) a,
  ({String sortLabel, bool labelMatched}) b,
  String lookFor,
) {
  if (a.labelMatched && !b.labelMatched) return -1;
  if (!a.labelMatched && b.labelMatched) return 1;
  if (!a.labelMatched && !b.labelMatched) return 0;
  return ideCompareAnything(a.sortLabel, b.sortLabel, lookFor);
}

/// A part of a label: text, or a `$(name)` / `$(name~modifier)` codicon
/// (`renderLabelWithIcons`; `\$(name)` is the text `$(name)`). [offset] is
/// where it starts in the label.
typedef LabelPart = ({String? text, String? icon, int offset});

final _labelWithIcons = RegExp(r'(\\)?\$\(([A-Za-z0-9-]+(?:~[A-Za-z]+)?)\)');

/// Upstream `renderLabelWithIcons`, as parts.
List<LabelPart> splitLabelWithIcons(String text) {
  final parts = <LabelPart>[];
  var start = 0;
  for (final match in _labelWithIcons.allMatches(text)) {
    if (match.start > start) {
      parts.add((
        text: text.substring(start, match.start),
        icon: null,
        offset: start,
      ));
    }
    if (match[1] != null) {
      // Escaped: the text without its backslash.
      parts.add((text: r'$(' '${match[2]})', icon: null, offset: match.start));
    } else {
      parts.add((text: null, icon: match[2], offset: match.start));
    }
    start = match.end;
  }
  if (start < text.length) {
    parts.add((text: text.substring(start), icon: null, offset: start));
  }
  return parts;
}

/// A link of a validation message or a prompt (`ILink`).
typedef LinkedTextLink = ({String label, String href, String? title});

final _link = RegExp(
  r'''\[([^\]]+)\]\(((?:https?:\/\/|command:|file:)[^\)\s]+)(?: (["'])(.+?)(\3))?\)''',
  caseSensitive: false,
);

/// Upstream `parseLinkedText`: text and `[label](href "title")` links, the
/// links being `http(s):`, `command:` or `file:` ones. Each node is a
/// [String] or a [LinkedTextLink].
List<Object> parseLinkedText(String text) {
  final nodes = <Object>[];
  var index = 0;
  for (final match in _link.allMatches(text)) {
    if (match.start > index) nodes.add(text.substring(index, match.start));
    final title = match[4];
    nodes.add((
      label: match[1]!,
      href: match[2]!,
      title: title == null || title.isEmpty ? null : title,
    ));
    index = match.end;
  }
  if (index < text.length) nodes.add(text.substring(index));
  return nodes;
}
