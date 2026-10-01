/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Checkout to… (`git.checkout`), which the status bar's branch runs: a
// quick pick of Create new branch…, Create new branch from… and Checkout
// detached…, then the branches, remote branches and tags, the last
// committed first, each with how long ago and its commit's author, hash and
// subject. Typing lists the matches first and the commands after them,
// which take the value as the new branch's name.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// extensions/git/src/commands.ts (`_checkout`, `createCheckoutItems`, the
// `RefItem`s and their processors, `_branch`, `promptForBranchName`,
// `sanitizeBranchName`).
//
// Deviations: the settings are their defaults (`git.checkoutType: all`,
// `git.showReferenceDetails`, `git.branchSortOrder: committerdate`, no
// `git.branchPrefix`, `git.branchValidationRegex`, random branch names or
// protected branches, no `git.pullBeforeCheckout`); a pick shows once the
// refs are read, where upstream shows it busy first; no remote source
// buttons (Open on GitHub); and a checkout that would overwrite local
// changes fails with Git's message, where upstream offers to stash,
// migrate or discard them.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/codicons.dart';
import '../ide_dates.dart';
import '../ide_input.dart';
import '../ide_quick_input.dart';
import 'git_model.dart';
import 'git_repository.dart';

/// `git.commitShortHashLength`.
const _shortCommitLength = 7;

/// Checkout to… on [git]: [show] opens its quick picks and input boxes in
/// the quick input. Completes when it is done; throws what Git reported.
Future<void> ideGitCheckout(
  IdeGitRepository git, {
  required ValueChanged<IdeQuickInputModel> show,
  required AppLocalizations l10n,
}) => _GitCheckout(git, show, l10n).checkout();

/// Upstream `sanitizeBranchName`: [name] with what Git does not allow in a
/// branch name (`..`, `~`, white space…) replaced by [whitespaceChar].
String ideSanitizeBranchName(String name, {String whitespaceChar = '-'}) =>
    name.isEmpty
    ? name
    : name
          .trim()
          .replaceFirst(RegExp(r'^-+'), '')
          .replaceAll(
            RegExp(
              r'^\.|\/\.|\.\.|~|\^|:|\/$|\.lock$|\.lock\/|\\|\*|\s|^\s*$|\.$|\[|\]$',
            ),
            whitespaceChar,
          );

/// A branch, remote branch or tag listed (upstream `RefItem`; a local
/// branch of Checkout to… is a `BranchItem`, its upstream's tracking in
/// its description).
class _RefItem extends IdeQuickPickItem {
  _RefItem(this.ref, AppLocalizations l10n, {bool branch = false})
    : super(
        label: ref.name,
        icon: Icon(switch (ref.kind) {
          IdeGitRefKind.remote => Codicons.cloud,
          IdeGitRefKind.tag => Codicons.tag,
          _ => Codicons.gitBranch,
        }),
        description: branch
            ? _branchDescription(ref, l10n)
            : _description(ref, l10n),
        detail: switch (ref.details) {
          final details? =>
            '${details.author}\$(circle-small-filled)${_short(ref)}'
                '\$(circle-small-filled)${details.subject}',
          null => null,
        },
      );

  final IdeGitRef ref;

  static String _short(IdeGitRef ref) {
    final commit = ref.commit ?? '';
    return commit.length > _shortCommitLength
        ? commit.substring(0, _shortCommitLength)
        : commit;
  }

  static String _ago(DateTime date, AppLocalizations l10n) =>
      ideFromNow(date, ago: true, fullWords: true, l10n: l10n);

  static String _description(IdeGitRef ref, AppLocalizations l10n) {
    if (ref.details case final details?) return _ago(details.date, l10n);
    return switch (ref.kind) {
      IdeGitRefKind.remote => l10n.gitRemoteBranchAt(_short(ref)),
      IdeGitRefKind.tag => l10n.gitTagAt(_short(ref)),
      _ => _short(ref),
    };
  }

