/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/test/common/model/intervalTree.test.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971. All 19 generated regressions,
// five Cormen searches and 208 explicit marker cases are retained below.
// Added deterministic random tests, metadata/cache/lifecycle checks, and
// differential goldens executed against the pinned TypeScript implementation.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/core/range.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/model/interval_tree.dart';

void main() {
  group('upstream generated regressions', () {
    for (final (name, ops) in _upstreamOperations) {
      test(name, () {
        final state = _TestState();
        for (final op in ops) {
          state.accept(op);
        }
      });
    }
  });

  group('upstream Cormen inclusive searches', () {
    final cases = <(int, int, List<(int, int)>)>[
      (1, 2, [(0, 3)]),
      (4, 8, [(5, 8), (6, 10), (8, 9)]),
      (10, 15, [(6, 10), (15, 23)]),
      (21, 25, [(15, 23), (16, 21), (25, 30)]),
      (24, 24, []),
    ];
    for (final (start, end, expected) in cases) {
      test('$start->$end', () {
        final tree = _cormenTree();
        expect(
          _offsets(tree.intervalSearch(start, end, 0, false, false, 0, false)),
          expected,
        );
        _assertTreeInvariants(tree);
      });
    }
  });

  group('upstream explicit marker movement cases', () {
    for (final c in _upstreamEdits) {
      final (
        name,
        a,
        b,
        sticky,
        start,
        end,
        length,
        force,
        expectedA,
        expectedB,
      ) = c;
      test(name, () {
        final node = IntervalNode('direct', a, b);
        setNodeStickiness(node, TrackedRangeStickiness.values[sticky]);
        nodeAcceptEdit(node, start, end, length, force);
        expect((node.start, node.end), (expectedA, expectedB));

        // Exercise the same boundary through removal, reinsertion and lazy
        // deltas, not just the standalone marker helper.
        final tree = IntervalTree();
        final tracked = IntervalNode('tracked', a, b);
        setNodeStickiness(tracked, TrackedRangeStickiness.values[sticky]);
        tree.insert(IntervalNode('before', 0, 0));
        tree.insert(tracked);
        tree.insert(IntervalNode('after', 50, 60));
        tree.acceptReplace(start, end - start, length, force);
        tree.resolveNode(tracked, 1);
        expect(
          (tracked.cachedAbsoluteStart, tracked.cachedAbsoluteEnd),
          (expectedA, expectedB),
        );
        _assertTreeInvariants(tree);
      });
    }
  });

  group('upstream randomized oracle, enabled with reproducible seeds', () {
    for (var seed = 1; seed <= 100; seed++) {
      test('seed $seed', () {
        final random = _Random(seed);
        final state = _TestState();
        final count = random.next(30) + 1;
        final changes = random.next(11) + 10;
        void search() {
          final (a, b) = _randomUpstreamRange(random);
          state.accept(_Op.search(a, b));
        }

        for (var i = 0; i < count; i++) {
          final (a, b) = _randomUpstreamRange(random);
          state.accept(_Op.insert(a, b));
          search();
        }
        for (var i = 0; i < changes; i++) {
          final (a, b) = _randomUpstreamRange(random);
          state.accept(_Op.change(random.next(count), a, b));
          search();
        }
        final remaining = List.generate(count, (i) => i);
        while (remaining.isNotEmpty) {
          // Same bias toward the latter half as upstream AutoTest.
          final half = remaining.length ~/ 2;
          final index = half + random.next(remaining.length - half);
          state.accept(_Op.delete(remaining.removeAt(index)));
          search();
        }
      });
    }
  });

  group('node metadata and contracts', () {
    test(
      'enum values and class names retain their upstream representation',
      () {
        expect(TrackedRangeStickiness.alwaysGrowsWhenTypingAtEdges.index, 0);
        expect(TrackedRangeStickiness.neverGrowsWhenTypingAtEdges.index, 1);
        expect(TrackedRangeStickiness.growsOnlyWhenTypingBefore.index, 2);
        expect(TrackedRangeStickiness.growsOnlyWhenTypingAfter.index, 3);
        expect(NodeColor.black.index, 0);
        expect(NodeColor.red.index, 1);
        expect(_classNames, [
          null,
          'squiggly-hint',
          'squiggly-info',
          'squiggly-warning',
          'squiggly-error',
          'squiggly-unnecessary',
          'squiggly-inline-unnecessary',
          'squiggly-inline-deprecated',
          'squiggly-error extra',
          '',
        ]);
      },
    );

    test('constructor, option defaults, packed bit isolation and detach', () {
      final node = IntervalNode('id', 10, 20);
      expect(node.metadata, 1 | (1 << 3));
      expect(node.parent, same(node));
      expect(node.left, same(node));
      expect(node.right, same(node));
      expect(node.ownerId, 0);
      expect(node.options, isNull);
      expect(node.range, isNull);
      expect(node.cachedVersionId, 0);
      expect((node.cachedAbsoluteStart, node.cachedAbsoluteEnd), (10, 20));
      expect((node.delta, node.maxEnd), (0, 20));
      node.setOptions(const IntervalNodeOptions());
      expect(
        node.metadata,
        1,
      ); // options default to always-growing, node does not
      expect(node.options!.className, isNull);
      expect(node.options!.glyphMarginClassName, isNull);
      expect(
        node.options!.stickiness,
        TrackedRangeStickiness.alwaysGrowsWhenTypingAtEdges,
      );
      expect(node.options!.collapseOnReplaceEdit, isFalse);
      expect(node.options!.affectsFont, isFalse);

      for (final sticky in TrackedRangeStickiness.values) {
        node.metadata = 3; // color + visited must survive every option setter
        final options = IntervalNodeOptions(
          className: ClassName.editorErrorDecoration,
          glyphMarginClassName:
              '', // contract checks null, not string truthiness
          stickiness: sticky,
          collapseOnReplaceEdit: true,
          affectsFont: true,
        );
        node.setOptions(options);
        expect(node.options, same(options));
        expect(node.metadata, 3 | 4 | (sticky.index << 3) | 32 | 64 | 128);
        for (final other in TrackedRangeStickiness.values) {
          setNodeStickiness(node, other);
          expect(node.metadata, 3 | 4 | (other.index << 3) | 32 | 64 | 128);
          expect(node.options, same(options)); // setter changes metadata only
        }
        node.setOptions(const IntervalNodeOptions());
        expect(node.metadata, 3);
      }
      node.detach();
      expect(node.parent, isNull);
      expect(node.left, isNull);
      expect(node.right, isNull);
      expect(node.id, 'id');
    });

    test(
      'reset and cached offsets preserve or invalidate range by version',
      () {
        final node = IntervalNode('id', 10, 20)..delta = 17;
        final range = Range(1, 11, 1, 21);
        node.reset(7, 10, 20, range);
        expect((node.start, node.end, node.maxEnd), (10, 20, 20));
        expect(
          node.delta,
          17,
        ); // upstream reset deliberately does not reset delta
        expect(node.range, same(range));
        node.setCachedOffsets(11, 22, 7);
        expect(node.range, same(range));
        expect((node.cachedAbsoluteStart, node.cachedAbsoluteEnd), (11, 22));
        node.setCachedOffsets(12, 23, 8);
        expect(node.range, isNull);
        expect(node.cachedVersionId, 8);
      },
    );

    test('all validation, owner, margin and font filter combinations', () {
      final tree = IntervalTree();
      final nodes = <IntervalNode>[];
      for (final name in _classNames) {
        for (var owner = 0; owner < 3; owner++) {
          for (final glyph in [null, '', 'glyph']) {
            for (final font in [null, false, true]) {
              final start = nodes.length * 5;
              final node = IntervalNode('${nodes.length}', start, start + 3)
                ..ownerId = owner;
              node.setOptions(
                IntervalNodeOptions(
                  className: name,
                  glyphMarginClassName: glyph,
                  affectsFont: font,
                ),
              );
              tree.insert(node);
              nodes.add(node);
            }
          }
        }
      }
      var version = 1;
      for (var owner = 0; owner <= 3; owner++) {
        for (final validation in [false, true]) {
          for (final font in [false, true]) {
            for (final margin in [false, true]) {
              bool include(IntervalNode n) {
                final o = n.options!;
                return (owner == 0 || n.ownerId == 0 || n.ownerId == owner) &&
                    (!validation || !_isValidation(o.className)) &&
                    (!font || o.affectsFont != true) &&
                    (!margin || o.glyphMarginClassName != null);
              }

              expect(
                tree.search(owner, validation, font, version, margin),
                nodes.where(include).toList(),
              );
              // Even excluded nodes are resolved by search before filtering.
              expect(nodes.every((n) => n.cachedVersionId == version), isTrue);
              version++;
              const start = 103, end = 600;
              final overlapping = nodes
                  .where(
                    (n) =>
                        n.cachedAbsoluteStart <= end &&
                        n.cachedAbsoluteEnd >= start,
                  )
                  .toList();
              expect(
                tree.intervalSearch(
                  start,
                  end,
                  owner,
                  validation,
                  font,
                  version,
                  margin,
                ),
                overlapping.where(include).toList(),
              );
              expect(
                overlapping.every((n) => n.cachedVersionId == version),
                isTrue,
              );
              expect(
                nodes
                    .where((n) => !overlapping.contains(n))
                    .every((n) => n.cachedVersionId == version - 1),
                isTrue,
              );
              version++;
              _assertTreeInvariants(tree);
            }
          }
        }
      }
    });
  });

  group('traversal, tracked range lifecycle and deltas', () {
    test('all empty-tree operations and sentinel sharing are safe', () {
      final tree = IntervalTree();
      expect(tree.search(0, false, false, 1, false), isEmpty);
      expect(tree.intervalSearch(0, 10, 0, false, false, 1, false), isEmpty);
      expect(tree.collectNodesFromOwner(0), isEmpty);
      expect(tree.collectNodesPostOrder(), isEmpty);
      expect(tree.getAllInOrder(), isEmpty);
      tree.acceptReplace(0, 100, 10, false);
      _assertTreeInvariants(tree);
      final other = _cormenTree();
      final node = IntervalNode('only', 1, 2);
      tree.insert(node);
      tree.delete(node);
      _assertTreeInvariants(tree);
      _assertTreeInvariants(other);
      expect(other.getAllInOrder(), hasLength(10));
    });

    test('owner and postorder collection do not resolve caches', () {
      final tree = _cormenTree();
      final nodes = tree.getAllInOrder();
      for (var i = 0; i < nodes.length; i++) {
        nodes[i].ownerId = i % 3;
        tree.resolveNode(nodes[i], 4);
        nodes[i].range = Range(
          1,
          nodes[i].cachedAbsoluteStart + 1,
          1,
          nodes[i].cachedAbsoluteEnd + 1,
        );
      }
      tree.acceptReplace(0, 0, 10, false);
      final before = nodes.map(_cache).toList();
      for (var i = 0; i < 3; i++) {
        expect(
          tree.collectNodesFromOwner(i),
          nodes.where((n) => n.ownerId == i).toList(),
        );
      }
      final expected = <IntervalNode>[];
      void visit(IntervalNode node) {
        if (node == sentinel) return;
        visit(node.left!);
        visit(node.right!);
        expected.add(node);
      }

      visit(tree.root);
      final actual = tree.collectNodesPostOrder();
      expect(actual, expected);
      expect(nodes.map(_cache).toList(), before);
      for (final node in actual) {
        tree.delete(node);
        expect([node.parent, node.left, node.right], [null, null, null]);
        _assertTreeInvariants(tree);
      }
      expect(tree.root, same(sentinel));
    });

    test(
      'tracked range update uses delete/reset/setOptions/reinsert identity',
      () {
        final tree = _cormenTree();
        final node = IntervalNode('tracked', 10, 20)..ownerId = 7;
        final options = const IntervalNodeOptions(
          stickiness: TrackedRangeStickiness.neverGrowsWhenTypingAtEdges,
        );
        node.setOptions(options);
        tree.insert(node);
        tree.acceptReplace(0, 0, 7, false);
        tree.resolveNode(node, 2);
        expect((node.cachedAbsoluteStart, node.cachedAbsoluteEnd), (17, 27));
        tree.delete(node);
        final newRange = Range(1, 31, 1, 41);
        node.reset(2, 30, 40, newRange);
        node.setOptions(
          const IntervalNodeOptions(
            stickiness: TrackedRangeStickiness.growsOnlyWhenTypingBefore,
          ),
        );
        tree.insert(node);
        tree.resolveNode(node, 2);
        expect(node.range, same(newRange));
        expect(node.id, 'tracked');
        expect(node.ownerId, 7);
        expect(tree.collectNodesFromOwner(7), [node]);
        tree.acceptReplace(30, 0, 5, false);
        tree.resolveNode(node, 3);
        expect(node.range, isNull);
        expect((node.cachedAbsoluteStart, node.cachedAbsoluteEnd), (30, 45));
        tree.acceptReplace(45, 0, 2, false);
        tree.resolveNode(node, 4);
        expect((node.cachedAbsoluteStart, node.cachedAbsoluteEnd), (30, 45));
        _assertTreeInvariants(tree);
      },
    );

    test(
      'resolveNode follows right-ancestor deltas without walking the tree',
      () {
        final tree = _cormenTree();
        final before = {
          for (final n in tree.getAllInOrder())
            n: (n.cachedAbsoluteStart, n.cachedAbsoluteEnd),
        };
        tree.acceptReplace(0, 0, 7, true);
        expect(tree.collectNodesPostOrder().any((n) => n.delta != 0), isTrue);
        for (final entry in before.entries) {
          tree.resolveNode(entry.key, 9);
          expect(
            (entry.key.cachedAbsoluteStart, entry.key.cachedAbsoluteEnd),
            (entry.value.$1 + 7, entry.value.$2 + 7),
          );
        }
        _assertTreeInvariants(tree);
      },
    );

    test('collapse-on-replace takes precedence over stickiness and forced movement', () {
      for (final sticky in TrackedRangeStickiness.values) {
        for (final force in [false, true]) {
          // node start/end, edit offset/deleted/inserted, expected start/end
          final cases = [
            (10, 20, 5, 20, 17, 5, 5),
            (10, 20, 10, 10, 3, 10, 10),
            (10, 20, 10, 10, 0, 10, 10),
            (15, 15, 15, 0, 3, 15, 15),
            (10, 20, 5, 7, 4, 9, 17),
            (10, 20, 18, 7, 4, 10, force ? 22 : 20),
          ];
          for (final (a, b, offset, deleted, inserted, expectedA, expectedB)
              in cases) {
            final tree = IntervalTree();
            final node = IntervalNode('collapse', a, b);
            node.setOptions(
              IntervalNodeOptions(
                stickiness: sticky,
                collapseOnReplaceEdit: true,
              ),
            );
            tree.insert(IntervalNode('before', 0, 1));
            tree.insert(node);
            tree.insert(IntervalNode('after', 50, 60));
            tree.acceptReplace(offset, deleted, inserted, force);
            tree.resolveNode(node, 1);
            expect(
              (node.cachedAbsoluteStart, node.cachedAbsoluteEnd),
              (expectedA, expectedB),
            );
            _assertTreeInvariants(tree);
          }
        }
      }
    });

    test(
      'deleting a two-child node transfers and normalizes an oversized delta',
      () {
        for (final sign in [-1, 1]) {
          final tree = IntervalTree();
          // Seed deltas as suggested by upstream FORCE_OVERFLOWING_TEST. Such
          // transient values can also occur between deletions in acceptReplace.
          final root = IntervalNode('root', 20, 25)
            ..delta = sign * ((1 << 30) + 1);
          final left = IntervalNode('left', 10, 15);
          final right = IntervalNode('right', 30, 35);
          tree.insert(root);
          tree.insert(left);
          tree.insert(right);
          _assertTreeInvariants(tree);
          tree.delete(root);
          expect(tree.requestNormalizeDelta, isFalse);
          expect([left.delta, right.delta], [0, 0]);
          expect(_offsets(tree.getAllInOrder()), [(10, 15), (30, 35)]);
          expect([root.parent, root.left, root.right], [null, null, null]);
          _assertTreeInvariants(tree);
        }
      },
    );

    for (final sign in [-1, 1]) {
      test(
        'normalization at the strict ${sign < 0 ? 'negative' : 'positive'} 2^30 boundary',
        () {
          const threshold = 1 << 30;
          final base = sign < 0 ? threshold * 3 : 100;
          final tree = IntervalTree();
          final nodes = List.generate(
            31,
            (i) => IntervalNode('$i', base + i * 10, base + i * 10 + 5),
          );
          for (final node in nodes) {
            tree.insert(node);
          }
          tree.acceptReplace(
            0,
            sign < 0 ? threshold : 0,
            sign > 0 ? threshold : 0,
            false,
          );
          expect(nodes.any((n) => n.delta == sign * threshold), isTrue);
          expect(tree.requestNormalizeDelta, isFalse);
          _assertTreeInvariants(tree);
          tree.acceptReplace(0, sign < 0 ? 1 : 0, sign > 0 ? 1 : 0, false);
          expect(nodes.every((n) => n.delta == 0), isTrue);
          expect(tree.requestNormalizeDelta, isFalse);
          for (var i = 0; i < nodes.length; i++) {
            tree.resolveNode(nodes[i], 1);
            final start = base + i * 10 + sign * (threshold + 1);
            expect(
              (nodes[i].cachedAbsoluteStart, nodes[i].cachedAbsoluteEnd),
              (start, start + 5),
            );
          }
          _assertTreeInvariants(tree);
        },
      );
    }

    test('explicit normalization preserves absolute ranges and cached range objects', () {
      final tree = _cormenTree();
      tree.acceptReplace(0, 0, 11, false);
      final nodes = tree.search(0, false, false, 7, false);
      final before = _offsets(nodes);
      for (final n in nodes) {
        n.range = Range(
          1,
          n.cachedAbsoluteStart + 1,
          1,
          n.cachedAbsoluteEnd + 1,
        );
      }
      final caches = nodes.map(_cache).toList();
      tree.requestNormalizeDelta = true;
      tree.insert(IntervalNode('extra', 100, 101));
      expect(nodes.every((n) => n.delta == 0), isTrue);
      expect(nodes.map(_cache).toList(), caches);
      for (final n in nodes) {
        tree.resolveNode(n, 7);
      }
      expect(_offsets(nodes), before);
      _assertTreeInvariants(tree);
    });

    test('comparison tie-breaking and exported maxEnd recomputation', () {
      expect(intervalCompare(1, 9, 2, 3), -1);
      expect(intervalCompare(1, 9, 1, 3), 6);
      expect(intervalCompare(1, 9, 1, 9), 0);
      final tree = _cormenTree();
      final root = tree.root;
      final expected = root.maxEnd;
      root.maxEnd = -1;
      recomputeMaxEnd(root);
      expect(root.maxEnd, expected);
      _assertTreeInvariants(tree);
    });
  });

  group('pinned TypeScript differential goldens', () {
    var index = 0;
    for (final sticky in TrackedRangeStickiness.values) {
      for (final force in [false, true]) {
        for (final collapse in [false, true]) {
          final expected = _boundaryGoldens[index++];
          test(
            'exhaustive boundaries ${sticky.name}, force=$force, collapse=$collapse',
            () {
              var hash = 0;
              for (var a = 0; a <= 6; a++) {
                for (var b = a; b <= 6; b++) {
                  for (var start = 0; start <= 6; start++) {
                    for (var end = start; end <= 6; end++) {
                      for (var length = 0; length <= 6; length++) {
                        final node = IntervalNode('', a, b);
                        node.setOptions(
                          IntervalNodeOptions(
                            stickiness: sticky,
                            collapseOnReplaceEdit: collapse,
                          ),
                        );
                        nodeAcceptEdit(node, start, end, length, force);
                        hash = _addHash(hash, [node.start, node.end]);
                      }
                    }
                  }
                }
              }
              expect(hash, expected);
            },
          );
        }
      }
    }
    for (final (seed, checkpoints) in _traceGoldens) {
      test('400 mixed edits, mutations, filters and caches, seed $seed', () {
        _checkUpstreamTrace(seed, checkpoints);
      });
    }
  });
}

