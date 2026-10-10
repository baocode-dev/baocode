/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// ANSI escape sequences in the Debug Console's output: styles and colors
// (SGR, 8 and 24-bit colors included) applied, other sequences hidden.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/browser/debugANSIHandling.ts, with
// media/repl.css' `code-*` rules as text styles.
//
// Deviations: the parse ([handleAnsiOutput]) gives the runs, [ansiTextSpan]
// draws them; no link detection or filter highlights in a run; blinking is
// drawn still, sub- and superscript smaller but on the line.

import 'package:bao_editor/monaco/vs/base/common/color.dart' as vs;
import 'package:flutter/painting.dart';

import '../../ide/terminal/terminal_colors.dart' show TerminalColors, ansiColorIdentifiers;
import '../../theme/workbench_theme.dart' show themeColors;

/// A color of a run: a theme color's id (`terminal.ansiRed`, …, as upstream's
/// `--vscode-debug-ansi-*`) or one of its own.
typedef AnsiColor = Object; // String | vs.RGBA

/// Text with the styles in effect for it (upstream's `span` with its
/// classes and inline colors).
final class AnsiRun {
  const AnsiRun(this.text, this.classes, {this.foreground, this.background, this.underline});

  final String text;

  /// `code-bold`, `code-foreground-colored`, … as upstream.
  final List<String> classes;
  final AnsiColor? foreground;
  final AnsiColor? background;
  final AnsiColor? underline;
}

