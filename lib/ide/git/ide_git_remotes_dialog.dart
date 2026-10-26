// JetBrains IDEs' Manage Remotes: a repository's remotes and their URLs,
// one added, edited (renamed, its URL changed) or removed.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../ide_button.dart';
import '../ide_dialog.dart';
import '../ide_hover.dart';
import '../ide_list.dart';
import '../ide_notifications.dart';
import 'git_repository.dart';

Future<void> showIdeGitRemotesDialog(
  BuildContext context, {
  required IdeGitRepository git,
  required IdeNotifications notifications,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) =>
      IdeGitRemotesDialog(git: git, notifications: notifications),
);

class IdeGitRemotesDialog extends StatefulWidget {
  const IdeGitRemotesDialog({
    super.key,
    required this.git,
    required this.notifications,
  });

  final IdeGitRepository git;
  final IdeNotifications notifications;

  @override
  State<IdeGitRemotesDialog> createState() => _IdeGitRemotesDialogState();
}

class _IdeGitRemotesDialogState extends State<IdeGitRemotesDialog> {
  late Future<Map<String, String>> _remotes = _read();
  String? _selected;

  Future<Map<String, String>> _read() => widget.git.service
      .remoteUrls()
      .catchError((Object _) => const <String, String>{});

  Future<void> _run(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      widget.notifications.notify(IdeSeverity.error, '$error');
    }
  }

  /// The remotes read again, [selected] the one selected.
  void _reread(String? selected) {
    if (!mounted) return;
    setState(() {
      _remotes = _read();
      _selected = selected;
    });
  }

  /// Asks for a remote's name and URL: [name]'s, to edit it; a new one's.
  Future<(String, String)?> _ask({String? name, String url = ''}) async {
    final l10n = context.l10n;
    // The first one, origin as Git names it.
    final first = (await _remotes).isEmpty;
    if (!mounted) return null;
    final result = await showIdeInputDialog(
      context,
      message: name == null ? l10n.gitRemoteAdd : l10n.gitRemoteEdit,
      buttons: [l10n.commonOk],
      inputs: [
        IdeDialogInput(
          placeholder: l10n.gitRemoteName,
          value: name ?? (first ? 'origin' : ''),
        ),
        IdeDialogInput(placeholder: l10n.gitRemoteUrl, value: url),
      ],
      type: IdeDialogType.question,
    );
    if (result == null || result.button != 0) return null;
    final newName = result.values[0].trim();
    final newUrl = result.values[1].trim();
    if (newName.isEmpty || newUrl.isEmpty) return null;
    return (newName, newUrl);
  }

  Future<void> _add() async {
    final answer = await _ask();
    if (answer == null) return;
    final (name, url) = answer;
    await _run(() => widget.git.addRemote(name, url));
    _reread(name);
  }

  Future<void> _edit(String name, String url) async {
    final answer = await _ask(name: name, url: url);
    if (answer == null) return;
    final (to, newUrl) = answer;
    await _run(
      () => widget.git.editRemote(
        name,
        to: to,
        url: newUrl == url ? null : newUrl,
      ),
    );
    _reread(to);
  }

  Future<void> _remove(String name) async {
    final l10n = context.l10n;
    final answer = await showIdeDialog(
      context,
      message: l10n.gitRemoteRemoveConfirm(name),
      detail: l10n.gitRemoteRemoveDetail,
      buttons: [l10n.gitRemoteRemove],
    );
    if (answer != 0) return;
    await _run(() => widget.git.removeRemote(name));
    _reread(null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final border = colors.get('widget.border') ?? Colors.transparent;
    final size = MediaQuery.sizeOf(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Align(
          alignment: const Alignment(0, -0.4),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: math.min(620.0, size.width * .9),
              height: math.min(360.0, size.height * .8),
              decoration: BoxDecoration(
                color: colors['editorWidget.background'],
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Color(0x26000000), blurRadius: 20),
                ],
              ),
              child: DefaultTextStyle(
                style: TextStyle(
                  fontSize: 13,
                  color: colors['editorWidget.foreground'],
                ),
                child: FutureBuilder<Map<String, String>>(
                  future: _remotes,
                  builder: (context, snapshot) {
                    final remotes = snapshot.data ?? const {};
                    final selected = remotes.containsKey(_selected)
                        ? _selected
                        : null;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.gitRemotesTitle,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IdeActionButton(
                                icon: Codicons.close,
                                tooltip: l10n.dialogCloseDialog,
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              IdeActionButton(
                                icon: Codicons.add,
                                tooltip: l10n.gitRemoteAdd,
                                onPressed: () => unawaited(_add()),
                              ),
                              IdeActionButton(
                                icon: Codicons.edit,
                                tooltip: l10n.gitRemoteEdit,
                                onPressed: selected == null
                                    ? null
                                    : () => unawaited(
                                        _edit(selected, remotes[selected]!),
                                      ),
                              ),
                              IdeActionButton(
                                icon: Codicons.remove,
                                tooltip: l10n.gitRemoteRemove,
                                onPressed: selected == null
                                    ? null
                                    : () => unawaited(_remove(selected)),
                              ),
                            ],
                          ),
                        ),
                        Container(height: 1, color: border),
                        Expanded(
                          child: remotes.isEmpty
                              ? Center(
                                  child: Text(
                                    l10n.gitRemotesNone,
                                    style: TextStyle(
                                      color: IdeListColors.description,
                                    ),
                                  ),
                                )
                              : ListView(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  children: [
                                    for (final MapEntry(key: name, value: url)
                                        in remotes.entries)
                                      IdeListRow(
                                        key: ValueKey('remote:$name'),
                                        selected: name == selected,
                                        onTap: () =>
                                            setState(() => _selected = name),
                                        onDoubleTap: () =>
                                            unawaited(_edit(name, url)),
                                        builder: (context, hovered) => Row(
                                          children: [
                                            const SizedBox(width: 12),
                                            SizedBox(
                                              width: 120,
                                              child: Text(
                                                name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                url,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color:
                                                      IdeListColors.description,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                        Container(height: 1, color: border),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IdeButton(
                                label: l10n.commonClose,
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
