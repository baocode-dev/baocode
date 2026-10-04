import 'package:baocode/ide/markdown/markdown_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('anchors are GitHub\'s, other scripts kept, repeats numbered', () {
    expect(markdownSlug('Getting Started!'), 'getting-started');
    expect(markdownSlug('`code` & more_things'), 'code--more_things');
    expect(markdownSlug('核心架构（必须遵守）'), '核心架构必须遵守');
    final source = MarkdownSource('# Usage\n\n## Usage\n\ntext\n\n### `Usage`');
    expect(source.anchors.values, ['usage', 'usage-1', 'usage-2']);
    expect(source.heading('usage-1'), 1);
    expect(source.heading('Usage'), 0);
    expect(source.heading('nope'), isNull);
  });

  test('link definitions apply to the whole document', () {
    final source = MarkdownSource('See [docs][d].\n\n[d]: https://dart.dev');
    final html = source.parse(source.blocks.first).single;
    expect(html.textContent, 'See docs.');
    expect(source.blocks, hasLength(2));
  });

  group('links', () {
    const doc = '/project/docs/guide.md';
    MarkdownLinkTarget? link(String href, [p.Context? context]) =>
        resolveMarkdownLink(href, doc, context ?? p.posix);

    test('anchors, web and mail', () {
      expect((link('#My%20Part') as MarkdownAnchorLink).anchor, 'My Part');
      expect((link('https://a.b/c') as MarkdownExternalLink).uri.host, 'a.b');
      expect(link('mailto:a@b.c'), isA<MarkdownExternalLink>());
      expect(link('vscode://open'), isNull);
      expect(link(''), isNull);
    });

    test('files, beside the document or absolute, with their fragment', () {
      final relative = link('../README.md#Usage') as MarkdownFileLink;
      expect(relative.path, '/project/README.md');
      expect(relative.fragment, 'Usage');
      final spaced = link('img/a%20b.png') as MarkdownFileLink;
      expect(spaced.path, '/project/docs/img/a b.png');
      expect(spaced.fragment, isNull);
      expect((link('/etc/hosts') as MarkdownFileLink).path, '/etc/hosts');
      expect((link('file:///tmp/x.md') as MarkdownFileLink).path, '/tmp/x.md');
    });

    test('a Windows path is no scheme', () {
      final windows = p.Context(style: p.Style.windows);
      final target = resolveMarkdownLink(
        r'C:\notes\a.md',
        r'C:\project\guide.md',
        windows,
      );
      expect((target as MarkdownFileLink).path, r'C:\notes\a.md');
      final relative = resolveMarkdownLink(
        'sub/b.md',
        r'C:\project\guide.md',
        windows,
      );
      expect((relative as MarkdownFileLink).path, r'C:\project\sub\b.md');
    });

    test('images: web ones by address, others by path', () {
      expect(
        resolveMarkdownImage('https://x.y/a.png', doc, p.posix)?.url,
        Uri.parse('https://x.y/a.png'),
      );
      expect(
        resolveMarkdownImage('a.png', doc, p.posix)?.path,
        '/project/docs/a.png',
      );
      expect(resolveMarkdownImage('mailto:a@b.c', doc, p.posix), isNull);
    });
  });
}