// Invariants from upstream, strengthened with parent links, cleared traversal
// bits, acyclicity, whole-subtree ordering and non-negative absolute offsets.
void _assertTreeInvariants(IntervalTree tree) {
  expect(getNodeColor(sentinel), NodeColor.black);
  expect(sentinel.parent, same(sentinel));
  expect(sentinel.left, same(sentinel));
  expect(sentinel.right, same(sentinel));
  expect([sentinel.start, sentinel.end, sentinel.delta], [0, 0, 0]);
  expect(sentinel.metadata & 2, 0);
  expect(tree.root.parent, same(sentinel));
  expect(getNodeColor(tree.root), NodeColor.black);
  final seen = <IntervalNode>{};
  (int, int)? previous;
  int visit(IntervalNode node, IntervalNode parent, int delta) {
    if (node == sentinel) return 1;
    expect(
      seen.add(node),
      isTrue,
      reason: 'cycle or repeated child ${node.id}',
    );
    expect(node.parent, same(parent));
    expect(node.metadata & 2, 0, reason: 'uncleared visited bit ${node.id}');
    expect(node.start + delta, greaterThanOrEqualTo(0));
    expect(node.start, lessThanOrEqualTo(node.end));
    final left = node.left!, right = node.right!;
    if (getNodeColor(node) == NodeColor.red) {
      expect(getNodeColor(left), NodeColor.black);
      expect(getNodeColor(right), NodeColor.black);
    }
    var maxEnd = node.end;
    if (left != sentinel) maxEnd = math.max(maxEnd, left.maxEnd);
    if (right != sentinel) maxEnd = math.max(maxEnd, right.maxEnd + node.delta);
    expect(node.maxEnd, maxEnd, reason: 'maxEnd of ${node.id}');
    final leftDepth = visit(left, node, delta);
    final absolute = (node.start + delta, node.end + delta);
    if (previous case final p?) {
      expect(
        intervalCompare(p.$1, p.$2, absolute.$1, absolute.$2),
        lessThanOrEqualTo(0),
      );
    }
    previous = absolute;
    final rightDepth = visit(right, node, delta + node.delta);
    expect(leftDepth, rightDepth, reason: 'black height at ${node.id}');
    return leftDepth + (getNodeColor(node) == NodeColor.black ? 1 : 0);
  }

  visit(tree.root, sentinel, 0);
}

