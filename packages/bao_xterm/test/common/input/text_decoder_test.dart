// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Adapted from xterm.js src/common/input/TextDecoder.test.ts (c58ea36).

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/common/input/text_decoder.dart';

// convert UTF32 codepoints to string
String toString(Uint32List data, int length) {
  return String.fromCharCodes(Uint32List.sublistView(data, 0, length));
}

// convert "bytestring" (charCode 0-255) to bytes
Uint8List fromByteString(String s) {
  final result = Uint8List(s.length);
  for (var i = 0; i < s.length; ++i) {
    result[i] = s.codeUnitAt(i);
  }
  return result;
}

Uint8List stringToUtf8Bytes(String s) {
  final bytes = <int>[];
  for (var i = 0; i < s.length; i++) {
    var cp = s.codeUnitAt(i);
    if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < s.length) {
      final next = s.codeUnitAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        cp = 0x10000 + ((cp - 0xD800) << 10) + (next - 0xDC00);
        i++;
      }
    }
    if (cp < 0x80) {
      bytes.add(cp);
    } else if (cp < 0x800) {
      bytes.addAll([0xC0 | (cp >> 6), 0x80 | (cp & 0x3F)]);
    } else if (cp < 0x10000) {
      bytes.addAll([
        0xE0 | (cp >> 12),
        0x80 | ((cp >> 6) & 0x3F),
        0x80 | (cp & 0x3F),
      ]);
    } else {
      bytes.addAll([
        0xF0 | (cp >> 18),
        0x80 | ((cp >> 12) & 0x3F),
        0x80 | ((cp >> 6) & 0x3F),
        0x80 | (cp & 0x3F),
      ]);
    }
  }
  return Uint8List.fromList(bytes);
}

/// Upstream's `Uint8Array.slice(start, end)`, which clamps [end].
Uint8List slice(Uint8List data, int start, [int? end]) {
  return data.sublist(start, math.min(end ?? data.length, data.length));
}

void assertDecodedRange(
  int min,
  int max,
  bool Function(int codePoint) skip,
  String Function(int codePoint) buildChar,
  int Function(String input, Uint32List target) decode,
  String Function(Uint32List data, int length) outputToString,
) {
  if (max <= min) {
    return;
  }
  final input = StringBuffer();
  var count = 0;
  for (var i = min; i < max; ++i) {
    if (skip(i)) {
      continue;
    }
    input.write(buildChar(i));
    count++;
  }
  final target = Uint32List(count);
  final length = decode(input.toString(), target);
  expect(length, count);
  var mismatchIndex = -1;
  var index = 0;
  for (var i = min; i < max; ++i) {
    if (skip(i)) {
      continue;
    }
    if (target[index] != i) {
      mismatchIndex = index;
      break;
    }
    index++;
  }
  expect(mismatchIndex, -1);
  expect(outputToString(target, length), input.toString());
}

const int batchSize = 8192;

