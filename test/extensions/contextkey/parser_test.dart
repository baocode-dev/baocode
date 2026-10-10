/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/contextkey/test/common/parser.test.ts (every case).

import 'package:baocode/extensions/contextkey/contextkey.dart';
import 'package:flutter_test/flutter_test.dart';

String parseToStr(String input) {
  final parser = Parser();
  final prints = <String>[];
  void print(List<String> ss) => prints.addAll(ss);
  final expr = parser.parse(input);
  if (expr == null) {
    if (parser.lexingErrors.isNotEmpty) {
      print(['Lexing errors:', '\n\n']);
      for (final e in parser.lexingErrors) {
        print([
          "Unexpected token '${e.lexeme}' at offset ${e.offset}. "
              '${e.additionalInfo}',
          '\n',
        ]);
      }
    }
    if (parser.parsingErrors.isNotEmpty) {
      if (parser.lexingErrors.isNotEmpty) print(['\n --- \n']);
      print(['Parsing errors:', '\n\n']);
      for (final e in parser.parsingErrors) {
        print(["Unexpected '${e.lexeme}' at offset ${e.offset}.", '\n']);
      }
    }
  } else {
    print([expr.serialize()]);
  }
  return prints.join();
}

void main() {
  void t(String input, String expected) =>
      test(input, () => expect(parseToStr(input), expected));

  group('Context Key Parser', () {
    t(' foo', 'foo');
    t('!foo', '!foo');
    t('foo =~ /bar/', 'foo =~ /bar/');
    t('foo || (foo =~ /bar/ && baz)', 'foo || baz && foo =~ /bar/');
    t('foo || (foo =~ /bar/ || baz)', 'baz || foo || foo =~ /bar/');
    t(
      '(foo || bar) && (jee || jar)',
      'bar && jar || bar && jee || foo && jar || foo && jee',
    );
    t('foo && foo =~ /zee/i', 'foo && foo =~ /zee/i');
    t('foo.bar==enabled', "foo.bar == 'enabled'");
    t("foo.bar == 'enabled'", "foo.bar == 'enabled'");
    t('foo.bar:zed==completed', "foo.bar:zed == 'completed'");
    t('a && b || c', 'c || a && b');
    t(
      'fooBar && baz.jar && fee.bee<K-loo+1>',
      'baz.jar && fee.bee<K-loo+1> && fooBar',
    );
    t('foo.barBaz<C-r> < 2', 'foo.barBaz<C-r> < 2');
    t('foo.bar >= -1', 'foo.bar >= -1');
    t(
      'view == vsc-packages-activitybar-folders && vsc-packages-folders-loaded',
      "vsc-packages-folders-loaded && view == 'vsc-packages-activitybar-folders'",
    );
    t('foo.bar <= -1', 'foo.bar <= -1');
    t(
      '!cmake:hideBuildCommand && cmake:enableFullFeatureSet',
      'cmake:enableFullFeatureSet && !cmake:hideBuildCommand',
    );
    t('!(foo && bar)', '!bar || !foo');
    t(
      '!(foo && bar || boar) || deer',
      'deer || !bar && !boar || !boar && !foo',
    );
    t('!(!foo)', 'foo');

    group('controversial', () {
      t('debugState == "stopped"', "debugState == '\"stopped\"'");
      t(
        ' viewItem == VSCode WorkSpace',
        "Parsing errors:\n\nUnexpected 'WorkSpace' at offset 20.\n",
      );
    });

    group('regex', () {
      t(
        'resource =~ //foo/(barr|door/(Foo-Bar%20Templates|Soo%20Looo)|Web%20Site%Jjj%20Llll)(/.*)*\$/',
        r'resource =~ /\/foo\/(barr|door\/(Foo-Bar%20Templates|Soo%20Looo)|Web%20Site%Jjj%20Llll)(\/.*)*$/',
      );
      t(
        r'resource =~ /((/scratch/(?!update)(.*)/)|((/src/).*/)).*$/',
        r'resource =~ /((\/scratch\/(?!update)(.*)\/)|((\/src\/).*\/)).*$/',
      );
      // The TypeScript source's `\.` in a template string is `.`.
      t(
        r'resourcePath =~ /.md(.yml|.txt)*$/giym',
        r'resourcePath =~ /.md(.yml|.txt)*$/im',
      );
    });

    group('error handling', () {
      t(
        '/foo',
        "Lexing errors:\n\nUnexpected token '/foo' at offset 0. Did you "
            "forget to escape the '/' (slash) character? Put two backslashes "
            "before it to escape, e.g., '\\\\/'.\n\n --- \nParsing errors:\n\n"
            "Unexpected '/foo' at offset 0.\n",
      );
      t("!b == 'true'", "Parsing errors:\n\nUnexpected '==' at offset 3.\n");
      t('!foo &&  in bar', "Parsing errors:\n\nUnexpected 'in' at offset 9.\n");
      t(
        'vim<c-r> == 1 && vim<2<=3',
        "Lexing errors:\n\nUnexpected token '=' at offset 23. Did you mean "
            "== or =~?\n\n --- \nParsing errors:\n\nUnexpected '=' at offset "
            '23.\n',
      );
      t(
        "foo && 'bar",
        "Lexing errors:\n\nUnexpected token ''bar' at offset 7. Did you "
            'forget to open or close the quote?\n\n --- \nParsing errors:\n\n'
            "Unexpected ''bar' at offset 7.\n",
      );
      t(
        r'config.foo &&  &&bar =~ /^foo$|^bar-foo$|^joo$|^jar$/ && !foo',
        "Parsing errors:\n\nUnexpected '&&' at offset 15.\n",
      );
      t("!foo == 'test'", "Parsing errors:\n\nUnexpected '==' at offset 5.\n");
      t('!!foo', "Parsing errors:\n\nUnexpected '!' at offset 1.\n");
    });
  });
}
