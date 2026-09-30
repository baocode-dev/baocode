/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/editor/test/common/modes/linkComputer.test.ts.

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/links/link_computer.dart';

class SimpleLinkComputerTarget implements ILinkComputerTarget {
  SimpleLinkComputerTarget(this._lines);

  final List<String> _lines;

  @override
  int getLineCount() {
    return _lines.length;
  }

  @override
  String getLineContent(int lineNumber) {
    return _lines[lineNumber - 1];
  }
}

List<ILink> myComputeLinks(List<String> lines) {
  final target = SimpleLinkComputerTarget(lines);
  return computeLinks(target);
}

void assertLink(String text, String extractedLink) {
  var startColumn = 0, endColumn = 0;
  String chr;
  var i = 0;

  for (i = 0; i < extractedLink.length; i++) {
    chr = extractedLink[i];
    if (chr != ' ' && chr != '\t') {
      startColumn = i + 1;
      break;
    }
  }

  for (i = extractedLink.length - 1; i >= 0; i--) {
    chr = extractedLink[i];
    if (chr != ' ' && chr != '\t') {
      endColumn = i + 2;
      break;
    }
  }

  final r = myComputeLinks([text]);
  expect(r, [
    (
      range: (
        startLineNumber: 1,
        startColumn: startColumn,
        endLineNumber: 1,
        endColumn: endColumn,
      ),
      url: extractedLink.substring(startColumn - 1, endColumn - 1),
    ),
  ]);
}

