import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:baocode/extensions/documents/ext_host_document_mirror.dart';
import 'package:baocode/extensions/language/language_feature_registry.dart';
import 'package:baocode/extensions/language/language_selector.dart';
import 'package:flutter_test/flutter_test.dart';

LanguageSelector sel(Object json) => LanguageSelector.parse(json)!;

ExtHostDocumentMirror doc(String path, String languageId) =>
    ExtHostDocumentMirror(
      uri: VsUri.file(path),
      languageId: languageId,
      text: 'x',
    );

void main() {
  final ts = doc('/w/a.ts', 'typescript');

  test('ordered: score, then builtin last, then most recent first', () {
    final registry = LanguageFeatureRegistry<String>();
    registry.register(sel('*'), 'any');
    registry.register(sel('typescript'), 'old');
    registry.register(sel({'language': 'typescript', 'isBuiltin': true}), 'builtin');
    registry.register(sel('typescript'), 'new');
    registry.register(sel('python'), 'python');

    expect(registry.ordered(ts), ['new', 'old', 'builtin', 'any']);
    expect(registry.orderedGroups(ts), [
      ['new', 'old', 'builtin'],
      ['any'],
    ]);
    expect(registry.has(ts), isTrue);
    expect(registry.has(doc('/w/a.rs', 'rust')), isTrue); // '*'
    expect(registry.ordered(doc('/w/a.py', 'python')), ['python', 'any']);
    expect(registry.registeredLanguageIds, {'*', 'typescript', 'python'});
  });

  test('exclusive selector wins alone, except recursively', () {
    final registry = LanguageFeatureRegistry<String>();
    registry.register(sel('typescript'), 'normal');
    registry.register(sel({'language': 'typescript', 'exclusive': true}), 'exclusive');
    registry.register(sel('*'), 'any');

    expect(registry.ordered(ts), ['exclusive']);
    expect(registry.ordered(ts, recursive: true), ['normal', 'any']);
  });

  test('unsynchronized documents only match hasAccessToAllModels', () {
    final registry = LanguageFeatureRegistry<String>();
    registry.register(sel('typescript'), 'ext');
    registry.register(
      sel({'language': 'typescript', 'hasAccessToAllModels': true}),
      'ui',
    );
    final big = _UnsyncedDoc(ts);
    expect(registry.ordered(big), ['ui']);
  });

  test('dispose of a registration removes it and fires', () {
    final registry = LanguageFeatureRegistry<String>();
    final counts = <int>[];
    registry.onDidChange.listen(counts.add);
    final a = registry.register(sel('typescript'), 'a');
    registry.register(sel('typescript'), 'b');
    expect(registry.ordered(ts), ['b', 'a']);
    a.dispose();
    a.dispose(); // idempotent
    expect(registry.ordered(ts), ['b']);
    expect(counts, [1, 2, 1]);
    registry.dispose();
  });

  test('notebook info resolver scores against the notebook', () {
    final cell = ExtHostDocumentMirror(
      uri: VsUri.parse('vscode-notebook-cell:///nb/a.ipynb#c1'),
      languageId: 'python',
      text: '',
    );
    final registry = LanguageFeatureRegistry<String>(
      (uri) => uri.scheme == 'vscode-notebook-cell'
          ? NotebookInfo(VsUri.file('/nb/a.ipynb'), 'jupyter')
          : null,
    );
    registry.register(sel({'notebookType': 'jupyter'}), 'jupyter');
    registry.register(sel({'notebookType': 'other'}), 'other');
    expect(registry.ordered(cell), ['jupyter']);
  });

  test('stableSort keeps equal elements in order', () {
    final list = [for (var i = 0; i < 50; i++) (i % 3, i)];
    stableSort(list, (a, b) => a.$1.compareTo(b.$1));
    for (var i = 1; i < list.length; i++) {
      if (list[i].$1 == list[i - 1].$1) {
        expect(list[i].$2, greaterThan(list[i - 1].$2));
      }
    }
  });
}

/// A document over the sync limit (`isTooLargeForSyncing`).
class _UnsyncedDoc implements ExtHostDocumentMirror {
  _UnsyncedDoc(this._inner);

  final ExtHostDocumentMirror _inner;

  @override
  bool get isSynchronized => false;

  @override
  VsUri get uri => _inner.uri;

  @override
  String get languageId => _inner.languageId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