List<(int, int)> _offsets(Iterable<IntervalNode> nodes) => [
  for (final n in nodes) (n.cachedAbsoluteStart, n.cachedAbsoluteEnd),
];

(int, int, int, Range?) _cache(IntervalNode node) => (
  node.cachedVersionId,
  node.cachedAbsoluteStart,
  node.cachedAbsoluteEnd,
  node.range,
);

IntervalTree _cormenTree() {
  final tree = IntervalTree();
  const ranges = [
    (16, 21),
    (8, 9),
    (25, 30),
    (5, 8),
    (15, 23),
    (17, 19),
    (26, 26),
    (0, 3),
    (6, 10),
    (19, 20),
  ];
  for (var i = 0; i < ranges.length; i++) {
    tree.insert(IntervalNode('$i', ranges[i].$1, ranges[i].$2));
  }
  return tree;
}

bool _isValidation(String? name) =>
    name == ClassName.editorErrorDecoration ||
    name == ClassName.editorWarningDecoration ||
    name == ClassName.editorInfoDecoration;

const _classNames = <String?>[
  null,
  ClassName.editorHintDecoration,
  ClassName.editorInfoDecoration,
  ClassName.editorWarningDecoration,
  ClassName.editorErrorDecoration,
  ClassName.editorUnnecessaryDecoration,
  ClassName.editorUnnecessaryInlineDecoration,
  ClassName.editorDeprecatedInlineDecoration,
  'squiggly-error extra',
  '',
];