  static String _branchDescription(IdeGitRef ref, AppLocalizations l10n) {
    final description = [
      if (ref.ahead != null && ref.behind != null)
        '${ref.behind}↓ ${ref.ahead}↑',
      if (ref.details case final details?) _ago(details.date, l10n),
    ];
    return description.isEmpty
        ? _short(ref)
        : description.join(r'$(circle-small-filled)');
  }
}

class _GitCheckout {
  _GitCheckout(this.git, this.show, this.l10n);

  final IdeGitRepository git;
  final ValueChanged<IdeQuickInputModel> show;
  final AppLocalizations l10n;

  /// Shows the pick [build] makes with the callbacks given, and completes
  /// with the item accepted (null: none) once it hid, as upstream's
  /// promise of `onDidAccept` and `onDidHide` does: what comes next shows
  /// after the focus went back.
  Future<IdeQuickPickItem?> _pick(
    IdeQuickPick Function(
      ValueChanged<IdeQuickPickItem?> onDidAccept,
      VoidCallback onDidHide,
    )
    build,
  ) {
    final hidden = Completer<IdeQuickPickItem?>();
    IdeQuickPickItem? accepted;
    show(
      build((item) => accepted = item, () {
        if (!hidden.isCompleted) hidden.complete(accepted);
      }),
    );
    return hidden.future;
  }

  /// [_pick] for an input box: the value accepted, else null.
  Future<String?> _input({
    required String placeholder,
    required String prompt,
    IdeInputValidation? Function(String value)? validate,
  }) {
    final hidden = Completer<String?>();
    String? accepted;
    show(
      IdeQuickInputBox(
        placeholder: placeholder,
        prompt: prompt,
        validate: validate,
        onDidAccept: (value) => accepted = value,
        onDidHide: () {
          if (!hidden.isCompleted) hidden.complete(accepted);
        },
      ),
    );
    return hidden.future;
  }

  /// Upstream `_checkout`: the branch commands (not [detached]) and the
  /// refs to check out.
  Future<void> checkout({bool detached = false}) async {
    final createBranch = IdeQuickPickItem(
      label: l10n.gitCreateBranch,
      icon: const Icon(Codicons.plus),
      alwaysShow: true,
    );
    final createBranchFrom = IdeQuickPickItem(
      label: l10n.gitCreateBranchFrom,
      icon: const Icon(Codicons.plus),
      alwaysShow: true,
    );
    final checkoutDetached = IdeQuickPickItem(
      label: l10n.gitCheckoutDetached,
      icon: const Icon(Codicons.debugDisconnect),
      alwaysShow: true,
    );
    final commands = [
      if (!detached) ...[createBranch, createBranchFrom, checkoutDetached],
    ];
    final picks = _checkoutItems(await git.refs(), detached: detached);
    var value = '';
    final choice = await _pick(
      (onDidAccept, onDidHide) => IdeQuickPick(
        placeholder: detached
            ? l10n.gitSelectBranchDetached
            : l10n.gitSelectBranchOrTag,
        sortByLabel: false,
        itemsFor: (text) => switch (text) {
          '' => [...commands, ...picks],
          _ when commands.isEmpty => picks,
          _ when picks.isEmpty => commands,
          _ => [...picks, const IdeQuickPickSeparator(), ...commands],
        },
        onDidChangeValue: (text) => value = text,
        onDidAccept: onDidAccept,
        onDidHide: onDidHide,
      ),
    );
    if (choice == null) return;
    if (identical(choice, createBranch)) {
      await _branch(value);
    } else if (identical(choice, createBranchFrom)) {
      await _branch(value, from: true);
    } else if (identical(choice, checkoutDetached)) {
      await checkout(detached: true);
    } else if (choice case _RefItem(:final ref)) {
      await _run(ref, detached: detached);
    }
  }

