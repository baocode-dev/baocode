/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/contextkey/test/common/scanner.test.ts (every case).

import 'package:baocode/extensions/contextkey/scanner.dart';
import 'package:flutter_test/flutter_test.dart';

String _type(Token token) => switch (token.type) {
  TokenType.regexStr => 'RegexStr',
  TokenType.str => 'Str',
  TokenType.quotedStr => 'QuotedStr',
  TokenType.error => 'ErrorToken',
  TokenType.eof => 'EOF',
  _ => Scanner.getLexeme(token),
};

List<Object> _scan(String input) => [
  for (final token in Scanner().reset(input).scan())
    token.lexeme != null &&
            (token.type == TokenType.regexStr ||
                token.type == TokenType.str ||
                token.type == TokenType.quotedStr ||
                token.type == TokenType.error)
        ? (_type(token), token.offset, token.lexeme!)
        : (_type(token), token.offset),
];

void _case(String input, List<Object> expected) {
  test(input, () => expect(_scan(input), expected));
}

void main() {
  _case("foo.bar<C-shift+2>", [("Str", 0, "foo.bar<C-shift+2>"), ("EOF", 18)]);
  _case("!foo", [("!", 0), ("Str", 1, "foo"), ("EOF", 4)]);
  _case("foo === bar", [
    ("Str", 0, "foo"),
    ("===", 4),
    ("Str", 8, "bar"),
    ("EOF", 11),
  ]);
  _case("foo  !== bar", [
    ("Str", 0, "foo"),
    ("!==", 5),
    ("Str", 9, "bar"),
    ("EOF", 12),
  ]);
  _case("!(foo && bar)", [
    ("!", 0),
    ("(", 1),
    ("Str", 2, "foo"),
    ("&&", 6),
    ("Str", 9, "bar"),
    (")", 12),
    ("EOF", 13),
  ]);
  _case("=~ ", [("=~", 0), ("EOF", 3)]);
  _case("foo =~ /bar/", [
    ("Str", 0, "foo"),
    ("=~", 4),
    ("RegexStr", 7, "/bar/"),
    ("EOF", 12),
  ]);
  _case("foo =~ /zee/i", [
    ("Str", 0, "foo"),
    ("=~", 4),
    ("RegexStr", 7, "/zee/i"),
    ("EOF", 13),
  ]);
  _case("foo =~ /zee/gm", [
    ("Str", 0, "foo"),
    ("=~", 4),
    ("RegexStr", 7, "/zee/gm"),
    ("EOF", 14),
  ]);
  _case("foo in barrr  ", [
    ("Str", 0, "foo"),
    ("in", 4),
    ("Str", 7, "barrr"),
    ("EOF", 14),
  ]);
  _case(
    "resource =~ //FileCabinet/(SuiteScripts|Templates/(E-mail%20Templates|Marketing%20Templates)|Web%20Site%20Hosting%20Files)(/.*)*\$/",
    [
      ("Str", 0, "resource"),
      ("=~", 9),
      ("RegexStr", 12, "//"),
      ("Str", 14, "FileCabinet/"),
      ("(", 26),
      ("Str", 27, "SuiteScripts"),
      ("ErrorToken", 39, "|"),
      ("Str", 40, "Templates/"),
      ("(", 50),
      ("Str", 51, "E-mail%20Templates"),
      ("ErrorToken", 69, "|"),
      ("Str", 70, "Marketing%20Templates"),
      (")", 91),
      ("ErrorToken", 92, "|"),
      ("Str", 93, "Web%20Site%20Hosting%20Files"),
      (")", 121),
      ("(", 122),
      ("RegexStr", 123, "/.*)*\$/"),
      ("EOF", 130),
    ],
  );
  _case(
    "editorLangId in testely.supportedLangIds && resourceFilename =~ /^.+(.test.(w+))\$/gm",
    [
      ("Str", 0, "editorLangId"),
      ("in", 13),
      ("Str", 16, "testely.supportedLangIds"),
      ("&&", 41),
      ("Str", 44, "resourceFilename"),
      ("=~", 61),
      ("RegexStr", 64, "/^.+(.test.(w+))\$/gm"),
      ("EOF", 84),
    ],
  );
  _case("!(foo && bar) && baz", [
    ("!", 0),
    ("(", 1),
    ("Str", 2, "foo"),
    ("&&", 6),
    ("Str", 9, "bar"),
    (")", 12),
    ("&&", 14),
    ("Str", 17, "baz"),
    ("EOF", 20),
  ]);
  _case("foo.bar:zed==completed", [
    ("Str", 0, "foo.bar:zed"),
    ("==", 11),
    ("Str", 13, "completed"),
    ("EOF", 22),
  ]);
  _case("a && b || c", [
    ("Str", 0, "a"),
    ("&&", 2),
    ("Str", 5, "b"),
    ("||", 7),
    ("Str", 10, "c"),
    ("EOF", 11),
  ]);
  _case("fooBar && baz.jar && fee.bee<K-loo+1>", [
    ("Str", 0, "fooBar"),
    ("&&", 7),
    ("Str", 10, "baz.jar"),
    ("&&", 18),
    ("Str", 21, "fee.bee<K-loo+1>"),
    ("EOF", 37),
  ]);
  _case("foo.barBaz<C-r> < 2", [
    ("Str", 0, "foo.barBaz<C-r>"),
    ("<", 16),
    ("Str", 18, "2"),
    ("EOF", 19),
  ]);
  _case("foo.bar >= -1", [
    ("Str", 0, "foo.bar"),
    (">=", 8),
    ("Str", 11, "-1"),
    ("EOF", 13),
  ]);
  _case("foo.bar <= -1", [
    ("Str", 0, "foo.bar"),
    ("<=", 8),
    ("Str", 11, "-1"),
    ("EOF", 13),
  ]);
  _case("resource =~ /\\/Objects\\/.+\\.xml\$/", [
    ("Str", 0, "resource"),
    ("=~", 9),
    ("RegexStr", 12, "/\\/Objects\\/.+\\.xml\$/"),
    ("EOF", 33),
  ]);
  _case(
    "view == vsc-packages-activitybar-folders\u00a0&& vsc-packages-folders-loaded",
    [
      ("Str", 0, "view"),
      ("==", 5),
      ("Str", 8, "vsc-packages-activitybar-folders"),
      ("&&", 41),
      ("Str", 44, "vsc-packages-folders-loaded"),
      ("EOF", 71),
    ],
  );
  _case(
    "sfdx:project_opened && resource =~ /.*\\/functions\\/.*\\/[^\\/]+(\\/[^\\/]+.(ts|js|java|json|toml))?\$/ && resourceFilename != package.json && resourceFilename != package-lock.json && resourceFilename != tsconfig.json",
    [
      ("Str", 0, "sfdx:project_opened"),
      ("&&", 20),
      ("Str", 23, "resource"),
      ("=~", 32),
      (
        "RegexStr",
        35,
        "/.*\\/functions\\/.*\\/[^\\/]+(\\/[^\\/]+.(ts|js|java|json|toml))?\$/",
      ),
      ("&&", 98),
      ("Str", 101, "resourceFilename"),
      ("!=", 118),
      ("Str", 121, "package.json"),
      ("&&", 134),
      ("Str", 137, "resourceFilename"),
      ("!=", 154),
      ("Str", 157, "package-lock.json"),
      ("&&", 175),
      ("Str", 178, "resourceFilename"),
      ("!=", 195),
      ("Str", 198, "tsconfig.json"),
      ("EOF", 211),
    ],
  );
  _case(
    "view =~ '/(servers)/' && viewItem =~ '/^(Starting|Started|Debugging|Stopping|Stopped)/'",
    [
      ("Str", 0, "view"),
      ("=~", 5),
      ("QuotedStr", 9, "/(servers)/"),
      ("&&", 22),
      ("Str", 25, "viewItem"),
      ("=~", 34),
      ("QuotedStr", 38, "/^(Starting|Started|Debugging|Stopping|Stopped)/"),
      ("EOF", 87),
    ],
  );
  _case("resourcePath =~ /.md(.yml|.txt)*\$/gim", [
    ("Str", 0, "resourcePath"),
    ("=~", 13),
    ("RegexStr", 16, "/.md(.yml|.txt)*\$/gim"),
    ("EOF", 37),
  ]);
  _case("foo === bar'", [
    ("Str", 0, "foo"),
    ("===", 4),
    ("Str", 8, "bar"),
    ("ErrorToken", 11, "'"),
    ("EOF", 12),
  ]);
  _case("foo === '", [
    ("Str", 0, "foo"),
    ("===", 4),
    ("ErrorToken", 8, "'"),
    ("EOF", 9),
  ]);
  _case("foo && 'bar", [
    ("Str", 0, "foo"),
    ("&&", 4),
    ("ErrorToken", 7, "'bar"),
    ("EOF", 11),
  ]);
  _case("vim<c-r> == 1 && vim<2 <= 3", [
    ("Str", 0, "vim<c-r>"),
    ("==", 9),
    ("Str", 12, "1"),
    ("&&", 14),
    ("Str", 17, "vim<2"),
    ("<=", 23),
    ("Str", 26, "3"),
    ("EOF", 27),
  ]);
  _case("vim<c-r>==1 && vim<2<=3", [
    ("Str", 0, "vim<c-r>"),
    ("==", 8),
    ("Str", 10, "1"),
    ("&&", 12),
    ("Str", 15, "vim<2<"),
    ("ErrorToken", 21, "="),
    ("Str", 22, "3"),
    ("EOF", 23),
  ]);
  _case("foo|bar", [
    ("Str", 0, "foo"),
    ("ErrorToken", 3, "|"),
    ("Str", 4, "bar"),
    ("EOF", 7),
  ]);
  _case(
    "resource =~ //foo/(barr|door/(Foo-Bar%20Templates|Soo%20Looo)|Web%20Site%Jjj%20Llll)(/.*)*\$/",
    [
      ("Str", 0, "resource"),
      ("=~", 9),
      ("RegexStr", 12, "//"),
      ("Str", 14, "foo/"),
      ("(", 18),
      ("Str", 19, "barr"),
      ("ErrorToken", 23, "|"),
      ("Str", 24, "door/"),
      ("(", 29),
      ("Str", 30, "Foo-Bar%20Templates"),
      ("ErrorToken", 49, "|"),
      ("Str", 50, "Soo%20Looo"),
      (")", 60),
      ("ErrorToken", 61, "|"),
      ("Str", 62, "Web%20Site%Jjj%20Llll"),
      (")", 83),
      ("(", 84),
      ("RegexStr", 85, "/.*)*\$/"),
      ("EOF", 92),
    ],
  );
  _case("/((/foo/(?!bar)(.*)/)|((/src/).*/)).*\$/", [
    ("RegexStr", 0, "/((/"),
    ("Str", 4, "foo/"),
    ("(", 8),
    ("Str", 9, "?"),
    ("!", 10),
    ("Str", 11, "bar"),
    (")", 14),
    ("(", 15),
    ("Str", 16, ".*"),
    (")", 18),
    ("RegexStr", 19, "/)|((/s"),
    ("Str", 26, "rc/"),
    (")", 29),
    ("Str", 30, ".*/"),
    (")", 33),
    (")", 34),
    ("Str", 35, ".*\$/"),
    ("EOF", 39),
  ]);
  _case(
    "resourcePath =~ //foo/barr// || resourcePath =~ //view/(jarrr|doooor|bees)/(web|templates)// && resourceExtname in foo.Bar",
    [
      ("Str", 0, "resourcePath"),
      ("=~", 13),
      ("RegexStr", 16, "//"),
      ("Str", 18, "foo/barr//"),
      ("||", 29),
      ("Str", 32, "resourcePath"),
      ("=~", 45),
      ("RegexStr", 48, "//"),
      ("Str", 50, "view/"),
      ("(", 55),
      ("Str", 56, "jarrr"),
      ("ErrorToken", 61, "|"),
      ("Str", 62, "doooor"),
      ("ErrorToken", 68, "|"),
      ("Str", 69, "bees"),
      (")", 73),
      ("RegexStr", 74, "/(web|templates)/"),
      ("ErrorToken", 91, "/ && resourceExtname in foo.Bar"),
      ("EOF", 122),
    ],
  );
  _case("foo =~ /file:// || bar", [
    ("Str", 0, "foo"),
    ("=~", 4),
    ("RegexStr", 7, "/file:/"),
    ("ErrorToken", 14, "/ || bar"),
    ("EOF", 22),
  ]);
}