class _Op {
  const _Op.insert(this.a, this.b) : kind = 'insert', id = -1;
  const _Op.delete(this.id) : kind = 'delete', a = 0, b = 0;
  const _Op.change(this.id, this.a, this.b) : kind = 'change';
  const _Op.search(this.a, this.b) : kind = 'search', id = -1;
  final String kind;
  final int id, a, b;
}

class _TestState {
  final tree = IntervalTree();
  final nodes = <IntervalNode?>[];
  final oracle = <int, (int, int)>{};

  void accept(_Op op) {
    switch (op.kind) {
      case 'insert':
        final node = IntervalNode('${nodes.length}', op.a, op.b);
        oracle[nodes.length] = (op.a, op.b);
        nodes.add(node);
        tree.insert(node);
      case 'delete':
        final node = nodes[op.id]!;
        tree.delete(node);
        expect([node.parent, node.left, node.right], [null, null, null]);
        nodes[op.id] = null;
        oracle.remove(op.id);
      case 'change':
        final node = nodes[op.id]!;
        tree.delete(node);
        node.reset(0, op.a, op.b, null);
        tree.insert(node);
        oracle[op.id] = (op.a, op.b);
      case 'search':
        expect(
          _offsets(tree.intervalSearch(op.a, op.b, 0, false, false, 0, false)),
          _sorted(oracle.values.where((r) => r.$1 <= op.b && r.$2 >= op.a)),
        );
    }
    _assertTreeInvariants(tree);
    expect(_offsets(tree.getAllInOrder()), _sorted(oracle.values));
  }
}

List<(int, int)> _sorted(Iterable<(int, int)> ranges) =>
    ranges.toList()..sort((a, b) => a.$1 == b.$1 ? a.$2 - b.$2 : a.$1 - b.$1);

class _Random {
  _Random(this.state);
  int state;
  int next(int bound) {
    state = (state * 1664525 + 1013904223) & 0xffffffff;
    return (state >>> 8) % bound;
  }
}

(int, int) _randomUpstreamRange(_Random random) {
  final start = random.next(100) + 1;
  final limit = random.next(10) < 2 ? 100 - start : math.min(100 - start, 10);
  return (start, start + random.next(limit + 1));
}

int _addHash(int hash, Object value) {
  for (final unit in jsonEncode(value).codeUnits) {
    hash = (hash * 31 + unit) & 0xffffffff;
  }
  return hash;
}