const List<String> testStrings = <String>[
  'Лорем ипсум долор сит амет, ех сеа аццусам диссентиет. Ан еос стет еирмод витуперата. Иус дицерет урбанитас ет. Ан при алтера долорес сплендиде, цу яуо интегре денияуе, игнота волуптариа инструцтиор цу вим.',
  'ლორემ იფსუმ დოლორ სით ამეთ, ფაცერ მუციუს ცონსეთეთურ ყუო იდ, ფერ ვივენდუმ ყუაერენდუმ ეა, ესთ ამეთ მოვეთ სუავითათე ცუ. ვითაე სენსიბუს ან ვიხ. ეხერცი დეთერრუისსეთ უთ ყუი. ვოცენთ დებითის ადიფისცი ეთ ფერ. ნეც ან ფეუგაით ფორენსიბუს ინთერესსეთ. იდ დიცო რიდენს იუს. დისსენთიეთ ცონსეყუუნთურ სედ ნე, ნოვუმ მუნერე ეუმ ათ, ნე ეუმ ნიჰილ ირაცუნდია ურბანითას.',
  'अधिकांश अमितकुमार प्रोत्साहित मुख्य जाने प्रसारन विश्लेषण विश्व दारी अनुवादक अधिकांश नवंबर विषय गटकउसि गोपनीयता विकास जनित परस्पर गटकउसि अन्तरराष्ट्रीयकरन होसके मानव पुर्णता कम्प्युटर यन्त्रालय प्रति साधन',
  '覧六子当聞社計文護行情投身斗来。増落世的況上席備界先関権能万。本物挙歯乳全事携供板栃果以。頭月患端撤競見界記引去法条公泊候。決海備駆取品目芸方用朝示上用報。講申務紙約週堂出応理田流団幸稿。起保帯吉対阜庭支肯豪彰属本躍。量抑熊事府募動極都掲仮読岸。自続工就断庫指北速配鳴約事新住米信中験。婚浜袋著金市生交保他取情距。',
  '八メル務問へふらく博辞説いわょ読全タヨムケ東校どっ知壁テケ禁去フミ人過を装5階がねぜ法逆はじ端40落ミ予竹マヘナセ任1悪た。省ぜりせ製暇ょへそけ風井イ劣手はぼまず郵富法く作断タオイ取座ゅょが出作ホシ月給26島ツチ皇面ユトクイ暮犯リワナヤ断連こうでつ蔭柔薄とレにの。演めけふぱ損田転10得観びトげぎ王物鉄夜がまけ理惜くち牡提づ車惑参ヘカユモ長臓超漫ぼドかわ。',
  '모든 국민은 행위시의 법률에 의하여 범죄를 구성하지 아니하는 행위로 소추되지 아니하며. 전직대통령의 신분과 예우에 관하여는 법률로 정한다, 국회는 헌법 또는 법률에 특별한 규정이 없는 한 재적의원 과반수의 출석과 출석의원 과반수의 찬성으로 의결한다. 군인·군무원·경찰공무원 기타 법률이 정하는 자가 전투·훈련등 직무집행과 관련하여 받은 손해에 대하여는 법률이 정하는 보상외에 국가 또는 공공단체에 공무원의 직무상 불법행위로 인한 배상은 청구할 수 없다.',
  'كان فشكّل الشرقي مع, واحدة للمجهود تزامناً بعض بل. وتم جنوب للصين غينيا لم, ان وبدون وكسبت الأمور ذلك, أسر الخاسر الانجليزية هو. نفس لغزو مواقعها هو. الجو علاقة الصعداء انه أي, كما مع بمباركة للإتحاد الوزراء. ترتيب الأولى أن حدى, الشتوية باستحداث مدن بل, كان قد أوسع عملية. الأوضاع بالمطالبة كل قام, دون إذ شمال الربيع،. هُزم الخاصّة ٣٠ أما, مايو الصينية مع قبل.',
  'או סדר החול מיזמי קרימינולוגיה. קהילה בגרסה לויקיפדים אל היא, של צעד ציור ואלקטרוניקה. מדע מה ברית המזנון ארכיאולוגיה, אל טבלאות מבוקשים כלל. מאמרשיחהצפה העריכהגירסאות שכל אל, כתב עיצוב מושגי של. קבלו קלאסיים ב מתן. נבחרים אווירונאוטיקה אם מלא, לוח למנוע ארכיאולוגיה מה. ארץ לערוך בקרבת מונחונים או, עזרה רקטות לויקיפדים אחר גם.',
  'Лорем ლორემ अधिकांश 覧六子 八メル 모든 בקרבת 💮 😂 äggg 123€ 𝄞.',
];

