import 'package:flutter_test/flutter_test.dart';

import 'semantics_tree.dart';

/// The desktop engines' tree, as the check every widget test runs models it.
void main() {
  test('takes a tree, and a node moved with all it holds', () {
    final tree = DesktopSemanticsTree();
    expect(
      tree.commit([
        (0, [1, 2]),
        (1, [3]),
        (2, []),
        (3, [4]),
        (4, []),
      ]),
      isNull,
    );
    // 3 moves from 1 to 2: the engine deletes it and 4 first, so both come
    // again, as the framework sends nodes it detached.
    expect(
      tree.commit([
        (1, []),
        (2, [3]),
        (3, [4]),
        (4, []),
      ]),
      isNull,
    );
  });

  test('a child it does not have must come with the update', () {
    final tree = DesktopSemanticsTree()
      ..commit([
        (0, [1]),
        (1, [2]),
        (2, []),
      ]);
    // 1 goes, and 2 with it; 1 comes back without 2.
    expect(tree.commit([(0, [])]), isNull);
    expect(
      tree.commit([
        (0, [1]),
        (1, [2]),
      ]),
      'Nodes left pending by the update: 2',
    );
  });

  test('a node whose parent went is not in the tree', () {
    final tree = DesktopSemanticsTree()
      ..commit([
        (0, [1]),
        (1, [2]),
        (2, []),
      ]);
    expect(tree.commit([(0, [])]), isNull);
    expect(
      tree.commit([(2, [])]),
      'Node 2 is not in the tree and not the new root',
    );
  });

  test('the root is no one\'s child', () {
    final tree = DesktopSemanticsTree()
      ..commit([
        (0, [1]),
        (1, []),
      ]);
    expect(
      tree.commit([
        (1, [0]),
      ]),
      contains('The root 0 is a child of 1'),
    );
  });
}