// This exact deterministic operation stream was run against intervalTree.ts
// using Node's stripTypeScriptTypes(mode: 'transform'), with only its imports
// replaced by model.ts's actual TrackedRangeStickiness enum. No Dart result was
// used to generate goldens. Source SHA-256:
// 4cb81bae1281ada05fd31391e816b36e0af79e0960f4c34c61fdb9df65f87bf7
// Every 50 steps, the rolling 32-bit polynomial hash covers JSON arrays of
// root identity, normalization flag, query/owner/postorder identities, and all
// live nodes' structural fields, metadata, offsets, versions and range presence.
// The exhaustive marker goldens use the same hash of [start,end] per case.
void _checkUpstreamTrace(int seed, List<int> checkpoints) {
  final random = _Random(seed);
  final tree = IntervalTree();
  final nodes = <IntervalNode>[];
  var length = 200, version = 1, nextId = 0, hash = 0;
  (int, int) range() {
    final start = random.next(length + 1);
    return (start, start + random.next(length - start + 1));
  }

  IntervalNodeOptions options() => IntervalNodeOptions(
    stickiness: TrackedRangeStickiness.values[random.next(4)],
    className: [
      null,
      'squiggly-error',
      'squiggly-warning',
      'squiggly-info',
      'squiggly-hint',
    ][random.next(5)],
    glyphMarginClassName: random.next(2) == 0 ? null : 'glyph',
    collapseOnReplaceEdit: random.next(2) == 1,
    affectsFont: random.next(2) == 1,
  );
  String? id(IntervalNode? node) => node == sentinel ? null : node?.id;
  for (var step = 0; step < 400; step++) {
    final op = random.next(10);
    if (nodes.isEmpty || op < 3) {
      final (a, b) = range();
      final node = IntervalNode('${nextId++}', a, b);
      node.reset(version, a, b, Range(1, a + 1, 1, b + 1));
      node.setOptions(options());
      node.ownerId = random.next(3);
      tree.insert(node);
      nodes.add(node);
    } else if (op == 3) {
      final index = random.next(nodes.length);
      tree.delete(nodes[index]);
      expect(
        [nodes[index].parent, nodes[index].left, nodes[index].right],
        [null, null, null],
      );
      nodes.removeAt(index);
    } else if (op == 4) {
      final node = nodes[random.next(nodes.length)];
      final (a, b) = range();
      tree.delete(node);
      node.reset(version, a, b, Range(1, a + 1, 1, b + 1));
      node.setOptions(options());
      tree.insert(node);
    } else if (op < 8) {
      final start = random.next(length + 1);
      final deleted = random.next(math.min(length - start, 40) + 1);
      final inserted = step % 37 == 0 ? (1 << 30) + 31 : random.next(41);
      tree.acceptReplace(start, deleted, inserted, random.next(2) == 1);
      length += inserted - deleted;
      version++;
    } else if (op == 8) {
      nodes[random.next(nodes.length)].setOptions(options());
    } else {
      tree.resolveNode(nodes[random.next(nodes.length)], version);
    }
    final (a, b) = range();
    final owner = random.next(3);
    final validation = random.next(2) == 1;
    final font = random.next(2) == 1;
    final margin = random.next(2) == 1;
    final result = step.isEven
        ? tree.intervalSearch(a, b, owner, validation, font, version, margin)
        : tree.search(owner, validation, font, version, margin);
    final owned = tree.collectNodesFromOwner(random.next(3));
    final post = tree.collectNodesPostOrder();
    if (nodes.isNotEmpty) {
      tree.resolveNode(nodes[random.next(nodes.length)], version);
    }
    hash = _addHash(hash, [
      id(tree.root),
      tree.requestNormalizeDelta,
      result.map(id).toList(),
      owned.map(id).toList(),
      post.map(id).toList(),
      [
        for (final n in nodes)
          [
            n.id,
            n.start,
            n.end,
            n.delta,
            n.maxEnd,
            n.metadata,
            n.ownerId,
            id(n.parent),
            id(n.left),
            id(n.right),
            n.cachedVersionId,
            n.cachedAbsoluteStart,
            n.cachedAbsoluteEnd,
            n.range != null,
          ],
      ],
    ]);
    _assertTreeInvariants(tree);
    if ((step + 1) % 50 == 0) {
      expect(
        hash,
        checkpoints[(step + 1) ~/ 50 - 1],
        reason: 'upstream seed $seed, step $step',
      );
    }
  }
}

const _upstreamOperations = <(String, List<_Op>)>[
  ('gen01', [_Op.insert(28, 35), _Op.insert(52, 54), _Op.insert(63, 69)]),
  ('gen02', [_Op.insert(80, 89), _Op.insert(92, 100), _Op.insert(99, 99)]),
  ('gen03', [_Op.insert(89, 96), _Op.insert(71, 74), _Op.delete(1)]),
  ('gen04', [_Op.insert(44, 46), _Op.insert(85, 88), _Op.delete(0)]),
  (
    'gen05',
    [_Op.insert(82, 90), _Op.insert(69, 73), _Op.delete(0), _Op.delete(1)],
  ),
  (
    'gen06',
    [_Op.insert(41, 63), _Op.insert(98, 98), _Op.insert(47, 51), _Op.delete(2)],
  ),
  (
    'gen07',
    [
      _Op.insert(24, 26),
      _Op.insert(11, 28),
      _Op.insert(27, 30),
      _Op.insert(80, 85),
      _Op.delete(1),
    ],
  ),
  ('gen08', [_Op.insert(100, 100), _Op.insert(100, 100)]),
  ('gen09', [_Op.insert(58, 65), _Op.insert(82, 96), _Op.insert(58, 65)]),
  ('gen10', [_Op.insert(32, 40), _Op.insert(25, 29), _Op.insert(24, 32)]),
  (
    'gen11',
    [
      _Op.insert(25, 70),
      _Op.insert(99, 100),
      _Op.insert(46, 51),
      _Op.insert(57, 57),
      _Op.delete(2),
    ],
  ),
  (
    'gen12',
    [
      _Op.insert(20, 26),
      _Op.insert(10, 18),
      _Op.insert(99, 99),
      _Op.insert(37, 59),
      _Op.delete(2),
    ],
  ),
  (
    'gen13',
    [
      _Op.insert(3, 91),
      _Op.insert(57, 57),
      _Op.insert(35, 44),
      _Op.insert(72, 81),
      _Op.delete(2),
    ],
  ),
  (
    'gen14',
    [
      _Op.insert(58, 61),
      _Op.insert(34, 35),
      _Op.insert(56, 62),
      _Op.insert(69, 78),
      _Op.delete(0),
    ],
  ),
  (
    'gen15',
    [
      _Op.insert(63, 69),
      _Op.insert(17, 24),
      _Op.insert(3, 13),
      _Op.insert(84, 94),
      _Op.insert(18, 23),
      _Op.insert(96, 98),
      _Op.delete(1),
    ],
  ),
  (
    'gen16',
    [
      _Op.insert(27, 27),
      _Op.insert(42, 87),
      _Op.insert(42, 49),
      _Op.insert(69, 71),
      _Op.insert(20, 27),
      _Op.insert(8, 9),
      _Op.insert(42, 49),
      _Op.delete(1),
    ],
  ),
  (
    'gen17',
    [
      _Op.insert(21, 23),
      _Op.insert(83, 87),
      _Op.insert(56, 58),
      _Op.insert(1, 55),
      _Op.insert(56, 59),
      _Op.insert(58, 60),
      _Op.insert(56, 65),
      _Op.delete(1),
      _Op.delete(0),
      _Op.delete(6),
    ],
  ),
  (
    'gen18',
    [_Op.insert(25, 25), _Op.insert(67, 79), _Op.delete(0), _Op.search(65, 75)],
  ),
  (
    'force delta overflow',
    [
      _Op.insert(686081138593427, 733009856502260),
      _Op.insert(591031326181669, 591031326181672),
      _Op.insert(940037682731896, 940037682731903),
      _Op.insert(598413641151120, 598413641151128),
      _Op.insert(800564156553344, 800564156553351),
      _Op.insert(894198957565481, 894198957565491),
    ],
  ),
];

