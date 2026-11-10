import 'package:flutter/widgets.dart';

import '../ide/ide_dialog.dart';
import '../l10n/l10n.dart';
import 'review/change_review.dart';
import 'rewind_files_setting.dart';

/// The most files named in the prompt; the rest are counted.
const _named = 8;

/// Whether the files the agent changed after a message go back as it is
/// sent again ([plan], what that would do): asked when there are some,
/// unless [RewindFilesSetting] says. Null when the user turned it down
/// (the message is still being edited).
Future<bool?> askRewindFiles(
  BuildContext context,
  Future<List<RewindFile>> Function() plan,
) async {
  final setting = RewindFilesSetting.current();
  final files = await plan();
  if (files.isEmpty) return false;
  switch (setting) {
    case RewindFilesSetting.revert:
      return true;
    case RewindFilesSetting.keep:
      return false;
    case RewindFilesSetting.ask:
  }
  if (!context.mounted) return null;
  final l10n = context.l10n;
  final result = await showIdeInputDialog(
    context,
    message: l10n.rewindFilesTitle,
    detail: rewindFilesDetail(l10n, files),
    buttons: [l10n.rewindFilesRevert, l10n.rewindFilesKeep],
    checkbox: l10n.rewindFilesRemember,
    type: IdeDialogType.question,
  );
  if (result == null || result.button < 0) return null;
  final revert = result.button == 0;
  if (result.checked) {
    RewindFilesSetting.write?.call(
      revert ? RewindFilesSetting.revert : RewindFilesSetting.keep,
    );
  }
  return revert;
}

/// What the prompt tells of [files]: those that go back, those changed
/// elsewhere since, and those that cannot.
String rewindFilesDetail(AppLocalizations l10n, List<RewindFile> files) {
  final undone = [
    for (final file in files)
      if (file.outcome != RewindOutcome.conflict) file,
  ];
  final conflicts = [
    for (final file in files)
      if (file.outcome == RewindOutcome.conflict) file,
  ];
  final merged = undone.where((file) => file.outcome == RewindOutcome.merge);
  List<String> named(List<RewindFile> files) => [
    for (final file in files.take(_named)) '  ${file.name}',
    if (files.length > _named)
      '  ${l10n.rewindFilesMore(files.length - _named)}',
  ];
  return [
    if (undone.isNotEmpty) ...[
      l10n.rewindFilesChanged(undone.length),
      ...named(undone),
      if (merged.isNotEmpty) l10n.rewindFilesMerged(merged.length),
      '',
    ],
    if (conflicts.isNotEmpty) ...[
      l10n.rewindFilesConflicts(conflicts.length),
      ...named(conflicts),
      '',
    ],
    l10n.rewindFilesCommands,
  ].join('\n');
}
