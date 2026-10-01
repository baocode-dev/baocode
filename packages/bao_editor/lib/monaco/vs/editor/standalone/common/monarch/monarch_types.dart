// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
// Ported from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/editor/standalone/common/monarch/monarchTypes.ts.

/// A Monarch language definition, including its user-defined attributes.
///
/// Dart adaptation: upstream's structural JSON interfaces are maps and its
/// heterogeneous tuple/union types are lists and [Object]. This preserves the
/// original grammar notation; [compile] (in monarch_compile.dart) validates it.
/// A pattern is a [String] or [RegExp]. An action is a string, an expanded action
/// map, or a list of actions. A rule is `[pattern, action]`,
/// `[pattern, action, nextState]`, or an expanded rule map.
///
/// Standard keys: `tokenizer`, `ignoreCase`, `unicode`, `defaultToken`,
/// `brackets`, `start`, `tokenPostfix`, `includeLF`. Other keys may be referenced
/// with `@attribute` in patterns and cases, or `$@attribute` in substitutions.
/// Brackets accept `{open, close, token}` maps and `[open, close, token]` lists.
/// No upstream declarations are omitted; aliases cannot enforce TypeScript's
/// structural union/tuple constraints, so these are checked by the compiler.
typedef IMonarchLanguage = Map<String, Object?>;

typedef IShortMonarchLanguageRule1 = List<Object?>;
typedef IShortMonarchLanguageRule2 = List<Object?>;

/// Keys: `regex` / `action`, or `include`. Object rules may also have `name`.
typedef IExpandedMonarchLanguageRule = Map<String, Object?>;
typedef IMonarchLanguageRule = Object;

typedef IShortMonarchLanguageAction = String;

/// Keys: `group`, `cases`, `token`, `next`, `switchTo`, `goBack`, `bracket`,
/// `nextEmbedded`, `log`. As in the pinned compiler, action groups are written
/// as lists; a map containing only `group` is not accepted by compileAction.
typedef IExpandedMonarchLanguageAction = Map<String, Object?>;
typedef IMonarchLanguageAction = Object;

/// Keys: `open`, `close`, `token` (all strings).
typedef IMonarchLanguageBracket = Map<String, Object?>;