// (upstream label, node start/end, stickiness, edit start/end, inserted
// length, forceMoveMarkers, expected start/end).
const _upstreamEdits = <(String, int, int, int, int, int, int, bool, int, int)>[
  ('A.000', 0, 0, 0, 0, 0, 0, false, 0, 0),
  ('A.001', 0, 0, 1, 0, 0, 0, false, 0, 0),
  ('A.002', 0, 0, 2, 0, 0, 0, false, 0, 0),
  ('A.003', 0, 0, 3, 0, 0, 0, false, 0, 0),
  ('A.004', 0, 0, 0, 0, 0, 0, true, 0, 0),
  ('A.005', 0, 0, 1, 0, 0, 0, true, 0, 0),
  ('A.006', 0, 0, 2, 0, 0, 0, true, 0, 0),
  ('A.007', 0, 0, 3, 0, 0, 0, true, 0, 0),
  ('A.008', 0, 0, 0, 0, 0, 1, false, 0, 1),
  ('A.009', 0, 0, 1, 0, 0, 1, false, 1, 1),
  ('A.010', 0, 0, 2, 0, 0, 1, false, 0, 0),
  ('A.011', 0, 0, 3, 0, 0, 1, false, 1, 1),
  ('A.012', 0, 0, 0, 0, 0, 1, true, 1, 1),
  ('A.013', 0, 0, 1, 0, 0, 1, true, 1, 1),
  ('A.014', 0, 0, 2, 0, 0, 1, true, 1, 1),
  ('A.015', 0, 0, 3, 0, 0, 1, true, 1, 1),
  ('B.000', 0, 5, 0, 0, 0, 0, false, 0, 5),
  ('B.001', 0, 5, 1, 0, 0, 0, false, 0, 5),
  ('B.002', 0, 5, 2, 0, 0, 0, false, 0, 5),
  ('B.003', 0, 5, 3, 0, 0, 0, false, 0, 5),
  ('B.004', 0, 5, 0, 0, 0, 0, true, 0, 5),
  ('B.005', 0, 5, 1, 0, 0, 0, true, 0, 5),
  ('B.006', 0, 5, 2, 0, 0, 0, true, 0, 5),
  ('B.007', 0, 5, 3, 0, 0, 0, true, 0, 5),
  ('B.008', 0, 5, 0, 0, 0, 1, false, 0, 6),
  ('B.009', 0, 5, 1, 0, 0, 1, false, 1, 6),
  ('B.010', 0, 5, 2, 0, 0, 1, false, 0, 6),
  ('B.011', 0, 5, 3, 0, 0, 1, false, 1, 6),
  ('B.012', 0, 5, 0, 0, 0, 1, true, 1, 6),
  ('B.013', 0, 5, 1, 0, 0, 1, true, 1, 6),
  ('B.014', 0, 5, 2, 0, 0, 1, true, 1, 6),
  ('B.015', 0, 5, 3, 0, 0, 1, true, 1, 6),
  ('B.016', 0, 5, 0, 2, 2, 1, false, 0, 6),
  ('B.017', 0, 5, 1, 2, 2, 1, false, 0, 6),
  ('B.018', 0, 5, 2, 2, 2, 1, false, 0, 6),
  ('B.019', 0, 5, 3, 2, 2, 1, false, 0, 6),
  ('B.020', 0, 5, 0, 2, 2, 1, true, 0, 6),
  ('B.021', 0, 5, 1, 2, 2, 1, true, 0, 6),
  ('B.022', 0, 5, 2, 2, 2, 1, true, 0, 6),
  ('B.023', 0, 5, 3, 2, 2, 1, true, 0, 6),
  ('B.024', 0, 5, 0, 5, 5, 1, false, 0, 6),
  ('B.025', 0, 5, 1, 5, 5, 1, false, 0, 5),
  ('B.026', 0, 5, 2, 5, 5, 1, false, 0, 5),
  ('B.027', 0, 5, 3, 5, 5, 1, false, 0, 6),
  ('B.028', 0, 5, 0, 5, 5, 1, true, 0, 6),
  ('B.029', 0, 5, 1, 5, 5, 1, true, 0, 6),
  ('B.030', 0, 5, 2, 5, 5, 1, true, 0, 6),
  ('B.031', 0, 5, 3, 5, 5, 1, true, 0, 6),
  ('B.032', 5, 10, 0, 4, 5, 2, false, 5, 11),
  ('B.033', 5, 10, 1, 4, 5, 2, false, 6, 11),
  ('B.034', 5, 10, 2, 4, 5, 2, false, 5, 11),
  ('B.035', 5, 10, 3, 4, 5, 2, false, 6, 11),
  ('B.036', 5, 10, 0, 4, 5, 2, true, 6, 11),
  ('B.037', 5, 10, 1, 4, 5, 2, true, 6, 11),
  ('B.038', 5, 10, 2, 4, 5, 2, true, 6, 11),
  ('B.039', 5, 10, 3, 4, 5, 2, true, 6, 11),
  ('B.040', 5, 10, 0, 3, 5, 1, false, 4, 9),
  ('B.041', 5, 10, 1, 3, 5, 1, false, 4, 9),
  ('B.042', 5, 10, 2, 3, 5, 1, false, 4, 9),
  ('B.043', 5, 10, 3, 3, 5, 1, false, 4, 9),
  ('B.044', 5, 10, 0, 3, 5, 1, true, 4, 9),
  ('B.045', 5, 10, 1, 3, 5, 1, true, 4, 9),
  ('B.046', 5, 10, 2, 3, 5, 1, true, 4, 9),
  ('B.047', 5, 10, 3, 3, 5, 1, true, 4, 9),
  ('B.048', 5, 10, 0, 4, 6, 3, false, 5, 11),
  ('B.049', 5, 10, 1, 4, 6, 3, false, 5, 11),
  ('B.050', 5, 10, 2, 4, 6, 3, false, 5, 11),
  ('B.051', 5, 10, 3, 4, 6, 3, false, 5, 11),
  ('B.052', 5, 10, 0, 4, 6, 3, true, 7, 11),
  ('B.053', 5, 10, 1, 4, 6, 3, true, 7, 11),
  ('B.054', 5, 10, 2, 4, 6, 3, true, 7, 11),
  ('B.055', 5, 10, 3, 4, 6, 3, true, 7, 11),
  ('B.056', 5, 10, 0, 4, 6, 1, false, 5, 9),
  ('B.057', 5, 10, 1, 4, 6, 1, false, 5, 9),
  ('B.058', 5, 10, 2, 4, 6, 1, false, 5, 9),
  ('B.059', 5, 10, 3, 4, 6, 1, false, 5, 9),
  ('B.060', 5, 10, 0, 4, 6, 1, true, 5, 9),
  ('B.061', 5, 10, 1, 4, 6, 1, true, 5, 9),
  ('B.062', 5, 10, 2, 4, 6, 1, true, 5, 9),
  ('B.063', 5, 10, 3, 4, 6, 1, true, 5, 9),
  ('B.064', 5, 10, 0, 5, 6, 2, false, 5, 11),
  ('B.065', 5, 10, 1, 5, 6, 2, false, 5, 11),
  ('B.066', 5, 10, 2, 5, 6, 2, false, 5, 11),
  ('B.067', 5, 10, 3, 5, 6, 2, false, 5, 11),
  ('B.068', 5, 10, 0, 5, 6, 2, true, 7, 11),
  ('B.069', 5, 10, 1, 5, 6, 2, true, 7, 11),
  ('B.070', 5, 10, 2, 5, 6, 2, true, 7, 11),
  ('B.071', 5, 10, 3, 5, 6, 2, true, 7, 11),
  ('B.072', 5, 10, 0, 5, 7, 1, false, 5, 9),
  ('B.073', 5, 10, 1, 5, 7, 1, false, 5, 9),
  ('B.074', 5, 10, 2, 5, 7, 1, false, 5, 9),
  ('B.075', 5, 10, 3, 5, 7, 1, false, 5, 9),
  ('B.076', 5, 10, 0, 5, 7, 1, true, 6, 9),
  ('B.077', 5, 10, 1, 5, 7, 1, true, 6, 9),
  ('B.078', 5, 10, 2, 5, 7, 1, true, 6, 9),
  ('B.079', 5, 10, 3, 5, 7, 1, true, 6, 9),
  ('B.080', 5, 10, 0, 9, 10, 2, false, 5, 11),
  ('B.081', 5, 10, 1, 9, 10, 2, false, 5, 10),
  ('B.082', 5, 10, 2, 9, 10, 2, false, 5, 10),
  ('B.083', 5, 10, 3, 9, 10, 2, false, 5, 11),
  ('B.084', 5, 10, 0, 9, 10, 2, true, 5, 11),
  ('B.085', 5, 10, 1, 9, 10, 2, true, 5, 11),
  ('B.086', 5, 10, 2, 9, 10, 2, true, 5, 11),
  ('B.087', 5, 10, 3, 9, 10, 2, true, 5, 11),
  ('B.088', 5, 10, 0, 8, 10, 1, false, 5, 9),
  ('B.089', 5, 10, 1, 8, 10, 1, false, 5, 9),
  ('B.090', 5, 10, 2, 8, 10, 1, false, 5, 9),
  ('B.091', 5, 10, 3, 8, 10, 1, false, 5, 9),
  ('B.092', 5, 10, 0, 8, 10, 1, true, 5, 9),
  ('B.093', 5, 10, 1, 8, 10, 1, true, 5, 9),
  ('B.094', 5, 10, 2, 8, 10, 1, true, 5, 9),
  ('B.095', 5, 10, 3, 8, 10, 1, true, 5, 9),
  ('B.096', 5, 10, 0, 9, 11, 3, false, 5, 10),
  ('B.097', 5, 10, 1, 9, 11, 3, false, 5, 10),
  ('B.098', 5, 10, 2, 9, 11, 3, false, 5, 10),
  ('B.099', 5, 10, 3, 9, 11, 3, false, 5, 10),
  ('B.100', 5, 10, 0, 9, 11, 3, true, 5, 12),
  ('B.101', 5, 10, 1, 9, 11, 3, true, 5, 12),
  ('B.102', 5, 10, 2, 9, 11, 3, true, 5, 12),
  ('B.103', 5, 10, 3, 9, 11, 3, true, 5, 12),
  ('B.104', 5, 10, 0, 9, 11, 1, false, 5, 10),
  ('B.105', 5, 10, 1, 9, 11, 1, false, 5, 10),
  ('B.106', 5, 10, 2, 9, 11, 1, false, 5, 10),
  ('B.107', 5, 10, 3, 9, 11, 1, false, 5, 10),
  ('B.108', 5, 10, 0, 9, 11, 1, true, 5, 10),
  ('B.109', 5, 10, 1, 9, 11, 1, true, 5, 10),
  ('B.110', 5, 10, 2, 9, 11, 1, true, 5, 10),
  ('B.111', 5, 10, 3, 9, 11, 1, true, 5, 10),
  ('B.112', 5, 10, 0, 10, 11, 3, false, 5, 10),
  ('B.113', 5, 10, 1, 10, 11, 3, false, 5, 10),
  ('B.114', 5, 10, 2, 10, 11, 3, false, 5, 10),
  ('B.115', 5, 10, 3, 10, 11, 3, false, 5, 10),
  ('B.116', 5, 10, 0, 10, 11, 3, true, 5, 13),
  ('B.117', 5, 10, 1, 10, 11, 3, true, 5, 13),
  ('B.118', 5, 10, 2, 10, 11, 3, true, 5, 13),
  ('B.119', 5, 10, 3, 10, 11, 3, true, 5, 13),
  ('B.120', 5, 10, 0, 10, 12, 1, false, 5, 10),
  ('B.121', 5, 10, 1, 10, 12, 1, false, 5, 10),
  ('B.122', 5, 10, 2, 10, 12, 1, false, 5, 10),
  ('B.123', 5, 10, 3, 10, 12, 1, false, 5, 10),
  ('B.124', 5, 10, 0, 10, 12, 1, true, 5, 11),
  ('B.125', 5, 10, 1, 10, 12, 1, true, 5, 11),
  ('B.126', 5, 10, 2, 10, 12, 1, true, 5, 11),
  ('B.127', 5, 10, 3, 10, 12, 1, true, 5, 11),
  ('B.128', 5, 10, 0, 4, 5, 0, false, 4, 9),
  ('B.129', 5, 10, 1, 4, 5, 0, false, 4, 9),
  ('B.130', 5, 10, 2, 4, 5, 0, false, 4, 9),
  ('B.131', 5, 10, 3, 4, 5, 0, false, 4, 9),
  ('B.132', 5, 10, 0, 4, 5, 0, true, 4, 9),
  ('B.133', 5, 10, 1, 4, 5, 0, true, 4, 9),
  ('B.134', 5, 10, 2, 4, 5, 0, true, 4, 9),
  ('B.135', 5, 10, 3, 4, 5, 0, true, 4, 9),
  ('B.136', 5, 10, 0, 4, 6, 0, false, 4, 8),
  ('B.137', 5, 10, 1, 4, 6, 0, false, 4, 8),
  ('B.138', 5, 10, 2, 4, 6, 0, false, 4, 8),
  ('B.139', 5, 10, 3, 4, 6, 0, false, 4, 8),
  ('B.140', 5, 10, 0, 4, 6, 0, true, 4, 8),
  ('B.141', 5, 10, 1, 4, 6, 0, true, 4, 8),
  ('B.142', 5, 10, 2, 4, 6, 0, true, 4, 8),
  ('B.143', 5, 10, 3, 4, 6, 0, true, 4, 8),
  ('B.144', 5, 10, 0, 5, 6, 0, false, 5, 9),
  ('B.145', 5, 10, 1, 5, 6, 0, false, 5, 9),
  ('B.146', 5, 10, 2, 5, 6, 0, false, 5, 9),
  ('B.147', 5, 10, 3, 5, 6, 0, false, 5, 9),
  ('B.148', 5, 10, 0, 5, 6, 0, true, 5, 9),
  ('B.149', 5, 10, 1, 5, 6, 0, true, 5, 9),
  ('B.150', 5, 10, 2, 5, 6, 0, true, 5, 9),
  ('B.151', 5, 10, 3, 5, 6, 0, true, 5, 9),
  ('B.152', 5, 10, 0, 9, 10, 0, false, 5, 9),
  ('B.153', 5, 10, 1, 9, 10, 0, false, 5, 9),
  ('B.154', 5, 10, 2, 9, 10, 0, false, 5, 9),
  ('B.155', 5, 10, 3, 9, 10, 0, false, 5, 9),
  ('B.156', 5, 10, 0, 9, 10, 0, true, 5, 9),
  ('B.157', 5, 10, 1, 9, 10, 0, true, 5, 9),
  ('B.158', 5, 10, 2, 9, 10, 0, true, 5, 9),
  ('B.159', 5, 10, 3, 9, 10, 0, true, 5, 9),
  ('B.160', 5, 10, 0, 9, 11, 0, false, 5, 9),
  ('B.161', 5, 10, 1, 9, 11, 0, false, 5, 9),
  ('B.162', 5, 10, 2, 9, 11, 0, false, 5, 9),
  ('B.163', 5, 10, 3, 9, 11, 0, false, 5, 9),
  ('B.164', 5, 10, 0, 9, 11, 0, true, 5, 9),
  ('B.165', 5, 10, 1, 9, 11, 0, true, 5, 9),
  ('B.166', 5, 10, 2, 9, 11, 0, true, 5, 9),
  ('B.167', 5, 10, 3, 9, 11, 0, true, 5, 9),
  ('B.168', 5, 10, 0, 10, 11, 0, false, 5, 10),
  ('B.169', 5, 10, 1, 10, 11, 0, false, 5, 10),
  ('B.170', 5, 10, 2, 10, 11, 0, false, 5, 10),
  ('B.171', 5, 10, 3, 10, 11, 0, false, 5, 10),
  ('B.172', 5, 10, 0, 10, 11, 0, true, 5, 10),
  ('B.173', 5, 10, 1, 10, 11, 0, true, 5, 10),
  ('B.174', 5, 10, 2, 10, 11, 0, true, 5, 10),
  ('B.175', 5, 10, 3, 10, 11, 0, true, 5, 10),
  ('B.176', 5, 10, 0, 5, 10, 3, false, 5, 8),
  ('B.177', 5, 10, 1, 5, 10, 3, false, 5, 8),
  ('B.178', 5, 10, 2, 5, 10, 3, false, 5, 8),
  ('B.179', 5, 10, 3, 5, 10, 3, false, 5, 8),
  ('B.180', 5, 10, 0, 5, 10, 3, true, 8, 8),
  ('B.181', 5, 10, 1, 5, 10, 3, true, 8, 8),
  ('B.182', 5, 10, 2, 5, 10, 3, true, 8, 8),
  ('B.183', 5, 10, 3, 5, 10, 3, true, 8, 8),
  ('B.184', 5, 10, 0, 5, 10, 7, false, 5, 12),
  ('B.185', 5, 10, 1, 5, 10, 7, false, 5, 10),
  ('B.186', 5, 10, 2, 5, 10, 7, false, 5, 10),
  ('B.187', 5, 10, 3, 5, 10, 7, false, 5, 12),
  ('B.188', 5, 10, 0, 5, 10, 7, true, 12, 12),
  ('B.189', 5, 10, 1, 5, 10, 7, true, 12, 12),
  ('B.190', 5, 10, 2, 5, 10, 7, true, 12, 12),
  ('B.191', 5, 10, 3, 5, 10, 7, true, 12, 12),
];