  /// `createCheckoutItems`: the local branches, the remote branches but
  /// `origin/HEAD` (but when [detached]), and the tags (not when
  /// [detached]), each kind under its separator.
  List<IdeQuickPickEntry> _checkoutItems(
    List<IdeGitRef> refs, {
    required bool detached,
  }) {
    List<IdeQuickPickEntry> group(
      IdeGitRefKind kind,
      String separator, {
      bool branch = false,
    }) {
      final items = [
        for (final ref in refs)
          if (ref.kind == kind && (detached || ref.name != 'origin/HEAD'))
            _RefItem(ref, l10n, branch: branch),
      ];
      return items.isEmpty
          ? const []
          : [IdeQuickPickSeparator(separator), ...items];
    }

    return [
      ...group(IdeGitRefKind.branch, l10n.gitBranches, branch: true),
      ...group(IdeGitRefKind.remote, l10n.gitRemoteBranches),
      if (!detached) ...group(IdeGitRefKind.tag, l10n.gitTags),
    ];
  }

  /// `CheckoutItem.run`, `CheckoutRemoteHeadItem.run` and
  /// `CheckoutTagItem.run`: a remote branch is checked out as the local
  /// branch tracking it, made if there is none.
  Future<void> _run(IdeGitRef ref, {required bool detached}) async {
    if (detached) {
      await git.checkout(ref.commit ?? ref.name, detached: true);
    } else if (ref.kind == IdeGitRefKind.remote) {
      final branches = await git.trackingBranches(ref.name);
      if (branches.isNotEmpty) {
        await git.checkout(branches.first);
      } else {
        await git.checkoutTracking(ref.name);
      }
    } else {
      await git.checkout(ref.name);
    }
  }

  /// Upstream `_branch`: a new branch at HEAD or, [from], at the ref
  /// picked, named [defaultName] or as typed.
  Future<void> _branch(String defaultName, {bool from = false}) async {
    var target = 'HEAD';
    if (from) {
      final refs = await git.refs();
      final head = await git.service.revParse('HEAD');
      final headItem = IdeQuickPickItem(
        label: 'HEAD',
        description: head == null || head.length <= _shortCommitLength
            ? head ?? ''
            : head.substring(0, _shortCommitLength),
        alwaysShow: true,
      );
      // `RefItemsProcessor` with its plain `RefProcessor`s.
      List<IdeQuickPickEntry> group(IdeGitRefKind kind, String separator) {
        final items = [
          for (final ref in refs)
            if (ref.kind == kind && ref.name != 'origin/HEAD')
              _RefItem(ref, l10n),
        ];
        return items.isEmpty
            ? const []
            : [IdeQuickPickSeparator(separator), ...items];
      }

      final choice = await _pick(
        (onDidAccept, onDidHide) => IdeQuickPick(
          placeholder: l10n.gitSelectRefToBranchFrom,
          items: [
            headItem,
            ...group(IdeGitRefKind.branch, l10n.gitBranches),
            ...group(IdeGitRefKind.remote, l10n.gitRemoteBranches),
            ...group(IdeGitRefKind.tag, l10n.gitTags),
          ],
          onDidAccept: onDidAccept,
          onDidHide: onDidHide,
        ),
      );
      if (choice == null) return;
      if (choice case _RefItem(:final ref)) target = ref.name;
    }
    final name = await _promptForBranchName(defaultName);
    if (name.isEmpty) return;
    await git.branch(name, ref: target);
  }

  /// Upstream `promptForBranchName`: [defaultName] when there is one, else
  /// the name typed, saying when it is taken or would change; sanitized.
  Future<String> _promptForBranchName(String defaultName) async {
    if (defaultName.isNotEmpty) return ideSanitizeBranchName(defaultName);
    final branches = {
      for (final ref in await git.refs())
        if (ref.kind == IdeGitRefKind.branch) ref.name,
    };
    final name = await _input(
      placeholder: l10n.gitBranchName,
      prompt: l10n.gitProvideBranchName,
      validate: (name) {
        final sanitized = ideSanitizeBranchName(name);
        if (branches.contains(sanitized)) {
          return IdeInputValidation(l10n.gitBranchExists(sanitized));
        }
        // `git.branchValidationRegex` is empty: every name matches.
        return name == sanitized
            ? null
            : IdeInputValidation(
                l10n.gitNewBranchWillBe(sanitized),
                IdeValidationSeverity.info,
              );
      },
    );
    return ideSanitizeBranchName(name ?? '');
  }
}