/// The runs of [text], its escape sequences applied (`handleANSIOutput`).
List<AnsiRun> handleAnsiOutput(String text) {
  final root = <AnsiRun>[];
  final textLength = text.length;

  var styleNames = <String>[];
  AnsiColor? customFgColor;
  AnsiColor? customBgColor;
  AnsiColor? customUnderlineColor;
  var colorsInverted = false;
  var currentPos = 0;
  var buffer = StringBuffer();

  void flush() {
    if (buffer.isEmpty) return;
    root.add(
      AnsiRun(
        buffer.toString(),
        [...styleNames],
        foreground: customFgColor,
        background: customBgColor,
        underline: customUnderlineColor,
      ),
    );
    buffer = StringBuffer();
  }

  // Changes the foreground, background or underline color: clears the
  // current one and adds [color] when there is one.
  void changeColor(String colorType, [AnsiColor? color]) {
    if (colorType == 'foreground') {
      customFgColor = color;
    } else if (colorType == 'background') {
      customBgColor = color;
    } else if (colorType == 'underline') {
      customUnderlineColor = color;
    }
    styleNames = styleNames.where((style) => style != 'code-$colorType-colored').toList();
    if (color != null) {
      styleNames.add('code-$colorType-colored');
    }
  }

  // Swaps foreground and background colors (inversion).
  void reverseForegroundAndBackgroundColors() {
    final oldFgColor = customFgColor;
    changeColor('foreground', customBgColor);
    changeColor('background', oldFgColor);
  }

  void toggle(String add, [List<String> remove = const []]) {
    styleNames = styleNames.where((style) => style != add && !remove.contains(style)).toList()..add(add);
  }

  void removeStyles(bool Function(String style) test) {
    styleNames = styleNames.where((style) => !test(style)).toList();
  }

  // The basic colors, bright and dark (30-37, 90-97, 40-47, 100-107), as
  // the theme's terminal colors.
  void setBasicColor(int styleCode) {
    String? colorType;
    int? colorIndex;
    if (styleCode >= 30 && styleCode <= 37) {
      colorIndex = styleCode - 30;
      colorType = 'foreground';
    } else if (styleCode >= 90 && styleCode <= 97) {
      colorIndex = (styleCode - 90) + 8; // High-intensity (bright)
      colorType = 'foreground';
    } else if (styleCode >= 40 && styleCode <= 47) {
      colorIndex = styleCode - 40;
      colorType = 'background';
    } else if (styleCode >= 100 && styleCode <= 107) {
      colorIndex = (styleCode - 100) + 8; // High-intensity (bright)
      colorType = 'background';
    }
    if (colorIndex != null && colorType != null) {
      changeColor(colorType, ansiColorIdentifiers[colorIndex]);
    }
  }

  // Bold, italic, underline, … on and off, color resets, basic colors.
  // New colors clear old ones; new formatting does not.
  void setBasicFormatters(List<int> styleCodes) {
    for (final code in styleCodes) {
      switch (code) {
        case 0: // reset (everything)
          styleNames = [];
          customFgColor = null;
          customBgColor = null;
        case 1: // bold
          toggle('code-bold');
        case 2: // dim
          toggle('code-dim');
        case 3: // italic
          toggle('code-italic');
        case 4: // underline
          toggle('code-underline', const ['code-double-underline']);
        case 5: // blink
          toggle('code-blink');
        case 6: // rapid blink
          toggle('code-rapid-blink');
        case 7: // invert foreground and background
          if (!colorsInverted) {
            colorsInverted = true;
            reverseForegroundAndBackgroundColors();
          }
        case 8: // hidden
          toggle('code-hidden');
        case 9: // strike-through/crossed-out
          toggle('code-strike-through');
        case 10: // normal default font
          removeStyles((style) => style.startsWith('code-font'));
        case >= 11 && <= 20: // font codes (and 20 is 'blackletter' font code)
          removeStyles((style) => style.startsWith('code-font'));
          styleNames.add('code-font-${code - 10}');
        case 21: // double underline
          toggle('code-double-underline', const ['code-underline']);
        case 22: // normal intensity (bold off and dim off)
          removeStyles((style) => style == 'code-bold' || style == 'code-dim');
        case 23: // Neither italic or blackletter (font 10)
          removeStyles((style) => style == 'code-italic' || style == 'code-font-10');
        case 24: // not underlined (Neither singly nor doubly underlined)
          removeStyles((style) => style == 'code-underline' || style == 'code-double-underline');
        case 25: // not blinking
          removeStyles((style) => style == 'code-blink' || style == 'code-rapid-blink');
        case 27: // not reversed/inverted
          if (colorsInverted) {
            colorsInverted = false;
            reverseForegroundAndBackgroundColors();
          }
        case 28: // not hidden (reveal)
          removeStyles((style) => style == 'code-hidden');
        case 29: // not crossed-out
          removeStyles((style) => style == 'code-strike-through');
        case 53: // overlined
          toggle('code-overline');
        case 55: // not overlined
          removeStyles((style) => style == 'code-overline');
        case 39: // default foreground color
          changeColor('foreground');
        case 49: // default background color
          changeColor('background');
        case 59: // default underline color
          changeColor('underline');
        case 73: // superscript
          toggle('code-superscript', const ['code-subscript']);
        case 74: // subscript
          toggle('code-subscript', const ['code-superscript']);
        case 75: // neither superscript or subscript
          removeStyles((style) => style == 'code-superscript' || style == 'code-subscript');
        default:
          setBasicColor(code);
      }
    }
  }

  // 24-bit colors: the two defining codes and the three RGB codes.
  void set24BitColor(List<int> styleCodes, String colorType) {
    if (styleCodes.length >= 5 &&
        styleCodes[2] >= 0 &&
        styleCodes[2] <= 255 &&
        styleCodes[3] >= 0 &&
        styleCodes[3] <= 255 &&
        styleCodes[4] >= 0 &&
        styleCodes[4] <= 255) {
      changeColor(colorType, vs.RGBA(styleCodes[2], styleCodes[3], styleCodes[4]));
    }
  }

  // 8-bit colors: the two defining codes and the color code.
  void set8BitColor(List<int> styleCodes, String colorType) {
    if (styleCodes.length < 3) return;
    var colorNumber = styleCodes[2];
    final color = calcAnsi8bitColor(colorNumber);
    if (color != null) {
      changeColor(colorType, color);
    } else if (colorNumber >= 0 && colorNumber <= 15) {
      if (colorType == 'underline') {
        // for underline colors we just decode the 0-15 color number to theme color, set and return
        changeColor(colorType, ansiColorIdentifiers[colorNumber]);
        return;
      }
      // Need to map to one of the four basic color ranges (30-37, 90-97, 40-47, 100-107)
      colorNumber += 30;
      if (colorNumber >= 38) {
        // Bright colors
        colorNumber += 52;
      }
      if (colorType == 'background') {
        colorNumber += 10;
      }
      setBasicColor(colorNumber);
    }
  }

  while (currentPos < textLength) {
    var sequenceFound = false;

    // Potentially an ANSI escape sequence.
    // See http://ascii-table.com/ansi-escape-sequences.php & https://en.wikipedia.org/wiki/ANSI_escape_code
    if (text.codeUnitAt(currentPos) == 27 && currentPos + 1 < textLength && text[currentPos + 1] == '[') {
      final startPos = currentPos;
      currentPos += 2; // Ignore 'Esc[' as it's in every sequence.

      final ansiSequence = StringBuffer();
      while (currentPos < textLength) {
        final char = text[currentPos];
        ansiSequence.write(char);
        currentPos++;
        // Look for a known sequence terminating character.
        if (_terminator.hasMatch(char)) {
          sequenceFound = true;
          break;
        }
      }

      if (sequenceFound) {
        // Flush buffer with previous styles.
        flush();

        // Certain ranges that are matched here do not contain real graphics
        // rendition sequences. For the sake of having a simpler expression,
        // they have been included anyway.
        final sequence = ansiSequence.toString();
        if (_graphicsRendition.hasMatch(sequence)) {
          final styleCodes = sequence
              .substring(0, sequence.length - 1) // Remove final 'm' character.
              .split(';') // Separate style codes.
              .where((elem) => elem.isNotEmpty) // Filter empty elems as '34;m' -> ['34', ''].
              .map(int.parse) // Convert to numbers.
              .toList();

          if (styleCodes.isNotEmpty && (styleCodes[0] == 38 || styleCodes[0] == 48 || styleCodes[0] == 58)) {
            // Advanced color code - can't be combined with formatting codes like simple colors can
            // Ignores invalid colors and additional info beyond what is necessary
            final colorType = styleCodes[0] == 38
                ? 'foreground'
                : styleCodes[0] == 48
                ? 'background'
                : 'underline';
            if (styleCodes.length > 1 && styleCodes[1] == 5) {
              set8BitColor(styleCodes, colorType);
            } else if (styleCodes.length > 1 && styleCodes[1] == 2) {
              set24BitColor(styleCodes, colorType);
            }
          } else {
            setBasicFormatters(styleCodes);
          }
        } else {
          // Unsupported sequence so simply hide it.
        }
      } else {
        currentPos = startPos;
      }
    }

    if (!sequenceFound) {
      buffer.write(text[currentPos]);
      currentPos++;
    }
  }

  // Flush remaining text buffer if not empty.
  flush();
  return root;
}