const _boundaryGoldens = <int>[
  1500300645,
  338582218,
  4010767602,
  514531180,
  3672801403,
  351701959,
  4010767602,
  514531180,
  1218768518,
  334739054,
  4010767602,
  514531180,
  1877181252,
  3630414773,
  4010767602,
  514531180,
];

const _traceGoldens = <(int, List<int>)>[
  (
    1,
    [
      2680828648,
      3457093497,
      3601582756,
      1795949931,
      609731017,
      551242215,
      2186469002,
      3698984854,
    ],
  ),
  (
    2,
    [
      3472825999,
      3478075899,
      3416896190,
      303975243,
      168258371,
      2447510772,
      4223648074,
      753781070,
    ],
  ),
  (
    3,
    [
      3616956155,
      1119634671,
      991388061,
      3689340128,
      3469557290,
      2170362316,
      178872478,
      383928397,
    ],
  ),
  (
    4,
    [
      354808095,
      1367072080,
      1378937750,
      1861278652,
      1679423518,
      2812631502,
      2074736033,
      673663495,
    ],
  ),
  (
    5,
    [
      1987226685,
      1467004405,
      304788872,
      3608589740,
      1571471951,
      1896791745,
      3660945232,
      1229037321,
    ],
  ),
  (
    7,
    [
      2295265817,
      2559734946,
      2194291926,
      1016888092,
      383873532,
      613684863,
      764090603,
      609711940,
    ],
  ),
  (
    11,
    [
      711777376,
      655658324,
      3915692457,
      2795816709,
      3522366048,
      2005416428,
      2669217458,
      1432537983,
    ],
  ),
  (
    19,
    [
      3217554082,
      889060872,
      3070872868,
      2658721883,
      2252387170,
      3157081817,
      1365919225,
      1408225565,
    ],
  ),
  (
    42,
    [
      1884183694,
      2478143282,
      1013066975,
      161908955,
      51051968,
      3006902129,
      1975737265,
      1157452235,
    ],
  ),
  (
    73,
    [
      966168413,
      3575782413,
      2468755484,
      2999401329,
      780418499,
      3310052468,
      4012052781,
      4104085418,
    ],
  ),
  (
    99,
    [
      3537693273,
      2832487327,
      3710167492,
      3368278879,
      2379348127,
      3958421493,
      1837728680,
      1684032767,
    ],
  ),
  (
    123,
    [
      1943600591,
      3253459963,
      2011225702,
      1418941244,
      3368736530,
      1022337837,
      3814473099,
      3902144753,
    ],
  ),
  (
    256,
    [
      2014472952,
      4293273820,
      2524353477,
      2726373551,
      3178313491,
      2194525166,
      3582130047,
      565890648,
    ],
  ),
  (
    512,
    [
      3546621709,
      1509378839,
      530940873,
      2188286012,
      2052538296,
      2244195379,
      4076322671,
      2467266303,
    ],
  ),
  (
    1024,
    [
      1414763965,
      3153502948,
      1614150361,
      4115661576,
      2059323607,
      3191722028,
      768770371,
      832246232,
    ],
  ),
  (
    2026,
    [
      2279639289,
      3564859738,
      3230410012,
      1874662576,
      2731405875,
      2056788917,
      2738357018,
      283561478,
    ],
  ),
  (
    65535,
    [
      1198559005,
      3923987078,
      2645649790,
      1593258557,
      191642115,
      1096840872,
      3958665759,
      4260815146,
    ],
  ),
  (
    104729,
    [
      2103194144,
      4174958222,
      1779964217,
      3394872372,
      1619739595,
      2654970824,
      2881418220,
      1249215378,
    ],
  ),
  (
    123456789,
    [
      732121091,
      768062638,
      1433282027,
      4080266083,
      132559911,
      368941533,
      2165598888,
      2177426266,
    ],
  ),
  (
    2147483647,
    [
      2479553942,
      2324774506,
      217401035,
      2584664411,
      2964155254,
      2331385106,
      1056194208,
      869189801,
    ],
  ),
];
