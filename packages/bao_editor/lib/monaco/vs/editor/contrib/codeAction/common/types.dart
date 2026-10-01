/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code at 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/base/common/hierarchicalKind.ts (HierarchicalKind),
// src/vs/editor/contrib/codeAction/common/types.ts (CodeActionKind),
// src/vs/editor/contrib/codeAction/browser/codeAction.ts
// (ManagedCodeActionSet comparators) and codeActionMenu.ts (toMenuItems
// grouping). Deviations: actions are described by [CodeActionInfo] instead
// of `languages.CodeAction`; there are no AI actions, previews, keybinding
// resolvers or icons.

class HierarchicalKind {
  const HierarchicalKind(this.value);

  static const String sep = '.';

  /// Special kind that matches nothing.
  static const HierarchicalKind none = HierarchicalKind('@@none@@');
  static const HierarchicalKind empty = HierarchicalKind('');

  final String value;

  bool equals(HierarchicalKind other) => value == other.value;

  bool contains(HierarchicalKind other) =>
      equals(other) || value.isEmpty || other.value.startsWith('$value$sep');

  bool intersects(HierarchicalKind other) =>
      contains(other) || other.contains(this);

  HierarchicalKind append(List<String> parts) => HierarchicalKind(
    (value.isNotEmpty ? [value, ...parts] : parts).join(sep),
  );
}

abstract final class CodeActionKind {
  static const quickFix = HierarchicalKind('quickfix');
  static const refactor = HierarchicalKind('refactor');
  static const refactorExtract = HierarchicalKind('refactor.extract');
  static const refactorInline = HierarchicalKind('refactor.inline');
  static const refactorMove = HierarchicalKind('refactor.move');
  static const refactorRewrite = HierarchicalKind('refactor.rewrite');
  static const notebook = HierarchicalKind('notebook');
  static const source = HierarchicalKind('source');
  static const sourceOrganizeImports = HierarchicalKind(
    'source.organizeImports',
  );
  static const sourceFixAll = HierarchicalKind('source.fixAll');
  static const surroundWith = HierarchicalKind('refactor.surround');
}

/// What ordering and grouping need to know about one code action.
abstract interface class CodeActionInfo {
  String? get kind;
  bool get isPreferred;
  bool get hasDiagnostics;
  bool get isDisabled;
}

int _codeActionsPreferredComparator(CodeActionInfo a, CodeActionInfo b) {
  if (a.isPreferred && !b.isPreferred) {
    return -1;
  } else if (!a.isPreferred && b.isPreferred) {
    return 1;
  } else {
    return 0;
  }
}

/// Actions fixing diagnostics first, preferred ones first within each part.
int codeActionsComparator(CodeActionInfo a, CodeActionInfo b) {
  if (a.hasDiagnostics) {
    return b.hasDiagnostics ? _codeActionsPreferredComparator(a, b) : -1;
  } else if (b.hasDiagnostics) {
    return 1;
  } else {
    return _codeActionsPreferredComparator(a, b); // both have no diagnostics
  }
}

/// A stable sort by [codeActionsComparator] (`ManagedCodeActionSet`).
List<T> sortCodeActions<T extends CodeActionInfo>(Iterable<T> actions) {
  final indexed = actions.indexed.toList()
    ..sort((a, b) {
      final order = codeActionsComparator(a.$2, b.$2);
      return order != 0 ? order : a.$1.compareTo(b.$1);
    });
  return [for (final (_, action) in indexed) action];
}

class CodeActionGroup {
  const CodeActionGroup(this.kind, this.title);

  final HierarchicalKind kind;
  final String title;
}

const CodeActionGroup uncategorizedCodeActionGroup = CodeActionGroup(
  HierarchicalKind.empty,
  'More Actions...',
);

const List<CodeActionGroup> codeActionGroups = [
  CodeActionGroup(CodeActionKind.quickFix, 'Quick Fix'),
  CodeActionGroup(CodeActionKind.refactorExtract, 'Extract'),
  CodeActionGroup(CodeActionKind.refactorInline, 'Inline'),
  CodeActionGroup(CodeActionKind.refactorRewrite, 'Rewrite'),
  CodeActionGroup(CodeActionKind.refactorMove, 'Move'),
  CodeActionGroup(CodeActionKind.surroundWith, 'Surround With'),
  CodeActionGroup(CodeActionKind.source, 'Source Action'),
  uncategorizedCodeActionGroup,
];

/// Upstream `toMenuItems` with headers: [actions] (already sorted) grouped
/// by kind in [codeActionGroups] order; empty groups are left out.
List<(CodeActionGroup, List<T>)> groupCodeActions<T extends CodeActionInfo>(
  List<T> actions,
) {
  final entries = [for (final group in codeActionGroups) (group, <T>[])];
  for (final action in actions) {
    final kind = action.kind != null
        ? HierarchicalKind(action.kind!)
        : HierarchicalKind.none;
    for (final (group, list) in entries) {
      if (group.kind.contains(kind)) {
        list.add(action);
        break;
      }
    }
  }
  return [
    for (final entry in entries)
      if (entry.$2.isNotEmpty) entry,
  ];
}