void main() {
  group('Editor Modes - Link Computer', () {
    test('Null model', () {
      final r = computeLinks(null);
      expect(r, <ILink>[]);
    });

    test('Parsing', () {
      assertLink('x = "http://foo.bar";', '     http://foo.bar  ');

      assertLink('x = (http://foo.bar);', '     http://foo.bar  ');

      assertLink('x = [http://foo.bar];', '     http://foo.bar  ');

      assertLink("x = 'http://foo.bar';", '     http://foo.bar  ');

      assertLink('x =  http://foo.bar ;', '     http://foo.bar  ');

      assertLink('x = <http://foo.bar>;', '     http://foo.bar  ');

      assertLink('x = {http://foo.bar};', '     http://foo.bar  ');

      assertLink('(see http://foo.bar)', '     http://foo.bar  ');
      assertLink('[see http://foo.bar]', '     http://foo.bar  ');
      assertLink('{see http://foo.bar}', '     http://foo.bar  ');
      assertLink('<see http://foo.bar>', '     http://foo.bar  ');
      assertLink(
        '<url>http://mylink.com</url>',
        '     http://mylink.com      ',
      );
      assertLink(
        '// Click here to learn more. https://go.microsoft.com/fwlink/?LinkID=513275&clcid=0x409',
        '                             https://go.microsoft.com/fwlink/?LinkID=513275&clcid=0x409',
      );
      assertLink(
        '// Click here to learn more. https://msdn.microsoft.com/en-us/library/windows/desktop/aa365247(v=vs.85).aspx',
        '                             https://msdn.microsoft.com/en-us/library/windows/desktop/aa365247(v=vs.85).aspx',
      );
      assertLink(
        '// https://github.com/projectkudu/kudu/blob/master/Kudu.Core/Scripts/selectNodeVersion.js',
        '   https://github.com/projectkudu/kudu/blob/master/Kudu.Core/Scripts/selectNodeVersion.js',
      );
      assertLink(
        '<!-- !!! Do not remove !!!   WebContentRef(link:https://go.microsoft.com/fwlink/?LinkId=166007, area:Admin, updated:2015, nextUpdate:2016, tags:SqlServer)   !!! Do not remove !!! -->',
        '                                                https://go.microsoft.com/fwlink/?LinkId=166007                                                                                        ',
      );
      assertLink(
        'For instructions, see https://go.microsoft.com/fwlink/?LinkId=166007.</value>',
        '                      https://go.microsoft.com/fwlink/?LinkId=166007         ',
      );
      assertLink(
        'For instructions, see https://msdn.microsoft.com/en-us/library/windows/desktop/aa365247(v=vs.85).aspx.</value>',
        '                      https://msdn.microsoft.com/en-us/library/windows/desktop/aa365247(v=vs.85).aspx         ',
      );
      assertLink(
        'x = "https://en.wikipedia.org/wiki/Zürich";',
        '     https://en.wikipedia.org/wiki/Zürich  ',
      );
      assertLink(
        '請參閱 http://go.microsoft.com/fwlink/?LinkId=761051。',
        '    http://go.microsoft.com/fwlink/?LinkId=761051 ',
      );
      assertLink(
        '（請參閱 http://go.microsoft.com/fwlink/?LinkId=761051）',
        '     http://go.microsoft.com/fwlink/?LinkId=761051 ',
      );

      assertLink('x = "file:///foo.bar";', '     file:///foo.bar  ');
      assertLink('x = "file://c:/foo.bar";', '     file://c:/foo.bar  ');

      assertLink(
        'x = "file://shares/foo.bar";',
        '     file://shares/foo.bar  ',
      );

      assertLink(
        'x = "file://shäres/foo.bar";',
        '     file://shäres/foo.bar  ',
      );
      assertLink(
        'Some text, then http://www.bing.com.',
        '                http://www.bing.com ',
      );
      assertLink(
        "let url = `http://***/_api/web/lists/GetByTitle('Teambuildingaanvragen')/items`;",
        "           http://***/_api/web/lists/GetByTitle('Teambuildingaanvragen')/items  ",
      );
    });

    test('issue #7855', () {
      assertLink(
        '7. At this point, ServiceMain has been called.  There is no functionality presently in ServiceMain, but you can consult the [MSDN documentation](https://msdn.microsoft.com/en-us/library/windows/desktop/ms687414(v=vs.85).aspx) to add functionality as desired!',
        '                                                                                                                                                 https://msdn.microsoft.com/en-us/library/windows/desktop/ms687414(v=vs.85).aspx                                  ',
      );
    });

    test('issue #62278: "Ctrl + click to follow link" for IPv6 URLs', () {
      assertLink(
        'let x = "http://[::1]:5000/connect/token"',
        '         http://[::1]:5000/connect/token  ',
      );
    });

    test('issue #70254: bold links dont open in markdown file using editor mode with ctrl + click', () {
      assertLink(
        '2. Navigate to **https://portal.azure.com**',
        '                 https://portal.azure.com  ',
      );
    });

    test('issue #86358: URL wrong recognition pattern', () {
      assertLink(
        'POST|https://portal.azure.com|2019-12-05|',
        '     https://portal.azure.com            ',
      );
    });

    test("issue #67022: Space as end of hyperlink isn't always good idea", () {
      assertLink(
        'aa  https://foo.bar/[this is foo site]  aa',
        '    https://foo.bar/[this is foo site]    ',
      );
    });

    test('issue #100353: Link detection stops at ＆(double-byte)', () {
      assertLink(
        'aa  http://tree-mark.chips.jp/レーズン＆ベリーミックス  aa',
        '    http://tree-mark.chips.jp/レーズン＆ベリーミックス    ',
      );
    });

    test('issue #121438: Link detection stops at【...】', () {
      assertLink(
        'aa  https://zh.wikipedia.org/wiki/【我推的孩子】 aa',
        '    https://zh.wikipedia.org/wiki/【我推的孩子】   ',
      );
    });

    test('issue #121438: Link detection stops at《...》', () {
      assertLink(
        'aa  https://zh.wikipedia.org/wiki/《新青年》编辑部旧址 aa',
        '    https://zh.wikipedia.org/wiki/《新青年》编辑部旧址   ',
      );
    });

    test('issue #121438: Link detection stops at “...”', () {
      assertLink(
        'aa  https://zh.wikipedia.org/wiki/“常凯申”误译事件 aa',
        '    https://zh.wikipedia.org/wiki/“常凯申”误译事件   ',
      );
    });

    test(
      'issue #150905: Colon after bare hyperlink is treated as its part',
      () {
        assertLink(
          'https://site.web/page.html: blah blah blah',
          'https://site.web/page.html                ',
        );
      },
    );

    // Removed because of #156875
    // test('issue #151631: Link parsing stoped where comments include a single quote ', () {
    // 	assertLink(
    // 		`aa https://regexper.com/#%2F''%2F aa`,
    // 		`   https://regexper.com/#%2F''%2F   `,
    // 	);
    // });

    test('issue #156875: Links include quotes ', () {
      assertLink(
        '"This file has been converted from https://github.com/jeff-hykin/better-c-syntax/blob/master/autogenerated/c.tmLanguage.json",',
        '                                   https://github.com/jeff-hykin/better-c-syntax/blob/master/autogenerated/c.tmLanguage.json  ',
      );
    });

    test("issue #225513: Cmd-Click doesn't work on JSDoc {@link URL|LinkText} format ", () {
      assertLink(
        ' * {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/withResolvers|Promise.withResolvers}',
        '          https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/withResolvers                       ',
      );
    });
  });
}
