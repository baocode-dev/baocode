// A README's HTML on the extension page: images and links kept, block
// tags part paragraphs, other tags dropped, code left as written.

import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/extensions/ui/readme_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

String _html(String markdown) =>
    md.renderToHtml(readmeNodes(MarkdownView.document().parse(markdown)));

void main() {
  test("an HTML block keeps its images and links (GitLens' figure)", () {
    const readme =
        '<figure align="center">\n'
        '  <a title="Watch" href="https://youtu.be/x">\n'
        '    <img src="https://example.com/video.png" alt="Watch the video" />\n'
        '  </a>\n'
        '</figure>\n';
    expect(
      _html(readme),
      '<p><a href="https://youtu.be/x">'
      '<img src="https://example.com/video.png" alt="Watch the video" />'
      '</a></p>',
    );
  });

  test('block tags part paragraphs; others are dropped', () {
    const readme =
        '<p align="center">\n'
        '  <b>Fast</b> and <i>small</i>\n'
        '</p>\n'
        '<div>Second<br>line</div>\n';
    expect(_html(readme), '<p>Fast and small</p>\n<p>Second<br />\nline</p>');
  });

  test('inline HTML in a paragraph', () {
    expect(
      _html('Press <kbd>Ctrl</kbd> or <img src="k.png" alt="key">.'),
      '<p>Press Ctrl or <img src="k.png" alt="key" />.</p>',
    );
  });

  test('comments go; code keeps its tags', () {
    expect(
      _html('<!-- badges -->\n\nUse `<div>` here.\n\n```html\n<b>x</b>\n```'),
      '<p>Use <code><div></code> here.</p>\n'
      '<pre><code class="language-html"><b>x</b>\n</code></pre>',
    );
  });

  test('markdown without HTML is as parsed', () {
    const readme = '# Title\n\n- one\n- two\n\n> quote\n';
    expect(
      _html(readme),
      md.renderToHtml(MarkdownView.document().parse(readme)),
    );
  });
}
