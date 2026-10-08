import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    CodeFont.families.value = CodeFont.defaultFamilies;
    CodeFont.size.value = CodeFont.defaultSize;
    CodeFont.ligatures.value = true;
    CodeFont.uiScale.value = CodeFont.defaultUiScale;
  });

  test('a family list: comma-separated or an array, quotes and blanks '
      'dropped; none left is the default', () {
    expect(CodeFont.parseFamilies(null), CodeFont.defaultFamilies);
    expect(CodeFont.parseFamilies(''), CodeFont.defaultFamilies);
    expect(CodeFont.parseFamilies(' , "" '), CodeFont.defaultFamilies);
    expect(CodeFont.parseFamilies('JetBrains Mono, Fira Code'), [
      'JetBrains Mono',
      'Fira Code',
    ]);
    expect(CodeFont.parseFamilies("'Iosevka', Consolas"), [
      'Iosevka',
      'Consolas',
    ]);
    expect(CodeFont.parseFamilies(['Iosevka', 3, 'Menlo']), [
      'Iosevka',
      'Menlo',
    ]);
  });

  test('the family setting is unwritten for the default', () {
    expect(CodeFont.familiesSetting(CodeFont.defaultFamilies), isNull);
    expect(CodeFont.familiesSetting(['Iosevka', 'Menlo']), 'Iosevka, Menlo');
  });

  test('a size: a number clamped to 8 to 32; unset is the default', () {
    expect(CodeFont.parseSize(null), CodeFont.defaultSize);
    expect(CodeFont.parseSize('big'), CodeFont.defaultSize);
    expect(CodeFont.parseSize(4), CodeFont.minSize);
    expect(CodeFont.parseSize(40), CodeFont.maxSize);
    expect(CodeFont.parseSize(16), 16);
    expect(CodeFont.sizeSetting(CodeFont.defaultSize), isNull);
    expect(CodeFont.sizeSetting(16), 16);
  });

  test('a size drawn at the editor\'s moves by the user\'s choice, and is '
      'the base at the default', () {
    expect(CodeFont.sized(13), CodeFont.defaultSize);
    CodeFont.size.value = 16;
    expect(CodeFont.sized(13), 16);
    expect(CodeFont.sized(12), 15);
    CodeFont.size.value = CodeFont.defaultSize;
    expect(CodeFont.sized(12), 12 + CodeFont.defaultSize - 13);
  });

  test('the code style: the family, its fallbacks and the size; ligatures '
      'come with it', () {
    CodeFont.families.value = ['Iosevka', 'Menlo'];
    CodeFont.size.value = 16;
    final style = AppFonts.codeStyle(13);
    expect(style.fontFamily, 'Iosevka');
    expect(style.fontFamilyFallback, ['Menlo']);
    expect(style.fontSize, 16);
    expect(style.fontFeatures, isNull);
    CodeFont.ligatures.value = false;
    expect(AppFonts.codeStyle(13).fontFeatures, isNotNull);
  });

  test('ligatures are on unless settings.json says off, and off turns '
      'their features off', () {
    expect(CodeFont.parseLigatures(null), isTrue);
    expect(CodeFont.parseLigatures(false), isFalse);
    expect(CodeFont.ligaturesSetting(true), isNull);
    expect(CodeFont.ligaturesSetting(false), false);
    expect(CodeFont.features, isNull);
    CodeFont.ligatures.value = false;
    final features = CodeFont.features!.map((f) => f.feature).toList();
    expect(features, ['liga', 'calt']);
  });

  test(
    'the window\'s text scale: one of its steps; the default is unwritten',
    () {
      expect(CodeFont.parseUiScale(null), CodeFont.defaultUiScale);
      expect(CodeFont.parseUiScale(111), CodeFont.defaultUiScale);
      expect(CodeFont.parseUiScale(125), 125);
      expect(CodeFont.uiScaleSetting(CodeFont.defaultUiScale), isNull);
      expect(CodeFont.uiScaleSetting(125), 125);
    },
  );

  test('follow sets the notifiers now, and again as settings.json changes', () {
    final settings = ValueNotifier<int>(0);
    final values = <String, Object?>{};
    CodeFont.follow(settings, (key) => values[key]);
    expect(CodeFont.families.value, CodeFont.defaultFamilies);
    expect(CodeFont.size.value, CodeFont.defaultSize);

    values[CodeFont.familySettingKey] = 'Iosevka';
    values[CodeFont.sizeSettingKey] = 18;
    values[CodeFont.ligaturesSettingKey] = false;
    values[CodeFont.uiScaleSettingKey] = 150;
    settings.value++;
    expect(CodeFont.families.value, ['Iosevka']);
    expect(CodeFont.size.value, 18);
    expect(CodeFont.ligatures.value, isFalse);
    expect(CodeFont.uiScale.value, 150);
    settings.dispose();
  });
}
