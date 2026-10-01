/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// GENERATED FILE - DO NOT EDIT. Written by tool/generate_color_registry.mjs from VS Code
// 6a598d4a13031703d483d103c1d934a36ad27971: the color registry
// (src/vs/platform/theme/common/colorUtils.ts `getColorRegistry().getColors()`) after the
// desktop workbench's registrations (65 files, 939 ids) and the built-in
// extensions' `contributes.colors` (11 ids), in registration order. A default that is a single
// ColorValue upstream is written for all four color schemes. Hex strings and `Color`s are
// written as `Color.Format.CSS.formatHexA(color, true)`, or as their RGBA where that hex
// would not keep the alpha.

import 'color_utils.dart';

/// The registered colors, in registration order.
const List<ColorContribution> colorRegistryData = [
  // src/vs/platform/theme/common/colors/baseColors.ts
  ColorContribution(
    'foreground',
    ColorDefaults(
      dark: ColorLiteral('#cccccc'),
      light: ColorLiteral('#616161'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'strongForeground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#000000'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#000000'),
    ),
  ),
  ColorContribution(
    'disabledForeground',
    ColorDefaults(
      dark: ColorLiteral('#cccccc80'),
      light: ColorLiteral('#61616180'),
      hcDark: ColorLiteral('#a5a5a5'),
      hcLight: ColorLiteral('#7f7f7f'),
    ),
  ),
  ColorContribution(
    'errorForeground',
    ColorDefaults(
      dark: ColorLiteral('#f48771'),
      light: ColorLiteral('#a1260d'),
      hcDark: ColorLiteral('#f48771'),
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution(
    'descriptionForeground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('foreground'), 0.7),
      light: ColorLiteral('#717171'),
      hcDark: TransparentTransform(ColorReference('foreground'), 0.7),
      hcLight: TransparentTransform(ColorReference('foreground'), 0.7),
    ),
  ),
  ColorContribution(
    'icon.foreground',
    ColorDefaults(
      dark: ColorLiteral('#c5c5c5'),
      light: ColorLiteral('#424242'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'focusBorder',
    ColorDefaults(
      dark: ColorLiteral('#007fd4'),
      light: ColorLiteral('#0090f1'),
      hcDark: ColorLiteral('#f38518'),
      hcLight: ColorLiteral('#006bbd'),
    ),
  ),
  ColorContribution(
    'contrastBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorLiteral('#6fc3df'),
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  ColorContribution(
    'contrastActiveBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('focusBorder'),
      hcLight: ColorReference('focusBorder'),
    ),
  ),
  ColorContribution('selection.background', null),
  ColorContribution(
    'textLink.foreground',
    ColorDefaults(
      dark: ColorLiteral('#3794ff'),
      light: ColorLiteral('#006ab1'),
      hcDark: ColorLiteral('#21a6ff'),
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  ColorContribution(
    'textLink.activeForeground',
    ColorDefaults(
      dark: ColorLiteral('#3794ff'),
      light: ColorLiteral('#006ab1'),
      hcDark: ColorLiteral('#21a6ff'),
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  ColorContribution(
    'textSeparator.foreground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff2e'),
      light: ColorLiteral('#0000002e'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'textPreformat.foreground',
    ColorDefaults(
      dark: ColorLiteral('#d7ba7d'),
      light: ColorLiteral('#a31515'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'textPreformat.background',
    ColorDefaults(
      dark: ColorLiteral('#ffffff1a'),
      light: ColorLiteral('#0000001a'),
      hcDark: null,
      hcLight: ColorLiteral('#09345f'),
    ),
  ),
  ColorContribution(
    'textPreformat.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastBorder'),
      hcLight: null,
    ),
  ),
  ColorContribution(
    'textBlockQuote.background',
    ColorDefaults(
      dark: ColorLiteral('#222222'),
      light: ColorLiteral('#f2f2f2'),
      hcDark: null,
      hcLight: ColorLiteral('#f2f2f2'),
    ),
  ),
  ColorContribution(
    'textBlockQuote.border',
    ColorDefaults(
      dark: ColorLiteral('#007acc80'),
      light: ColorLiteral('#007acc80'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'textCodeBlock.background',
    ColorDefaults(
      dark: ColorLiteral('#0a0a0a66'),
      light: ColorLiteral('#dcdcdc66'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#f2f2f2'),
    ),
  ),
  // src/vs/platform/theme/common/colors/miscColors.ts
  ColorContribution(
    'sash.hoverBorder',
    ColorDefaults(
      dark: ColorReference('focusBorder'),
      light: ColorReference('focusBorder'),
      hcDark: ColorReference('focusBorder'),
      hcLight: ColorReference('focusBorder'),
    ),
  ),
  ColorContribution(
    'badge.background',
    ColorDefaults(
      dark: ColorLiteral('#4d4d4d'),
      light: ColorLiteral('#c4c4c4'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  ColorContribution(
    'badge.foreground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#333333'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'activityWarningBadge.foreground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#ffffff'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'activityWarningBadge.background',
    ColorDefaults(
      dark: ColorLiteral('#b27c00'),
      light: ColorLiteral('#b27c00'),
      hcDark: null,
      hcLight: ColorLiteral('#b27c00'),
    ),
  ),
  ColorContribution(
    'activityErrorBadge.foreground',
    ColorDefaults(
      dark: ColorLiteral('#000000'),
      light: ColorLiteral('#ffffff'),
      hcDark: null,
      hcLight: ColorLiteral('#000000'),
    ),
  ),
  ColorContribution(
    'activityErrorBadge.background',
    ColorDefaults(
      dark: ColorLiteral('#f14c4c'),
      light: ColorLiteral('#e51400'),
      hcDark: null,
      hcLight: ColorLiteral('#f14c4c'),
    ),
  ),
  ColorContribution(
    'scrollbar.shadow',
    ColorDefaults(
      dark: ColorLiteral('#000000'),
      light: ColorLiteral('#dddddd'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'scrollbarSlider.background',
    ColorDefaults(
      dark: ColorLiteral('#79797966'),
      light: ColorLiteral('#64646466'),
      hcDark: TransparentTransform(ColorReference('contrastBorder'), 0.6),
      hcLight: TransparentTransform(ColorReference('contrastBorder'), 0.4),
    ),
  ),
  ColorContribution(
    'scrollbarSlider.hoverBackground',
    ColorDefaults(
      dark: ColorLiteral.rgba(100, 100, 100, 0.7),
      light: ColorLiteral.rgba(100, 100, 100, 0.7),
      hcDark: TransparentTransform(ColorReference('contrastBorder'), 0.8),
      hcLight: TransparentTransform(ColorReference('contrastBorder'), 0.8),
    ),
  ),
  ColorContribution(
    'scrollbarSlider.activeBackground',
    ColorDefaults(
      dark: ColorLiteral('#bfbfbf66'),
      light: ColorLiteral('#00000099'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution('scrollbar.background', null),
  ColorContribution(
    'progressBar.background',
    ColorDefaults(
      dark: ColorLiteral('#0e70c0'),
      light: ColorLiteral('#0e70c0'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'chart.line',
    ColorDefaults(
      dark: ColorLiteral('#236b8e'),
      light: ColorLiteral('#236b8e'),
      hcDark: ColorLiteral('#236b8e'),
      hcLight: ColorLiteral('#236b8e'),
    ),
  ),
  ColorContribution(
    'chart.axis',
    ColorDefaults(
      dark: ColorLiteral('#bfbfbf66'),
      light: ColorLiteral('#00000099'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'chart.guide',
    ColorDefaults(
      dark: ColorLiteral('#bfbfbf33'),
      light: ColorLiteral('#00000033'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  // src/vs/platform/theme/common/colors/editorColors.ts
  ColorContribution(
    'editor.background',
    ColorDefaults(
      dark: ColorLiteral('#1e1e1e'),
      light: ColorLiteral('#ffffff'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'editor.foreground',
    ColorDefaults(
      dark: ColorLiteral('#bbbbbb'),
      light: ColorLiteral('#333333'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'editorStickyScroll.background',
    ColorDefaults(
      dark: ColorReference('editor.background'),
      light: ColorReference('editor.background'),
      hcDark: ColorReference('editor.background'),
      hcLight: ColorReference('editor.background'),
    ),
  ),
  ColorContribution(
    'editorStickyScrollGutter.background',
    ColorDefaults(
      dark: ColorReference('editor.background'),
      light: ColorReference('editor.background'),
      hcDark: ColorReference('editor.background'),
      hcLight: ColorReference('editor.background'),
    ),
  ),
  ColorContribution(
    'editorStickyScrollHover.background',
    ColorDefaults(
      dark: ColorLiteral('#2a2d2e'),
      light: ColorLiteral('#f0f0f0'),
      hcDark: null,
      hcLight: ColorLiteral.rgba(15, 74, 133, 0.1),
    ),
  ),
  ColorContribution(
    'editorStickyScroll.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'editorStickyScroll.shadow',
    ColorDefaults(
      dark: ColorReference('scrollbar.shadow'),
      light: ColorReference('scrollbar.shadow'),
      hcDark: ColorReference('scrollbar.shadow'),
      hcLight: ColorReference('scrollbar.shadow'),
    ),
  ),
  ColorContribution(
    'editorWidget.background',
    ColorDefaults(
      dark: ColorLiteral('#252526'),
      light: ColorLiteral('#f3f3f3'),
      hcDark: ColorLiteral('#0c141f'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'editorWidget.foreground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'editorWidget.border',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editorWidget.foreground'),
        0.2,
      ),
      light: TransparentTransform(
        ColorReference('editorWidget.foreground'),
        0.2,
      ),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution('editorWidget.resizeBorder', null),
  ColorContribution('editorError.background', null),
  ColorContribution(
    'editorError.foreground',
    ColorDefaults(
      dark: ColorLiteral('#f14c4c'),
      light: ColorLiteral('#e51400'),
      hcDark: ColorLiteral('#f48771'),
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution(
    'editorError.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorLiteral('#e47777cc'),
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution('editorWarning.background', null),
  ColorContribution(
    'editorWarning.foreground',
    ColorDefaults(
      dark: ColorLiteral('#cca700'),
      light: ColorLiteral('#bf8803'),
      hcDark: ColorLiteral('#ffd370'),
      hcLight: ColorLiteral('#895503'),
    ),
  ),
  ColorContribution(
    'editorWarning.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorLiteral('#ffcc00cc'),
      hcLight: ColorLiteral('#ffcc00cc'),
    ),
  ),
  ColorContribution('editorInfo.background', null),
  ColorContribution(
    'editorInfo.foreground',
    ColorDefaults(
      dark: ColorLiteral('#59a4f9'),
      light: ColorLiteral('#0063d3'),
      hcDark: ColorLiteral('#59a4f9'),
      hcLight: ColorLiteral('#0063d3'),
    ),
  ),
  ColorContribution(
    'editorInfo.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorLiteral('#59a4f9cc'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'editorHint.foreground',
    ColorDefaults(
      dark: ColorLiteral.rgba(238, 238, 238, 0.7),
      light: ColorLiteral('#6c6c6c'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'editorHint.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorLiteral('#eeeeeecc'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'editorLink.activeForeground',
    ColorDefaults(
      dark: ColorLiteral('#4e94ce'),
      light: ColorLiteral('#0000ff'),
      hcDark: ColorLiteral('#00ffff'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'editor.selectionBackground',
    ColorDefaults(
      dark: ColorLiteral('#264f78'),
      light: ColorLiteral('#add6ff'),
      hcDark: ColorLiteral('#f3f518'),
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  ColorContribution(
    'editor.selectionForeground',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'editor.inactiveSelectionBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editor.selectionBackground'),
        0.5,
      ),
      light: TransparentTransform(
        ColorReference('editor.selectionBackground'),
        0.5,
      ),
      hcDark: TransparentTransform(
        ColorReference('editor.selectionBackground'),
        0.7,
      ),
      hcLight: TransparentTransform(
        ColorReference('editor.selectionBackground'),
        0.5,
      ),
    ),
  ),
  ColorContribution(
    'editor.selectionHighlightBackground',
    ColorDefaults(
      dark: LessProminentTransform(
        ColorReference('editor.selectionBackground'),
        ColorReference('editor.background'),
        0.3,
        0.6,
      ),
      light: LessProminentTransform(
        ColorReference('editor.selectionBackground'),
        ColorReference('editor.background'),
        0.3,
        0.6,
      ),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'editor.selectionHighlightBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'editor.compositionBorder',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#000000'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#000000'),
    ),
  ),
  ColorContribution(
    'editor.findMatchBackground',
    ColorDefaults(
      dark: ColorLiteral('#515c6a'),
      light: ColorLiteral('#a8ac94'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution('editor.findMatchForeground', null),
  ColorContribution(
    'editor.findMatchHighlightBackground',
    ColorDefaults(
      dark: ColorLiteral('#ea5c0055'),
      light: ColorLiteral('#ea5c0055'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution('editor.findMatchHighlightForeground', null),
  ColorContribution(
    'editor.findRangeHighlightBackground',
    ColorDefaults(
      dark: ColorLiteral('#3a3d4166'),
      light: ColorLiteral('#b4b4b44d'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'editor.findMatchBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'editor.findMatchHighlightBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'editor.findRangeHighlightBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: TransparentTransform(ColorReference('contrastActiveBorder'), 0.4),
      hcLight: TransparentTransform(
        ColorReference('contrastActiveBorder'),
        0.4,
      ),
    ),
  ),
  ColorContribution(
    'editor.hoverHighlightBackground',
    ColorDefaults(
      dark: ColorLiteral('#264f7840'),
      light: ColorLiteral('#add6ff26'),
      hcDark: ColorLiteral('#add6ff26'),
      hcLight: null,
    ),
  ),
  ColorContribution(
    'editorHoverWidget.background',
    ColorDefaults(
      dark: ColorReference('editorWidget.background'),
      light: ColorReference('editorWidget.background'),
      hcDark: ColorReference('editorWidget.background'),
      hcLight: ColorReference('editorWidget.background'),
    ),
  ),
  ColorContribution(
    'editorHoverWidget.foreground',
    ColorDefaults(
      dark: ColorReference('editorWidget.foreground'),
      light: ColorReference('editorWidget.foreground'),
      hcDark: ColorReference('editorWidget.foreground'),
      hcLight: ColorReference('editorWidget.foreground'),
    ),
  ),
  ColorContribution(
    'editorHoverWidget.border',
    ColorDefaults(
      dark: ColorReference('editorWidget.border'),
      light: ColorReference('editorWidget.border'),
      hcDark: ColorReference('editorWidget.border'),
      hcLight: ColorReference('editorWidget.border'),
    ),
  ),
  ColorContribution(
    'editorHoverWidget.statusBarBackground',
    ColorDefaults(
      dark: LightenTransform(
        ColorReference('editorHoverWidget.background'),
        0.2,
      ),
      light: DarkenTransform(
        ColorReference('editorHoverWidget.background'),
        0.05,
      ),
      hcDark: ColorReference('editorWidget.background'),
      hcLight: ColorReference('editorWidget.background'),
    ),
  ),
  ColorContribution(
    'editorInlayHint.foreground',
    ColorDefaults(
      dark: ColorLiteral('#969696'),
      light: ColorLiteral('#969696'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#000000'),
    ),
  ),
  ColorContribution(
    'editorInlayHint.background',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('badge.background'), 0.1),
      light: TransparentTransform(ColorReference('badge.background'), 0.1),
      hcDark: TransparentTransform(ColorLiteral('#ffffff'), 0.1),
      hcLight: TransparentTransform(ColorReference('badge.background'), 0.1),
    ),
  ),
  ColorContribution(
    'editorInlayHint.typeForeground',
    ColorDefaults(
      dark: ColorReference('editorInlayHint.foreground'),
      light: ColorReference('editorInlayHint.foreground'),
      hcDark: ColorReference('editorInlayHint.foreground'),
      hcLight: ColorReference('editorInlayHint.foreground'),
    ),
  ),
  ColorContribution(
    'editorInlayHint.typeBackground',
    ColorDefaults(
      dark: ColorReference('editorInlayHint.background'),
      light: ColorReference('editorInlayHint.background'),
      hcDark: ColorReference('editorInlayHint.background'),
      hcLight: ColorReference('editorInlayHint.background'),
    ),
  ),
  ColorContribution(
    'editorInlayHint.parameterForeground',
    ColorDefaults(
      dark: ColorReference('editorInlayHint.foreground'),
      light: ColorReference('editorInlayHint.foreground'),
      hcDark: ColorReference('editorInlayHint.foreground'),
      hcLight: ColorReference('editorInlayHint.foreground'),
    ),
  ),
  ColorContribution(
    'editorInlayHint.parameterBackground',
    ColorDefaults(
      dark: ColorReference('editorInlayHint.background'),
      light: ColorReference('editorInlayHint.background'),
      hcDark: ColorReference('editorInlayHint.background'),
      hcLight: ColorReference('editorInlayHint.background'),
    ),
  ),
  ColorContribution(
    'editorLightBulb.foreground',
    ColorDefaults(
      dark: ColorLiteral('#ffcc00'),
      light: ColorLiteral('#ddb100'),
      hcDark: ColorLiteral('#ffcc00'),
      hcLight: ColorLiteral('#007acc'),
    ),
  ),
  ColorContribution(
    'editorLightBulbAutoFix.foreground',
    ColorDefaults(
      dark: ColorLiteral('#75beff'),
      light: ColorLiteral('#007acc'),
      hcDark: ColorLiteral('#75beff'),
      hcLight: ColorLiteral('#007acc'),
    ),
  ),
  ColorContribution(
    'editorLightBulbAi.foreground',
    ColorDefaults(
      dark: ColorReference('editorLightBulb.foreground'),
      light: ColorReference('editorLightBulb.foreground'),
      hcDark: ColorReference('editorLightBulb.foreground'),
      hcLight: ColorReference('editorLightBulb.foreground'),
    ),
  ),
  ColorContribution(
    'editor.snippetTabstopHighlightBackground',
    ColorDefaults(
      dark: ColorLiteral.rgba(124, 124, 124, 0.3),
      light: ColorLiteral('#0a326433'),
      hcDark: ColorLiteral.rgba(124, 124, 124, 0.3),
      hcLight: ColorLiteral('#0a326433'),
    ),
  ),
  ColorContribution('editor.snippetTabstopHighlightBorder', null),
  ColorContribution('editor.snippetFinalTabstopHighlightBackground', null),
  ColorContribution(
    'editor.snippetFinalTabstopHighlightBorder',
    ColorDefaults(
      dark: ColorLiteral('#525252'),
      light: ColorLiteral.rgba(10, 50, 100, 0.5),
      hcDark: ColorLiteral('#525252'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'diffEditor.insertedTextBackground',
    ColorDefaults(
      dark: ColorLiteral('#9ccc2c33'),
      light: ColorLiteral('#9ccc2c40'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'diffEditor.removedTextBackground',
    ColorDefaults(
      dark: ColorLiteral('#ff000033'),
      light: ColorLiteral('#ff000033'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'diffEditor.insertedLineBackground',
    ColorDefaults(
      dark: ColorLiteral('#9bb95533'),
      light: ColorLiteral('#9bb95533'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'diffEditor.removedLineBackground',
    ColorDefaults(
      dark: ColorLiteral('#ff000033'),
      light: ColorLiteral('#ff000033'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution('diffEditorGutter.insertedLineBackground', null),
  ColorContribution('diffEditorGutter.removedLineBackground', null),
  ColorContribution('diffEditorOverview.insertedForeground', null),
  ColorContribution('diffEditorOverview.removedForeground', null),
  ColorContribution(
    'diffEditor.insertedTextBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorLiteral('#33ff2e'),
      hcLight: ColorLiteral('#374e06'),
    ),
  ),
  ColorContribution(
    'diffEditor.removedTextBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorLiteral('#ff008f'),
      hcLight: ColorLiteral('#ad0707'),
    ),
  ),
  ColorContribution(
    'diffEditor.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'diffEditor.diagonalFill',
    ColorDefaults(
      dark: ColorLiteral('#cccccc33'),
      light: ColorLiteral('#22222233'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'diffEditor.unchangedRegionBackground',
    ColorDefaults(
      dark: ColorReference('sideBar.background'),
      light: ColorReference('sideBar.background'),
      hcDark: ColorReference('sideBar.background'),
      hcLight: ColorReference('sideBar.background'),
    ),
  ),
  ColorContribution(
    'diffEditor.unchangedRegionForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'diffEditor.unchangedCodeBackground',
    ColorDefaults(
      dark: ColorLiteral('#74747429'),
      light: ColorLiteral('#b8b8b829'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'widget.shadow',
    ColorDefaults(
      dark: TransparentTransform(ColorLiteral('#000000'), 0.36),
      light: TransparentTransform(ColorLiteral('#000000'), 0.16),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'widget.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'toolbar.hoverBackground',
    ColorDefaults(
      dark: ColorLiteral('#5a5d5e50'),
      light: ColorLiteral('#b8b8b850'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'toolbar.hoverOutline',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'toolbar.activeBackground',
    ColorDefaults(
      dark: LightenTransform(ColorReference('toolbar.hoverBackground'), 0.1),
      light: DarkenTransform(ColorReference('toolbar.hoverBackground'), 0.1),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'breadcrumb.foreground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('foreground'), 0.8),
      light: TransparentTransform(ColorReference('foreground'), 0.8),
      hcDark: TransparentTransform(ColorReference('foreground'), 0.8),
      hcLight: TransparentTransform(ColorReference('foreground'), 0.8),
    ),
  ),
  ColorContribution(
    'breadcrumb.background',
    ColorDefaults(
      dark: ColorReference('editor.background'),
      light: ColorReference('editor.background'),
      hcDark: ColorReference('editor.background'),
      hcLight: ColorReference('editor.background'),
    ),
  ),
  ColorContribution(
    'breadcrumb.focusForeground',
    ColorDefaults(
      dark: LightenTransform(ColorReference('foreground'), 0.1),
      light: DarkenTransform(ColorReference('foreground'), 0.2),
      hcDark: LightenTransform(ColorReference('foreground'), 0.1),
      hcLight: LightenTransform(ColorReference('foreground'), 0.1),
    ),
  ),
  ColorContribution(
    'breadcrumb.activeSelectionForeground',
    ColorDefaults(
      dark: LightenTransform(ColorReference('foreground'), 0.1),
      light: DarkenTransform(ColorReference('foreground'), 0.2),
      hcDark: LightenTransform(ColorReference('foreground'), 0.1),
      hcLight: LightenTransform(ColorReference('foreground'), 0.1),
    ),
  ),
  ColorContribution(
    'breadcrumbPicker.background',
    ColorDefaults(
      dark: ColorReference('editorWidget.background'),
      light: ColorReference('editorWidget.background'),
      hcDark: ColorReference('editorWidget.background'),
      hcLight: ColorReference('editorWidget.background'),
    ),
  ),
  ColorContribution(
    'merge.currentHeaderBackground',
    ColorDefaults(
      dark: ColorLiteral.rgba(64, 200, 174, 0.5),
      light: ColorLiteral.rgba(64, 200, 174, 0.5),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'merge.currentContentBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('merge.currentHeaderBackground'),
        0.4,
      ),
      light: TransparentTransform(
        ColorReference('merge.currentHeaderBackground'),
        0.4,
      ),
      hcDark: TransparentTransform(
        ColorReference('merge.currentHeaderBackground'),
        0.4,
      ),
      hcLight: TransparentTransform(
        ColorReference('merge.currentHeaderBackground'),
        0.4,
      ),
    ),
  ),
  ColorContribution(
    'merge.incomingHeaderBackground',
    ColorDefaults(
      dark: ColorLiteral.rgba(64, 166, 255, 0.5),
      light: ColorLiteral.rgba(64, 166, 255, 0.5),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'merge.incomingContentBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('merge.incomingHeaderBackground'),
        0.4,
      ),
      light: TransparentTransform(
        ColorReference('merge.incomingHeaderBackground'),
        0.4,
      ),
      hcDark: TransparentTransform(
        ColorReference('merge.incomingHeaderBackground'),
        0.4,
      ),
      hcLight: TransparentTransform(
        ColorReference('merge.incomingHeaderBackground'),
        0.4,
      ),
    ),
  ),
  ColorContribution(
    'merge.commonHeaderBackground',
    ColorDefaults(
      dark: ColorLiteral('#60606066'),
      light: ColorLiteral('#60606066'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'merge.commonContentBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('merge.commonHeaderBackground'),
        0.4,
      ),
      light: TransparentTransform(
        ColorReference('merge.commonHeaderBackground'),
        0.4,
      ),
      hcDark: TransparentTransform(
        ColorReference('merge.commonHeaderBackground'),
        0.4,
      ),
      hcLight: TransparentTransform(
        ColorReference('merge.commonHeaderBackground'),
        0.4,
      ),
    ),
  ),
  ColorContribution(
    'merge.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorLiteral('#c3df6f'),
      hcLight: ColorLiteral('#007acc'),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.currentContentForeground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('merge.currentHeaderBackground'),
        1.0,
      ),
      light: TransparentTransform(
        ColorReference('merge.currentHeaderBackground'),
        1.0,
      ),
      hcDark: ColorReference('merge.border'),
      hcLight: ColorReference('merge.border'),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.incomingContentForeground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('merge.incomingHeaderBackground'),
        1.0,
      ),
      light: TransparentTransform(
        ColorReference('merge.incomingHeaderBackground'),
        1.0,
      ),
      hcDark: ColorReference('merge.border'),
      hcLight: ColorReference('merge.border'),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.commonContentForeground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('merge.commonHeaderBackground'),
        1.0,
      ),
      light: TransparentTransform(
        ColorReference('merge.commonHeaderBackground'),
        1.0,
      ),
      hcDark: ColorReference('merge.border'),
      hcLight: ColorReference('merge.border'),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.findMatchForeground',
    ColorDefaults(
      dark: ColorLiteral('#d186167e'),
      light: ColorLiteral('#d186167e'),
      hcDark: ColorLiteral('#ab5a00'),
      hcLight: ColorLiteral('#ab5a00'),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.selectionHighlightForeground',
    ColorDefaults(
      dark: ColorLiteral('#a0a0a0cc'),
      light: ColorLiteral('#a0a0a0cc'),
      hcDark: ColorLiteral('#a0a0a0cc'),
      hcLight: ColorLiteral('#a0a0a0cc'),
    ),
  ),
  ColorContribution(
    'problemsErrorIcon.foreground',
    ColorDefaults(
      dark: ColorReference('editorError.foreground'),
      light: ColorReference('editorError.foreground'),
      hcDark: ColorReference('editorError.foreground'),
      hcLight: ColorReference('editorError.foreground'),
    ),
  ),
  ColorContribution(
    'problemsWarningIcon.foreground',
    ColorDefaults(
      dark: ColorReference('editorWarning.foreground'),
      light: ColorReference('editorWarning.foreground'),
      hcDark: ColorReference('editorWarning.foreground'),
      hcLight: ColorReference('editorWarning.foreground'),
    ),
  ),
  ColorContribution(
    'problemsInfoIcon.foreground',
    ColorDefaults(
      dark: ColorReference('editorInfo.foreground'),
      light: ColorReference('editorInfo.foreground'),
      hcDark: ColorReference('editorInfo.foreground'),
      hcLight: ColorReference('editorInfo.foreground'),
    ),
  ),
  // src/vs/platform/theme/common/colors/minimapColors.ts
  ColorContribution(
    'minimap.findMatchHighlight',
    ColorDefaults(
      dark: ColorReference('editor.findMatchHighlightBackground'),
      light: ColorReference('editor.findMatchHighlightBackground'),
      hcDark: ColorReference('editor.findMatchHighlightBackground'),
      hcLight: ColorReference('editor.findMatchHighlightBackground'),
    ),
  ),
  ColorContribution(
    'minimap.selectionOccurrenceHighlight',
    ColorDefaults(
      dark: ColorReference('editor.selectionHighlightBackground'),
      light: ColorReference('editor.selectionHighlightBackground'),
      hcDark: ColorReference('editor.selectionHighlightBackground'),
      hcLight: ColorReference('editor.selectionHighlightBackground'),
    ),
  ),
  ColorContribution(
    'minimap.selectionHighlight',
    ColorDefaults(
      dark: ColorReference('editor.selectionBackground'),
      light: ColorReference('editor.selectionBackground'),
      hcDark: ColorReference('editor.selectionBackground'),
      hcLight: ColorReference('editor.selectionBackground'),
    ),
  ),
  ColorContribution(
    'minimap.infoHighlight',
    ColorDefaults(
      dark: ColorReference('editorInfo.foreground'),
      light: ColorReference('editorInfo.foreground'),
      hcDark: ColorReference('editorInfo.border'),
      hcLight: ColorReference('editorInfo.border'),
    ),
  ),
  ColorContribution(
    'minimap.warningHighlight',
    ColorDefaults(
      dark: ColorReference('editorWarning.foreground'),
      light: ColorReference('editorWarning.foreground'),
      hcDark: ColorReference('editorWarning.border'),
      hcLight: ColorReference('editorWarning.border'),
    ),
  ),
  ColorContribution(
    'minimap.errorHighlight',
    ColorDefaults(
      dark: ColorLiteral.rgba(255, 18, 18, 0.7),
      light: ColorLiteral.rgba(255, 18, 18, 0.7),
      hcDark: ColorLiteral('#ff3232'),
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution('minimap.background', null),
  ColorContribution(
    'minimap.foregroundOpacity',
    ColorDefaults(
      dark: ColorLiteral('#000000'),
      light: ColorLiteral('#000000'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#000000'),
    ),
  ),
  ColorContribution(
    'minimapSlider.background',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('scrollbarSlider.background'),
        0.5,
      ),
      light: TransparentTransform(
        ColorReference('scrollbarSlider.background'),
        0.5,
      ),
      hcDark: TransparentTransform(
        ColorReference('scrollbarSlider.background'),
        0.5,
      ),
      hcLight: TransparentTransform(
        ColorReference('scrollbarSlider.background'),
        0.5,
      ),
    ),
  ),
  ColorContribution(
    'minimapSlider.hoverBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('scrollbarSlider.hoverBackground'),
        0.5,
      ),
      light: TransparentTransform(
        ColorReference('scrollbarSlider.hoverBackground'),
        0.5,
      ),
      hcDark: TransparentTransform(
        ColorReference('scrollbarSlider.hoverBackground'),
        0.5,
      ),
      hcLight: TransparentTransform(
        ColorReference('scrollbarSlider.hoverBackground'),
        0.5,
      ),
    ),
  ),
  ColorContribution(
    'minimapSlider.activeBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('scrollbarSlider.activeBackground'),
        0.5,
      ),
      light: TransparentTransform(
        ColorReference('scrollbarSlider.activeBackground'),
        0.5,
      ),
      hcDark: TransparentTransform(
        ColorReference('scrollbarSlider.activeBackground'),
        0.5,
      ),
      hcLight: TransparentTransform(
        ColorReference('scrollbarSlider.activeBackground'),
        0.5,
      ),
    ),
  ),
  // src/vs/platform/theme/common/colors/chartsColors.ts
  ColorContribution(
    'charts.foreground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'charts.lines',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('foreground'), 0.5),
      light: TransparentTransform(ColorReference('foreground'), 0.5),
      hcDark: TransparentTransform(ColorReference('foreground'), 0.5),
      hcLight: TransparentTransform(ColorReference('foreground'), 0.5),
    ),
  ),
  ColorContribution(
    'charts.red',
    ColorDefaults(
      dark: ColorReference('editorError.foreground'),
      light: ColorReference('editorError.foreground'),
      hcDark: ColorReference('editorError.foreground'),
      hcLight: ColorReference('editorError.foreground'),
    ),
  ),
  ColorContribution(
    'charts.blue',
    ColorDefaults(
      dark: ColorReference('editorInfo.foreground'),
      light: ColorReference('editorInfo.foreground'),
      hcDark: ColorReference('editorInfo.foreground'),
      hcLight: ColorReference('editorInfo.foreground'),
    ),
  ),
  ColorContribution(
    'charts.yellow',
    ColorDefaults(
      dark: ColorReference('editorWarning.foreground'),
      light: ColorReference('editorWarning.foreground'),
      hcDark: ColorReference('editorWarning.foreground'),
      hcLight: ColorReference('editorWarning.foreground'),
    ),
  ),
  ColorContribution(
    'charts.orange',
    ColorDefaults(
      dark: ColorReference('minimap.findMatchHighlight'),
      light: ColorReference('minimap.findMatchHighlight'),
      hcDark: ColorReference('minimap.findMatchHighlight'),
      hcLight: ColorReference('minimap.findMatchHighlight'),
    ),
  ),
  ColorContribution(
    'charts.green',
    ColorDefaults(
      dark: ColorLiteral('#89d185'),
      light: ColorLiteral('#388a34'),
      hcDark: ColorLiteral('#89d185'),
      hcLight: ColorLiteral('#374e06'),
    ),
  ),
  ColorContribution(
    'charts.purple',
    ColorDefaults(
      dark: ColorLiteral('#b180d7'),
      light: ColorLiteral('#652d90'),
      hcDark: ColorLiteral('#b180d7'),
      hcLight: ColorLiteral('#652d90'),
    ),
  ),
  // src/vs/platform/theme/common/colors/listColors.ts
  ColorContribution('list.focusBackground', null),
  ColorContribution('list.focusForeground', null),
  ColorContribution(
    'list.focusOutline',
    ColorDefaults(
      dark: ColorReference('focusBorder'),
      light: ColorReference('focusBorder'),
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution('list.focusAndSelectionOutline', null),
  ColorContribution(
    'list.activeSelectionBackground',
    ColorDefaults(
      dark: ColorLiteral('#04395e'),
      light: ColorLiteral('#0060c0'),
      hcDark: null,
      hcLight: ColorLiteral.rgba(15, 74, 133, 0.1),
    ),
  ),
  ColorContribution(
    'list.activeSelectionForeground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#ffffff'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution('list.activeSelectionIconForeground', null),
  ColorContribution(
    'list.inactiveSelectionBackground',
    ColorDefaults(
      dark: ColorLiteral('#37373d'),
      light: ColorLiteral('#e4e6f1'),
      hcDark: null,
      hcLight: ColorLiteral.rgba(15, 74, 133, 0.1),
    ),
  ),
  ColorContribution('list.inactiveSelectionForeground', null),
  ColorContribution('list.inactiveSelectionIconForeground', null),
  ColorContribution('list.inactiveFocusBackground', null),
  ColorContribution('list.inactiveFocusOutline', null),
  ColorContribution(
    'list.hoverBackground',
    ColorDefaults(
      dark: ColorLiteral('#2a2d2e'),
      light: ColorLiteral('#f0f0f0'),
      hcDark: ColorLiteral.rgba(255, 255, 255, 0.1),
      hcLight: ColorLiteral.rgba(15, 74, 133, 0.1),
    ),
  ),
  ColorContribution('list.hoverForeground', null),
  ColorContribution(
    'list.dropBackground',
    ColorDefaults(
      dark: ColorLiteral('#062f4a'),
      light: ColorLiteral('#d6ebff'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'list.dropBetweenBackground',
    ColorDefaults(
      dark: ColorReference('icon.foreground'),
      light: ColorReference('icon.foreground'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'list.highlightForeground',
    ColorDefaults(
      dark: ColorLiteral('#2aaaff'),
      light: ColorLiteral('#0066bf'),
      hcDark: ColorReference('focusBorder'),
      hcLight: ColorReference('focusBorder'),
    ),
  ),
  ColorContribution(
    'list.focusHighlightForeground',
    ColorDefaults(
      dark: ColorReference('list.highlightForeground'),
      light: IfDefinedThenElseTransform(
        'list.activeSelectionBackground',
        ColorReference('list.highlightForeground'),
        ColorLiteral('#bbe7ff'),
      ),
      hcDark: ColorReference('list.highlightForeground'),
      hcLight: ColorReference('list.highlightForeground'),
    ),
  ),
  ColorContribution(
    'list.invalidItemForeground',
    ColorDefaults(
      dark: ColorLiteral('#b89500'),
      light: ColorLiteral('#b89500'),
      hcDark: ColorLiteral('#b89500'),
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution(
    'list.errorForeground',
    ColorDefaults(
      dark: ColorLiteral('#f88070'),
      light: ColorLiteral('#b01011'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'list.warningForeground',
    ColorDefaults(
      dark: ColorLiteral('#cca700'),
      light: ColorLiteral('#855f00'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'listFilterWidget.background',
    ColorDefaults(
      dark: LightenTransform(ColorReference('editorWidget.background'), 0.0),
      light: DarkenTransform(ColorReference('editorWidget.background'), 0.0),
      hcDark: ColorReference('editorWidget.background'),
      hcLight: ColorReference('editorWidget.background'),
    ),
  ),
  ColorContribution(
    'listFilterWidget.outline',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#f38518'),
      hcLight: ColorLiteral('#007acc'),
    ),
  ),
  ColorContribution(
    'listFilterWidget.noMatchesOutline',
    ColorDefaults(
      dark: ColorLiteral('#be1100'),
      light: ColorLiteral('#be1100'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'listFilterWidget.shadow',
    ColorDefaults(
      dark: ColorReference('widget.shadow'),
      light: ColorReference('widget.shadow'),
      hcDark: ColorReference('widget.shadow'),
      hcLight: ColorReference('widget.shadow'),
    ),
  ),
  ColorContribution(
    'list.filterMatchBackground',
    ColorDefaults(
      dark: ColorReference('editor.findMatchHighlightBackground'),
      light: ColorReference('editor.findMatchHighlightBackground'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'list.filterMatchBorder',
    ColorDefaults(
      dark: ColorReference('editor.findMatchHighlightBorder'),
      light: ColorReference('editor.findMatchHighlightBorder'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'list.deemphasizedForeground',
    ColorDefaults(
      dark: ColorLiteral('#8c8c8c'),
      light: ColorLiteral('#8e8e90'),
      hcDark: ColorLiteral('#a7a8a9'),
      hcLight: ColorLiteral('#666666'),
    ),
  ),
  ColorContribution(
    'tree.indentGuidesStroke',
    ColorDefaults(
      dark: ColorLiteral('#585858'),
      light: ColorLiteral('#a9a9a9'),
      hcDark: ColorLiteral('#a9a9a9'),
      hcLight: ColorLiteral('#a5a5a5'),
    ),
  ),
  ColorContribution(
    'tree.inactiveIndentGuidesStroke',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('tree.indentGuidesStroke'),
        0.4,
      ),
      light: TransparentTransform(
        ColorReference('tree.indentGuidesStroke'),
        0.4,
      ),
      hcDark: TransparentTransform(
        ColorReference('tree.indentGuidesStroke'),
        0.4,
      ),
      hcLight: TransparentTransform(
        ColorReference('tree.indentGuidesStroke'),
        0.4,
      ),
    ),
  ),
  ColorContribution(
    'tree.tableColumnsBorder',
    ColorDefaults(
      dark: ColorLiteral('#cccccc20'),
      light: ColorLiteral('#61616120'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'tree.tableOddRowsBackground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('foreground'), 0.04),
      light: TransparentTransform(ColorReference('foreground'), 0.04),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'editorActionList.background',
    ColorDefaults(
      dark: ColorReference('editorWidget.background'),
      light: ColorReference('editorWidget.background'),
      hcDark: ColorReference('editorWidget.background'),
      hcLight: ColorReference('editorWidget.background'),
    ),
  ),
  ColorContribution(
    'editorActionList.foreground',
    ColorDefaults(
      dark: ColorReference('editorWidget.foreground'),
      light: ColorReference('editorWidget.foreground'),
      hcDark: ColorReference('editorWidget.foreground'),
      hcLight: ColorReference('editorWidget.foreground'),
    ),
  ),
  ColorContribution(
    'editorActionList.focusForeground',
    ColorDefaults(
      dark: ColorReference('list.activeSelectionForeground'),
      light: ColorReference('list.activeSelectionForeground'),
      hcDark: ColorReference('list.activeSelectionForeground'),
      hcLight: ColorReference('list.activeSelectionForeground'),
    ),
  ),
  ColorContribution(
    'editorActionList.focusBackground',
    ColorDefaults(
      dark: ColorReference('list.activeSelectionBackground'),
      light: ColorReference('list.activeSelectionBackground'),
      hcDark: ColorReference('list.activeSelectionBackground'),
      hcLight: ColorReference('list.activeSelectionBackground'),
    ),
  ),
  // src/vs/platform/theme/common/colors/inputColors.ts
  ColorContribution(
    'input.background',
    ColorDefaults(
      dark: ColorLiteral('#3c3c3c'),
      light: ColorLiteral('#ffffff'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'input.foreground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'input.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'inputOption.activeBorder',
    ColorDefaults(
      dark: ColorLiteral('#007acc'),
      light: ColorLiteral('#007acc'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'inputOption.hoverBackground',
    ColorDefaults(
      dark: ColorLiteral('#5a5d5e80'),
      light: ColorLiteral('#b8b8b850'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'inputOption.activeBackground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('focusBorder'), 0.4),
      light: TransparentTransform(ColorReference('focusBorder'), 0.2),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'inputOption.activeForeground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#000000'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'input.placeholderForeground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('foreground'), 0.5),
      light: TransparentTransform(ColorReference('foreground'), 0.5),
      hcDark: TransparentTransform(ColorReference('foreground'), 0.7),
      hcLight: TransparentTransform(ColorReference('foreground'), 0.7),
    ),
  ),
  ColorContribution(
    'inputValidation.infoBackground',
    ColorDefaults(
      dark: ColorLiteral('#063b49'),
      light: ColorLiteral('#d6ecf2'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'inputValidation.infoForeground',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: null,
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'inputValidation.infoBorder',
    ColorDefaults(
      dark: ColorLiteral('#007acc'),
      light: ColorLiteral('#007acc'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'inputValidation.warningBackground',
    ColorDefaults(
      dark: ColorLiteral('#352a05'),
      light: ColorLiteral('#f6f5d2'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'inputValidation.warningForeground',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: null,
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'inputValidation.warningBorder',
    ColorDefaults(
      dark: ColorLiteral('#b89500'),
      light: ColorLiteral('#b89500'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'inputValidation.errorBackground',
    ColorDefaults(
      dark: ColorLiteral('#5a1d1d'),
      light: ColorLiteral('#f2dede'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'inputValidation.errorForeground',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: null,
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'inputValidation.errorBorder',
    ColorDefaults(
      dark: ColorLiteral('#be1100'),
      light: ColorLiteral('#be1100'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'dropdown.background',
    ColorDefaults(
      dark: ColorLiteral('#3c3c3c'),
      light: ColorLiteral('#ffffff'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'dropdown.listBackground',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'dropdown.foreground',
    ColorDefaults(
      dark: ColorLiteral('#f0f0f0'),
      light: ColorReference('foreground'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'dropdown.border',
    ColorDefaults(
      dark: ColorReference('dropdown.background'),
      light: ColorLiteral('#cecece'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'button.foreground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#ffffff'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'button.separator',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('button.foreground'), 0.4),
      light: TransparentTransform(ColorReference('button.foreground'), 0.4),
      hcDark: TransparentTransform(ColorReference('button.foreground'), 0.4),
      hcLight: TransparentTransform(ColorReference('button.foreground'), 0.4),
    ),
  ),
  ColorContribution(
    'button.background',
    ColorDefaults(
      dark: ColorLiteral('#0e639c'),
      light: ColorLiteral('#007acc'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  ColorContribution(
    'button.hoverBackground',
    ColorDefaults(
      dark: LightenTransform(ColorReference('button.background'), 0.2),
      light: DarkenTransform(ColorReference('button.background'), 0.2),
      hcDark: ColorReference('button.background'),
      hcLight: ColorReference('button.background'),
    ),
  ),
  ColorContribution(
    'button.border',
    ColorDefaults(
      dark: ColorReference('contrastBorder'),
      light: ColorReference('contrastBorder'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'button.secondaryForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'button.secondaryBackground',
    ColorDefaults(
      dark: ColorReference('list.hoverBackground'),
      light: ColorReference('list.hoverBackground'),
      hcDark: null,
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'button.secondaryBorder',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('foreground'), 0.15),
      light: TransparentTransform(ColorReference('foreground'), 0.15),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'button.secondaryHoverBackground',
    ColorDefaults(
      dark: LightenTransform(ColorReference('list.hoverBackground'), 0.2),
      light: LightenTransform(ColorReference('list.hoverBackground'), 0.2),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'radio.activeForeground',
    ColorDefaults(
      dark: ColorReference('inputOption.activeForeground'),
      light: ColorReference('inputOption.activeForeground'),
      hcDark: ColorReference('inputOption.activeForeground'),
      hcLight: ColorReference('inputOption.activeForeground'),
    ),
  ),
  ColorContribution(
    'radio.activeBackground',
    ColorDefaults(
      dark: ColorReference('inputOption.activeBackground'),
      light: ColorReference('inputOption.activeBackground'),
      hcDark: ColorReference('inputOption.activeBackground'),
      hcLight: ColorReference('inputOption.activeBackground'),
    ),
  ),
  ColorContribution(
    'radio.activeBorder',
    ColorDefaults(
      dark: ColorReference('inputOption.activeBorder'),
      light: ColorReference('inputOption.activeBorder'),
      hcDark: ColorReference('inputOption.activeBorder'),
      hcLight: ColorReference('inputOption.activeBorder'),
    ),
  ),
  ColorContribution('radio.inactiveForeground', null),
  ColorContribution('radio.inactiveBackground', null),
  ColorContribution(
    'radio.inactiveBorder',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('radio.activeForeground'), 0.2),
      light: TransparentTransform(
        ColorReference('radio.activeForeground'),
        0.2,
      ),
      hcDark: TransparentTransform(
        ColorReference('radio.activeForeground'),
        0.4,
      ),
      hcLight: TransparentTransform(
        ColorReference('radio.activeForeground'),
        0.2,
      ),
    ),
  ),
  ColorContribution(
    'radio.inactiveHoverBackground',
    ColorDefaults(
      dark: ColorReference('inputOption.hoverBackground'),
      light: ColorReference('inputOption.hoverBackground'),
      hcDark: ColorReference('inputOption.hoverBackground'),
      hcLight: ColorReference('inputOption.hoverBackground'),
    ),
  ),
  ColorContribution(
    'checkbox.background',
    ColorDefaults(
      dark: ColorReference('dropdown.background'),
      light: ColorReference('dropdown.background'),
      hcDark: ColorReference('dropdown.background'),
      hcLight: ColorReference('dropdown.background'),
    ),
  ),
  ColorContribution(
    'checkbox.selectBackground',
    ColorDefaults(
      dark: ColorReference('editorWidget.background'),
      light: ColorReference('editorWidget.background'),
      hcDark: ColorReference('editorWidget.background'),
      hcLight: ColorReference('editorWidget.background'),
    ),
  ),
  ColorContribution(
    'checkbox.foreground',
    ColorDefaults(
      dark: ColorReference('dropdown.foreground'),
      light: ColorReference('dropdown.foreground'),
      hcDark: ColorReference('dropdown.foreground'),
      hcLight: ColorReference('dropdown.foreground'),
    ),
  ),
  ColorContribution(
    'checkbox.border',
    ColorDefaults(
      dark: ColorReference('dropdown.border'),
      light: ColorReference('dropdown.border'),
      hcDark: ColorReference('dropdown.border'),
      hcLight: ColorReference('dropdown.border'),
    ),
  ),
  ColorContribution(
    'checkbox.selectBorder',
    ColorDefaults(
      dark: ColorReference('icon.foreground'),
      light: ColorReference('icon.foreground'),
      hcDark: ColorReference('icon.foreground'),
      hcLight: ColorReference('icon.foreground'),
    ),
  ),
  ColorContribution(
    'checkbox.disabled.background',
    ColorDefaults(
      dark: MixTransform(
        ColorReference('checkbox.background'),
        ColorReference('checkbox.foreground'),
        0.33,
      ),
      light: MixTransform(
        ColorReference('checkbox.background'),
        ColorReference('checkbox.foreground'),
        0.33,
      ),
      hcDark: MixTransform(
        ColorReference('checkbox.background'),
        ColorReference('checkbox.foreground'),
        0.33,
      ),
      hcLight: MixTransform(
        ColorReference('checkbox.background'),
        ColorReference('checkbox.foreground'),
        0.33,
      ),
    ),
  ),
  ColorContribution(
    'checkbox.disabled.foreground',
    ColorDefaults(
      dark: MixTransform(
        ColorReference('checkbox.foreground'),
        ColorReference('checkbox.background'),
        0.33,
      ),
      light: MixTransform(
        ColorReference('checkbox.foreground'),
        ColorReference('checkbox.background'),
        0.33,
      ),
      hcDark: MixTransform(
        ColorReference('checkbox.foreground'),
        ColorReference('checkbox.background'),
        0.33,
      ),
      hcLight: MixTransform(
        ColorReference('checkbox.foreground'),
        ColorReference('checkbox.background'),
        0.33,
      ),
    ),
  ),
  ColorContribution(
    'keybindingLabel.background',
    ColorDefaults(
      dark: ColorLiteral.rgba(128, 128, 128, 0.17),
      light: ColorLiteral('#dddddd66'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'keybindingLabel.foreground',
    ColorDefaults(
      dark: ColorLiteral('#cccccc'),
      light: ColorLiteral('#555555'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'keybindingLabel.border',
    ColorDefaults(
      dark: ColorLiteral('#33333399'),
      light: ColorLiteral('#cccccc66'),
      hcDark: ColorLiteral('#6fc3df'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'keybindingLabel.bottomBorder',
    ColorDefaults(
      dark: ColorLiteral('#44444499'),
      light: ColorLiteral('#bbbbbb66'),
      hcDark: ColorLiteral('#6fc3df'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  // src/vs/platform/theme/common/colors/menuColors.ts
  ColorContribution(
    'menu.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'menu.foreground',
    ColorDefaults(
      dark: ColorReference('dropdown.foreground'),
      light: ColorReference('dropdown.foreground'),
      hcDark: ColorReference('dropdown.foreground'),
      hcLight: ColorReference('dropdown.foreground'),
    ),
  ),
  ColorContribution(
    'menu.background',
    ColorDefaults(
      dark: ColorReference('dropdown.background'),
      light: ColorReference('dropdown.background'),
      hcDark: ColorReference('dropdown.background'),
      hcLight: ColorReference('dropdown.background'),
    ),
  ),
  ColorContribution(
    'menu.selectionForeground',
    ColorDefaults(
      dark: ColorReference('list.activeSelectionForeground'),
      light: ColorReference('list.activeSelectionForeground'),
      hcDark: ColorReference('list.activeSelectionForeground'),
      hcLight: ColorReference('list.activeSelectionForeground'),
    ),
  ),
  ColorContribution(
    'menu.selectionBackground',
    ColorDefaults(
      dark: ColorReference('list.activeSelectionBackground'),
      light: ColorReference('list.activeSelectionBackground'),
      hcDark: ColorReference('list.activeSelectionBackground'),
      hcLight: ColorReference('list.activeSelectionBackground'),
    ),
  ),
  ColorContribution(
    'menu.selectionBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'menu.separatorBackground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('foreground'), 0.2),
      light: TransparentTransform(ColorReference('foreground'), 0.2),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  // src/vs/platform/theme/common/colors/quickpickColors.ts
  ColorContribution(
    'quickInput.background',
    ColorDefaults(
      dark: ColorReference('editorWidget.background'),
      light: ColorReference('editorWidget.background'),
      hcDark: ColorReference('editorWidget.background'),
      hcLight: ColorReference('editorWidget.background'),
    ),
  ),
  ColorContribution(
    'quickInput.foreground',
    ColorDefaults(
      dark: ColorReference('editorWidget.foreground'),
      light: ColorReference('editorWidget.foreground'),
      hcDark: ColorReference('editorWidget.foreground'),
      hcLight: ColorReference('editorWidget.foreground'),
    ),
  ),
  ColorContribution(
    'quickInputTitle.background',
    ColorDefaults(
      dark: ColorLiteral.rgba(255, 255, 255, 0.105),
      light: ColorLiteral.rgba(0, 0, 0, 0.06),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'pickerGroup.foreground',
    ColorDefaults(
      dark: ColorLiteral('#3794ff'),
      light: ColorLiteral('#0066bf'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  ColorContribution(
    'pickerGroup.border',
    ColorDefaults(
      dark: ColorLiteral('#3f3f46'),
      light: ColorLiteral('#cccedb'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  ColorContribution('quickInput.list.focusBackground', null),
  ColorContribution(
    'quickInputList.focusForeground',
    ColorDefaults(
      dark: ColorReference('list.activeSelectionForeground'),
      light: ColorReference('list.activeSelectionForeground'),
      hcDark: ColorReference('list.activeSelectionForeground'),
      hcLight: ColorReference('list.activeSelectionForeground'),
    ),
  ),
  ColorContribution(
    'quickInputList.focusIconForeground',
    ColorDefaults(
      dark: ColorReference('list.activeSelectionIconForeground'),
      light: ColorReference('list.activeSelectionIconForeground'),
      hcDark: ColorReference('list.activeSelectionIconForeground'),
      hcLight: ColorReference('list.activeSelectionIconForeground'),
    ),
  ),
  ColorContribution(
    'quickInputList.focusBackground',
    ColorDefaults(
      dark: OneOfTransform([
        ColorReference('quickInput.list.focusBackground'),
        ColorReference('list.activeSelectionBackground'),
      ]),
      light: OneOfTransform([
        ColorReference('quickInput.list.focusBackground'),
        ColorReference('list.activeSelectionBackground'),
      ]),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'quickInputList.focusHighlightForeground',
    ColorDefaults(
      dark: ColorReference('list.focusHighlightForeground'),
      light: ColorReference('list.focusHighlightForeground'),
      hcDark: ColorReference('list.focusHighlightForeground'),
      hcLight: ColorReference('list.focusHighlightForeground'),
    ),
  ),
  // src/vs/platform/theme/common/colors/searchColors.ts
  ColorContribution(
    'search.resultsInfoForeground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('foreground'), 0.65),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'searchEditor.findMatchBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editor.findMatchHighlightBackground'),
        0.66,
      ),
      light: TransparentTransform(
        ColorReference('editor.findMatchHighlightBackground'),
        0.66,
      ),
      hcDark: ColorReference('editor.findMatchHighlightBackground'),
      hcLight: ColorReference('editor.findMatchHighlightBackground'),
    ),
  ),
  ColorContribution(
    'searchEditor.findMatchBorder',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editor.findMatchHighlightBorder'),
        0.66,
      ),
      light: TransparentTransform(
        ColorReference('editor.findMatchHighlightBorder'),
        0.66,
      ),
      hcDark: ColorReference('editor.findMatchHighlightBorder'),
      hcLight: ColorReference('editor.findMatchHighlightBorder'),
    ),
  ),
  // src/vs/editor/common/core/editorColorRegistry.ts
  ColorContribution('editor.lineHighlightBackground', null),
  ColorContribution(
    'editor.inactiveLineHighlightBackground',
    ColorDefaults(
      dark: ColorReference('editor.lineHighlightBackground'),
      light: ColorReference('editor.lineHighlightBackground'),
      hcDark: ColorReference('editor.lineHighlightBackground'),
      hcLight: ColorReference('editor.lineHighlightBackground'),
    ),
  ),
  ColorContribution(
    'editor.lineHighlightBorder',
    ColorDefaults(
      dark: ColorLiteral('#282828'),
      light: ColorLiteral('#eeeeee'),
      hcDark: ColorLiteral('#f38518'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'editor.rangeHighlightBackground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff0b'),
      light: ColorLiteral('#fdff0033'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'editor.rangeHighlightBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'editor.symbolHighlightBackground',
    ColorDefaults(
      dark: ColorReference('editor.findMatchHighlightBackground'),
      light: ColorReference('editor.findMatchHighlightBackground'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'editor.symbolHighlightBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'editorCursor.foreground',
    ColorDefaults(
      dark: ColorLiteral('#aeafad'),
      light: ColorLiteral('#000000'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  ColorContribution('editorCursor.background', null),
  ColorContribution(
    'editorMultiCursor.primary.foreground',
    ColorDefaults(
      dark: ColorReference('editorCursor.foreground'),
      light: ColorReference('editorCursor.foreground'),
      hcDark: ColorReference('editorCursor.foreground'),
      hcLight: ColorReference('editorCursor.foreground'),
    ),
  ),
  ColorContribution(
    'editorMultiCursor.primary.background',
    ColorDefaults(
      dark: ColorReference('editorCursor.background'),
      light: ColorReference('editorCursor.background'),
      hcDark: ColorReference('editorCursor.background'),
      hcLight: ColorReference('editorCursor.background'),
    ),
  ),
  ColorContribution(
    'editorMultiCursor.secondary.foreground',
    ColorDefaults(
      dark: ColorReference('editorCursor.foreground'),
      light: ColorReference('editorCursor.foreground'),
      hcDark: ColorReference('editorCursor.foreground'),
      hcLight: ColorReference('editorCursor.foreground'),
    ),
  ),
  ColorContribution(
    'editorMultiCursor.secondary.background',
    ColorDefaults(
      dark: ColorReference('editorCursor.background'),
      light: ColorReference('editorCursor.background'),
      hcDark: ColorReference('editorCursor.background'),
      hcLight: ColorReference('editorCursor.background'),
    ),
  ),
  ColorContribution(
    'editorWhitespace.foreground',
    ColorDefaults(
      dark: ColorLiteral('#e3e4e229'),
      light: ColorLiteral('#33333333'),
      hcDark: ColorLiteral('#e3e4e229'),
      hcLight: ColorLiteral('#cccccc'),
    ),
  ),
  ColorContribution(
    'editorWordWrapIndicator.foreground',
    ColorDefaults(
      dark: ColorReference('editorWhitespace.foreground'),
      light: ColorReference('editorWhitespace.foreground'),
      hcDark: ColorReference('editorWhitespace.foreground'),
      hcLight: ColorReference('editorWhitespace.foreground'),
    ),
  ),
  ColorContribution(
    'editorLineNumber.foreground',
    ColorDefaults(
      dark: ColorLiteral('#858585'),
      light: ColorLiteral('#237893'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'editorIndentGuide.background',
    ColorDefaults(
      dark: ColorReference('editorWhitespace.foreground'),
      light: ColorReference('editorWhitespace.foreground'),
      hcDark: ColorReference('editorWhitespace.foreground'),
      hcLight: ColorReference('editorWhitespace.foreground'),
    ),
  ),
  ColorContribution(
    'editorIndentGuide.activeBackground',
    ColorDefaults(
      dark: ColorReference('editorWhitespace.foreground'),
      light: ColorReference('editorWhitespace.foreground'),
      hcDark: ColorReference('editorWhitespace.foreground'),
      hcLight: ColorReference('editorWhitespace.foreground'),
    ),
  ),
  ColorContribution(
    'editorIndentGuide.background1',
    ColorDefaults(
      dark: ColorReference('editorIndentGuide.background'),
      light: ColorReference('editorIndentGuide.background'),
      hcDark: ColorReference('editorIndentGuide.background'),
      hcLight: ColorReference('editorIndentGuide.background'),
    ),
  ),
  ColorContribution(
    'editorIndentGuide.background2',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorIndentGuide.background3',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorIndentGuide.background4',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorIndentGuide.background5',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorIndentGuide.background6',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorIndentGuide.activeBackground1',
    ColorDefaults(
      dark: ColorReference('editorIndentGuide.activeBackground'),
      light: ColorReference('editorIndentGuide.activeBackground'),
      hcDark: ColorReference('editorIndentGuide.activeBackground'),
      hcLight: ColorReference('editorIndentGuide.activeBackground'),
    ),
  ),
  ColorContribution(
    'editorIndentGuide.activeBackground2',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorIndentGuide.activeBackground3',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorIndentGuide.activeBackground4',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorIndentGuide.activeBackground5',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorIndentGuide.activeBackground6',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorActiveLineNumber.foreground',
    ColorDefaults(
      dark: ColorLiteral('#c6c6c6'),
      light: ColorLiteral('#0b216f'),
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'editorLineNumber.activeForeground',
    ColorDefaults(
      dark: ColorReference('editorActiveLineNumber.foreground'),
      light: ColorReference('editorActiveLineNumber.foreground'),
      hcDark: ColorReference('editorActiveLineNumber.foreground'),
      hcLight: ColorReference('editorActiveLineNumber.foreground'),
    ),
  ),
  ColorContribution('editorLineNumber.dimmedForeground', null),
  ColorContribution(
    'editorRuler.foreground',
    ColorDefaults(
      dark: ColorLiteral('#5a5a5a'),
      light: ColorLiteral('#d3d3d3'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'editorCodeLens.foreground',
    ColorDefaults(
      dark: ColorLiteral('#999999'),
      light: ColorLiteral('#919191'),
      hcDark: ColorLiteral('#999999'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'editorBracketMatch.background',
    ColorDefaults(
      dark: ColorLiteral('#0064001a'),
      light: ColorLiteral('#0064001a'),
      hcDark: ColorLiteral('#0064001a'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorBracketMatch.border',
    ColorDefaults(
      dark: ColorLiteral('#888888'),
      light: ColorLiteral('#b9b9b9'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution('editorBracketMatch.foreground', null),
  ColorContribution(
    'editorOverviewRuler.border',
    ColorDefaults(
      dark: ColorLiteral('#7f7f7f4d'),
      light: ColorLiteral('#7f7f7f4d'),
      hcDark: ColorLiteral('#7f7f7f4d'),
      hcLight: ColorLiteral('#666666'),
    ),
  ),
  ColorContribution('editorOverviewRuler.background', null),
  ColorContribution(
    'editorGutter.background',
    ColorDefaults(
      dark: ColorReference('editor.background'),
      light: ColorReference('editor.background'),
      hcDark: ColorReference('editor.background'),
      hcLight: ColorReference('editor.background'),
    ),
  ),
  ColorContribution(
    'editorUnnecessaryCode.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorLiteral('#ffffffcc'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'editorUnnecessaryCode.opacity',
    ColorDefaults(
      dark: ColorLiteral('#000000aa'),
      light: ColorLiteral('#00000077'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'editorGhostText.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorLiteral('#ffffffcc'),
      hcLight: ColorLiteral('#292929cc'),
    ),
  ),
  ColorContribution(
    'editorGhostText.foreground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff56'),
      light: ColorLiteral('#00000077'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution('editorGhostText.background', null),
  ColorContribution(
    'editorOverviewRuler.rangeHighlightForeground',
    ColorDefaults(
      dark: ColorLiteral('#007acc99'),
      light: ColorLiteral('#007acc99'),
      hcDark: ColorLiteral('#007acc99'),
      hcLight: ColorLiteral('#007acc99'),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.errorForeground',
    ColorDefaults(
      dark: ColorLiteral.rgba(255, 18, 18, 0.7),
      light: ColorLiteral.rgba(255, 18, 18, 0.7),
      hcDark: ColorLiteral('#ff3232'),
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.warningForeground',
    ColorDefaults(
      dark: ColorReference('editorWarning.foreground'),
      light: ColorReference('editorWarning.foreground'),
      hcDark: ColorReference('editorWarning.border'),
      hcLight: ColorReference('editorWarning.border'),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.infoForeground',
    ColorDefaults(
      dark: ColorReference('editorInfo.foreground'),
      light: ColorReference('editorInfo.foreground'),
      hcDark: ColorReference('editorInfo.border'),
      hcLight: ColorReference('editorInfo.border'),
    ),
  ),
  ColorContribution(
    'editorBracketHighlight.foreground1',
    ColorDefaults(
      dark: ColorLiteral('#ffd700'),
      light: ColorLiteral('#0431fa'),
      hcDark: ColorLiteral('#ffd700'),
      hcLight: ColorLiteral('#0431fa'),
    ),
  ),
  ColorContribution(
    'editorBracketHighlight.foreground2',
    ColorDefaults(
      dark: ColorLiteral('#da70d6'),
      light: ColorLiteral('#319331'),
      hcDark: ColorLiteral('#da70d6'),
      hcLight: ColorLiteral('#319331'),
    ),
  ),
  ColorContribution(
    'editorBracketHighlight.foreground3',
    ColorDefaults(
      dark: ColorLiteral('#179fff'),
      light: ColorLiteral('#7b3814'),
      hcDark: ColorLiteral('#87cefa'),
      hcLight: ColorLiteral('#7b3814'),
    ),
  ),
  ColorContribution(
    'editorBracketHighlight.foreground4',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorBracketHighlight.foreground5',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorBracketHighlight.foreground6',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorBracketHighlight.unexpectedBracket.foreground',
    ColorDefaults(
      dark: ColorLiteral('#ff1212cc'),
      light: ColorLiteral('#ff1212cc'),
      hcDark: ColorLiteral('#ff3232'),
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution(
    'editorBracketPairGuide.background1',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorBracketPairGuide.background2',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorBracketPairGuide.background3',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorBracketPairGuide.background4',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorBracketPairGuide.background5',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorBracketPairGuide.background6',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorBracketPairGuide.activeBackground1',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorBracketPairGuide.activeBackground2',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorBracketPairGuide.activeBackground3',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorBracketPairGuide.activeBackground4',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorBracketPairGuide.activeBackground5',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorBracketPairGuide.activeBackground6',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'editorUnicodeHighlight.border',
    ColorDefaults(
      dark: ColorReference('editorWarning.foreground'),
      light: ColorReference('editorWarning.foreground'),
      hcDark: ColorReference('editorWarning.foreground'),
      hcLight: ColorReference('editorWarning.foreground'),
    ),
  ),
  ColorContribution(
    'editorUnicodeHighlight.background',
    ColorDefaults(
      dark: ColorReference('editorWarning.background'),
      light: ColorReference('editorWarning.background'),
      hcDark: ColorReference('editorWarning.background'),
      hcLight: ColorReference('editorWarning.background'),
    ),
  ),
  // src/vs/editor/browser/widget/diffEditor/registrations.contribution.ts
  ColorContribution(
    'diffEditor.move.border',
    ColorDefaults(
      dark: ColorLiteral('#8b8b8b9c'),
      light: ColorLiteral('#8b8b8b9c'),
      hcDark: ColorLiteral('#8b8b8b9c'),
      hcLight: ColorLiteral('#8b8b8b9c'),
    ),
  ),
  ColorContribution(
    'diffEditor.moveActive.border',
    ColorDefaults(
      dark: ColorLiteral('#ffa500'),
      light: ColorLiteral('#ffa500'),
      hcDark: ColorLiteral('#ffa500'),
      hcLight: ColorLiteral('#ffa500'),
    ),
  ),
  ColorContribution(
    'diffEditor.unchangedRegionShadow',
    ColorDefaults(
      dark: ColorLiteral('#000000'),
      light: ColorLiteral('#737373bf'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#737373bf'),
    ),
  ),
  // src/vs/editor/contrib/bracketMatching/browser/bracketMatching.ts
  ColorContribution(
    'editorOverviewRuler.bracketMatchForeground',
    ColorDefaults(
      dark: ColorLiteral('#a0a0a0'),
      light: ColorLiteral('#a0a0a0'),
      hcDark: ColorLiteral('#a0a0a0'),
      hcLight: ColorLiteral('#a0a0a0'),
    ),
  ),
  // src/vs/platform/actionWidget/browser/actionWidget.ts
  ColorContribution(
    'actionBar.toggledBackground',
    ColorDefaults(
      dark: ColorReference('inputOption.activeBackground'),
      light: ColorReference('inputOption.activeBackground'),
      hcDark: ColorReference('inputOption.activeBackground'),
      hcLight: ColorReference('inputOption.activeBackground'),
    ),
  ),
  // src/vs/editor/contrib/symbolIcons/browser/symbolIcons.ts
  ColorContribution(
    'symbolIcon.arrayForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.booleanForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.classForeground',
    ColorDefaults(
      dark: ColorLiteral('#ee9d28'),
      light: ColorLiteral('#d67e00'),
      hcDark: ColorLiteral('#ee9d28'),
      hcLight: ColorLiteral('#d67e00'),
    ),
  ),
  ColorContribution(
    'symbolIcon.colorForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.constantForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.constructorForeground',
    ColorDefaults(
      dark: ColorLiteral('#b180d7'),
      light: ColorLiteral('#652d90'),
      hcDark: ColorLiteral('#b180d7'),
      hcLight: ColorLiteral('#652d90'),
    ),
  ),
  ColorContribution(
    'symbolIcon.enumeratorForeground',
    ColorDefaults(
      dark: ColorLiteral('#ee9d28'),
      light: ColorLiteral('#d67e00'),
      hcDark: ColorLiteral('#ee9d28'),
      hcLight: ColorLiteral('#d67e00'),
    ),
  ),
  ColorContribution(
    'symbolIcon.enumeratorMemberForeground',
    ColorDefaults(
      dark: ColorLiteral('#75beff'),
      light: ColorLiteral('#007acc'),
      hcDark: ColorLiteral('#75beff'),
      hcLight: ColorLiteral('#007acc'),
    ),
  ),
  ColorContribution(
    'symbolIcon.eventForeground',
    ColorDefaults(
      dark: ColorLiteral('#ee9d28'),
      light: ColorLiteral('#d67e00'),
      hcDark: ColorLiteral('#ee9d28'),
      hcLight: ColorLiteral('#d67e00'),
    ),
  ),
  ColorContribution(
    'symbolIcon.fieldForeground',
    ColorDefaults(
      dark: ColorLiteral('#75beff'),
      light: ColorLiteral('#007acc'),
      hcDark: ColorLiteral('#75beff'),
      hcLight: ColorLiteral('#007acc'),
    ),
  ),
  ColorContribution(
    'symbolIcon.fileForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.folderForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.functionForeground',
    ColorDefaults(
      dark: ColorLiteral('#b180d7'),
      light: ColorLiteral('#652d90'),
      hcDark: ColorLiteral('#b180d7'),
      hcLight: ColorLiteral('#652d90'),
    ),
  ),
  ColorContribution(
    'symbolIcon.interfaceForeground',
    ColorDefaults(
      dark: ColorLiteral('#75beff'),
      light: ColorLiteral('#007acc'),
      hcDark: ColorLiteral('#75beff'),
      hcLight: ColorLiteral('#007acc'),
    ),
  ),
  ColorContribution(
    'symbolIcon.keyForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.keywordForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.methodForeground',
    ColorDefaults(
      dark: ColorLiteral('#b180d7'),
      light: ColorLiteral('#652d90'),
      hcDark: ColorLiteral('#b180d7'),
      hcLight: ColorLiteral('#652d90'),
    ),
  ),
  ColorContribution(
    'symbolIcon.moduleForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.namespaceForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.nullForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.numberForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.objectForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.operatorForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.packageForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.propertyForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.referenceForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.snippetForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.stringForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.structForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.textForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.typeParameterForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.unitForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'symbolIcon.variableForeground',
    ColorDefaults(
      dark: ColorLiteral('#75beff'),
      light: ColorLiteral('#007acc'),
      hcDark: ColorLiteral('#75beff'),
      hcLight: ColorLiteral('#007acc'),
    ),
  ),
  // src/vs/editor/contrib/peekView/browser/peekView.ts
  ColorContribution(
    'peekViewTitle.background',
    ColorDefaults(
      dark: ColorLiteral('#252526'),
      light: ColorLiteral('#f3f3f3'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'peekViewTitleLabel.foreground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#000000'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('editor.foreground'),
    ),
  ),
  ColorContribution(
    'peekViewTitleDescription.foreground',
    ColorDefaults(
      dark: ColorLiteral('#ccccccb3'),
      light: ColorLiteral('#616161'),
      hcDark: ColorLiteral('#ffffff99'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'peekView.border',
    ColorDefaults(
      dark: ColorReference('editorInfo.foreground'),
      light: ColorReference('editorInfo.foreground'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'peekViewResult.background',
    ColorDefaults(
      dark: ColorLiteral('#252526'),
      light: ColorLiteral('#f3f3f3'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'peekViewResult.lineForeground',
    ColorDefaults(
      dark: ColorLiteral('#bbbbbb'),
      light: ColorLiteral('#646465'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('editor.foreground'),
    ),
  ),
  ColorContribution(
    'peekViewResult.fileForeground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#1e1e1e'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('editor.foreground'),
    ),
  ),
  ColorContribution(
    'peekViewResult.selectionBackground',
    ColorDefaults(
      dark: ColorLiteral('#3399ff33'),
      light: ColorLiteral('#3399ff33'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'peekViewResult.selectionForeground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#6c6c6c'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('editor.foreground'),
    ),
  ),
  ColorContribution(
    'peekViewEditor.background',
    ColorDefaults(
      dark: ColorLiteral('#001f33'),
      light: ColorLiteral('#f2f8fc'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'peekViewEditorGutter.background',
    ColorDefaults(
      dark: ColorReference('peekViewEditor.background'),
      light: ColorReference('peekViewEditor.background'),
      hcDark: ColorReference('peekViewEditor.background'),
      hcLight: ColorReference('peekViewEditor.background'),
    ),
  ),
  ColorContribution(
    'peekViewEditorStickyScroll.background',
    ColorDefaults(
      dark: ColorReference('peekViewEditor.background'),
      light: ColorReference('peekViewEditor.background'),
      hcDark: ColorReference('peekViewEditor.background'),
      hcLight: ColorReference('peekViewEditor.background'),
    ),
  ),
  ColorContribution(
    'peekViewEditorStickyScrollGutter.background',
    ColorDefaults(
      dark: ColorReference('peekViewEditor.background'),
      light: ColorReference('peekViewEditor.background'),
      hcDark: ColorReference('peekViewEditor.background'),
      hcLight: ColorReference('peekViewEditor.background'),
    ),
  ),
  ColorContribution(
    'peekViewResult.matchHighlightBackground',
    ColorDefaults(
      dark: ColorLiteral('#ea5c004d'),
      light: ColorLiteral('#ea5c004d'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'peekViewEditor.matchHighlightBackground',
    ColorDefaults(
      dark: ColorLiteral('#ff8f0099'),
      light: ColorLiteral('#f5d802de'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'peekViewEditor.matchHighlightBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  // src/vs/editor/contrib/folding/browser/foldingDecorations.ts
  ColorContribution(
    'editor.foldBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editor.selectionBackground'),
        0.3,
      ),
      light: TransparentTransform(
        ColorReference('editor.selectionBackground'),
        0.3,
      ),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'editor.foldPlaceholderForeground',
    ColorDefaults(
      dark: ColorLiteral('#808080'),
      light: ColorLiteral('#808080'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'editorGutter.foldingControlForeground',
    ColorDefaults(
      dark: ColorReference('icon.foreground'),
      light: ColorReference('icon.foreground'),
      hcDark: ColorReference('icon.foreground'),
      hcLight: ColorReference('icon.foreground'),
    ),
  ),
  // src/vs/editor/contrib/gotoError/browser/gotoErrorWidget.ts
  ColorContribution(
    'editorMarkerNavigationError.background',
    ColorDefaults(
      dark: OneOfTransform([
        ColorReference('editorError.foreground'),
        ColorReference('editorError.border'),
      ]),
      light: OneOfTransform([
        ColorReference('editorError.foreground'),
        ColorReference('editorError.border'),
      ]),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'editorMarkerNavigationError.headerBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editorMarkerNavigationError.background'),
        0.1,
      ),
      light: TransparentTransform(
        ColorReference('editorMarkerNavigationError.background'),
        0.1,
      ),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'editorMarkerNavigationWarning.background',
    ColorDefaults(
      dark: OneOfTransform([
        ColorReference('editorWarning.foreground'),
        ColorReference('editorWarning.border'),
      ]),
      light: OneOfTransform([
        ColorReference('editorWarning.foreground'),
        ColorReference('editorWarning.border'),
      ]),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'editorMarkerNavigationWarning.headerBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editorMarkerNavigationWarning.background'),
        0.1,
      ),
      light: TransparentTransform(
        ColorReference('editorMarkerNavigationWarning.background'),
        0.1,
      ),
      hcDark: ColorLiteral('#0c141f'),
      hcLight: TransparentTransform(
        ColorReference('editorMarkerNavigationWarning.background'),
        0.2,
      ),
    ),
  ),
  ColorContribution(
    'editorMarkerNavigationInfo.background',
    ColorDefaults(
      dark: OneOfTransform([
        ColorReference('editorInfo.foreground'),
        ColorReference('editorInfo.border'),
      ]),
      light: OneOfTransform([
        ColorReference('editorInfo.foreground'),
        ColorReference('editorInfo.border'),
      ]),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'editorMarkerNavigationInfo.headerBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editorMarkerNavigationInfo.background'),
        0.1,
      ),
      light: TransparentTransform(
        ColorReference('editorMarkerNavigationInfo.background'),
        0.1,
      ),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'editorMarkerNavigation.background',
    ColorDefaults(
      dark: ColorReference('editor.background'),
      light: ColorReference('editor.background'),
      hcDark: ColorReference('editor.background'),
      hcLight: ColorReference('editor.background'),
    ),
  ),
  // src/vs/editor/contrib/suggest/browser/suggestWidget.ts
  ColorContribution(
    'editorSuggestWidget.background',
    ColorDefaults(
      dark: ColorReference('editorWidget.background'),
      light: ColorReference('editorWidget.background'),
      hcDark: ColorReference('editorWidget.background'),
      hcLight: ColorReference('editorWidget.background'),
    ),
  ),
  ColorContribution(
    'editorSuggestWidget.border',
    ColorDefaults(
      dark: ColorReference('editorWidget.border'),
      light: ColorReference('editorWidget.border'),
      hcDark: ColorReference('editorWidget.border'),
      hcLight: ColorReference('editorWidget.border'),
    ),
  ),
  ColorContribution(
    'editorSuggestWidget.foreground',
    ColorDefaults(
      dark: ColorReference('editor.foreground'),
      light: ColorReference('editor.foreground'),
      hcDark: ColorReference('editor.foreground'),
      hcLight: ColorReference('editor.foreground'),
    ),
  ),
  ColorContribution(
    'editorSuggestWidget.selectedForeground',
    ColorDefaults(
      dark: ColorReference('quickInputList.focusForeground'),
      light: ColorReference('quickInputList.focusForeground'),
      hcDark: ColorReference('editorSuggestWidget.background'),
      hcLight: ColorReference('editorSuggestWidget.background'),
    ),
  ),
  ColorContribution(
    'editorSuggestWidget.selectedIconForeground',
    ColorDefaults(
      dark: ColorReference('quickInputList.focusIconForeground'),
      light: ColorReference('quickInputList.focusIconForeground'),
      hcDark: ColorReference('editorSuggestWidget.background'),
      hcLight: ColorReference('editorSuggestWidget.background'),
    ),
  ),
  ColorContribution(
    'editorSuggestWidget.selectedBackground',
    ColorDefaults(
      dark: ColorReference('quickInputList.focusBackground'),
      light: ColorReference('quickInputList.focusBackground'),
      hcDark: ColorReference('editorSuggestWidget.foreground'),
      hcLight: ColorReference('editorSuggestWidget.foreground'),
    ),
  ),
  ColorContribution(
    'editorSuggestWidget.focusOutline',
    ColorDefaults(
      dark: ColorReference('contrastActiveBorder'),
      light: ColorReference('contrastActiveBorder'),
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'editorSuggestWidget.highlightForeground',
    ColorDefaults(
      dark: ColorReference('list.highlightForeground'),
      light: ColorReference('list.highlightForeground'),
      hcDark: ColorReference('list.highlightForeground'),
      hcLight: ColorReference('list.highlightForeground'),
    ),
  ),
  ColorContribution(
    'editorSuggestWidget.focusHighlightForeground',
    ColorDefaults(
      dark: ColorReference('list.focusHighlightForeground'),
      light: ColorReference('list.focusHighlightForeground'),
      hcDark: ColorReference('editorSuggestWidget.selectedForeground'),
      hcLight: ColorReference('editorSuggestWidget.selectedForeground'),
    ),
  ),
  ColorContribution(
    'editorSuggestWidgetStatus.foreground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editorSuggestWidget.foreground'),
        0.5,
      ),
      light: TransparentTransform(
        ColorReference('editorSuggestWidget.foreground'),
        0.5,
      ),
      hcDark: TransparentTransform(
        ColorReference('editorSuggestWidget.foreground'),
        0.5,
      ),
      hcLight: TransparentTransform(
        ColorReference('editorSuggestWidget.foreground'),
        0.5,
      ),
    ),
  ),
  // src/vs/editor/contrib/inlineCompletions/browser/view/inlineEdits/theme.ts
  ColorContribution(
    'inlineEdit.originalBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.2,
      ),
      light: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.2,
      ),
      hcDark: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.2,
      ),
      hcLight: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.2,
      ),
    ),
  ),
  ColorContribution(
    'inlineEdit.modifiedBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.3,
      ),
      light: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.3,
      ),
      hcDark: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.3,
      ),
      hcLight: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.3,
      ),
    ),
  ),
  ColorContribution(
    'inlineEdit.originalChangedLineBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.8,
      ),
      light: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.8,
      ),
      hcDark: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.8,
      ),
      hcLight: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.8,
      ),
    ),
  ),
  ColorContribution(
    'inlineEdit.originalChangedTextBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.8,
      ),
      light: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.8,
      ),
      hcDark: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.8,
      ),
      hcLight: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.8,
      ),
    ),
  ),
  ColorContribution(
    'inlineEdit.modifiedChangedLineBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('diffEditor.insertedLineBackground'),
        0.7,
      ),
      light: TransparentTransform(
        ColorReference('diffEditor.insertedLineBackground'),
        0.7,
      ),
      hcDark: ColorReference('diffEditor.insertedLineBackground'),
      hcLight: ColorReference('diffEditor.insertedLineBackground'),
    ),
  ),
  ColorContribution(
    'inlineEdit.modifiedChangedTextBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.7,
      ),
      light: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.7,
      ),
      hcDark: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.7,
      ),
      hcLight: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.7,
      ),
    ),
  ),
  ColorContribution(
    'inlineEdit.gutterIndicator.primaryForeground',
    ColorDefaults(
      dark: ColorReference('button.foreground'),
      light: ColorReference('button.foreground'),
      hcDark: ColorReference('button.foreground'),
      hcLight: ColorReference('button.foreground'),
    ),
  ),
  ColorContribution(
    'inlineEdit.gutterIndicator.primaryBorder',
    ColorDefaults(
      dark: ColorReference('button.background'),
      light: ColorReference('button.background'),
      hcDark: ColorReference('button.background'),
      hcLight: ColorReference('button.background'),
    ),
  ),
  ColorContribution(
    'inlineEdit.gutterIndicator.primaryBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('inlineEdit.gutterIndicator.primaryBorder'),
        0.4,
      ),
      light: TransparentTransform(
        ColorReference('inlineEdit.gutterIndicator.primaryBorder'),
        0.5,
      ),
      hcDark: TransparentTransform(
        ColorReference('inlineEdit.gutterIndicator.primaryBorder'),
        0.4,
      ),
      hcLight: TransparentTransform(
        ColorReference('inlineEdit.gutterIndicator.primaryBorder'),
        0.5,
      ),
    ),
  ),
  ColorContribution(
    'inlineEdit.gutterIndicator.secondaryForeground',
    ColorDefaults(
      dark: ColorReference('editorHoverWidget.foreground'),
      light: ColorReference('editorHoverWidget.foreground'),
      hcDark: ColorReference('editorHoverWidget.foreground'),
      hcLight: ColorReference('editorHoverWidget.foreground'),
    ),
  ),
  ColorContribution(
    'inlineEdit.gutterIndicator.secondaryBorder',
    ColorDefaults(
      dark: ColorReference('editorHoverWidget.border'),
      light: ColorReference('editorHoverWidget.border'),
      hcDark: ColorReference('editorHoverWidget.border'),
      hcLight: ColorReference('editorHoverWidget.border'),
    ),
  ),
  ColorContribution(
    'inlineEdit.gutterIndicator.secondaryBackground',
    ColorDefaults(
      dark: ColorReference('editorHoverWidget.background'),
      light: ColorReference('editorHoverWidget.background'),
      hcDark: ColorReference('editorHoverWidget.background'),
      hcLight: ColorReference('editorHoverWidget.background'),
    ),
  ),
  ColorContribution(
    'inlineEdit.gutterIndicator.successfulForeground',
    ColorDefaults(
      dark: ColorReference('button.foreground'),
      light: ColorReference('button.foreground'),
      hcDark: ColorReference('button.foreground'),
      hcLight: ColorReference('button.foreground'),
    ),
  ),
  ColorContribution(
    'inlineEdit.gutterIndicator.successfulBorder',
    ColorDefaults(
      dark: ColorReference('button.background'),
      light: ColorReference('button.background'),
      hcDark: ColorReference('button.background'),
      hcLight: ColorReference('button.background'),
    ),
  ),
  ColorContribution(
    'inlineEdit.gutterIndicator.successfulBackground',
    ColorDefaults(
      dark: ColorReference('inlineEdit.gutterIndicator.successfulBorder'),
      light: ColorReference('inlineEdit.gutterIndicator.successfulBorder'),
      hcDark: ColorReference('inlineEdit.gutterIndicator.successfulBorder'),
      hcLight: ColorReference('inlineEdit.gutterIndicator.successfulBorder'),
    ),
  ),
  ColorContribution(
    'inlineEdit.gutterIndicator.background',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('tab.inactiveBackground'), 0.5),
      light: ColorLiteral('#5f5f5f18'),
      hcDark: TransparentTransform(
        ColorReference('tab.inactiveBackground'),
        0.5,
      ),
      hcLight: TransparentTransform(
        ColorReference('tab.inactiveBackground'),
        0.5,
      ),
    ),
  ),
  ColorContribution(
    'inlineEdit.originalBorder',
    ColorDefaults(
      dark: ColorReference('diffEditor.removedTextBackground'),
      light: ColorReference('diffEditor.removedTextBackground'),
      hcDark: ColorReference('diffEditor.removedTextBackground'),
      hcLight: ColorReference('diffEditor.removedTextBackground'),
    ),
  ),
  ColorContribution(
    'inlineEdit.modifiedBorder',
    ColorDefaults(
      dark: ColorReference('diffEditor.insertedTextBackground'),
      light: DarkenTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.6,
      ),
      hcDark: ColorReference('diffEditor.insertedTextBackground'),
      hcLight: ColorReference('diffEditor.insertedTextBackground'),
    ),
  ),
  ColorContribution(
    'inlineEdit.tabWillAcceptModifiedBorder',
    ColorDefaults(
      dark: DarkenTransform(ColorReference('inlineEdit.modifiedBorder'), 0.0),
      light: DarkenTransform(ColorReference('inlineEdit.modifiedBorder'), 0.0),
      hcDark: DarkenTransform(ColorReference('inlineEdit.modifiedBorder'), 0.0),
      hcLight: DarkenTransform(
        ColorReference('inlineEdit.modifiedBorder'),
        0.0,
      ),
    ),
  ),
  ColorContribution(
    'inlineEdit.tabWillAcceptOriginalBorder',
    ColorDefaults(
      dark: DarkenTransform(ColorReference('inlineEdit.originalBorder'), 0.0),
      light: DarkenTransform(ColorReference('inlineEdit.originalBorder'), 0.0),
      hcDark: DarkenTransform(ColorReference('inlineEdit.originalBorder'), 0.0),
      hcLight: DarkenTransform(
        ColorReference('inlineEdit.originalBorder'),
        0.0,
      ),
    ),
  ),
  // src/vs/editor/contrib/linkedEditing/browser/linkedEditing.ts
  ColorContribution(
    'editor.linkedEditingBackground',
    ColorDefaults(
      dark: ColorLiteral.rgba(255, 0, 0, 0.3),
      light: ColorLiteral.rgba(255, 0, 0, 0.3),
      hcDark: ColorLiteral.rgba(255, 0, 0, 0.3),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  // src/vs/editor/contrib/wordHighlighter/browser/highlightDecorations.ts
  ColorContribution(
    'editor.wordHighlightBackground',
    ColorDefaults(
      dark: ColorLiteral('#575757b8'),
      light: ColorLiteral('#57575740'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'editor.wordHighlightStrongBackground',
    ColorDefaults(
      dark: ColorLiteral('#004972b8'),
      light: ColorLiteral('#0e639c40'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'editor.wordHighlightTextBackground',
    ColorDefaults(
      dark: ColorReference('editor.wordHighlightBackground'),
      light: ColorReference('editor.wordHighlightBackground'),
      hcDark: ColorReference('editor.wordHighlightBackground'),
      hcLight: ColorReference('editor.wordHighlightBackground'),
    ),
  ),
  ColorContribution(
    'editor.wordHighlightBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'editor.wordHighlightStrongBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'editor.wordHighlightTextBorder',
    ColorDefaults(
      dark: ColorReference('editor.wordHighlightBorder'),
      light: ColorReference('editor.wordHighlightBorder'),
      hcDark: ColorReference('editor.wordHighlightBorder'),
      hcLight: ColorReference('editor.wordHighlightBorder'),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.wordHighlightForeground',
    ColorDefaults(
      dark: ColorLiteral('#a0a0a0cc'),
      light: ColorLiteral('#a0a0a0cc'),
      hcDark: ColorLiteral('#a0a0a0cc'),
      hcLight: ColorLiteral('#a0a0a0cc'),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.wordHighlightStrongForeground',
    ColorDefaults(
      dark: ColorLiteral('#c0a0c0cc'),
      light: ColorLiteral('#c0a0c0cc'),
      hcDark: ColorLiteral('#c0a0c0cc'),
      hcLight: ColorLiteral('#c0a0c0cc'),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.wordHighlightTextForeground',
    ColorDefaults(
      dark: ColorReference('editorOverviewRuler.selectionHighlightForeground'),
      light: ColorReference('editorOverviewRuler.selectionHighlightForeground'),
      hcDark: ColorReference(
        'editorOverviewRuler.selectionHighlightForeground',
      ),
      hcLight: ColorReference(
        'editorOverviewRuler.selectionHighlightForeground',
      ),
    ),
  ),
  // src/vs/editor/contrib/parameterHints/browser/parameterHintsWidget.ts
  ColorContribution(
    'editorHoverWidget.highlightForeground',
    ColorDefaults(
      dark: ColorReference('list.highlightForeground'),
      light: ColorReference('list.highlightForeground'),
      hcDark: ColorReference('list.highlightForeground'),
      hcLight: ColorReference('list.highlightForeground'),
    ),
  ),
  // src/vs/editor/contrib/placeholderText/browser/placeholderText.contribution.ts
  ColorContribution(
    'editor.placeholder.foreground',
    ColorDefaults(
      dark: ColorReference('editorGhostText.foreground'),
      light: ColorReference('editorGhostText.foreground'),
      hcDark: ColorReference('editorGhostText.foreground'),
      hcLight: ColorReference('editorGhostText.foreground'),
    ),
  ),
  // src/vs/workbench/common/theme.ts
  ColorContribution(
    'tab.activeBackground',
    ColorDefaults(
      dark: ColorReference('editor.background'),
      light: ColorReference('editor.background'),
      hcDark: ColorReference('editor.background'),
      hcLight: ColorReference('editor.background'),
    ),
  ),
  ColorContribution(
    'tab.unfocusedActiveBackground',
    ColorDefaults(
      dark: ColorReference('tab.activeBackground'),
      light: ColorReference('tab.activeBackground'),
      hcDark: ColorReference('tab.activeBackground'),
      hcLight: ColorReference('tab.activeBackground'),
    ),
  ),
  ColorContribution(
    'tab.inactiveBackground',
    ColorDefaults(
      dark: ColorLiteral('#2d2d2d'),
      light: ColorLiteral('#ececec'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'tab.unfocusedInactiveBackground',
    ColorDefaults(
      dark: ColorReference('tab.inactiveBackground'),
      light: ColorReference('tab.inactiveBackground'),
      hcDark: ColorReference('tab.inactiveBackground'),
      hcLight: ColorReference('tab.inactiveBackground'),
    ),
  ),
  ColorContribution(
    'tab.activeForeground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#333333'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'tab.inactiveForeground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('tab.activeForeground'), 0.5),
      light: TransparentTransform(ColorReference('tab.activeForeground'), 0.7),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'tab.unfocusedActiveForeground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('tab.activeForeground'), 0.5),
      light: TransparentTransform(ColorReference('tab.activeForeground'), 0.7),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'tab.unfocusedInactiveForeground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('tab.inactiveForeground'), 0.5),
      light: TransparentTransform(
        ColorReference('tab.inactiveForeground'),
        0.5,
      ),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution('tab.hoverBackground', null),
  ColorContribution(
    'tab.unfocusedHoverBackground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('tab.hoverBackground'), 0.5),
      light: TransparentTransform(ColorReference('tab.hoverBackground'), 0.7),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution('tab.hoverForeground', null),
  ColorContribution(
    'tab.unfocusedHoverForeground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('tab.hoverForeground'), 0.5),
      light: TransparentTransform(ColorReference('tab.hoverForeground'), 0.5),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'tab.border',
    ColorDefaults(
      dark: ColorLiteral('#252526'),
      light: ColorLiteral('#f3f3f3'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'tab.lastPinnedBorder',
    ColorDefaults(
      dark: ColorReference('tree.indentGuidesStroke'),
      light: ColorReference('tree.indentGuidesStroke'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution('tab.activeBorder', null),
  ColorContribution(
    'tab.unfocusedActiveBorder',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('tab.activeBorder'), 0.5),
      light: TransparentTransform(ColorReference('tab.activeBorder'), 0.7),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'tab.activeBorderTop',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: null,
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution(
    'tab.unfocusedActiveBorderTop',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('tab.activeBorderTop'), 0.5),
      light: TransparentTransform(ColorReference('tab.activeBorderTop'), 0.7),
      hcDark: null,
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution(
    'tab.selectedBorderTop',
    ColorDefaults(
      dark: ColorReference('focusBorder'),
      light: ColorReference('focusBorder'),
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'tab.selectedBackground',
    ColorDefaults(
      dark: ColorReference('list.inactiveSelectionBackground'),
      light: ColorReference('list.inactiveSelectionBackground'),
      hcDark: ColorReference('list.inactiveSelectionBackground'),
      hcLight: ColorReference('list.inactiveSelectionBackground'),
    ),
  ),
  ColorContribution(
    'tab.selectedForeground',
    ColorDefaults(
      dark: ColorReference('tab.activeForeground'),
      light: ColorReference('tab.activeForeground'),
      hcDark: ColorReference('tab.activeForeground'),
      hcLight: ColorReference('tab.activeForeground'),
    ),
  ),
  ColorContribution('tab.hoverBorder', null),
  ColorContribution(
    'tab.unfocusedHoverBorder',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('tab.hoverBorder'), 0.5),
      light: TransparentTransform(ColorReference('tab.hoverBorder'), 0.7),
      hcDark: null,
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'tab.dragAndDropBorder',
    ColorDefaults(
      dark: ColorReference('tab.activeForeground'),
      light: ColorReference('tab.activeForeground'),
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'tab.activeModifiedBorder',
    ColorDefaults(
      dark: ColorLiteral('#3399cc'),
      light: ColorLiteral('#33aaee'),
      hcDark: null,
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'tab.inactiveModifiedBorder',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('tab.activeModifiedBorder'),
        0.5,
      ),
      light: TransparentTransform(
        ColorReference('tab.activeModifiedBorder'),
        0.5,
      ),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'tab.unfocusedActiveModifiedBorder',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('tab.activeModifiedBorder'),
        0.5,
      ),
      light: TransparentTransform(
        ColorReference('tab.activeModifiedBorder'),
        0.7,
      ),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'tab.unfocusedInactiveModifiedBorder',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('tab.inactiveModifiedBorder'),
        0.5,
      ),
      light: TransparentTransform(
        ColorReference('tab.inactiveModifiedBorder'),
        0.5,
      ),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'editorPane.background',
    ColorDefaults(
      dark: ColorReference('editor.background'),
      light: ColorReference('editor.background'),
      hcDark: ColorReference('editor.background'),
      hcLight: ColorReference('editor.background'),
    ),
  ),
  ColorContribution('editorGroup.emptyBackground', null),
  ColorContribution(
    'editorGroup.focusedEmptyBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('focusBorder'),
      hcLight: ColorReference('focusBorder'),
    ),
  ),
  ColorContribution(
    'editorGroupHeader.tabsBackground',
    ColorDefaults(
      dark: ColorLiteral('#252526'),
      light: ColorLiteral('#f3f3f3'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'editorGroupHeader.connectedTabsBackground',
    ColorDefaults(
      dark: ColorReference('editorGroupHeader.tabsBackground'),
      light: ColorReference('editorGroupHeader.tabsBackground'),
      hcDark: ColorReference('editorGroupHeader.tabsBackground'),
      hcLight: ColorReference('editorGroupHeader.tabsBackground'),
    ),
  ),
  ColorContribution('editorGroupHeader.tabsBorder', null),
  ColorContribution(
    'editorGroupHeader.noTabsBackground',
    ColorDefaults(
      dark: ColorReference('editor.background'),
      light: ColorReference('editor.background'),
      hcDark: ColorReference('editor.background'),
      hcLight: ColorReference('editor.background'),
    ),
  ),
  ColorContribution(
    'editorGroupHeader.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'editorGroup.border',
    ColorDefaults(
      dark: ColorLiteral('#444444'),
      light: ColorLiteral('#e7e7e7'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'editorGroup.dropBackground',
    ColorDefaults(
      dark: ColorLiteral.rgba(83, 89, 93, 0.5),
      light: ColorLiteral('#2677cb2e'),
      hcDark: null,
      hcLight: ColorLiteral.rgba(15, 74, 133, 0.5),
    ),
  ),
  ColorContribution(
    'editorGroup.dropIntoPromptForeground',
    ColorDefaults(
      dark: ColorReference('editorWidget.foreground'),
      light: ColorReference('editorWidget.foreground'),
      hcDark: ColorReference('editorWidget.foreground'),
      hcLight: ColorReference('editorWidget.foreground'),
    ),
  ),
  ColorContribution(
    'editorGroup.dropIntoPromptBackground',
    ColorDefaults(
      dark: ColorReference('editorWidget.background'),
      light: ColorReference('editorWidget.background'),
      hcDark: ColorReference('editorWidget.background'),
      hcLight: ColorReference('editorWidget.background'),
    ),
  ),
  ColorContribution(
    'editorGroup.dropIntoPromptBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'sideBySideEditor.horizontalBorder',
    ColorDefaults(
      dark: ColorReference('editorGroup.border'),
      light: ColorReference('editorGroup.border'),
      hcDark: ColorReference('editorGroup.border'),
      hcLight: ColorReference('editorGroup.border'),
    ),
  ),
  ColorContribution(
    'sideBySideEditor.verticalBorder',
    ColorDefaults(
      dark: ColorReference('editorGroup.border'),
      light: ColorReference('editorGroup.border'),
      hcDark: ColorReference('editorGroup.border'),
      hcLight: ColorReference('editorGroup.border'),
    ),
  ),
  ColorContribution('outputView.background', null),
  ColorContribution(
    'outputViewStickyScroll.background',
    ColorDefaults(
      dark: ColorReference('outputView.background'),
      light: ColorReference('outputView.background'),
      hcDark: ColorReference('outputView.background'),
      hcLight: ColorReference('outputView.background'),
    ),
  ),
  ColorContribution(
    'banner.background',
    ColorDefaults(
      dark: ColorReference('list.activeSelectionBackground'),
      light: DarkenTransform(
        ColorReference('list.activeSelectionBackground'),
        0.3,
      ),
      hcDark: ColorReference('list.activeSelectionBackground'),
      hcLight: ColorReference('list.activeSelectionBackground'),
    ),
  ),
  ColorContribution(
    'banner.foreground',
    ColorDefaults(
      dark: ColorReference('list.activeSelectionForeground'),
      light: ColorReference('list.activeSelectionForeground'),
      hcDark: ColorReference('list.activeSelectionForeground'),
      hcLight: ColorReference('list.activeSelectionForeground'),
    ),
  ),
  ColorContribution(
    'banner.iconForeground',
    ColorDefaults(
      dark: ColorReference('editorInfo.foreground'),
      light: ColorReference('editorInfo.foreground'),
      hcDark: ColorReference('editorInfo.foreground'),
      hcLight: ColorReference('editorInfo.foreground'),
    ),
  ),
  ColorContribution(
    'statusBar.foreground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#ffffff'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('editor.foreground'),
    ),
  ),
  ColorContribution(
    'statusBar.noFolderForeground',
    ColorDefaults(
      dark: ColorReference('statusBar.foreground'),
      light: ColorReference('statusBar.foreground'),
      hcDark: ColorReference('statusBar.foreground'),
      hcLight: ColorReference('statusBar.foreground'),
    ),
  ),
  ColorContribution(
    'statusBar.background',
    ColorDefaults(
      dark: ColorLiteral('#007acc'),
      light: ColorLiteral('#007acc'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'statusBar.inactiveBackground',
    ColorDefaults(dark: null, light: null, hcDark: null, hcLight: null),
  ),
  ColorContribution(
    'statusBar.noFolderBackground',
    ColorDefaults(
      dark: ColorLiteral('#68217a'),
      light: ColorLiteral('#68217a'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'statusBar.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'statusBar.focusBorder',
    ColorDefaults(
      dark: ColorReference('statusBar.foreground'),
      light: ColorReference('statusBar.foreground'),
      hcDark: null,
      hcLight: ColorReference('statusBar.foreground'),
    ),
  ),
  ColorContribution(
    'statusBar.noFolderBorder',
    ColorDefaults(
      dark: ColorReference('statusBar.border'),
      light: ColorReference('statusBar.border'),
      hcDark: ColorReference('statusBar.border'),
      hcLight: ColorReference('statusBar.border'),
    ),
  ),
  ColorContribution(
    'statusBarItem.activeBackground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff2e'),
      light: ColorLiteral('#ffffff2e'),
      hcDark: ColorLiteral('#ffffff2e'),
      hcLight: ColorLiteral('#0000002e'),
    ),
  ),
  ColorContribution(
    'statusBarItem.focusBorder',
    ColorDefaults(
      dark: ColorReference('statusBar.foreground'),
      light: ColorReference('statusBar.foreground'),
      hcDark: null,
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'statusBarItem.hoverBackground',
    ColorDefaults(
      dark: ColorLiteral.rgba(255, 255, 255, 0.12),
      light: ColorLiteral.rgba(0, 0, 0, 0.12),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'statusBarItem.hoverForeground',
    ColorDefaults(
      dark: ColorReference('statusBar.foreground'),
      light: ColorReference('statusBar.foreground'),
      hcDark: ColorReference('statusBar.foreground'),
      hcLight: ColorReference('statusBar.foreground'),
    ),
  ),
  ColorContribution(
    'statusBarItem.compactHoverBackground',
    ColorDefaults(
      dark: ColorLiteral.rgba(255, 255, 255, 0.12),
      light: ColorLiteral.rgba(0, 0, 0, 0.12),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'statusBarItem.prominentForeground',
    ColorDefaults(
      dark: ColorReference('statusBar.foreground'),
      light: ColorReference('statusBar.foreground'),
      hcDark: ColorReference('statusBar.foreground'),
      hcLight: ColorReference('statusBar.foreground'),
    ),
  ),
  ColorContribution(
    'statusBarItem.prominentBackground',
    ColorDefaults(
      dark: ColorLiteral.rgba(0, 0, 0, 0.5),
      light: ColorLiteral.rgba(0, 0, 0, 0.5),
      hcDark: ColorLiteral.rgba(0, 0, 0, 0.5),
      hcLight: ColorLiteral.rgba(0, 0, 0, 0.5),
    ),
  ),
  ColorContribution(
    'statusBarItem.prominentHoverForeground',
    ColorDefaults(
      dark: ColorReference('statusBarItem.hoverForeground'),
      light: ColorReference('statusBarItem.hoverForeground'),
      hcDark: ColorReference('statusBarItem.hoverForeground'),
      hcLight: ColorReference('statusBarItem.hoverForeground'),
    ),
  ),
  ColorContribution(
    'statusBarItem.prominentHoverBackground',
    ColorDefaults(
      dark: ColorReference('statusBarItem.hoverBackground'),
      light: ColorReference('statusBarItem.hoverBackground'),
      hcDark: ColorReference('statusBarItem.hoverBackground'),
      hcLight: ColorReference('statusBarItem.hoverBackground'),
    ),
  ),
  ColorContribution(
    'statusBarItem.errorBackground',
    ColorDefaults(
      dark: DarkenTransform(ColorReference('errorForeground'), 0.4),
      light: DarkenTransform(ColorReference('errorForeground'), 0.4),
      hcDark: null,
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution(
    'statusBarItem.errorForeground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#ffffff'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'statusBarItem.errorHoverForeground',
    ColorDefaults(
      dark: ColorReference('statusBarItem.hoverForeground'),
      light: ColorReference('statusBarItem.hoverForeground'),
      hcDark: ColorReference('statusBarItem.hoverForeground'),
      hcLight: ColorReference('statusBarItem.hoverForeground'),
    ),
  ),
  ColorContribution(
    'statusBarItem.errorHoverBackground',
    ColorDefaults(
      dark: ColorReference('statusBarItem.hoverBackground'),
      light: ColorReference('statusBarItem.hoverBackground'),
      hcDark: ColorReference('statusBarItem.hoverBackground'),
      hcLight: ColorReference('statusBarItem.hoverBackground'),
    ),
  ),
  ColorContribution(
    'statusBarItem.warningBackground',
    ColorDefaults(
      dark: DarkenTransform(ColorReference('editorWarning.foreground'), 0.4),
      light: DarkenTransform(ColorReference('editorWarning.foreground'), 0.4),
      hcDark: null,
      hcLight: ColorLiteral('#895503'),
    ),
  ),
  ColorContribution(
    'statusBarItem.warningForeground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#ffffff'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'statusBarItem.warningHoverForeground',
    ColorDefaults(
      dark: ColorReference('statusBarItem.hoverForeground'),
      light: ColorReference('statusBarItem.hoverForeground'),
      hcDark: ColorReference('statusBarItem.hoverForeground'),
      hcLight: ColorReference('statusBarItem.hoverForeground'),
    ),
  ),
  ColorContribution(
    'statusBarItem.warningHoverBackground',
    ColorDefaults(
      dark: ColorReference('statusBarItem.hoverBackground'),
      light: ColorReference('statusBarItem.hoverBackground'),
      hcDark: ColorReference('statusBarItem.hoverBackground'),
      hcLight: ColorReference('statusBarItem.hoverBackground'),
    ),
  ),
  ColorContribution(
    'activityBar.background',
    ColorDefaults(
      dark: ColorLiteral('#333333'),
      light: ColorLiteral('#2c2c2c'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'activityBar.foreground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#ffffff'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('editor.foreground'),
    ),
  ),
  ColorContribution(
    'activityBar.inactiveForeground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('activityBar.foreground'), 0.4),
      light: TransparentTransform(
        ColorReference('activityBar.foreground'),
        0.4,
      ),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('editor.foreground'),
    ),
  ),
  ColorContribution(
    'activityBar.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'activityBar.activeBorder',
    ColorDefaults(
      dark: ColorReference('activityBar.foreground'),
      light: ColorReference('activityBar.foreground'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'activityBar.activeFocusBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: null,
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution('activityBar.activeBackground', null),
  ColorContribution(
    'activityBar.dropBorder',
    ColorDefaults(
      dark: ColorReference('activityBar.foreground'),
      light: ColorReference('activityBar.foreground'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'activityBarBadge.background',
    ColorDefaults(
      dark: ColorLiteral('#007acc'),
      light: ColorLiteral('#007acc'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  ColorContribution(
    'activityBarBadge.foreground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#ffffff'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'activityBarTop.foreground',
    ColorDefaults(
      dark: ColorLiteral('#e7e7e7'),
      light: ColorLiteral('#424242'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('editor.foreground'),
    ),
  ),
  ColorContribution(
    'activityBarTop.activeBorder',
    ColorDefaults(
      dark: ColorReference('activityBarTop.foreground'),
      light: ColorReference('activityBarTop.foreground'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution('activityBarTop.activeBackground', null),
  ColorContribution(
    'activityBarTop.inactiveForeground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('activityBarTop.foreground'),
        0.6,
      ),
      light: TransparentTransform(
        ColorReference('activityBarTop.foreground'),
        0.75,
      ),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('editor.foreground'),
    ),
  ),
  ColorContribution(
    'activityBarTop.dropBorder',
    ColorDefaults(
      dark: ColorReference('activityBarTop.foreground'),
      light: ColorReference('activityBarTop.foreground'),
      hcDark: ColorReference('activityBarTop.foreground'),
      hcLight: ColorReference('activityBarTop.foreground'),
    ),
  ),
  ColorContribution('activityBarTop.background', null),
  ColorContribution(
    'panel.background',
    ColorDefaults(
      dark: ColorReference('editor.background'),
      light: ColorReference('editor.background'),
      hcDark: ColorReference('editor.background'),
      hcLight: ColorReference('editor.background'),
    ),
  ),
  ColorContribution(
    'panel.border',
    ColorDefaults(
      dark: ColorLiteral.rgba(128, 128, 128, 0.35),
      light: ColorLiteral.rgba(128, 128, 128, 0.35),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'panelTitle.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('panel.border'),
      hcLight: ColorReference('panel.border'),
    ),
  ),
  ColorContribution(
    'panelTitle.activeForeground',
    ColorDefaults(
      dark: ColorLiteral('#e7e7e7'),
      light: ColorLiteral('#424242'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('editor.foreground'),
    ),
  ),
  ColorContribution(
    'panelTitle.inactiveForeground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('panelTitle.activeForeground'),
        0.6,
      ),
      light: TransparentTransform(
        ColorReference('panelTitle.activeForeground'),
        0.75,
      ),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('editor.foreground'),
    ),
  ),
  ColorContribution(
    'panelTitle.activeBorder',
    ColorDefaults(
      dark: ColorReference('panelTitle.activeForeground'),
      light: ColorReference('panelTitle.activeForeground'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution(
    'panelTitleBadge.background',
    ColorDefaults(
      dark: ColorReference('activityBarBadge.background'),
      light: ColorReference('activityBarBadge.background'),
      hcDark: ColorReference('activityBarBadge.background'),
      hcLight: ColorReference('activityBarBadge.background'),
    ),
  ),
  ColorContribution(
    'panelTitleBadge.foreground',
    ColorDefaults(
      dark: ColorReference('activityBarBadge.foreground'),
      light: ColorReference('activityBarBadge.foreground'),
      hcDark: ColorReference('activityBarBadge.foreground'),
      hcLight: ColorReference('activityBarBadge.foreground'),
    ),
  ),
  ColorContribution(
    'panelInput.border',
    ColorDefaults(
      dark: ColorReference('input.border'),
      light: ColorLiteral('#dddddd'),
      hcDark: ColorReference('input.border'),
      hcLight: ColorReference('input.border'),
    ),
  ),
  ColorContribution(
    'panel.dropBorder',
    ColorDefaults(
      dark: ColorReference('panelTitle.activeForeground'),
      light: ColorReference('panelTitle.activeForeground'),
      hcDark: ColorReference('panelTitle.activeForeground'),
      hcLight: ColorReference('panelTitle.activeForeground'),
    ),
  ),
  ColorContribution(
    'panelSection.dropBackground',
    ColorDefaults(
      dark: ColorReference('editorGroup.dropBackground'),
      light: ColorReference('editorGroup.dropBackground'),
      hcDark: ColorReference('editorGroup.dropBackground'),
      hcLight: ColorReference('editorGroup.dropBackground'),
    ),
  ),
  ColorContribution(
    'panelSectionHeader.background',
    ColorDefaults(
      dark: ColorLiteral('#80808033'),
      light: ColorLiteral('#80808033'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution('panelSectionHeader.foreground', null),
  ColorContribution(
    'panelSectionHeader.border',
    ColorDefaults(
      dark: ColorReference('contrastBorder'),
      light: ColorReference('contrastBorder'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'panelSection.border',
    ColorDefaults(
      dark: ColorReference('panel.border'),
      light: ColorReference('panel.border'),
      hcDark: ColorReference('panel.border'),
      hcLight: ColorReference('panel.border'),
    ),
  ),
  ColorContribution(
    'panelStickyScroll.background',
    ColorDefaults(
      dark: ColorReference('panel.background'),
      light: ColorReference('panel.background'),
      hcDark: ColorReference('panel.background'),
      hcLight: ColorReference('panel.background'),
    ),
  ),
  ColorContribution('panelStickyScroll.border', null),
  ColorContribution(
    'panelStickyScroll.shadow',
    ColorDefaults(
      dark: ColorReference('scrollbar.shadow'),
      light: ColorReference('scrollbar.shadow'),
      hcDark: ColorReference('scrollbar.shadow'),
      hcLight: ColorReference('scrollbar.shadow'),
    ),
  ),
  ColorContribution(
    'browser.border',
    ColorDefaults(
      dark: ColorReference('tab.border'),
      light: ColorReference('tab.border'),
      hcDark: ColorReference('tab.border'),
      hcLight: ColorReference('tab.border'),
    ),
  ),
  ColorContribution(
    'profileBadge.background',
    ColorDefaults(
      dark: ColorLiteral('#4d4d4d'),
      light: ColorLiteral('#c4c4c4'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#000000'),
    ),
  ),
  ColorContribution(
    'profileBadge.foreground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#333333'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'statusBarItem.remoteBackground',
    ColorDefaults(
      dark: ColorReference('activityBarBadge.background'),
      light: ColorReference('activityBarBadge.background'),
      hcDark: ColorReference('activityBarBadge.background'),
      hcLight: ColorReference('activityBarBadge.background'),
    ),
  ),
  ColorContribution(
    'statusBarItem.remoteForeground',
    ColorDefaults(
      dark: ColorReference('activityBarBadge.foreground'),
      light: ColorReference('activityBarBadge.foreground'),
      hcDark: ColorReference('activityBarBadge.foreground'),
      hcLight: ColorReference('activityBarBadge.foreground'),
    ),
  ),
  ColorContribution(
    'statusBarItem.remoteHoverForeground',
    ColorDefaults(
      dark: ColorReference('statusBarItem.hoverForeground'),
      light: ColorReference('statusBarItem.hoverForeground'),
      hcDark: ColorReference('statusBarItem.hoverForeground'),
      hcLight: ColorReference('statusBarItem.hoverForeground'),
    ),
  ),
  ColorContribution(
    'statusBarItem.remoteHoverBackground',
    ColorDefaults(
      dark: ColorReference('statusBarItem.hoverBackground'),
      light: ColorReference('statusBarItem.hoverBackground'),
      hcDark: ColorReference('statusBarItem.hoverBackground'),
      hcLight: null,
    ),
  ),
  ColorContribution(
    'statusBarItem.offlineBackground',
    ColorDefaults(
      dark: ColorLiteral('#6c1717'),
      light: ColorLiteral('#6c1717'),
      hcDark: ColorLiteral('#6c1717'),
      hcLight: ColorLiteral('#6c1717'),
    ),
  ),
  ColorContribution(
    'statusBarItem.offlineForeground',
    ColorDefaults(
      dark: ColorReference('statusBarItem.remoteForeground'),
      light: ColorReference('statusBarItem.remoteForeground'),
      hcDark: ColorReference('statusBarItem.remoteForeground'),
      hcLight: ColorReference('statusBarItem.remoteForeground'),
    ),
  ),
  ColorContribution(
    'statusBarItem.offlineHoverForeground',
    ColorDefaults(
      dark: ColorReference('statusBarItem.hoverForeground'),
      light: ColorReference('statusBarItem.hoverForeground'),
      hcDark: ColorReference('statusBarItem.hoverForeground'),
      hcLight: ColorReference('statusBarItem.hoverForeground'),
    ),
  ),
  ColorContribution(
    'statusBarItem.offlineHoverBackground',
    ColorDefaults(
      dark: ColorReference('statusBarItem.hoverBackground'),
      light: ColorReference('statusBarItem.hoverBackground'),
      hcDark: ColorReference('statusBarItem.hoverBackground'),
      hcLight: null,
    ),
  ),
  ColorContribution(
    'extensionBadge.remoteBackground',
    ColorDefaults(
      dark: ColorReference('activityBarBadge.background'),
      light: ColorReference('activityBarBadge.background'),
      hcDark: ColorReference('activityBarBadge.background'),
      hcLight: ColorReference('activityBarBadge.background'),
    ),
  ),
  ColorContribution(
    'extensionBadge.remoteForeground',
    ColorDefaults(
      dark: ColorReference('activityBarBadge.foreground'),
      light: ColorReference('activityBarBadge.foreground'),
      hcDark: ColorReference('activityBarBadge.foreground'),
      hcLight: ColorReference('activityBarBadge.foreground'),
    ),
  ),
  ColorContribution(
    'sideBar.background',
    ColorDefaults(
      dark: ColorLiteral('#252526'),
      light: ColorLiteral('#f3f3f3'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution('sideBar.foreground', null),
  ColorContribution(
    'sideBar.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'sideBarTitle.background',
    ColorDefaults(
      dark: ColorReference('sideBar.background'),
      light: ColorReference('sideBar.background'),
      hcDark: ColorReference('sideBar.background'),
      hcLight: ColorReference('sideBar.background'),
    ),
  ),
  ColorContribution(
    'sideBarTitle.foreground',
    ColorDefaults(
      dark: ColorReference('sideBar.foreground'),
      light: ColorReference('sideBar.foreground'),
      hcDark: ColorReference('sideBar.foreground'),
      hcLight: ColorReference('sideBar.foreground'),
    ),
  ),
  ColorContribution(
    'sideBarTitle.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('sideBar.border'),
      hcLight: ColorReference('sideBar.border'),
    ),
  ),
  ColorContribution(
    'sideBar.dropBackground',
    ColorDefaults(
      dark: ColorReference('editorGroup.dropBackground'),
      light: ColorReference('editorGroup.dropBackground'),
      hcDark: ColorReference('editorGroup.dropBackground'),
      hcLight: ColorReference('editorGroup.dropBackground'),
    ),
  ),
  ColorContribution(
    'sideBarSectionHeader.background',
    ColorDefaults(
      dark: ColorLiteral('#80808033'),
      light: ColorLiteral('#80808033'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'sideBarSectionHeader.foreground',
    ColorDefaults(
      dark: ColorReference('sideBar.foreground'),
      light: ColorReference('sideBar.foreground'),
      hcDark: ColorReference('sideBar.foreground'),
      hcLight: ColorReference('sideBar.foreground'),
    ),
  ),
  ColorContribution(
    'sideBarSectionHeader.border',
    ColorDefaults(
      dark: ColorReference('contrastBorder'),
      light: ColorReference('contrastBorder'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'sideBarActivityBarTop.border',
    ColorDefaults(
      dark: ColorReference('sideBarSectionHeader.border'),
      light: ColorReference('sideBarSectionHeader.border'),
      hcDark: ColorReference('sideBarSectionHeader.border'),
      hcLight: ColorReference('sideBarSectionHeader.border'),
    ),
  ),
  ColorContribution(
    'sideBarStickyScroll.background',
    ColorDefaults(
      dark: ColorReference('sideBar.background'),
      light: ColorReference('sideBar.background'),
      hcDark: ColorReference('sideBar.background'),
      hcLight: ColorReference('sideBar.background'),
    ),
  ),
  ColorContribution('sideBarStickyScroll.border', null),
  ColorContribution(
    'sideBarStickyScroll.shadow',
    ColorDefaults(
      dark: ColorReference('scrollbar.shadow'),
      light: ColorReference('scrollbar.shadow'),
      hcDark: ColorReference('scrollbar.shadow'),
      hcLight: ColorReference('scrollbar.shadow'),
    ),
  ),
  ColorContribution(
    'surface.background',
    ColorDefaults(
      dark: ColorReference('sideBar.background'),
      light: ColorReference('editor.background'),
      hcDark: ColorReference('sideBar.background'),
      hcLight: ColorReference('sideBar.background'),
    ),
  ),
  ColorContribution(
    'surface.foreground',
    ColorDefaults(
      dark: ColorReference('sideBar.foreground'),
      light: ColorReference('sideBar.foreground'),
      hcDark: ColorReference('sideBar.foreground'),
      hcLight: ColorReference('sideBar.foreground'),
    ),
  ),
  ColorContribution(
    'surface.border',
    ColorDefaults(
      dark: OpaqueTransform(
        TransparentTransform(ColorReference('foreground'), 0.15),
        ColorReference('surface.background'),
      ),
      light: OpaqueTransform(
        TransparentTransform(ColorReference('foreground'), 0.15),
        ColorReference('surface.background'),
      ),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'editor.border',
    ColorDefaults(
      dark: ColorReference('surface.border'),
      light: ColorReference('surface.border'),
      hcDark: ColorReference('surface.border'),
      hcLight: ColorReference('surface.border'),
    ),
  ),
  ColorContribution(
    'modernPanel.border',
    ColorDefaults(
      dark: ColorReference('surface.border'),
      light: ColorReference('surface.border'),
      hcDark: ColorReference('surface.border'),
      hcLight: ColorReference('surface.border'),
    ),
  ),
  ColorContribution(
    'modernSash.gripForeground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('foreground'), 0.4),
      light: TransparentTransform(ColorReference('foreground'), 0.4),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'modernTab.activeBackground',
    ColorDefaults(
      dark: ColorReference('list.inactiveSelectionBackground'),
      light: ColorReference('list.inactiveSelectionBackground'),
      hcDark: ColorReference('list.inactiveSelectionBackground'),
      hcLight: ColorReference('list.inactiveSelectionBackground'),
    ),
  ),
  ColorContribution(
    'modernTab.activeForeground',
    ColorDefaults(
      dark: OneOfTransform([
        ColorReference('list.inactiveSelectionForeground'),
        ColorReference('foreground'),
      ]),
      light: OneOfTransform([
        ColorReference('list.inactiveSelectionForeground'),
        ColorReference('foreground'),
      ]),
      hcDark: OneOfTransform([
        ColorReference('list.inactiveSelectionForeground'),
        ColorReference('foreground'),
      ]),
      hcLight: OneOfTransform([
        ColorReference('list.inactiveSelectionForeground'),
        ColorReference('foreground'),
      ]),
    ),
  ),
  ColorContribution(
    'modernTab.hoverBackground',
    ColorDefaults(
      dark: ColorReference('list.hoverBackground'),
      light: ColorReference('list.hoverBackground'),
      hcDark: ColorReference('list.hoverBackground'),
      hcLight: ColorReference('list.hoverBackground'),
    ),
  ),
  ColorContribution(
    'modernTab.hoverForeground',
    ColorDefaults(
      dark: OneOfTransform([
        ColorReference('list.hoverForeground'),
        ColorReference('foreground'),
      ]),
      light: OneOfTransform([
        ColorReference('list.hoverForeground'),
        ColorReference('foreground'),
      ]),
      hcDark: OneOfTransform([
        ColorReference('list.hoverForeground'),
        ColorReference('foreground'),
      ]),
      hcLight: OneOfTransform([
        ColorReference('list.hoverForeground'),
        ColorReference('foreground'),
      ]),
    ),
  ),
  ColorContribution(
    'modernEditorTab.activeBackground',
    ColorDefaults(
      dark: ColorReference('modernTab.activeBackground'),
      light: ColorReference('modernTab.activeBackground'),
      hcDark: ColorReference('modernTab.activeBackground'),
      hcLight: ColorReference('modernTab.activeBackground'),
    ),
  ),
  ColorContribution(
    'modernEditorTab.activeActionBackground',
    ColorDefaults(
      dark: OpaqueTransform(
        ColorReference('modernEditorTab.activeBackground'),
        ColorReference('editor.background'),
      ),
      light: OpaqueTransform(
        ColorReference('modernEditorTab.activeBackground'),
        ColorReference('editor.background'),
      ),
      hcDark: OpaqueTransform(
        ColorReference('modernEditorTab.activeBackground'),
        ColorReference('editor.background'),
      ),
      hcLight: OpaqueTransform(
        ColorReference('modernEditorTab.activeBackground'),
        ColorReference('editor.background'),
      ),
    ),
  ),
  ColorContribution(
    'modernEditorTab.activeForeground',
    ColorDefaults(
      dark: ColorReference('modernTab.activeForeground'),
      light: ColorReference('modernTab.activeForeground'),
      hcDark: ColorReference('modernTab.activeForeground'),
      hcLight: ColorReference('modernTab.activeForeground'),
    ),
  ),
  ColorContribution(
    'modernEditorTab.inactiveBackground',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'modernEditorTab.hoverBackground',
    ColorDefaults(
      dark: ColorReference('modernTab.hoverBackground'),
      light: ColorReference('modernTab.hoverBackground'),
      hcDark: ColorReference('modernTab.hoverBackground'),
      hcLight: ColorReference('modernTab.hoverBackground'),
    ),
  ),
  ColorContribution(
    'modernEditorTab.hoverActionBackground',
    ColorDefaults(
      dark: OpaqueTransform(
        ColorReference('modernEditorTab.hoverBackground'),
        ColorReference('editor.background'),
      ),
      light: OpaqueTransform(
        ColorReference('modernEditorTab.hoverBackground'),
        ColorReference('editor.background'),
      ),
      hcDark: OpaqueTransform(
        ColorReference('modernEditorTab.hoverBackground'),
        ColorReference('editor.background'),
      ),
      hcLight: OpaqueTransform(
        ColorReference('modernEditorTab.hoverBackground'),
        ColorReference('editor.background'),
      ),
    ),
  ),
  ColorContribution(
    'modernEditorTab.hoverForeground',
    ColorDefaults(
      dark: ColorReference('modernTab.hoverForeground'),
      light: ColorReference('modernTab.hoverForeground'),
      hcDark: ColorReference('modernTab.hoverForeground'),
      hcLight: ColorReference('modernTab.hoverForeground'),
    ),
  ),
  ColorContribution(
    'modernEditorTab.activeHoverBackground',
    ColorDefaults(
      dark: ColorReference('modernEditorTab.hoverBackground'),
      light: ColorReference('modernEditorTab.hoverBackground'),
      hcDark: ColorReference('modernEditorTab.hoverBackground'),
      hcLight: ColorReference('modernEditorTab.hoverBackground'),
    ),
  ),
  ColorContribution(
    'modernEditorTab.activeHoverActionBackground',
    ColorDefaults(
      dark: OpaqueTransform(
        ColorReference('modernEditorTab.activeHoverBackground'),
        ColorReference('editor.background'),
      ),
      light: OpaqueTransform(
        ColorReference('modernEditorTab.activeHoverBackground'),
        ColorReference('editor.background'),
      ),
      hcDark: OpaqueTransform(
        ColorReference('modernEditorTab.activeHoverBackground'),
        ColorReference('editor.background'),
      ),
      hcLight: OpaqueTransform(
        ColorReference('modernEditorTab.activeHoverBackground'),
        ColorReference('editor.background'),
      ),
    ),
  ),
  ColorContribution(
    'modernEditorTab.selectedActionBackground',
    ColorDefaults(
      dark: OpaqueTransform(
        ColorReference('tab.selectedBackground'),
        ColorReference('editor.background'),
      ),
      light: OpaqueTransform(
        ColorReference('tab.selectedBackground'),
        ColorReference('editor.background'),
      ),
      hcDark: OpaqueTransform(
        ColorReference('tab.selectedBackground'),
        ColorReference('editor.background'),
      ),
      hcLight: OpaqueTransform(
        ColorReference('tab.selectedBackground'),
        ColorReference('editor.background'),
      ),
    ),
  ),
  ColorContribution(
    'modernActivityBar.background',
    ColorDefaults(
      dark: ColorReference('activityBar.background'),
      light: ColorReference('activityBar.background'),
      hcDark: ColorReference('activityBar.background'),
      hcLight: ColorReference('activityBar.background'),
    ),
  ),
  ColorContribution(
    'modernActivityBar.inactiveBackground',
    ColorDefaults(
      dark: ColorReference('modernActivityBar.background'),
      light: ColorReference('modernActivityBar.background'),
      hcDark: ColorReference('modernActivityBar.background'),
      hcLight: ColorReference('modernActivityBar.background'),
    ),
  ),
  ColorContribution('modernActivityBar.activeBackground', null),
  ColorContribution('modernActivityBar.activeForeground', null),
  ColorContribution('modernActivityBar.hoverBackground', null),
  ColorContribution('modernActivityBar.hoverForeground', null),
  ColorContribution(
    'modernActivityBarItem.activeBackground',
    ColorDefaults(
      dark: OneOfTransform([
        ColorReference('modernActivityBar.activeBackground'),
        ColorReference('modernTab.activeBackground'),
      ]),
      light: OneOfTransform([
        ColorReference('modernActivityBar.activeBackground'),
        ColorReference('modernTab.activeBackground'),
      ]),
      hcDark: OneOfTransform([
        ColorReference('modernActivityBar.activeBackground'),
        ColorReference('modernTab.activeBackground'),
      ]),
      hcLight: OneOfTransform([
        ColorReference('modernActivityBar.activeBackground'),
        ColorReference('modernTab.activeBackground'),
      ]),
    ),
  ),
  ColorContribution(
    'modernActivityBarItem.activeForeground',
    ColorDefaults(
      dark: OneOfTransform([
        ColorReference('modernActivityBar.activeForeground'),
        ColorReference('modernTab.activeForeground'),
      ]),
      light: OneOfTransform([
        ColorReference('modernActivityBar.activeForeground'),
        ColorReference('modernTab.activeForeground'),
      ]),
      hcDark: OneOfTransform([
        ColorReference('modernActivityBar.activeForeground'),
        ColorReference('modernTab.activeForeground'),
      ]),
      hcLight: OneOfTransform([
        ColorReference('modernActivityBar.activeForeground'),
        ColorReference('modernTab.activeForeground'),
      ]),
    ),
  ),
  ColorContribution(
    'modernActivityBarItem.hoverBackground',
    ColorDefaults(
      dark: OneOfTransform([
        ColorReference('modernActivityBar.hoverBackground'),
        ColorReference('modernTab.hoverBackground'),
      ]),
      light: OneOfTransform([
        ColorReference('modernActivityBar.hoverBackground'),
        ColorReference('modernTab.hoverBackground'),
      ]),
      hcDark: OneOfTransform([
        ColorReference('modernActivityBar.hoverBackground'),
        ColorReference('modernTab.hoverBackground'),
      ]),
      hcLight: OneOfTransform([
        ColorReference('modernActivityBar.hoverBackground'),
        ColorReference('modernTab.hoverBackground'),
      ]),
    ),
  ),
  ColorContribution(
    'modernActivityBarItem.hoverForeground',
    ColorDefaults(
      dark: OneOfTransform([
        ColorReference('modernActivityBar.hoverForeground'),
        ColorReference('modernTab.hoverForeground'),
      ]),
      light: OneOfTransform([
        ColorReference('modernActivityBar.hoverForeground'),
        ColorReference('modernTab.hoverForeground'),
      ]),
      hcDark: OneOfTransform([
        ColorReference('modernActivityBar.hoverForeground'),
        ColorReference('modernTab.hoverForeground'),
      ]),
      hcLight: OneOfTransform([
        ColorReference('modernActivityBar.hoverForeground'),
        ColorReference('modernTab.hoverForeground'),
      ]),
    ),
  ),
  ColorContribution(
    'modernActivityBar.border',
    ColorDefaults(
      dark: ColorReference('surface.border'),
      light: ColorReference('surface.border'),
      hcDark: ColorReference('surface.border'),
      hcLight: ColorReference('surface.border'),
    ),
  ),
  ColorContribution(
    'titleBar.activeForeground',
    ColorDefaults(
      dark: ColorLiteral('#cccccc'),
      light: ColorLiteral('#333333'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'titleBar.inactiveForeground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('titleBar.activeForeground'),
        0.6,
      ),
      light: TransparentTransform(
        ColorReference('titleBar.activeForeground'),
        0.6,
      ),
      hcDark: null,
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'titleBar.activeBackground',
    ColorDefaults(
      dark: ColorLiteral('#3c3c3c'),
      light: ColorLiteral('#dddddd'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'titleBar.inactiveBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('titleBar.activeBackground'),
        0.6,
      ),
      light: TransparentTransform(
        ColorReference('titleBar.activeBackground'),
        0.6,
      ),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'modernUI.shellBackground',
    ColorDefaults(
      dark: ColorReference('titleBar.activeBackground'),
      light: ColorReference('titleBar.activeBackground'),
      hcDark: ColorReference('titleBar.activeBackground'),
      hcLight: ColorReference('titleBar.activeBackground'),
    ),
  ),
  ColorContribution(
    'modernUI.inactiveShellBackground',
    ColorDefaults(
      dark: ColorReference('titleBar.inactiveBackground'),
      light: ColorReference('titleBar.inactiveBackground'),
      hcDark: ColorReference('titleBar.inactiveBackground'),
      hcLight: ColorReference('titleBar.inactiveBackground'),
    ),
  ),
  ColorContribution(
    'titleBar.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'menubar.selectionForeground',
    ColorDefaults(
      dark: ColorReference('titleBar.activeForeground'),
      light: ColorReference('titleBar.activeForeground'),
      hcDark: ColorReference('titleBar.activeForeground'),
      hcLight: ColorReference('titleBar.activeForeground'),
    ),
  ),
  ColorContribution(
    'menubar.selectionBackground',
    ColorDefaults(
      dark: ColorReference('toolbar.hoverBackground'),
      light: ColorReference('toolbar.hoverBackground'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'menubar.selectionBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'commandCenter.foreground',
    ColorDefaults(
      dark: ColorReference('titleBar.activeForeground'),
      light: ColorReference('titleBar.activeForeground'),
      hcDark: ColorReference('titleBar.activeForeground'),
      hcLight: ColorReference('titleBar.activeForeground'),
    ),
  ),
  ColorContribution(
    'commandCenter.activeForeground',
    ColorDefaults(
      dark: ColorReference('menubar.selectionForeground'),
      light: ColorReference('menubar.selectionForeground'),
      hcDark: ColorReference('menubar.selectionForeground'),
      hcLight: ColorReference('menubar.selectionForeground'),
    ),
  ),
  ColorContribution(
    'commandCenter.inactiveForeground',
    ColorDefaults(
      dark: ColorReference('titleBar.inactiveForeground'),
      light: ColorReference('titleBar.inactiveForeground'),
      hcDark: ColorReference('titleBar.inactiveForeground'),
      hcLight: ColorReference('titleBar.inactiveForeground'),
    ),
  ),
  ColorContribution(
    'commandCenter.background',
    ColorDefaults(
      dark: ColorLiteral.rgba(255, 255, 255, 0.05),
      light: ColorLiteral.rgba(0, 0, 0, 0.05),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'commandCenter.activeBackground',
    ColorDefaults(
      dark: ColorLiteral.rgba(255, 255, 255, 0.08),
      light: ColorLiteral.rgba(0, 0, 0, 0.08),
      hcDark: ColorReference('menubar.selectionBackground'),
      hcLight: ColorReference('menubar.selectionBackground'),
    ),
  ),
  ColorContribution(
    'commandCenter.border',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('titleBar.activeForeground'),
        0.2,
      ),
      light: TransparentTransform(
        ColorReference('titleBar.activeForeground'),
        0.2,
      ),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'commandCenter.activeBorder',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('titleBar.activeForeground'),
        0.3,
      ),
      light: TransparentTransform(
        ColorReference('titleBar.activeForeground'),
        0.3,
      ),
      hcDark: ColorReference('titleBar.activeForeground'),
      hcLight: ColorReference('titleBar.activeForeground'),
    ),
  ),
  ColorContribution(
    'commandCenter.inactiveBorder',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('titleBar.inactiveForeground'),
        0.25,
      ),
      light: TransparentTransform(
        ColorReference('titleBar.inactiveForeground'),
        0.25,
      ),
      hcDark: TransparentTransform(
        ColorReference('titleBar.inactiveForeground'),
        0.25,
      ),
      hcLight: TransparentTransform(
        ColorReference('titleBar.inactiveForeground'),
        0.25,
      ),
    ),
  ),
  ColorContribution(
    'notificationCenter.border',
    ColorDefaults(
      dark: ColorReference('widget.border'),
      light: ColorReference('widget.border'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'notificationToast.border',
    ColorDefaults(
      dark: ColorReference('widget.border'),
      light: ColorReference('widget.border'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'notifications.foreground',
    ColorDefaults(
      dark: ColorReference('editorWidget.foreground'),
      light: ColorReference('editorWidget.foreground'),
      hcDark: ColorReference('editorWidget.foreground'),
      hcLight: ColorReference('editorWidget.foreground'),
    ),
  ),
  ColorContribution(
    'notifications.background',
    ColorDefaults(
      dark: ColorReference('editorWidget.background'),
      light: ColorReference('editorWidget.background'),
      hcDark: ColorReference('editorWidget.background'),
      hcLight: ColorReference('editorWidget.background'),
    ),
  ),
  ColorContribution(
    'notificationLink.foreground',
    ColorDefaults(
      dark: ColorReference('textLink.foreground'),
      light: ColorReference('textLink.foreground'),
      hcDark: ColorReference('textLink.foreground'),
      hcLight: ColorReference('textLink.foreground'),
    ),
  ),
  ColorContribution('notificationCenterHeader.foreground', null),
  ColorContribution(
    'notificationCenterHeader.background',
    ColorDefaults(
      dark: LightenTransform(ColorReference('notifications.background'), 0.3),
      light: DarkenTransform(ColorReference('notifications.background'), 0.05),
      hcDark: ColorReference('notifications.background'),
      hcLight: ColorReference('notifications.background'),
    ),
  ),
  ColorContribution(
    'notifications.border',
    ColorDefaults(
      dark: ColorReference('notificationCenterHeader.background'),
      light: ColorReference('notificationCenterHeader.background'),
      hcDark: ColorReference('notificationCenterHeader.background'),
      hcLight: ColorReference('notificationCenterHeader.background'),
    ),
  ),
  ColorContribution(
    'notificationsErrorIcon.foreground',
    ColorDefaults(
      dark: ColorReference('editorError.foreground'),
      light: ColorReference('editorError.foreground'),
      hcDark: ColorReference('editorError.foreground'),
      hcLight: ColorReference('editorError.foreground'),
    ),
  ),
  ColorContribution(
    'notificationsWarningIcon.foreground',
    ColorDefaults(
      dark: ColorReference('editorWarning.foreground'),
      light: ColorReference('editorWarning.foreground'),
      hcDark: ColorReference('editorWarning.foreground'),
      hcLight: ColorReference('editorWarning.foreground'),
    ),
  ),
  ColorContribution(
    'notificationsInfoIcon.foreground',
    ColorDefaults(
      dark: ColorReference('editorInfo.foreground'),
      light: ColorReference('editorInfo.foreground'),
      hcDark: ColorReference('editorInfo.foreground'),
      hcLight: ColorReference('editorInfo.foreground'),
    ),
  ),
  ColorContribution(
    'window.activeBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'window.inactiveBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  // src/vs/workbench/contrib/chat/browser/agentSessions/agentSessions.ts
  ColorContribution(
    'agentSessionReadIndicator.foreground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('foreground'), 0.2),
      light: TransparentTransform(ColorReference('foreground'), 0.2),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'agentSessionSelectedBadge.border',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('list.activeSelectionForeground'),
        0.3,
      ),
      light: TransparentTransform(
        ColorReference('list.activeSelectionForeground'),
        0.3,
      ),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'agentSessionSelectedUnfocusedBadge.border',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('foreground'), 0.3),
      light: TransparentTransform(ColorReference('foreground'), 0.3),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  // src/vs/workbench/contrib/scm/common/quickDiff.ts
  ColorContribution(
    'editorGutter.modifiedBackground',
    ColorDefaults(
      dark: ColorLiteral('#1b81a8'),
      light: ColorLiteral('#2090d3'),
      hcDark: ColorLiteral('#1b81a8'),
      hcLight: ColorLiteral('#2090d3'),
    ),
  ),
  ColorContribution(
    'editorGutter.modifiedSecondaryBackground',
    ColorDefaults(
      dark: DarkenTransform(
        ColorReference('editorGutter.modifiedBackground'),
        0.5,
      ),
      light: LightenTransform(
        ColorReference('editorGutter.modifiedBackground'),
        0.7,
      ),
      hcDark: ColorLiteral('#1b81a8'),
      hcLight: ColorLiteral('#2090d3'),
    ),
  ),
  ColorContribution(
    'editorGutter.addedBackground',
    ColorDefaults(
      dark: ColorLiteral('#487e02'),
      light: ColorLiteral('#48985d'),
      hcDark: ColorLiteral('#487e02'),
      hcLight: ColorLiteral('#48985d'),
    ),
  ),
  ColorContribution(
    'editorGutter.addedSecondaryBackground',
    ColorDefaults(
      dark: DarkenTransform(
        ColorReference('editorGutter.addedBackground'),
        0.5,
      ),
      light: LightenTransform(
        ColorReference('editorGutter.addedBackground'),
        0.7,
      ),
      hcDark: ColorLiteral('#487e02'),
      hcLight: ColorLiteral('#48985d'),
    ),
  ),
  ColorContribution(
    'editorGutter.deletedBackground',
    ColorDefaults(
      dark: ColorReference('editorError.foreground'),
      light: ColorReference('editorError.foreground'),
      hcDark: ColorReference('editorError.foreground'),
      hcLight: ColorReference('editorError.foreground'),
    ),
  ),
  ColorContribution(
    'editorGutter.deletedSecondaryBackground',
    ColorDefaults(
      dark: DarkenTransform(
        ColorReference('editorGutter.deletedBackground'),
        0.4,
      ),
      light: LightenTransform(
        ColorReference('editorGutter.deletedBackground'),
        0.3,
      ),
      hcDark: ColorLiteral('#f48771'),
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution(
    'minimapGutter.modifiedBackground',
    ColorDefaults(
      dark: ColorReference('editorGutter.modifiedBackground'),
      light: ColorReference('editorGutter.modifiedBackground'),
      hcDark: ColorReference('editorGutter.modifiedBackground'),
      hcLight: ColorReference('editorGutter.modifiedBackground'),
    ),
  ),
  ColorContribution(
    'minimapGutter.addedBackground',
    ColorDefaults(
      dark: ColorReference('editorGutter.addedBackground'),
      light: ColorReference('editorGutter.addedBackground'),
      hcDark: ColorReference('editorGutter.addedBackground'),
      hcLight: ColorReference('editorGutter.addedBackground'),
    ),
  ),
  ColorContribution(
    'minimapGutter.deletedBackground',
    ColorDefaults(
      dark: ColorReference('editorGutter.deletedBackground'),
      light: ColorReference('editorGutter.deletedBackground'),
      hcDark: ColorReference('editorGutter.deletedBackground'),
      hcLight: ColorReference('editorGutter.deletedBackground'),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.modifiedForeground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editorGutter.modifiedBackground'),
        0.6,
      ),
      light: TransparentTransform(
        ColorReference('editorGutter.modifiedBackground'),
        0.6,
      ),
      hcDark: TransparentTransform(
        ColorReference('editorGutter.modifiedBackground'),
        0.6,
      ),
      hcLight: TransparentTransform(
        ColorReference('editorGutter.modifiedBackground'),
        0.6,
      ),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.addedForeground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editorGutter.addedBackground'),
        0.6,
      ),
      light: TransparentTransform(
        ColorReference('editorGutter.addedBackground'),
        0.6,
      ),
      hcDark: TransparentTransform(
        ColorReference('editorGutter.addedBackground'),
        0.6,
      ),
      hcLight: TransparentTransform(
        ColorReference('editorGutter.addedBackground'),
        0.6,
      ),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.deletedForeground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editorGutter.deletedBackground'),
        0.6,
      ),
      light: TransparentTransform(
        ColorReference('editorGutter.deletedBackground'),
        0.6,
      ),
      hcDark: TransparentTransform(
        ColorReference('editorGutter.deletedBackground'),
        0.6,
      ),
      hcLight: TransparentTransform(
        ColorReference('editorGutter.deletedBackground'),
        0.6,
      ),
    ),
  ),
  ColorContribution(
    'editorGutter.itemGlyphForeground',
    ColorDefaults(
      dark: ColorReference('editor.foreground'),
      light: ColorReference('editor.foreground'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'editorGutter.itemBackground',
    ColorDefaults(
      dark: OpaqueTransform(
        ColorReference('list.inactiveSelectionBackground'),
        ColorReference('editor.background'),
      ),
      light: DarkenTransform(
        OpaqueTransform(
          ColorReference('list.inactiveSelectionBackground'),
          ColorReference('editor.background'),
        ),
        0.05,
      ),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#000000'),
    ),
  ),
  // src/vs/workbench/contrib/terminal/common/terminalColorRegistry.ts
  ColorContribution('terminal.background', null),
  ColorContribution(
    'terminal.foreground',
    ColorDefaults(
      dark: ColorLiteral('#cccccc'),
      light: ColorLiteral('#333333'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution('terminalCursor.foreground', null),
  ColorContribution('terminalCursor.background', null),
  ColorContribution(
    'terminal.selectionBackground',
    ColorDefaults(
      dark: ColorReference('editor.selectionBackground'),
      light: ColorReference('editor.selectionBackground'),
      hcDark: ColorReference('editor.selectionBackground'),
      hcLight: ColorReference('editor.selectionBackground'),
    ),
  ),
  ColorContribution(
    'terminal.inactiveSelectionBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('terminal.selectionBackground'),
        0.5,
      ),
      light: TransparentTransform(
        ColorReference('terminal.selectionBackground'),
        0.5,
      ),
      hcDark: TransparentTransform(
        ColorReference('terminal.selectionBackground'),
        0.7,
      ),
      hcLight: TransparentTransform(
        ColorReference('terminal.selectionBackground'),
        0.5,
      ),
    ),
  ),
  ColorContribution(
    'terminal.selectionForeground',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'terminalCommandDecoration.defaultBackground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff40'),
      light: ColorLiteral('#00000040'),
      hcDark: ColorLiteral('#ffffff80'),
      hcLight: ColorLiteral('#00000040'),
    ),
  ),
  ColorContribution(
    'terminalCommandDecoration.successBackground',
    ColorDefaults(
      dark: ColorLiteral('#1b81a8'),
      light: ColorLiteral('#2090d3'),
      hcDark: ColorLiteral('#1b81a8'),
      hcLight: ColorLiteral('#007100'),
    ),
  ),
  ColorContribution(
    'terminalCommandDecoration.errorBackground',
    ColorDefaults(
      dark: ColorLiteral('#f14c4c'),
      light: ColorLiteral('#e51400'),
      hcDark: ColorLiteral('#f14c4c'),
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution(
    'terminalOverviewRuler.cursorForeground',
    ColorDefaults(
      dark: ColorLiteral('#a0a0a0cc'),
      light: ColorLiteral('#a0a0a0cc'),
      hcDark: ColorLiteral('#a0a0a0cc'),
      hcLight: ColorLiteral('#a0a0a0cc'),
    ),
  ),
  ColorContribution(
    'terminal.border',
    ColorDefaults(
      dark: ColorReference('panel.border'),
      light: ColorReference('panel.border'),
      hcDark: ColorReference('panel.border'),
      hcLight: ColorReference('panel.border'),
    ),
  ),
  ColorContribution(
    'terminalOverviewRuler.border',
    ColorDefaults(
      dark: ColorReference('editorOverviewRuler.border'),
      light: ColorReference('editorOverviewRuler.border'),
      hcDark: ColorReference('editorOverviewRuler.border'),
      hcLight: ColorReference('editorOverviewRuler.border'),
    ),
  ),
  ColorContribution(
    'terminal.findMatchBackground',
    ColorDefaults(
      dark: ColorReference('editor.findMatchBackground'),
      light: ColorReference('editor.findMatchBackground'),
      hcDark: null,
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  ColorContribution(
    'terminal.hoverHighlightBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editor.hoverHighlightBackground'),
        0.5,
      ),
      light: TransparentTransform(
        ColorReference('editor.hoverHighlightBackground'),
        0.5,
      ),
      hcDark: TransparentTransform(
        ColorReference('editor.hoverHighlightBackground'),
        0.5,
      ),
      hcLight: TransparentTransform(
        ColorReference('editor.hoverHighlightBackground'),
        0.5,
      ),
    ),
  ),
  ColorContribution(
    'terminal.findMatchBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorLiteral('#f38518'),
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  ColorContribution(
    'terminal.findMatchHighlightBackground',
    ColorDefaults(
      dark: ColorReference('editor.findMatchHighlightBackground'),
      light: ColorReference('editor.findMatchHighlightBackground'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'terminal.findMatchHighlightBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorLiteral('#f38518'),
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  ColorContribution(
    'terminalOverviewRuler.findMatchForeground',
    ColorDefaults(
      dark: ColorReference('editorOverviewRuler.findMatchForeground'),
      light: ColorReference('editorOverviewRuler.findMatchForeground'),
      hcDark: ColorLiteral('#f38518'),
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  ColorContribution(
    'terminal.dropBackground',
    ColorDefaults(
      dark: ColorReference('editorGroup.dropBackground'),
      light: ColorReference('editorGroup.dropBackground'),
      hcDark: ColorReference('editorGroup.dropBackground'),
      hcLight: ColorReference('editorGroup.dropBackground'),
    ),
  ),
  ColorContribution(
    'terminal.tab.activeBorder',
    ColorDefaults(
      dark: ColorReference('tab.activeBorder'),
      light: ColorReference('tab.activeBorder'),
      hcDark: ColorReference('tab.activeBorder'),
      hcLight: ColorReference('tab.activeBorder'),
    ),
  ),
  ColorContribution(
    'terminal.initialHintForeground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff56'),
      light: ColorLiteral('#00000077'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  // src/vs/workbench/contrib/scm/browser/scmHistory.ts
  ColorContribution(
    'scmGraph.historyItemRefColor',
    ColorDefaults(
      dark: ColorReference('charts.blue'),
      light: ColorReference('charts.blue'),
      hcDark: ColorReference('charts.blue'),
      hcLight: ColorReference('charts.blue'),
    ),
  ),
  ColorContribution(
    'scmGraph.historyItemRemoteRefColor',
    ColorDefaults(
      dark: ColorReference('charts.purple'),
      light: ColorReference('charts.purple'),
      hcDark: ColorReference('charts.purple'),
      hcLight: ColorReference('charts.purple'),
    ),
  ),
  ColorContribution(
    'scmGraph.historyItemBaseRefColor',
    ColorDefaults(
      dark: ColorLiteral('#ea5c00'),
      light: ColorLiteral('#ea5c00'),
      hcDark: ColorLiteral('#ea5c00'),
      hcLight: ColorLiteral('#ea5c00'),
    ),
  ),
  ColorContribution(
    'scmGraph.historyItemHoverDefaultLabelForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'scmGraph.historyItemHoverDefaultLabelBackground',
    ColorDefaults(
      dark: ColorReference('badge.background'),
      light: ColorReference('badge.background'),
      hcDark: ColorReference('badge.background'),
      hcLight: ColorReference('badge.background'),
    ),
  ),
  ColorContribution(
    'scmGraph.historyItemHoverLabelForeground',
    ColorDefaults(
      dark: ColorReference('panel.background'),
      light: ColorReference('panel.background'),
      hcDark: ColorReference('panel.background'),
      hcLight: ColorReference('panel.background'),
    ),
  ),
  ColorContribution(
    'scmGraph.historyItemHoverAdditionsForeground',
    ColorDefaults(
      dark: ColorLiteral('#81b88b'),
      light: ColorLiteral('#587c0c'),
      hcDark: ColorLiteral('#a1e3ad'),
      hcLight: ColorLiteral('#374e06'),
    ),
  ),
  ColorContribution(
    'scmGraph.historyItemHoverDeletionsForeground',
    ColorDefaults(
      dark: ColorLiteral('#c74e39'),
      light: ColorLiteral('#ad0707'),
      hcDark: ColorLiteral('#c74e39'),
      hcLight: ColorLiteral('#ad0707'),
    ),
  ),
  ColorContribution(
    'scmGraph.foreground1',
    ColorDefaults(
      dark: ColorLiteral('#ffb000'),
      light: ColorLiteral('#ffb000'),
      hcDark: ColorLiteral('#ffb000'),
      hcLight: ColorLiteral('#ffb000'),
    ),
  ),
  ColorContribution(
    'scmGraph.foreground2',
    ColorDefaults(
      dark: ColorLiteral('#dc267f'),
      light: ColorLiteral('#dc267f'),
      hcDark: ColorLiteral('#dc267f'),
      hcLight: ColorLiteral('#dc267f'),
    ),
  ),
  ColorContribution(
    'scmGraph.foreground3',
    ColorDefaults(
      dark: ColorLiteral('#994f00'),
      light: ColorLiteral('#994f00'),
      hcDark: ColorLiteral('#994f00'),
      hcLight: ColorLiteral('#994f00'),
    ),
  ),
  ColorContribution(
    'scmGraph.foreground4',
    ColorDefaults(
      dark: ColorLiteral('#40b0a6'),
      light: ColorLiteral('#40b0a6'),
      hcDark: ColorLiteral('#40b0a6'),
      hcLight: ColorLiteral('#40b0a6'),
    ),
  ),
  ColorContribution(
    'scmGraph.foreground5',
    ColorDefaults(
      dark: ColorLiteral('#b66dff'),
      light: ColorLiteral('#b66dff'),
      hcDark: ColorLiteral('#b66dff'),
      hcLight: ColorLiteral('#b66dff'),
    ),
  ),
  // src/vs/workbench/contrib/comments/browser/commentColors.ts
  ColorContribution(
    'commentsView.resolvedIcon',
    ColorDefaults(
      dark: ColorReference('disabledForeground'),
      light: ColorReference('disabledForeground'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'commentsView.unresolvedIcon',
    ColorDefaults(
      dark: ColorReference('list.focusOutline'),
      light: ColorReference('list.focusOutline'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'editorCommentsWidget.replyInputBackground',
    ColorDefaults(
      dark: ColorReference('peekViewTitle.background'),
      light: ColorReference('peekViewTitle.background'),
      hcDark: ColorReference('peekViewTitle.background'),
      hcLight: ColorReference('peekViewTitle.background'),
    ),
  ),
  ColorContribution(
    'editorCommentsWidget.resolvedBorder',
    ColorDefaults(
      dark: ColorReference('commentsView.resolvedIcon'),
      light: ColorReference('commentsView.resolvedIcon'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'editorCommentsWidget.unresolvedBorder',
    ColorDefaults(
      dark: ColorReference('commentsView.unresolvedIcon'),
      light: ColorReference('commentsView.unresolvedIcon'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'editorCommentsWidget.rangeBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editorCommentsWidget.unresolvedBorder'),
        0.1,
      ),
      light: TransparentTransform(
        ColorReference('editorCommentsWidget.unresolvedBorder'),
        0.1,
      ),
      hcDark: TransparentTransform(
        ColorReference('editorCommentsWidget.unresolvedBorder'),
        0.1,
      ),
      hcLight: TransparentTransform(
        ColorReference('editorCommentsWidget.unresolvedBorder'),
        0.1,
      ),
    ),
  ),
  ColorContribution(
    'editorCommentsWidget.rangeActiveBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editorCommentsWidget.unresolvedBorder'),
        0.1,
      ),
      light: TransparentTransform(
        ColorReference('editorCommentsWidget.unresolvedBorder'),
        0.1,
      ),
      hcDark: TransparentTransform(
        ColorReference('editorCommentsWidget.unresolvedBorder'),
        0.1,
      ),
      hcLight: TransparentTransform(
        ColorReference('editorCommentsWidget.unresolvedBorder'),
        0.1,
      ),
    ),
  ),
  // src/vs/workbench/contrib/comments/browser/commentGlyphWidget.ts
  ColorContribution(
    'editorGutter.commentRangeForeground',
    ColorDefaults(
      dark: OpaqueTransform(
        ColorReference('list.inactiveSelectionBackground'),
        ColorReference('editor.background'),
      ),
      light: DarkenTransform(
        OpaqueTransform(
          ColorReference('list.inactiveSelectionBackground'),
          ColorReference('editor.background'),
        ),
        0.05,
      ),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#000000'),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.commentForeground',
    ColorDefaults(
      dark: ColorReference('editorGutter.commentRangeForeground'),
      light: ColorReference('editorGutter.commentRangeForeground'),
      hcDark: ColorReference('editorGutter.commentRangeForeground'),
      hcLight: ColorReference('editorGutter.commentRangeForeground'),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.commentUnresolvedForeground',
    ColorDefaults(
      dark: ColorReference('editorOverviewRuler.commentForeground'),
      light: ColorReference('editorOverviewRuler.commentForeground'),
      hcDark: ColorReference('editorOverviewRuler.commentForeground'),
      hcLight: ColorReference('editorOverviewRuler.commentForeground'),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.commentDraftForeground',
    ColorDefaults(
      dark: ColorReference('editorOverviewRuler.commentUnresolvedForeground'),
      light: ColorReference('editorOverviewRuler.commentUnresolvedForeground'),
      hcDark: ColorReference('editorOverviewRuler.commentUnresolvedForeground'),
      hcLight: ColorReference(
        'editorOverviewRuler.commentUnresolvedForeground',
      ),
    ),
  ),
  ColorContribution(
    'editorGutter.commentGlyphForeground',
    ColorDefaults(
      dark: ColorReference('editor.foreground'),
      light: ColorReference('editor.foreground'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'editorGutter.commentUnresolvedGlyphForeground',
    ColorDefaults(
      dark: ColorReference('editorGutter.commentGlyphForeground'),
      light: ColorReference('editorGutter.commentGlyphForeground'),
      hcDark: ColorReference('editorGutter.commentGlyphForeground'),
      hcLight: ColorReference('editorGutter.commentGlyphForeground'),
    ),
  ),
  ColorContribution(
    'editorGutter.commentDraftGlyphForeground',
    ColorDefaults(
      dark: ColorReference('editorGutter.commentGlyphForeground'),
      light: ColorReference('editorGutter.commentGlyphForeground'),
      hcDark: ColorReference('editorGutter.commentGlyphForeground'),
      hcLight: ColorReference('editorGutter.commentGlyphForeground'),
    ),
  ),
  // src/vs/workbench/contrib/agentsVoice/common/agentsVoiceColors.ts
  ColorContribution(
    'agentsVoice.speakingForeground',
    ColorDefaults(
      dark: ColorLiteral('#a371f7'),
      light: ColorLiteral('#8250df'),
      hcDark: ColorLiteral('#d2a8ff'),
      hcLight: ColorLiteral('#6639ba'),
    ),
  ),
  ColorContribution(
    'agentsVoice.speakingBackground',
    ColorDefaults(
      dark: ColorLiteral('#a371f714'),
      light: ColorLiteral('#8250df14'),
      hcDark: ColorLiteral('#d2a8ff14'),
      hcLight: ColorLiteral('#6639ba14'),
    ),
  ),
  // src/vs/sessions/common/theme.ts
  ColorContribution(
    'agents.background',
    ColorDefaults(
      dark: ColorReference('editor.background'),
      light: ColorReference('sideBar.background'),
      hcDark: ColorReference('editor.background'),
      hcLight: ColorReference('editor.background'),
    ),
  ),
  ColorContribution(
    'agentsPanel.background',
    ColorDefaults(
      dark: ColorReference('sideBar.background'),
      light: ColorReference('editor.background'),
      hcDark: ColorReference('sideBar.background'),
      hcLight: ColorReference('sideBar.background'),
    ),
  ),
  ColorContribution(
    'agentsDetail.background',
    ColorDefaults(
      dark: ColorReference('editor.background'),
      light: ColorReference('editor.background'),
      hcDark: ColorReference('editor.background'),
      hcLight: ColorReference('editor.background'),
    ),
  ),
  ColorContribution(
    'agentsPanel.foreground',
    ColorDefaults(
      dark: ColorReference('sideBar.foreground'),
      light: ColorReference('sideBar.foreground'),
      hcDark: ColorReference('sideBar.foreground'),
      hcLight: ColorReference('sideBar.foreground'),
    ),
  ),
  ColorContribution(
    'agentsPanel.border',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('foreground'), 0.15),
      light: TransparentTransform(ColorReference('foreground'), 0.15),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'agentsCard.border',
    ColorDefaults(
      dark: ColorReference('agentsPanel.border'),
      light: ColorReference('agentsPanel.border'),
      hcDark: ColorReference('agentsPanel.border'),
      hcLight: ColorReference('agentsPanel.border'),
    ),
  ),
  ColorContribution(
    'agentsBottomPanel.border',
    ColorDefaults(
      dark: ColorReference('agentsPanel.border'),
      light: ColorReference('agentsPanel.border'),
      hcDark: ColorReference('agentsPanel.border'),
      hcLight: ColorReference('agentsPanel.border'),
    ),
  ),
  ColorContribution(
    'agentsGradient.tintColor',
    ColorDefaults(
      dark: ColorReference('button.background'),
      light: ColorReference('button.background'),
      hcDark: ColorReference('button.background'),
      hcLight: ColorReference('button.background'),
    ),
  ),
  ColorContribution(
    'agentFeedbackEditorWidget.background',
    ColorDefaults(
      dark: LightenTransform(ColorReference('editorWidget.background'), 0.08),
      light: DarkenTransform(ColorReference('editorWidget.background'), 0.04),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'agentFeedbackEditorWidget.border',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('foreground'), 0.35),
      light: TransparentTransform(ColorReference('foreground'), 0.35),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'agentFeedbackInputWidget.border',
    ColorDefaults(
      dark: ColorReference('editorWidget.border'),
      light: ColorReference('editorWidget.border'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'agentsUpdateButton.downloadingBackground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('button.background'), 0.4),
      light: TransparentTransform(ColorReference('button.background'), 0.4),
      hcDark: TransparentTransform(ColorReference('button.background'), 0.4),
      hcLight: TransparentTransform(ColorReference('button.background'), 0.4),
    ),
  ),
  ColorContribution(
    'agentsUpdateButton.downloadedBackground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('button.background'), 0.7),
      light: TransparentTransform(ColorReference('button.background'), 0.7),
      hcDark: TransparentTransform(ColorReference('button.background'), 0.7),
      hcLight: TransparentTransform(ColorReference('button.background'), 0.7),
    ),
  ),
  ColorContribution(
    'agentsChatInput.background',
    ColorDefaults(
      dark: ColorReference('input.background'),
      light: ColorReference('input.background'),
      hcDark: ColorReference('input.background'),
      hcLight: ColorReference('input.background'),
    ),
  ),
  ColorContribution(
    'agentsChatInput.foreground',
    ColorDefaults(
      dark: ColorReference('input.foreground'),
      light: ColorReference('input.foreground'),
      hcDark: ColorReference('input.foreground'),
      hcLight: ColorReference('input.foreground'),
    ),
  ),
  ColorContribution(
    'agentsChatInput.border',
    ColorDefaults(
      dark: ColorReference('input.border'),
      light: ColorReference('input.border'),
      hcDark: ColorReference('input.border'),
      hcLight: ColorReference('input.border'),
    ),
  ),
  ColorContribution(
    'agentsChatInput.focusBorder',
    ColorDefaults(
      dark: ColorReference('focusBorder'),
      light: ColorReference('focusBorder'),
      hcDark: ColorReference('focusBorder'),
      hcLight: ColorReference('focusBorder'),
    ),
  ),
  ColorContribution(
    'agentsChatInput.placeholderForeground',
    ColorDefaults(
      dark: ColorReference('input.placeholderForeground'),
      light: ColorReference('input.placeholderForeground'),
      hcDark: ColorReference('input.placeholderForeground'),
      hcLight: ColorReference('input.placeholderForeground'),
    ),
  ),
  ColorContribution(
    'agentsNewSessionButton.background',
    ColorDefaults(
      dark: ColorLiteral('#00000000'),
      light: ColorLiteral('#00000000'),
      hcDark: ColorLiteral('#00000000'),
      hcLight: ColorLiteral('#00000000'),
    ),
  ),
  ColorContribution(
    'agentsNewSessionButton.foreground',
    ColorDefaults(
      dark: ColorReference('sideBar.foreground'),
      light: ColorReference('sideBar.foreground'),
      hcDark: ColorReference('sideBar.foreground'),
      hcLight: ColorReference('sideBar.foreground'),
    ),
  ),
  ColorContribution(
    'agentsNewSessionButton.border',
    ColorDefaults(
      dark: ColorReference('button.secondaryBorder'),
      light: ColorReference('button.secondaryBorder'),
      hcDark: ColorReference('button.secondaryBorder'),
      hcLight: ColorReference('button.secondaryBorder'),
    ),
  ),
  ColorContribution(
    'agentsNewSessionButton.hoverBackground',
    ColorDefaults(
      dark: ColorReference('toolbar.hoverBackground'),
      light: ColorReference('toolbar.hoverBackground'),
      hcDark: ColorReference('toolbar.hoverBackground'),
      hcLight: ColorReference('toolbar.hoverBackground'),
    ),
  ),
  ColorContribution(
    'agentsBadge.background',
    ColorDefaults(
      dark: ColorReference('activityBarBadge.background'),
      light: ColorReference('activityBarBadge.background'),
      hcDark: ColorReference('activityBarBadge.background'),
      hcLight: ColorReference('activityBarBadge.background'),
    ),
  ),
  ColorContribution(
    'agentsBadge.foreground',
    ColorDefaults(
      dark: ColorReference('activityBarBadge.foreground'),
      light: ColorReference('activityBarBadge.foreground'),
      hcDark: ColorReference('activityBarBadge.foreground'),
      hcLight: ColorReference('activityBarBadge.foreground'),
    ),
  ),
  ColorContribution(
    'agentsUnreadBadge.background',
    ColorDefaults(
      dark: ColorReference('activityBarBadge.background'),
      light: ColorReference('activityBarBadge.background'),
      hcDark: ColorReference('activityBarBadge.background'),
      hcLight: ColorReference('activityBarBadge.background'),
    ),
  ),
  ColorContribution(
    'agentsUnreadBadge.foreground',
    ColorDefaults(
      dark: ColorReference('activityBarBadge.foreground'),
      light: ColorReference('activityBarBadge.foreground'),
      hcDark: ColorReference('activityBarBadge.foreground'),
      hcLight: ColorReference('activityBarBadge.foreground'),
    ),
  ),
  ColorContribution(
    'activeSessionView.background',
    ColorDefaults(
      dark: ColorReference('agentsPanel.background'),
      light: ColorReference('agentsPanel.background'),
      hcDark: ColorReference('agentsPanel.background'),
      hcLight: ColorReference('agentsPanel.background'),
    ),
  ),
  ColorContribution(
    'inactiveSessionView.background',
    ColorDefaults(
      dark: ColorReference('agents.background'),
      light: ColorReference('agents.background'),
      hcDark: ColorReference('agents.background'),
      hcLight: ColorReference('agents.background'),
    ),
  ),
  ColorContribution(
    'activeSessionView.foreground',
    ColorDefaults(
      dark: ColorReference('agentsPanel.foreground'),
      light: ColorReference('agentsPanel.foreground'),
      hcDark: ColorReference('agentsPanel.foreground'),
      hcLight: ColorReference('agentsPanel.foreground'),
    ),
  ),
  ColorContribution(
    'inactiveSessionView.foreground',
    ColorDefaults(
      dark: ColorReference('agentsPanel.foreground'),
      light: ColorReference('agentsPanel.foreground'),
      hcDark: ColorReference('agentsPanel.foreground'),
      hcLight: ColorReference('agentsPanel.foreground'),
    ),
  ),
  // src/vs/workbench/contrib/remote/browser/tunnelView.ts
  ColorContribution(
    'ports.iconRunningProcessForeground',
    ColorDefaults(
      dark: ColorReference('statusBarItem.remoteBackground'),
      light: ColorReference('statusBarItem.remoteBackground'),
      hcDark: ColorReference('statusBarItem.remoteBackground'),
      hcLight: ColorReference('statusBarItem.remoteBackground'),
    ),
  ),
  // src/vs/workbench/contrib/preferences/common/settingsEditorColorRegistry.ts
  ColorContribution(
    'settings.headerForeground',
    ColorDefaults(
      dark: ColorLiteral('#e7e7e7'),
      light: ColorLiteral('#444444'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#292929'),
    ),
  ),
  ColorContribution(
    'settings.settingsHeaderHoverForeground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('settings.headerForeground'),
        0.7,
      ),
      light: TransparentTransform(
        ColorReference('settings.headerForeground'),
        0.7,
      ),
      hcDark: TransparentTransform(
        ColorReference('settings.headerForeground'),
        0.7,
      ),
      hcLight: TransparentTransform(
        ColorReference('settings.headerForeground'),
        0.7,
      ),
    ),
  ),
  ColorContribution(
    'settings.modifiedItemIndicator',
    ColorDefaults(
      dark: ColorLiteral('#0c7d9d'),
      light: ColorLiteral('#66afe0'),
      hcDark: ColorLiteral('#00497a'),
      hcLight: ColorLiteral('#66afe0'),
    ),
  ),
  ColorContribution(
    'settings.headerBorder',
    ColorDefaults(
      dark: ColorReference('panel.border'),
      light: ColorReference('panel.border'),
      hcDark: ColorReference('panel.border'),
      hcLight: ColorReference('panel.border'),
    ),
  ),
  ColorContribution(
    'settings.sashBorder',
    ColorDefaults(
      dark: ColorReference('panel.border'),
      light: ColorReference('panel.border'),
      hcDark: ColorReference('panel.border'),
      hcLight: ColorReference('panel.border'),
    ),
  ),
  ColorContribution(
    'settings.dropdownBackground',
    ColorDefaults(
      dark: ColorReference('dropdown.background'),
      light: ColorReference('dropdown.background'),
      hcDark: ColorReference('dropdown.background'),
      hcLight: ColorReference('dropdown.background'),
    ),
  ),
  ColorContribution(
    'settings.dropdownForeground',
    ColorDefaults(
      dark: ColorReference('dropdown.foreground'),
      light: ColorReference('dropdown.foreground'),
      hcDark: ColorReference('dropdown.foreground'),
      hcLight: ColorReference('dropdown.foreground'),
    ),
  ),
  ColorContribution(
    'settings.dropdownBorder',
    ColorDefaults(
      dark: ColorReference('dropdown.border'),
      light: ColorReference('dropdown.border'),
      hcDark: ColorReference('dropdown.border'),
      hcLight: ColorReference('dropdown.border'),
    ),
  ),
  ColorContribution(
    'settings.dropdownListBorder',
    ColorDefaults(
      dark: ColorReference('editorWidget.border'),
      light: ColorReference('editorWidget.border'),
      hcDark: ColorReference('editorWidget.border'),
      hcLight: ColorReference('editorWidget.border'),
    ),
  ),
  ColorContribution(
    'settings.checkboxBackground',
    ColorDefaults(
      dark: ColorReference('checkbox.background'),
      light: ColorReference('checkbox.background'),
      hcDark: ColorReference('checkbox.background'),
      hcLight: ColorReference('checkbox.background'),
    ),
  ),
  ColorContribution(
    'settings.checkboxForeground',
    ColorDefaults(
      dark: ColorReference('checkbox.foreground'),
      light: ColorReference('checkbox.foreground'),
      hcDark: ColorReference('checkbox.foreground'),
      hcLight: ColorReference('checkbox.foreground'),
    ),
  ),
  ColorContribution(
    'settings.checkboxBorder',
    ColorDefaults(
      dark: ColorReference('checkbox.border'),
      light: ColorReference('checkbox.border'),
      hcDark: ColorReference('checkbox.border'),
      hcLight: ColorReference('checkbox.border'),
    ),
  ),
  ColorContribution(
    'settings.textInputBackground',
    ColorDefaults(
      dark: ColorReference('input.background'),
      light: ColorReference('input.background'),
      hcDark: ColorReference('input.background'),
      hcLight: ColorReference('input.background'),
    ),
  ),
  ColorContribution(
    'settings.textInputForeground',
    ColorDefaults(
      dark: ColorReference('input.foreground'),
      light: ColorReference('input.foreground'),
      hcDark: ColorReference('input.foreground'),
      hcLight: ColorReference('input.foreground'),
    ),
  ),
  ColorContribution(
    'settings.textInputBorder',
    ColorDefaults(
      dark: ColorReference('input.border'),
      light: ColorReference('input.border'),
      hcDark: ColorReference('input.border'),
      hcLight: ColorReference('input.border'),
    ),
  ),
  ColorContribution(
    'settings.numberInputBackground',
    ColorDefaults(
      dark: ColorReference('input.background'),
      light: ColorReference('input.background'),
      hcDark: ColorReference('input.background'),
      hcLight: ColorReference('input.background'),
    ),
  ),
  ColorContribution(
    'settings.numberInputForeground',
    ColorDefaults(
      dark: ColorReference('input.foreground'),
      light: ColorReference('input.foreground'),
      hcDark: ColorReference('input.foreground'),
      hcLight: ColorReference('input.foreground'),
    ),
  ),
  ColorContribution(
    'settings.numberInputBorder',
    ColorDefaults(
      dark: ColorReference('input.border'),
      light: ColorReference('input.border'),
      hcDark: ColorReference('input.border'),
      hcLight: ColorReference('input.border'),
    ),
  ),
  ColorContribution(
    'settings.focusedRowBackground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('list.hoverBackground'), 0.6),
      light: TransparentTransform(ColorReference('list.hoverBackground'), 0.6),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'settings.rowHoverBackground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('list.hoverBackground'), 0.3),
      light: TransparentTransform(ColorReference('list.hoverBackground'), 0.3),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'settings.focusedRowBorder',
    ColorDefaults(
      dark: ColorReference('focusBorder'),
      light: ColorReference('focusBorder'),
      hcDark: ColorReference('focusBorder'),
      hcLight: ColorReference('focusBorder'),
    ),
  ),
  // src/vs/workbench/contrib/preferences/browser/keybindingsEditor.ts
  ColorContribution(
    'keybindingTable.headerBackground',
    ColorDefaults(
      dark: ColorReference('tree.tableOddRowsBackground'),
      light: ColorReference('tree.tableOddRowsBackground'),
      hcDark: ColorReference('tree.tableOddRowsBackground'),
      hcLight: ColorReference('tree.tableOddRowsBackground'),
    ),
  ),
  ColorContribution(
    'keybindingTable.rowsBackground',
    ColorDefaults(
      dark: ColorReference('tree.tableOddRowsBackground'),
      light: ColorReference('tree.tableOddRowsBackground'),
      hcDark: ColorReference('tree.tableOddRowsBackground'),
      hcLight: ColorReference('tree.tableOddRowsBackground'),
    ),
  ),
  // src/vs/workbench/contrib/extensions/browser/extensionsActions.ts
  ColorContribution(
    'extensionButton.background',
    ColorDefaults(
      dark: ColorReference('button.secondaryBackground'),
      light: ColorReference('button.secondaryBackground'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'extensionButton.foreground',
    ColorDefaults(
      dark: ColorReference('button.secondaryForeground'),
      light: ColorReference('button.secondaryForeground'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'extensionButton.hoverBackground',
    ColorDefaults(
      dark: ColorReference('button.secondaryHoverBackground'),
      light: ColorReference('button.secondaryHoverBackground'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'extensionButton.border',
    ColorDefaults(
      dark: ColorReference('button.secondaryBorder'),
      light: ColorReference('button.secondaryBorder'),
      hcDark: ColorReference('button.secondaryBorder'),
      hcLight: ColorReference('button.secondaryBorder'),
    ),
  ),
  ColorContribution(
    'extensionButton.separator',
    ColorDefaults(
      dark: ColorReference('button.separator'),
      light: ColorReference('button.separator'),
      hcDark: ColorReference('button.separator'),
      hcLight: ColorReference('button.separator'),
    ),
  ),
  ColorContribution(
    'extensionButton.prominentBackground',
    ColorDefaults(
      dark: ColorReference('button.background'),
      light: ColorReference('button.background'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'extensionButton.prominentForeground',
    ColorDefaults(
      dark: ColorReference('button.foreground'),
      light: ColorReference('button.foreground'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'extensionButton.prominentHoverBackground',
    ColorDefaults(
      dark: ColorReference('button.hoverBackground'),
      light: ColorReference('button.hoverBackground'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  // src/vs/workbench/contrib/debug/browser/debugColors.ts
  ColorContribution(
    'debugToolBar.background',
    ColorDefaults(
      dark: ColorLiteral('#333333'),
      light: ColorLiteral('#f3f3f3'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution('debugToolBar.border', null),
  ColorContribution(
    'debugIcon.startForeground',
    ColorDefaults(
      dark: ColorLiteral('#89d185'),
      light: ColorLiteral('#388a34'),
      hcDark: ColorLiteral('#89d185'),
      hcLight: ColorLiteral('#388a34'),
    ),
  ),
  // src/vs/workbench/contrib/notebook/browser/notebookEditorWidget.ts
  ColorContribution(
    'notebook.cellBorderColor',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('list.inactiveSelectionBackground'),
        1.0,
      ),
      light: TransparentTransform(
        ColorReference('list.inactiveSelectionBackground'),
        1.0,
      ),
      hcDark: ColorReference('panel.border'),
      hcLight: ColorReference('panel.border'),
    ),
  ),
  ColorContribution(
    'notebook.focusedEditorBorder',
    ColorDefaults(
      dark: ColorReference('focusBorder'),
      light: ColorReference('focusBorder'),
      hcDark: ColorReference('focusBorder'),
      hcLight: ColorReference('focusBorder'),
    ),
  ),
  ColorContribution(
    'notebookStatusSuccessIcon.foreground',
    ColorDefaults(
      dark: ColorReference('debugIcon.startForeground'),
      light: ColorReference('debugIcon.startForeground'),
      hcDark: ColorReference('debugIcon.startForeground'),
      hcLight: ColorReference('debugIcon.startForeground'),
    ),
  ),
  ColorContribution(
    'notebookEditorOverviewRuler.runningCellForeground',
    ColorDefaults(
      dark: ColorReference('debugIcon.startForeground'),
      light: ColorReference('debugIcon.startForeground'),
      hcDark: ColorReference('debugIcon.startForeground'),
      hcLight: ColorReference('debugIcon.startForeground'),
    ),
  ),
  ColorContribution(
    'notebookStatusErrorIcon.foreground',
    ColorDefaults(
      dark: ColorReference('errorForeground'),
      light: ColorReference('errorForeground'),
      hcDark: ColorReference('errorForeground'),
      hcLight: ColorReference('errorForeground'),
    ),
  ),
  ColorContribution(
    'notebookStatusRunningIcon.foreground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution('notebook.outputContainerBorderColor', null),
  ColorContribution('notebook.outputContainerBackgroundColor', null),
  ColorContribution(
    'notebook.cellToolbarSeparator',
    ColorDefaults(
      dark: ColorLiteral.rgba(128, 128, 128, 0.35),
      light: ColorLiteral.rgba(128, 128, 128, 0.35),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution('notebook.focusedCellBackground', null),
  ColorContribution(
    'notebook.selectedCellBackground',
    ColorDefaults(
      dark: ColorReference('list.inactiveSelectionBackground'),
      light: ColorReference('list.inactiveSelectionBackground'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'notebook.cellHoverBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('notebook.focusedCellBackground'),
        0.5,
      ),
      light: TransparentTransform(
        ColorReference('notebook.focusedCellBackground'),
        0.7,
      ),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'notebook.selectedCellBorder',
    ColorDefaults(
      dark: ColorReference('notebook.cellBorderColor'),
      light: ColorReference('notebook.cellBorderColor'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'notebook.inactiveSelectedCellBorder',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorReference('focusBorder'),
      hcLight: ColorReference('focusBorder'),
    ),
  ),
  ColorContribution(
    'notebook.focusedCellBorder',
    ColorDefaults(
      dark: ColorReference('focusBorder'),
      light: ColorReference('focusBorder'),
      hcDark: ColorReference('focusBorder'),
      hcLight: ColorReference('focusBorder'),
    ),
  ),
  ColorContribution(
    'notebook.inactiveFocusedCellBorder',
    ColorDefaults(
      dark: ColorReference('notebook.cellBorderColor'),
      light: ColorReference('notebook.cellBorderColor'),
      hcDark: ColorReference('notebook.cellBorderColor'),
      hcLight: ColorReference('notebook.cellBorderColor'),
    ),
  ),
  ColorContribution(
    'notebook.cellStatusBarItemHoverBackground',
    ColorDefaults(
      dark: ColorLiteral.rgba(255, 255, 255, 0.15),
      light: ColorLiteral.rgba(0, 0, 0, 0.08),
      hcDark: ColorLiteral.rgba(255, 255, 255, 0.15),
      hcLight: ColorLiteral.rgba(0, 0, 0, 0.08),
    ),
  ),
  ColorContribution(
    'notebook.cellInsertionIndicator',
    ColorDefaults(
      dark: ColorReference('focusBorder'),
      light: ColorReference('focusBorder'),
      hcDark: ColorReference('focusBorder'),
      hcLight: ColorReference('focusBorder'),
    ),
  ),
  ColorContribution(
    'notebookScrollbarSlider.background',
    ColorDefaults(
      dark: ColorReference('scrollbarSlider.background'),
      light: ColorReference('scrollbarSlider.background'),
      hcDark: ColorReference('scrollbarSlider.background'),
      hcLight: ColorReference('scrollbarSlider.background'),
    ),
  ),
  ColorContribution(
    'notebookScrollbarSlider.hoverBackground',
    ColorDefaults(
      dark: ColorReference('scrollbarSlider.hoverBackground'),
      light: ColorReference('scrollbarSlider.hoverBackground'),
      hcDark: ColorReference('scrollbarSlider.hoverBackground'),
      hcLight: ColorReference('scrollbarSlider.hoverBackground'),
    ),
  ),
  ColorContribution(
    'notebookScrollbarSlider.activeBackground',
    ColorDefaults(
      dark: ColorReference('scrollbarSlider.activeBackground'),
      light: ColorReference('scrollbarSlider.activeBackground'),
      hcDark: ColorReference('scrollbarSlider.activeBackground'),
      hcLight: ColorReference('scrollbarSlider.activeBackground'),
    ),
  ),
  ColorContribution(
    'notebook.symbolHighlightBackground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff0b'),
      light: ColorLiteral('#fdff0033'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'notebook.cellEditorBackground',
    ColorDefaults(
      dark: ColorReference('sideBar.background'),
      light: ColorReference('sideBar.background'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'notebook.editorBackground',
    ColorDefaults(
      dark: ColorReference('editorPane.background'),
      light: ColorReference('editorPane.background'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  // src/vs/workbench/contrib/inlineChat/common/inlineChat.ts
  ColorContribution(
    'inlineChat.foreground',
    ColorDefaults(
      dark: ColorReference('editorWidget.foreground'),
      light: ColorReference('editorWidget.foreground'),
      hcDark: ColorReference('editorWidget.foreground'),
      hcLight: ColorReference('editorWidget.foreground'),
    ),
  ),
  ColorContribution(
    'inlineChat.background',
    ColorDefaults(
      dark: ColorReference('editorWidget.background'),
      light: ColorReference('editorWidget.background'),
      hcDark: ColorReference('editorWidget.background'),
      hcLight: ColorReference('editorWidget.background'),
    ),
  ),
  ColorContribution(
    'inlineChat.border',
    ColorDefaults(
      dark: ColorReference('editorWidget.border'),
      light: ColorReference('editorWidget.border'),
      hcDark: ColorReference('editorWidget.border'),
      hcLight: ColorReference('editorWidget.border'),
    ),
  ),
  ColorContribution(
    'inlineChat.shadow',
    ColorDefaults(
      dark: ColorReference('widget.shadow'),
      light: ColorReference('widget.shadow'),
      hcDark: ColorReference('widget.shadow'),
      hcLight: ColorReference('widget.shadow'),
    ),
  ),
  ColorContribution(
    'inlineChatInput.border',
    ColorDefaults(
      dark: ColorReference('editorWidget.border'),
      light: ColorReference('editorWidget.border'),
      hcDark: ColorReference('editorWidget.border'),
      hcLight: ColorReference('editorWidget.border'),
    ),
  ),
  ColorContribution(
    'inlineChatInput.focusBorder',
    ColorDefaults(
      dark: ColorReference('focusBorder'),
      light: ColorReference('focusBorder'),
      hcDark: ColorReference('focusBorder'),
      hcLight: ColorReference('focusBorder'),
    ),
  ),
  ColorContribution(
    'inlineChatInput.placeholderForeground',
    ColorDefaults(
      dark: ColorReference('input.placeholderForeground'),
      light: ColorReference('input.placeholderForeground'),
      hcDark: ColorReference('input.placeholderForeground'),
      hcLight: ColorReference('input.placeholderForeground'),
    ),
  ),
  ColorContribution(
    'inlineChatInput.background',
    ColorDefaults(
      dark: ColorReference('input.background'),
      light: ColorReference('input.background'),
      hcDark: ColorReference('input.background'),
      hcLight: ColorReference('input.background'),
    ),
  ),
  ColorContribution(
    'inlineChatDiff.inserted',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.5,
      ),
      light: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.5,
      ),
      hcDark: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.5,
      ),
      hcLight: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.5,
      ),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.inlineChatInserted',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.6,
      ),
      light: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.8,
      ),
      hcDark: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.6,
      ),
      hcLight: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.8,
      ),
    ),
  ),
  ColorContribution(
    'editorMinimap.inlineChatInserted',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.6,
      ),
      light: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.8,
      ),
      hcDark: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.6,
      ),
      hcLight: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.8,
      ),
    ),
  ),
  ColorContribution(
    'inlineChatDiff.removed',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.5,
      ),
      light: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.5,
      ),
      hcDark: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.5,
      ),
      hcLight: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.5,
      ),
    ),
  ),
  ColorContribution(
    'editorOverviewRuler.inlineChatRemoved',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.6,
      ),
      light: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.8,
      ),
      hcDark: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.6,
      ),
      hcLight: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        0.8,
      ),
    ),
  ),
  // src/vs/workbench/contrib/chat/common/widget/chatColors.ts
  ColorContribution(
    'agentStatusIndicator.background',
    ColorDefaults(
      dark: ColorReference('commandCenter.background'),
      light: ColorReference('commandCenter.background'),
      hcDark: ColorReference('commandCenter.background'),
      hcLight: ColorReference('commandCenter.background'),
    ),
  ),
  ColorContribution(
    'chat.requestBorder',
    ColorDefaults(
      dark: ColorLiteral.rgba(255, 255, 255, 0.1),
      light: ColorLiteral.rgba(0, 0, 0, 0.1),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'chat.requestBackground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('editor.background'), 0.62),
      light: TransparentTransform(ColorReference('editor.background'), 0.62),
      hcDark: ColorReference('editorWidget.background'),
      hcLight: null,
    ),
  ),
  ColorContribution(
    'chat.statusBackground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('foreground'), 0.08),
      light: TransparentTransform(ColorReference('foreground'), 0.08),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'chat.sessionStateIndicator.inProgressBorder',
    ColorDefaults(
      dark: ColorReference('charts.yellow'),
      light: ColorReference('charts.yellow'),
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'chat.sessionStateIndicator.unvisitedBorder',
    ColorDefaults(
      dark: ColorReference('charts.green'),
      light: ColorReference('charts.green'),
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'chat.sessionStateIndicator.needsInputBorder',
    ColorDefaults(
      dark: ColorReference('errorForeground'),
      light: ColorReference('errorForeground'),
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'chat.slashCommandBackground',
    ColorDefaults(
      dark: ColorLiteral('#26477866'),
      light: ColorLiteral('#adceff7a'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorReference('badge.background'),
    ),
  ),
  ColorContribution(
    'chat.slashCommandForeground',
    ColorDefaults(
      dark: ColorLiteral('#85b6ff'),
      light: ColorLiteral('#26569e'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorReference('badge.foreground'),
    ),
  ),
  ColorContribution(
    'chat.avatarBackground',
    ColorDefaults(
      dark: ColorLiteral('#1f1f1f'),
      light: ColorLiteral('#f2f2f2'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'chat.avatarForeground',
    ColorDefaults(
      dark: ColorReference('foreground'),
      light: ColorReference('foreground'),
      hcDark: ColorReference('foreground'),
      hcLight: ColorReference('foreground'),
    ),
  ),
  ColorContribution(
    'chat.editedFileForeground',
    ColorDefaults(
      dark: ColorLiteral('#e2c08d'),
      light: ColorLiteral('#895503'),
      hcDark: ColorLiteral('#e2c08d'),
      hcLight: ColorLiteral('#895503'),
    ),
  ),
  ColorContribution(
    'chat.requestCodeBorder',
    ColorDefaults(
      dark: ColorLiteral('#004972b8'),
      light: ColorLiteral('#0e639c40'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'chat.requestBubbleBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editor.selectionBackground'),
        0.3,
      ),
      light: TransparentTransform(
        ColorReference('editor.selectionBackground'),
        0.3,
      ),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'chat.requestBubbleHoverBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('editor.selectionBackground'),
        0.6,
      ),
      light: TransparentTransform(
        ColorReference('editor.selectionBackground'),
        0.6,
      ),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'chat.checkpointSeparator',
    ColorDefaults(
      dark: ColorLiteral('#585858'),
      light: ColorLiteral('#a9a9a9'),
      hcDark: ColorLiteral('#a9a9a9'),
      hcLight: ColorLiteral('#a5a5a5'),
    ),
  ),
  ColorContribution(
    'chat.linesAddedForeground',
    ColorDefaults(
      dark: ColorLiteral('#54b054'),
      light: ColorLiteral('#107c10'),
      hcDark: ColorLiteral('#54b054'),
      hcLight: ColorLiteral('#107c10'),
    ),
  ),
  ColorContribution(
    'chat.linesRemovedForeground',
    ColorDefaults(
      dark: ColorLiteral('#fc6a6a'),
      light: ColorLiteral('#bc2f32'),
      hcDark: ColorLiteral('#f48771'),
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution(
    'chat.findMatchHighlightBackground',
    ColorDefaults(
      dark: ColorReference('editor.findMatchHighlightBackground'),
      light: ColorReference('editor.findMatchHighlightBackground'),
      hcDark: ColorLiteral('#ea5c0055'),
      hcLight: ColorLiteral('#ea5c0055'),
    ),
  ),
  ColorContribution(
    'chat.findMatchBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('chat.findMatchHighlightBackground'),
        2.0,
      ),
      light: TransparentTransform(
        ColorReference('chat.findMatchHighlightBackground'),
        2.0,
      ),
      hcDark: ColorLiteral('#ea5c00aa'),
      hcLight: ColorLiteral('#ea5c00aa'),
    ),
  ),
  ColorContribution(
    'chat.thinkingShimmer',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#000000'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#000000'),
    ),
  ),
  ColorContribution(
    'chat.workingProgressStableIconForeground',
    ColorDefaults(
      dark: ColorLiteral('#007acc'),
      light: ColorLiteral('#007acc'),
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'chat.workingProgressInsidersIconForeground',
    ColorDefaults(
      dark: ColorLiteral('#24bfa5'),
      light: ColorLiteral('#24bfa5'),
      hcDark: ColorReference('contrastActiveBorder'),
      hcLight: ColorReference('contrastActiveBorder'),
    ),
  ),
  ColorContribution(
    'chat.inputWorkingBorderColor1',
    ColorDefaults(
      dark: ColorReference('button.background'),
      light: ColorReference('button.background'),
      hcDark: ColorLiteral('#ffffff'),
      hcLight: ColorLiteral('#000000'),
    ),
  ),
  ColorContribution(
    'chat.inputWorkingBorderColor2',
    ColorDefaults(
      dark: DarkenTransform(ColorReference('button.background'), 0.5),
      light: DarkenTransform(ColorReference('button.background'), 0.3),
      hcDark: ColorLiteral('#a0a0a0'),
      hcLight: ColorLiteral('#555555'),
    ),
  ),
  ColorContribution(
    'chat.inputWorkingBorderColor3',
    ColorDefaults(
      dark: LightenTransform(ColorReference('button.background'), 0.5),
      light: LightenTransform(ColorReference('button.background'), 0.3),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorLiteral('#000000'),
    ),
  ),
  ColorContribution(
    'chat.voiceGlowBaseColor',
    ColorDefaults(
      dark: ColorReference('focusBorder'),
      light: ColorReference('focusBorder'),
      hcDark: ColorReference('focusBorder'),
      hcLight: ColorReference('focusBorder'),
    ),
  ),
  ColorContribution(
    'chat.voiceListeningGlow',
    ColorDefaults(dark: null, light: null, hcDark: null, hcLight: null),
  ),
  ColorContribution(
    'chat.voiceSpeakingGlow',
    ColorDefaults(dark: null, light: null, hcDark: null, hcLight: null),
  ),
  ColorContribution(
    'chat.dictationActiveMicGlow',
    ColorDefaults(
      dark: ColorReference('chat.voiceGlowBaseColor'),
      light: ColorReference('chat.voiceGlowBaseColor'),
      hcDark: ColorReference('chat.voiceGlowBaseColor'),
      hcLight: ColorReference('chat.voiceGlowBaseColor'),
    ),
  ),
  // src/vs/workbench/services/extensionManagement/common/extensionsIcons.ts
  ColorContribution(
    'extensionIcon.verifiedForeground',
    ColorDefaults(
      dark: ColorReference('textLink.foreground'),
      light: ColorReference('textLink.foreground'),
      hcDark: ColorReference('textLink.foreground'),
      hcLight: ColorReference('textLink.foreground'),
    ),
  ),
  // src/vs/workbench/contrib/extensions/browser/extensionsWidgets.ts
  ColorContribution(
    'extensionIcon.starForeground',
    ColorDefaults(
      dark: ColorLiteral('#ff8e00'),
      light: ColorLiteral('#df6100'),
      hcDark: ColorLiteral('#ff8e00'),
      hcLight: ColorReference('textLink.foreground'),
    ),
  ),
  ColorContribution(
    'extensionIcon.preReleaseForeground',
    ColorDefaults(
      dark: ColorLiteral('#1d9271'),
      light: ColorLiteral('#1d9271'),
      hcDark: ColorLiteral('#1d9271'),
      hcLight: ColorReference('textLink.foreground'),
    ),
  ),
  ColorContribution(
    'extensionIcon.sponsorForeground',
    ColorDefaults(
      dark: ColorLiteral('#d758b3'),
      light: ColorLiteral('#b51e78'),
      hcDark: null,
      hcLight: ColorLiteral('#b51e78'),
    ),
  ),
  ColorContribution(
    'extensionIcon.privateForeground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff60'),
      light: ColorLiteral('#00000060'),
      hcDark: ColorLiteral('#ffffff60'),
      hcLight: ColorLiteral('#00000060'),
    ),
  ),
  // src/vs/workbench/contrib/codeEditor/browser/find/simpleFindWidget.ts
  ColorContribution(
    'simpleFindWidget.sashBorder',
    ColorDefaults(
      dark: ColorLiteral('#454545'),
      light: ColorLiteral('#c8c8c8'),
      hcDark: ColorLiteral('#6fc3df'),
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  // src/vs/workbench/contrib/debug/browser/exceptionWidget.ts
  ColorContribution(
    'debugExceptionWidget.border',
    ColorDefaults(
      dark: ColorLiteral('#a31515'),
      light: ColorLiteral('#a31515'),
      hcDark: ColorLiteral('#a31515'),
      hcLight: ColorLiteral('#a31515'),
    ),
  ),
  ColorContribution(
    'debugExceptionWidget.background',
    ColorDefaults(
      dark: ColorLiteral('#420b0d'),
      light: ColorLiteral('#f1dfde'),
      hcDark: ColorLiteral('#420b0d'),
      hcLight: ColorLiteral('#f1dfde'),
    ),
  ),
  // src/vs/workbench/contrib/debug/browser/debugEditorContribution.ts
  ColorContribution(
    'editor.inlineValuesForeground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff80'),
      light: ColorLiteral('#00000080'),
      hcDark: ColorLiteral('#ffffff80'),
      hcLight: ColorLiteral('#00000080'),
    ),
  ),
  ColorContribution(
    'editor.inlineValuesBackground',
    ColorDefaults(
      dark: ColorLiteral('#ffc80033'),
      light: ColorLiteral('#ffc80033'),
      hcDark: ColorLiteral('#ffc80033'),
      hcLight: ColorLiteral('#ffc80033'),
    ),
  ),
  // src/vs/workbench/contrib/debug/browser/breakpointEditorContribution.ts
  ColorContribution(
    'debugIcon.breakpointForeground',
    ColorDefaults(
      dark: ColorLiteral('#e51400'),
      light: ColorLiteral('#e51400'),
      hcDark: ColorLiteral('#e51400'),
      hcLight: ColorLiteral('#e51400'),
    ),
  ),
  ColorContribution(
    'debugIcon.breakpointDisabledForeground',
    ColorDefaults(
      dark: ColorLiteral('#848484'),
      light: ColorLiteral('#848484'),
      hcDark: ColorLiteral('#848484'),
      hcLight: ColorLiteral('#848484'),
    ),
  ),
  ColorContribution(
    'debugIcon.breakpointUnverifiedForeground',
    ColorDefaults(
      dark: ColorLiteral('#848484'),
      light: ColorLiteral('#848484'),
      hcDark: ColorLiteral('#848484'),
      hcLight: ColorLiteral('#848484'),
    ),
  ),
  ColorContribution(
    'debugIcon.breakpointCurrentStackframeForeground',
    ColorDefaults(
      dark: ColorLiteral('#ffcc00'),
      light: ColorLiteral('#be8700'),
      hcDark: ColorLiteral('#ffcc00'),
      hcLight: ColorLiteral('#be8700'),
    ),
  ),
  ColorContribution(
    'debugIcon.breakpointStackframeForeground',
    ColorDefaults(
      dark: ColorLiteral('#89d185'),
      light: ColorLiteral('#89d185'),
      hcDark: ColorLiteral('#89d185'),
      hcLight: ColorLiteral('#89d185'),
    ),
  ),
  // src/vs/workbench/contrib/debug/browser/callStackEditorContribution.ts
  ColorContribution(
    'editor.stackFrameHighlightBackground',
    ColorDefaults(
      dark: ColorLiteral('#ffff0033'),
      light: ColorLiteral('#ffff6673'),
      hcDark: ColorLiteral('#ffff0033'),
      hcLight: ColorLiteral('#ffff6673'),
    ),
  ),
  ColorContribution(
    'editor.focusedStackFrameHighlightBackground',
    ColorDefaults(
      dark: ColorLiteral('#7abd7a4d'),
      light: ColorLiteral('#cee7ce73'),
      hcDark: ColorLiteral('#7abd7a4d'),
      hcLight: ColorLiteral('#cee7ce73'),
    ),
  ),
  // src/vs/editor/browser/widget/multiDiffEditor/colors.ts
  ColorContribution(
    'multiDiffEditor.headerBackground',
    ColorDefaults(
      dark: ColorLiteral('#262626'),
      light: ColorReference('tab.inactiveBackground'),
      hcDark: ColorReference('tab.inactiveBackground'),
      hcLight: ColorReference('tab.inactiveBackground'),
    ),
  ),
  ColorContribution(
    'multiDiffEditor.background',
    ColorDefaults(
      dark: ColorReference('editor.background'),
      light: ColorReference('editor.background'),
      hcDark: ColorReference('editor.background'),
      hcLight: ColorReference('editor.background'),
    ),
  ),
  ColorContribution(
    'multiDiffEditor.border',
    ColorDefaults(
      dark: ColorReference('sideBarSectionHeader.border'),
      light: ColorLiteral('#cccccc'),
      hcDark: ColorReference('sideBarSectionHeader.border'),
      hcLight: ColorLiteral('#cccccc'),
    ),
  ),
  // src/vs/workbench/contrib/chat/browser/chatEditing/chatEditingModifiedFileEntry.ts
  ColorContribution(
    'minimap.chatEditHighlight',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('editor.background'), 0.6),
      light: TransparentTransform(ColorReference('editor.background'), 0.6),
      hcDark: TransparentTransform(ColorReference('editor.background'), 0.6),
      hcLight: TransparentTransform(ColorReference('editor.background'), 0.6),
    ),
  ),
  // src/vs/workbench/contrib/mcp/browser/mcpServerWidgets.ts
  ColorContribution(
    'mcpIcon.starForeground',
    ColorDefaults(
      dark: ColorLiteral('#ff8e00'),
      light: ColorLiteral('#df6100'),
      hcDark: ColorLiteral('#ff8e00'),
      hcLight: ColorReference('textLink.foreground'),
    ),
  ),
  // src/vs/workbench/contrib/interactive/browser/interactive.contribution.ts
  ColorContribution(
    'interactive.activeCodeBorder',
    ColorDefaults(
      dark: IfDefinedThenElseTransform(
        'peekView.border',
        ColorReference('peekView.border'),
        ColorLiteral('#007acc'),
      ),
      light: IfDefinedThenElseTransform(
        'peekView.border',
        ColorReference('peekView.border'),
        ColorLiteral('#007acc'),
      ),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'interactive.inactiveCodeBorder',
    ColorDefaults(
      dark: IfDefinedThenElseTransform(
        'list.inactiveSelectionBackground',
        ColorReference('list.inactiveSelectionBackground'),
        ColorLiteral('#37373d'),
      ),
      light: IfDefinedThenElseTransform(
        'list.inactiveSelectionBackground',
        ColorReference('list.inactiveSelectionBackground'),
        ColorLiteral('#e4e6f1'),
      ),
      hcDark: ColorReference('panel.border'),
      hcLight: ColorReference('panel.border'),
    ),
  ),
  // src/vs/workbench/contrib/testing/browser/theme.ts
  ColorContribution(
    'testing.iconFailed',
    ColorDefaults(
      dark: ColorReference('list.errorForeground'),
      light: ColorReference('list.errorForeground'),
      hcDark: ColorReference('list.errorForeground'),
      hcLight: ColorReference('list.errorForeground'),
    ),
  ),
  ColorContribution(
    'testing.iconErrored',
    ColorDefaults(
      dark: ColorReference('list.errorForeground'),
      light: ColorReference('list.errorForeground'),
      hcDark: ColorReference('list.errorForeground'),
      hcLight: ColorReference('list.errorForeground'),
    ),
  ),
  ColorContribution(
    'testing.iconPassed',
    ColorDefaults(
      dark: ColorLiteral('#73c991'),
      light: ColorLiteral('#73c991'),
      hcDark: ColorLiteral('#73c991'),
      hcLight: ColorLiteral('#007100'),
    ),
  ),
  ColorContribution(
    'testing.runAction',
    ColorDefaults(
      dark: ColorReference('testing.iconPassed'),
      light: ColorReference('testing.iconPassed'),
      hcDark: ColorReference('testing.iconPassed'),
      hcLight: ColorReference('testing.iconPassed'),
    ),
  ),
  ColorContribution(
    'testing.iconQueued',
    ColorDefaults(
      dark: ColorReference('list.warningForeground'),
      light: ColorReference('list.warningForeground'),
      hcDark: ColorReference('list.warningForeground'),
      hcLight: ColorReference('list.warningForeground'),
    ),
  ),
  ColorContribution(
    'testing.iconUnset',
    ColorDefaults(
      dark: ColorLiteral('#848484'),
      light: ColorLiteral('#848484'),
      hcDark: ColorLiteral('#848484'),
      hcLight: ColorLiteral('#848484'),
    ),
  ),
  ColorContribution(
    'testing.iconSkipped',
    ColorDefaults(
      dark: ColorLiteral('#848484'),
      light: ColorLiteral('#848484'),
      hcDark: ColorLiteral('#848484'),
      hcLight: ColorLiteral('#848484'),
    ),
  ),
  ColorContribution(
    'testing.peekBorder',
    ColorDefaults(
      dark: ColorReference('editorError.foreground'),
      light: ColorReference('editorError.foreground'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'testing.messagePeekBorder',
    ColorDefaults(
      dark: ColorReference('editorInfo.foreground'),
      light: ColorReference('editorInfo.foreground'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'testing.peekHeaderBackground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('editorError.foreground'), 0.1),
      light: TransparentTransform(
        ColorReference('editorError.foreground'),
        0.1,
      ),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'testing.messagePeekHeaderBackground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('editorInfo.foreground'), 0.1),
      light: TransparentTransform(ColorReference('editorInfo.foreground'), 0.1),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'testing.coveredBackground',
    ColorDefaults(
      dark: ColorReference('diffEditor.insertedTextBackground'),
      light: ColorReference('diffEditor.insertedTextBackground'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'testing.coveredBorder',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('testing.coveredBackground'),
        0.75,
      ),
      light: TransparentTransform(
        ColorReference('testing.coveredBackground'),
        0.75,
      ),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'testing.coveredGutterBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.6,
      ),
      light: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.6,
      ),
      hcDark: ColorReference('charts.green'),
      hcLight: ColorReference('charts.green'),
    ),
  ),
  ColorContribution(
    'testing.uncoveredBranchBackground',
    ColorDefaults(
      dark: OpaqueTransform(
        TransparentTransform(
          ColorReference('diffEditor.removedTextBackground'),
          2.0,
        ),
        ColorReference('editor.background'),
      ),
      light: OpaqueTransform(
        TransparentTransform(
          ColorReference('diffEditor.removedTextBackground'),
          2.0,
        ),
        ColorReference('editor.background'),
      ),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'testing.uncoveredBackground',
    ColorDefaults(
      dark: ColorReference('diffEditor.removedTextBackground'),
      light: ColorReference('diffEditor.removedTextBackground'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'testing.uncoveredBorder',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('testing.uncoveredBackground'),
        0.75,
      ),
      light: TransparentTransform(
        ColorReference('testing.uncoveredBackground'),
        0.75,
      ),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'testing.uncoveredGutterBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        1.5,
      ),
      light: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        1.5,
      ),
      hcDark: ColorReference('charts.red'),
      hcLight: ColorReference('charts.red'),
    ),
  ),
  ColorContribution(
    'testing.coveredMinimapBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.6,
      ),
      light: TransparentTransform(
        ColorReference('diffEditor.insertedTextBackground'),
        0.6,
      ),
      hcDark: ColorReference('charts.green'),
      hcLight: ColorReference('charts.green'),
    ),
  ),
  ColorContribution(
    'testing.uncoveredMinimapBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        1.5,
      ),
      light: TransparentTransform(
        ColorReference('diffEditor.removedTextBackground'),
        1.5,
      ),
      hcDark: ColorReference('charts.red'),
      hcLight: ColorReference('charts.red'),
    ),
  ),
  ColorContribution(
    'testing.coverCountBadgeBackground',
    ColorDefaults(
      dark: ColorReference('badge.background'),
      light: ColorReference('badge.background'),
      hcDark: ColorReference('badge.background'),
      hcLight: ColorReference('badge.background'),
    ),
  ),
  ColorContribution(
    'testing.coverCountBadgeForeground',
    ColorDefaults(
      dark: ColorReference('badge.foreground'),
      light: ColorReference('badge.foreground'),
      hcDark: ColorReference('badge.foreground'),
      hcLight: ColorReference('badge.foreground'),
    ),
  ),
  ColorContribution(
    'testing.message.error.badgeBackground',
    ColorDefaults(
      dark: ColorReference('activityErrorBadge.background'),
      light: ColorReference('activityErrorBadge.background'),
      hcDark: ColorReference('activityErrorBadge.background'),
      hcLight: ColorReference('activityErrorBadge.background'),
    ),
  ),
  ColorContribution(
    'testing.message.error.badgeBorder',
    ColorDefaults(
      dark: ColorReference('testing.message.error.badgeBackground'),
      light: ColorReference('testing.message.error.badgeBackground'),
      hcDark: ColorReference('testing.message.error.badgeBackground'),
      hcLight: ColorReference('testing.message.error.badgeBackground'),
    ),
  ),
  ColorContribution(
    'testing.message.error.badgeForeground',
    ColorDefaults(
      dark: ColorReference('activityErrorBadge.foreground'),
      light: ColorReference('activityErrorBadge.foreground'),
      hcDark: ColorReference('activityErrorBadge.foreground'),
      hcLight: ColorReference('activityErrorBadge.foreground'),
    ),
  ),
  ColorContribution('testing.message.error.lineBackground', null),
  ColorContribution(
    'testing.message.info.decorationForeground',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('editor.foreground'), 0.5),
      light: TransparentTransform(ColorReference('editor.foreground'), 0.5),
      hcDark: TransparentTransform(ColorReference('editor.foreground'), 0.5),
      hcLight: TransparentTransform(ColorReference('editor.foreground'), 0.5),
    ),
  ),
  ColorContribution('testing.message.info.lineBackground', null),
  ColorContribution(
    'testing.iconErrored.retired',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('testing.iconErrored'), 0.7),
      light: TransparentTransform(ColorReference('testing.iconErrored'), 0.7),
      hcDark: TransparentTransform(ColorReference('testing.iconErrored'), 0.7),
      hcLight: TransparentTransform(ColorReference('testing.iconErrored'), 0.7),
    ),
  ),
  ColorContribution(
    'testing.iconFailed.retired',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('testing.iconFailed'), 0.7),
      light: TransparentTransform(ColorReference('testing.iconFailed'), 0.7),
      hcDark: TransparentTransform(ColorReference('testing.iconFailed'), 0.7),
      hcLight: TransparentTransform(ColorReference('testing.iconFailed'), 0.7),
    ),
  ),
  ColorContribution(
    'testing.iconPassed.retired',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('testing.iconPassed'), 0.7),
      light: TransparentTransform(ColorReference('testing.iconPassed'), 0.7),
      hcDark: TransparentTransform(ColorReference('testing.iconPassed'), 0.7),
      hcLight: TransparentTransform(ColorReference('testing.iconPassed'), 0.7),
    ),
  ),
  ColorContribution(
    'testing.iconQueued.retired',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('testing.iconQueued'), 0.7),
      light: TransparentTransform(ColorReference('testing.iconQueued'), 0.7),
      hcDark: TransparentTransform(ColorReference('testing.iconQueued'), 0.7),
      hcLight: TransparentTransform(ColorReference('testing.iconQueued'), 0.7),
    ),
  ),
  ColorContribution(
    'testing.iconUnset.retired',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('testing.iconUnset'), 0.7),
      light: TransparentTransform(ColorReference('testing.iconUnset'), 0.7),
      hcDark: TransparentTransform(ColorReference('testing.iconUnset'), 0.7),
      hcLight: TransparentTransform(ColorReference('testing.iconUnset'), 0.7),
    ),
  ),
  ColorContribution(
    'testing.iconSkipped.retired',
    ColorDefaults(
      dark: TransparentTransform(ColorReference('testing.iconSkipped'), 0.7),
      light: TransparentTransform(ColorReference('testing.iconSkipped'), 0.7),
      hcDark: TransparentTransform(ColorReference('testing.iconSkipped'), 0.7),
      hcLight: TransparentTransform(ColorReference('testing.iconSkipped'), 0.7),
    ),
  ),
  // src/vs/workbench/contrib/searchEditor/browser/searchEditor.ts
  ColorContribution(
    'searchEditor.textInputBorder',
    ColorDefaults(
      dark: ColorReference('input.border'),
      light: ColorReference('input.border'),
      hcDark: ColorReference('input.border'),
      hcLight: ColorReference('input.border'),
    ),
  ),
  // src/vs/workbench/contrib/debug/browser/statusbarColorProvider.ts
  ColorContribution(
    'statusBar.debuggingBackground',
    ColorDefaults(
      dark: ColorLiteral('#cc6633'),
      light: ColorLiteral('#cc6633'),
      hcDark: ColorLiteral('#ba592c'),
      hcLight: ColorLiteral('#b5200d'),
    ),
  ),
  ColorContribution(
    'statusBar.debuggingForeground',
    ColorDefaults(
      dark: ColorReference('statusBar.foreground'),
      light: ColorReference('statusBar.foreground'),
      hcDark: ColorReference('statusBar.foreground'),
      hcLight: ColorLiteral('#ffffff'),
    ),
  ),
  ColorContribution(
    'statusBar.debuggingBorder',
    ColorDefaults(
      dark: ColorReference('statusBar.border'),
      light: ColorReference('statusBar.border'),
      hcDark: ColorReference('statusBar.border'),
      hcLight: ColorReference('statusBar.border'),
    ),
  ),
  ColorContribution(
    'commandCenter.debuggingBackground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('statusBar.debuggingBackground'),
        0.258,
      ),
      light: TransparentTransform(
        ColorReference('statusBar.debuggingBackground'),
        0.258,
      ),
      hcDark: TransparentTransform(
        ColorReference('statusBar.debuggingBackground'),
        0.258,
      ),
      hcLight: TransparentTransform(
        ColorReference('statusBar.debuggingBackground'),
        0.258,
      ),
    ),
  ),
  // src/vs/workbench/contrib/mergeEditor/browser/view/colors.ts
  ColorContribution(
    'mergeEditor.change.background',
    ColorDefaults(
      dark: ColorLiteral('#9bb95533'),
      light: ColorLiteral('#9bb95533'),
      hcDark: ColorLiteral('#9bb95533'),
      hcLight: ColorLiteral('#9bb95533'),
    ),
  ),
  ColorContribution(
    'mergeEditor.change.word.background',
    ColorDefaults(
      dark: ColorLiteral('#9ccc2c33'),
      light: ColorLiteral('#9ccc2c66'),
      hcDark: ColorLiteral('#9ccc2c33'),
      hcLight: ColorLiteral('#9ccc2c66'),
    ),
  ),
  ColorContribution(
    'mergeEditor.changeBase.background',
    ColorDefaults(
      dark: ColorLiteral('#4b1818'),
      light: ColorLiteral('#ffcccc'),
      hcDark: ColorLiteral('#4b1818'),
      hcLight: ColorLiteral('#ffcccc'),
    ),
  ),
  ColorContribution(
    'mergeEditor.changeBase.word.background',
    ColorDefaults(
      dark: ColorLiteral('#6f1313'),
      light: ColorLiteral('#ffa3a3'),
      hcDark: ColorLiteral('#6f1313'),
      hcLight: ColorLiteral('#ffa3a3'),
    ),
  ),
  ColorContribution(
    'mergeEditor.conflict.unhandledUnfocused.border',
    ColorDefaults(
      dark: ColorLiteral('#ffa6007a'),
      light: ColorLiteral('#ffa600'),
      hcDark: ColorLiteral('#ffa6007a'),
      hcLight: ColorLiteral('#ffa6007a'),
    ),
  ),
  ColorContribution(
    'mergeEditor.conflict.unhandledFocused.border',
    ColorDefaults(
      dark: ColorLiteral('#ffa600'),
      light: ColorLiteral('#ffa600'),
      hcDark: ColorLiteral('#ffa600'),
      hcLight: ColorLiteral('#ffa600'),
    ),
  ),
  ColorContribution(
    'mergeEditor.conflict.handledUnfocused.border',
    ColorDefaults(
      dark: ColorLiteral('#86868649'),
      light: ColorLiteral('#86868649'),
      hcDark: ColorLiteral('#86868649'),
      hcLight: ColorLiteral('#86868649'),
    ),
  ),
  ColorContribution(
    'mergeEditor.conflict.handledFocused.border',
    ColorDefaults(
      dark: ColorLiteral('#c1c1c1cc'),
      light: ColorLiteral('#c1c1c1cc'),
      hcDark: ColorLiteral('#c1c1c1cc'),
      hcLight: ColorLiteral('#c1c1c1cc'),
    ),
  ),
  ColorContribution(
    'mergeEditor.conflict.handled.minimapOverViewRuler',
    ColorDefaults(
      dark: ColorLiteral('#adaca8ee'),
      light: ColorLiteral('#adaca8ee'),
      hcDark: ColorLiteral('#adaca8ee'),
      hcLight: ColorLiteral('#adaca8ee'),
    ),
  ),
  ColorContribution(
    'mergeEditor.conflict.unhandled.minimapOverViewRuler',
    ColorDefaults(
      dark: ColorLiteral('#fcba03'),
      light: ColorLiteral('#fcba03'),
      hcDark: ColorLiteral('#fcba03'),
      hcLight: ColorLiteral('#fcba03'),
    ),
  ),
  ColorContribution(
    'mergeEditor.conflictingLines.background',
    ColorDefaults(
      dark: ColorLiteral('#ffea0047'),
      light: ColorLiteral('#ffea0047'),
      hcDark: ColorLiteral('#ffea0047'),
      hcLight: ColorLiteral('#ffea0047'),
    ),
  ),
  ColorContribution(
    'mergeEditor.conflict.input1.background',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('merge.currentHeaderBackground'),
        0.4,
      ),
      light: TransparentTransform(
        ColorReference('merge.currentHeaderBackground'),
        0.4,
      ),
      hcDark: TransparentTransform(
        ColorReference('merge.currentHeaderBackground'),
        0.4,
      ),
      hcLight: TransparentTransform(
        ColorReference('merge.currentHeaderBackground'),
        0.4,
      ),
    ),
  ),
  ColorContribution(
    'mergeEditor.conflict.input2.background',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('merge.incomingHeaderBackground'),
        0.4,
      ),
      light: TransparentTransform(
        ColorReference('merge.incomingHeaderBackground'),
        0.4,
      ),
      hcDark: TransparentTransform(
        ColorReference('merge.incomingHeaderBackground'),
        0.4,
      ),
      hcLight: TransparentTransform(
        ColorReference('merge.incomingHeaderBackground'),
        0.4,
      ),
    ),
  ),
  // src/vs/workbench/contrib/terminalContrib/stickyScroll/browser/terminalStickyScrollColorRegistry.ts
  ColorContribution('terminalStickyScroll.background', null),
  ColorContribution(
    'terminalStickyScrollHover.background',
    ColorDefaults(
      dark: ColorLiteral('#2a2d2e'),
      light: ColorLiteral('#f0f0f0'),
      hcDark: ColorLiteral('#e48b39'),
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  ColorContribution(
    'terminalStickyScroll.border',
    ColorDefaults(
      dark: null,
      light: null,
      hcDark: ColorLiteral('#6fc3df'),
      hcLight: ColorLiteral('#0f4a85'),
    ),
  ),
  // src/vs/workbench/contrib/terminalContrib/commandGuide/browser/terminal.commandGuide.contribution.ts
  ColorContribution(
    'terminalCommandGuide.foreground',
    ColorDefaults(
      dark: TransparentTransform(
        ColorReference('list.inactiveSelectionBackground'),
        1.0,
      ),
      light: TransparentTransform(
        ColorReference('list.inactiveSelectionBackground'),
        1.0,
      ),
      hcDark: ColorReference('panel.border'),
      hcLight: ColorReference('panel.border'),
    ),
  ),
  // src/vs/workbench/contrib/terminalContrib/suggest/browser/terminalSymbolIcons.ts
  ColorContribution(
    'terminalSymbolIcon.flagForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.enumeratorForeground'),
      light: ColorReference('symbolIcon.enumeratorForeground'),
      hcDark: ColorReference('symbolIcon.enumeratorForeground'),
      hcLight: ColorReference('symbolIcon.enumeratorForeground'),
    ),
  ),
  ColorContribution(
    'terminalSymbolIcon.aliasForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.methodForeground'),
      light: ColorReference('symbolIcon.methodForeground'),
      hcDark: ColorReference('symbolIcon.methodForeground'),
      hcLight: ColorReference('symbolIcon.methodForeground'),
    ),
  ),
  ColorContribution(
    'terminalSymbolIcon.optionValueForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.enumeratorMemberForeground'),
      light: ColorReference('symbolIcon.enumeratorMemberForeground'),
      hcDark: ColorReference('symbolIcon.enumeratorMemberForeground'),
      hcLight: ColorReference('symbolIcon.enumeratorMemberForeground'),
    ),
  ),
  ColorContribution(
    'terminalSymbolIcon.methodForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.methodForeground'),
      light: ColorReference('symbolIcon.methodForeground'),
      hcDark: ColorReference('symbolIcon.methodForeground'),
      hcLight: ColorReference('symbolIcon.methodForeground'),
    ),
  ),
  ColorContribution(
    'terminalSymbolIcon.argumentForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.variableForeground'),
      light: ColorReference('symbolIcon.variableForeground'),
      hcDark: ColorReference('symbolIcon.variableForeground'),
      hcLight: ColorReference('symbolIcon.variableForeground'),
    ),
  ),
  ColorContribution(
    'terminalSymbolIcon.optionForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.enumeratorForeground'),
      light: ColorReference('symbolIcon.enumeratorForeground'),
      hcDark: ColorReference('symbolIcon.enumeratorForeground'),
      hcLight: ColorReference('symbolIcon.enumeratorForeground'),
    ),
  ),
  ColorContribution('terminalSymbolIcon.inlineSuggestionForeground', null),
  ColorContribution(
    'terminalSymbolIcon.fileForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.fileForeground'),
      light: ColorReference('symbolIcon.fileForeground'),
      hcDark: ColorReference('symbolIcon.fileForeground'),
      hcLight: ColorReference('symbolIcon.fileForeground'),
    ),
  ),
  ColorContribution(
    'terminalSymbolIcon.folderForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.folderForeground'),
      light: ColorReference('symbolIcon.folderForeground'),
      hcDark: ColorReference('symbolIcon.folderForeground'),
      hcLight: ColorReference('symbolIcon.folderForeground'),
    ),
  ),
  ColorContribution(
    'terminalSymbolIcon.commitForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.fileForeground'),
      light: ColorReference('symbolIcon.fileForeground'),
      hcDark: ColorReference('symbolIcon.fileForeground'),
      hcLight: ColorReference('symbolIcon.fileForeground'),
    ),
  ),
  ColorContribution(
    'terminalSymbolIcon.branchForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.fileForeground'),
      light: ColorReference('symbolIcon.fileForeground'),
      hcDark: ColorReference('symbolIcon.fileForeground'),
      hcLight: ColorReference('symbolIcon.fileForeground'),
    ),
  ),
  ColorContribution(
    'terminalSymbolIcon.tagForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.fileForeground'),
      light: ColorReference('symbolIcon.fileForeground'),
      hcDark: ColorReference('symbolIcon.fileForeground'),
      hcLight: ColorReference('symbolIcon.fileForeground'),
    ),
  ),
  ColorContribution(
    'terminalSymbolIcon.stashForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.fileForeground'),
      light: ColorReference('symbolIcon.fileForeground'),
      hcDark: ColorReference('symbolIcon.fileForeground'),
      hcLight: ColorReference('symbolIcon.fileForeground'),
    ),
  ),
  ColorContribution(
    'terminalSymbolIcon.remoteForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.fileForeground'),
      light: ColorReference('symbolIcon.fileForeground'),
      hcDark: ColorReference('symbolIcon.fileForeground'),
      hcLight: ColorReference('symbolIcon.fileForeground'),
    ),
  ),
  ColorContribution(
    'terminalSymbolIcon.pullRequestForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.fileForeground'),
      light: ColorReference('symbolIcon.fileForeground'),
      hcDark: ColorReference('symbolIcon.fileForeground'),
      hcLight: ColorReference('symbolIcon.fileForeground'),
    ),
  ),
  ColorContribution(
    'terminalSymbolIcon.pullRequestDoneForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.fileForeground'),
      light: ColorReference('symbolIcon.fileForeground'),
      hcDark: ColorReference('symbolIcon.fileForeground'),
      hcLight: ColorReference('symbolIcon.fileForeground'),
    ),
  ),
  ColorContribution(
    'terminalSymbolIcon.symbolicLinkFileForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.fileForeground'),
      light: ColorReference('symbolIcon.fileForeground'),
      hcDark: ColorReference('symbolIcon.fileForeground'),
      hcLight: ColorReference('symbolIcon.fileForeground'),
    ),
  ),
  ColorContribution(
    'terminalSymbolIcon.symbolicLinkFolderForeground',
    ColorDefaults(
      dark: ColorReference('symbolIcon.folderForeground'),
      light: ColorReference('symbolIcon.folderForeground'),
      hcDark: ColorReference('symbolIcon.folderForeground'),
      hcLight: ColorReference('symbolIcon.folderForeground'),
    ),
  ),
  ColorContribution(
    'terminalSymbolIcon.symbolText',
    ColorDefaults(
      dark: ColorReference('symbolIcon.fileForeground'),
      light: ColorReference('symbolIcon.fileForeground'),
      hcDark: ColorReference('symbolIcon.fileForeground'),
      hcLight: ColorReference('symbolIcon.fileForeground'),
    ),
  ),
  // src/vs/workbench/contrib/markdown/common/markdownColors.ts
  ColorContribution(
    'markdownAlert.note.foreground',
    ColorDefaults(
      dark: ColorReference('editorInfo.foreground'),
      light: ColorReference('editorInfo.foreground'),
      hcDark: ColorReference('editorInfo.foreground'),
      hcLight: ColorReference('editorInfo.foreground'),
    ),
  ),
  ColorContribution(
    'markdownAlert.tip.foreground',
    ColorDefaults(
      dark: ColorReference('charts.green'),
      light: ColorReference('charts.green'),
      hcDark: ColorReference('charts.green'),
      hcLight: ColorReference('charts.green'),
    ),
  ),
  ColorContribution(
    'markdownAlert.important.foreground',
    ColorDefaults(
      dark: ColorReference('charts.purple'),
      light: ColorReference('charts.purple'),
      hcDark: ColorReference('charts.purple'),
      hcLight: ColorReference('charts.purple'),
    ),
  ),
  ColorContribution(
    'markdownAlert.warning.foreground',
    ColorDefaults(
      dark: ColorReference('editorWarning.foreground'),
      light: ColorReference('editorWarning.foreground'),
      hcDark: ColorReference('editorWarning.foreground'),
      hcLight: ColorReference('editorWarning.foreground'),
    ),
  ),
  ColorContribution(
    'markdownAlert.caution.foreground',
    ColorDefaults(
      dark: ColorReference('editorError.foreground'),
      light: ColorReference('editorError.foreground'),
      hcDark: ColorReference('editorError.foreground'),
      hcLight: ColorReference('editorError.foreground'),
    ),
  ),
  // src/vs/workbench/contrib/welcomeGettingStarted/browser/gettingStartedColors.ts
  ColorContribution('welcomePage.background', null),
  ColorContribution(
    'welcomePage.tileBackground',
    ColorDefaults(
      dark: ColorReference('editorWidget.background'),
      light: ColorReference('editorWidget.background'),
      hcDark: ColorLiteral('#000000'),
      hcLight: ColorReference('editorWidget.background'),
    ),
  ),
  ColorContribution(
    'welcomePage.tileHoverBackground',
    ColorDefaults(
      dark: LightenTransform(ColorReference('editorWidget.background'), 0.2),
      light: DarkenTransform(ColorReference('editorWidget.background'), 0.1),
      hcDark: null,
      hcLight: null,
    ),
  ),
  ColorContribution(
    'welcomePage.tileBorder',
    ColorDefaults(
      dark: ColorLiteral('#ffffff1a'),
      light: ColorLiteral('#0000001a'),
      hcDark: ColorReference('contrastBorder'),
      hcLight: ColorReference('contrastBorder'),
    ),
  ),
  ColorContribution(
    'welcomePage.progress.background',
    ColorDefaults(
      dark: ColorReference('input.background'),
      light: ColorReference('input.background'),
      hcDark: ColorReference('input.background'),
      hcLight: ColorReference('input.background'),
    ),
  ),
  ColorContribution(
    'welcomePage.progress.foreground',
    ColorDefaults(
      dark: ColorReference('textLink.foreground'),
      light: ColorReference('textLink.foreground'),
      hcDark: ColorReference('textLink.foreground'),
      hcLight: ColorReference('textLink.foreground'),
    ),
  ),
  ColorContribution(
    'walkthrough.stepTitle.foreground',
    ColorDefaults(
      dark: ColorLiteral('#ffffff'),
      light: ColorLiteral('#000000'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  // src/vs/workbench/contrib/welcomeWalkthrough/common/walkThroughUtils.ts
  ColorContribution(
    'walkThrough.embeddedEditorBackground',
    ColorDefaults(
      dark: ColorLiteral('#00000066'),
      light: ColorLiteral('#f4f4f4'),
      hcDark: null,
      hcLight: null,
    ),
  ),
  // src/vs/workbench/contrib/userDataProfile/browser/userDataProfilesEditor.ts
  ColorContribution(
    'profiles.sashBorder',
    ColorDefaults(
      dark: ColorReference('panel.border'),
      light: ColorReference('panel.border'),
      hcDark: ColorReference('panel.border'),
      hcLight: ColorReference('panel.border'),
    ),
  ),
  // extensions/git/package.json contributes.colors
  ColorContribution(
    'gitDecoration.addedResourceForeground',
    ColorDefaults(
      dark: ColorLiteral('#81b88b'),
      light: ColorLiteral('#587c0c'),
      hcDark: ColorLiteral('#a1e3ad'),
      hcLight: ColorLiteral('#374e06'),
    ),
  ),
  ColorContribution(
    'gitDecoration.modifiedResourceForeground',
    ColorDefaults(
      dark: ColorLiteral('#e2c08d'),
      light: ColorLiteral('#895503'),
      hcDark: ColorLiteral('#e2c08d'),
      hcLight: ColorLiteral('#895503'),
    ),
  ),
  ColorContribution(
    'gitDecoration.deletedResourceForeground',
    ColorDefaults(
      dark: ColorLiteral('#c74e39'),
      light: ColorLiteral('#ad0707'),
      hcDark: ColorLiteral('#c74e39'),
      hcLight: ColorLiteral('#ad0707'),
    ),
  ),
  ColorContribution(
    'gitDecoration.renamedResourceForeground',
    ColorDefaults(
      dark: ColorLiteral('#73c991'),
      light: ColorLiteral('#007100'),
      hcDark: ColorLiteral('#73c991'),
      hcLight: ColorLiteral('#007100'),
    ),
  ),
  ColorContribution(
    'gitDecoration.untrackedResourceForeground',
    ColorDefaults(
      dark: ColorLiteral('#73c991'),
      light: ColorLiteral('#007100'),
      hcDark: ColorLiteral('#73c991'),
      hcLight: ColorLiteral('#007100'),
    ),
  ),
  ColorContribution(
    'gitDecoration.ignoredResourceForeground',
    ColorDefaults(
      dark: ColorLiteral('#8c8c8c'),
      light: ColorLiteral('#8e8e90'),
      hcDark: ColorLiteral('#a7a8a9'),
      hcLight: ColorLiteral('#8e8e90'),
    ),
  ),
  ColorContribution(
    'gitDecoration.stageModifiedResourceForeground',
    ColorDefaults(
      dark: ColorLiteral('#e2c08d'),
      light: ColorLiteral('#895503'),
      hcDark: ColorLiteral('#e2c08d'),
      hcLight: ColorLiteral('#895503'),
    ),
  ),
  ColorContribution(
    'gitDecoration.stageDeletedResourceForeground',
    ColorDefaults(
      dark: ColorLiteral('#c74e39'),
      light: ColorLiteral('#ad0707'),
      hcDark: ColorLiteral('#c74e39'),
      hcLight: ColorLiteral('#ad0707'),
    ),
  ),
  ColorContribution(
    'gitDecoration.conflictingResourceForeground',
    ColorDefaults(
      dark: ColorLiteral('#e4676b'),
      light: ColorLiteral('#ad0707'),
      hcDark: ColorLiteral('#c74e39'),
      hcLight: ColorLiteral('#ad0707'),
    ),
  ),
  ColorContribution(
    'gitDecoration.submoduleResourceForeground',
    ColorDefaults(
      dark: ColorLiteral('#8db9e2'),
      light: ColorLiteral('#1258a7'),
      hcDark: ColorLiteral('#8db9e2'),
      hcLight: ColorLiteral('#1258a7'),
    ),
  ),
  ColorContribution(
    'git.blame.editorDecorationForeground',
    ColorDefaults(
      dark: ColorReference('editorInlayHint.foreground'),
      light: ColorReference('editorInlayHint.foreground'),
      hcDark: ColorReference('editorInlayHint.foreground'),
      hcLight: ColorReference('editorInlayHint.foreground'),
    ),
  ),
];