final _terminator = RegExp(r'^[ABCDHIJKfhmpsu]$');
final _graphicsRendition = RegExp(
  r'^(?:[34][0-8]|9[0-7]|10[0-7]|[0-9]|2[1-5,7-9]|[34]9|5[8,9]|1[0-9])(?:;[349][0-7]|10[0-7]|[013]|[245]|[34]9)?(?:;[012]?[0-9]?[0-9])*;?m$',
);

/// A color of the 8-bit set (16-255); null for the standard and bright
/// ones (the theme's) and invalid numbers (`calcANSI8bitColor`).
vs.RGBA? calcAnsi8bitColor(num colorNumber) {
  if (colorNumber % 1 != 0) {
    // Should be integer
    return null;
  }
  var n = colorNumber.toInt();
  if (n >= 16 && n <= 231) {
    // Converts to one of 216 RGB colors
    n -= 16;
    var blue = n % 6;
    n = (n - blue) ~/ 6;
    var green = n % 6;
    n = (n - green) ~/ 6;
    var red = n;

    // red, green, blue now range on [0, 5], need to map to [0,255]
    const convFactor = 255 / 5;
    blue = (blue * convFactor).round();
    green = (green * convFactor).round();
    red = (red * convFactor).round();
    return vs.RGBA(red, green, blue);
  } else if (n >= 232 && n <= 255) {
    // Converts to a grayscale value
    n -= 232;
    final colorLevel = (n / 23 * 255).round();
    return vs.RGBA(colorLevel, colorLevel, colorLevel);
  }
  return null;
}

/// [text] with its escape sequences drawn over [style], on [background]:
/// the theme's ANSI colors made to stand out from it as upstream's theming
/// participant does (a contrast ratio of 4).
TextSpan ansiTextSpan(String text, TextStyle style, {required Color background}) {
  final bg = _vsColor(background);
  Color? resolve(AnsiColor? color) => switch (color) {
    null => null,
    final vs.RGBA rgba => Color.fromARGB((rgba.a * 255).round(), rgba.r, rgba.g, rgba.b),
    final String id => _flutterColor(
      bg.ensureConstrast(_vsColor(themeColors.get(id) ?? TerminalColors.ansi[ansiColorIdentifiers.indexOf(id)]), 4),
    ),
    _ => null,
  };

  return TextSpan(
    children: [
      for (final run in handleAnsiOutput(text)) TextSpan(text: run.text, style: _runStyle(run, style, resolve)),
    ],
  );
}

TextStyle _runStyle(AnsiRun run, TextStyle base, Color? Function(AnsiColor?) resolve) {
  final has = run.classes.contains;
  var color = resolve(run.foreground) ?? base.color;
  if (color != null) {
    if (has('code-hidden')) {
      color = color.withValues(alpha: 0);
    } else if (has('code-dim')) {
      color = color.withValues(alpha: color.a * 0.4);
    }
  }
  final decorations = [
    if (has('code-underline') || has('code-double-underline')) TextDecoration.underline,
    if (has('code-strike-through')) TextDecoration.lineThrough,
    if (has('code-overline')) TextDecoration.overline,
  ];
  final smaller = has('code-superscript') || has('code-subscript');
  return base.copyWith(
    color: color,
    backgroundColor: resolve(run.background),
    fontWeight: has('code-bold') ? FontWeight.bold : null,
    fontStyle: has('code-italic') ? FontStyle.italic : null,
    decoration: decorations.isEmpty ? null : TextDecoration.combine(decorations),
    decorationStyle: has('code-double-underline') ? TextDecorationStyle.double : null,
    decorationColor: resolve(run.underline),
    fontSize: smaller && base.fontSize != null ? base.fontSize! * 0.83 : null,
  );
}

vs.Color _vsColor(Color c) => vs.Color(vs.RGBA((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round(), c.a));

Color _flutterColor(vs.Color c) => Color.fromARGB((c.rgba.a * 255).round(), c.rgba.r, c.rgba.g, c.rgba.b);