void main() {
  group('text encodings', () {
    test('stringFromCodePoint/utf32ToString', () {
      const s = 'abcdefg';
      final data = Uint32List(s.length);
      for (var i = 0; i < s.length; ++i) {
        data[i] = s.codeUnitAt(i);
        expect(stringFromCodePoint(data[i]), s[i]);
      }
      expect(utf32ToString(data), s);
    });

    group('StringToUtf32 decoder', () {
      group('full codepoint test', () {
        for (var min = 0; min < 65535; min += batchSize) {
          final max = math.min(min + batchSize, 65536);
          test(formatRange(min, max), () {
            final decoder = StringToUtf32();
            assertDecodedRange(
              min,
              max,
              (i) => (i >= 0xD800 && i <= 0xDFFF) || i == 0xFEFF,
              (i) => String.fromCharCode(i),
              (input, target) => decoder.decode(input, target),
              (data, length) => utf32ToString(data, 0, length),
            );
          });
        }
        for (var min = 65536; min < 0x10FFFF; min += batchSize) {
          final max = math.min(min + batchSize, 0x10FFFF);
          test('${formatRange(min, max)} (surrogates)', () {
            final decoder = StringToUtf32();
            assertDecodedRange(
              min,
              max,
              (_) => false,
              (i) {
                final codePoint = i - 0x10000;
                return String.fromCharCodes([
                  (codePoint >> 10) + 0xD800,
                  (codePoint % 0x400) + 0xDC00,
                ]);
              },
              (input, target) => decoder.decode(input, target),
              (data, length) => utf32ToString(data, 0, length),
            );
          });
        }

        test('0xFEFF(BOM)', () {
          final decoder = StringToUtf32();
          final target = Uint32List(5);
          final length = decoder.decode(String.fromCharCode(0xFEFF), target);
          expect(length, 0);
          decoder.clear();
        });
      });

      test('test strings', () {
        final decoder = StringToUtf32();
        final target = Uint32List(500);
        for (var i = 0; i < testStrings.length; ++i) {
          final length = decoder.decode(testStrings[i], target);
          expect(toString(target, length), testStrings[i]);
          decoder.clear();
        }
      });

      group('stream handling', () {
        test('surrogates mixed advance by 1', () {
          final decoder = StringToUtf32();
          final target = Uint32List(5);
          const input = 'Ä€𝄞Ö𝄞€Ü𝄞€';
          var decoded = '';
          for (var i = 0; i < input.length; ++i) {
            final written = decoder.decode(input[i], target);
            decoded += toString(target, written);
          }
          expect(decoded, 'Ä€𝄞Ö𝄞€Ü𝄞€');
        });
      });
    });

    group('Utf8ToUtf32 decoder', () {
      group('full codepoint test', () {
        for (var min = 0; min < 65535; min += batchSize) {
          final max = math.min(min + batchSize, 65536);
          test('${formatRange(min, max)} (1/2/3 byte sequences)', () {
            final decoder = Utf8ToUtf32();
            assertDecodedRange(
              min,
              max,
              (i) => (i >= 0xD800 && i <= 0xDFFF) || i == 0xFEFF,
              (i) => String.fromCharCode(i),
              (input, target) =>
                  decoder.decode(stringToUtf8Bytes(input), target),
              (data, length) => toString(data, length),
            );
          });
        }
        for (var minRaw = 60000; minRaw < 0x10FFFF; minRaw += batchSize) {
          final min = math.max(minRaw, 65536);
          final max = math.min(minRaw + batchSize, 0x10FFFF);
          test('${formatRange(min, max)} (4 byte sequences)', () {
            final decoder = Utf8ToUtf32();
            assertDecodedRange(
              min,
              max,
              (_) => false,
              (i) => stringFromCodePoint(i),
              (input, target) =>
                  decoder.decode(stringToUtf8Bytes(input), target),
              (data, length) => toString(data, length),
            );
          });
        }

        test('0xFEFF(BOM)', () {
          final decoder = Utf8ToUtf32();
          final target = Uint32List(5);
          final utf8Data = stringToUtf8Bytes(String.fromCharCode(0xFEFF));
          final length = decoder.decode(utf8Data, target);
          expect(length, 0);
          decoder.clear();
        });
      });

      test('test strings', () {
        final decoder = Utf8ToUtf32();
        final target = Uint32List(500);
        for (var i = 0; i < testStrings.length; ++i) {
          final utf8Data = stringToUtf8Bytes(testStrings[i]);
          final length = decoder.decode(utf8Data, target);
          expect(toString(target, length), testStrings[i]);
          decoder.clear();
        }
      });

      group('stream handling', () {
        test('2 byte sequences - advance by 1', () {
          final decoder = Utf8ToUtf32();
          final target = Uint32List(5);
          final utf8Data = fromByteString(
            '\xc3\x84\xc3\x96\xc3\x9c\xc3\x9f\xc3\xb6\xc3\xa4\xc3\xbc',
          );
          var decoded = '';
          for (var i = 0; i < utf8Data.length; ++i) {
            final written = decoder.decode(slice(utf8Data, i, i + 1), target);
            decoded += toString(target, written);
          }
          expect(decoded, 'ÄÖÜßöäü');
        });

        test('2/3 byte sequences - advance by 1', () {
          final decoder = Utf8ToUtf32();
          final target = Uint32List(5);
          final utf8Data = fromByteString(
            '\xc3\x84\xe2\x82\xac\xc3\x96\xe2\x82\xac\xc3\x9c\xe2\x82\xac\xc3\x9f\xe2\x82\xac\xc3\xb6\xe2\x82\xac\xc3\xa4\xe2\x82\xac\xc3\xbc',
          );
          var decoded = '';
          for (var i = 0; i < utf8Data.length; ++i) {
            final written = decoder.decode(slice(utf8Data, i, i + 1), target);
            decoded += toString(target, written);
          }
          expect(decoded, 'Ä€Ö€Ü€ß€ö€ä€ü');
        });

        test('2/3/4 byte sequences - advance by 1', () {
          final decoder = Utf8ToUtf32();
          final target = Uint32List(5);
          final utf8Data = fromByteString(
            '\xc3\x84\xe2\x82\xac\xf0\x9d\x84\x9e\xc3\x96\xf0\x9d\x84\x9e\xe2\x82\xac\xc3\x9c\xf0\x9d\x84\x9e\xe2\x82\xac',
          );
          var decoded = '';
          for (var i = 0; i < utf8Data.length; ++i) {
            final written = decoder.decode(slice(utf8Data, i, i + 1), target);
            decoded += toString(target, written);
          }
          expect(decoded, 'Ä€𝄞Ö𝄞€Ü𝄞€');
        });

        test('2/3/4 byte sequences - advance by 2', () {
          final decoder = Utf8ToUtf32();
          final target = Uint32List(5);
          final utf8Data = fromByteString(
            '\xc3\x84\xe2\x82\xac\xf0\x9d\x84\x9e\xc3\x96\xf0\x9d\x84\x9e\xe2\x82\xac\xc3\x9c\xf0\x9d\x84\x9e\xe2\x82\xac',
          );
          var decoded = '';
          for (var i = 0; i < utf8Data.length; i += 2) {
            final written = decoder.decode(slice(utf8Data, i, i + 2), target);
            decoded += toString(target, written);
          }
          expect(decoded, 'Ä€𝄞Ö𝄞€Ü𝄞€');
        });

        test('2/3/4 byte sequences - advance by 3', () {
          final decoder = Utf8ToUtf32();
          final target = Uint32List(5);
          final utf8Data = fromByteString(
            '\xc3\x84\xe2\x82\xac\xf0\x9d\x84\x9e\xc3\x96\xf0\x9d\x84\x9e\xe2\x82\xac\xc3\x9c\xf0\x9d\x84\x9e\xe2\x82\xac',
          );
          var decoded = '';
          for (var i = 0; i < utf8Data.length; i += 3) {
            final written = decoder.decode(slice(utf8Data, i, i + 3), target);
            decoded += toString(target, written);
          }
          expect(decoded, 'Ä€𝄞Ö𝄞€Ü𝄞€');
        });

        test('BOMs (3 byte sequences) - advance by 2', () {
          final decoder = Utf8ToUtf32();
          final target = Uint32List(5);
          final utf8Data = fromByteString('\xef\xbb\xbf\xef\xbb\xbf');
          var decoded = '';
          for (var i = 0; i < utf8Data.length; i += 2) {
            final written = decoder.decode(slice(utf8Data, i, i + 2), target);
            decoded += toString(target, written);
          }
          expect(decoded, '');
        });

        test('test break after 3 bytes - issue #2495', () {
          final decoder = Utf8ToUtf32();
          final target = Uint32List(5);
          final utf8Data = fromByteString('\xf0\xa0\x9c\x8e');
          var written = decoder.decode(slice(utf8Data, 0, 3), target);
          expect(written, 0);
          written = decoder.decode(slice(utf8Data, 3), target);
          expect(written, 1);
          expect(toString(target, written), '𠜎');
        });

        group('0x80 not swallowed in continuation', () {
          test('A—B', () {
            final decoder = Utf8ToUtf32();
            final target = Uint32List(5);
            final utf8Data = utf8.encode('A—BA—BA—BA—BA—B');
            var decoded = '';
            for (var i = 0; i < utf8Data.length; i += 2) {
              final written = decoder.decode(slice(utf8Data, i, i + 2), target);
              decoded += toString(target, written);
            }
            expect(decoded, 'A—BA—BA—BA—BA—B');
          });
          test('A𐀀B', () {
            final decoder = Utf8ToUtf32();
            final target = Uint32List(5);
            final utf8Data = utf8.encode('A𐀀BA𐀀BA𐀀BA𐀀BA𐀀B');
            var decoded = '';
            for (var i = 0; i < utf8Data.length; i += 2) {
              final written = decoder.decode(slice(utf8Data, i, i + 2), target);
              decoded += toString(target, written);
            }
            expect(decoded, 'A𐀀BA𐀀BA𐀀BA𐀀BA𐀀B');
          });
        });
      });
    });
  });
}

String formatRange(int min, int max) {
  return '$min..$max (0x${min.toRadixString(16).toUpperCase()}..0x${max.toRadixString(16).toUpperCase()})';
}
