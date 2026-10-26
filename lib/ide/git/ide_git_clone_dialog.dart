// JetBrains IDEs' Get from Version Control: a repository's URL and the
// folder it goes in (named after it until changed, under the folder last
// cloned into), then Clone; what went wrong shown in the dialog, the
// folder opened once it is there.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../ide_button.dart';
import '../ide_hover.dart';
import '../ide_input.dart';
import '../ide_list.dart';
import '../ide_spinning.dart';
import 'git_model.dart';
import 'git_service.dart';

/// Clones a repository, asked for; the folder it went in, or null.
/// [parent] is where it goes at first; [pickDirectory], Browse….
Future<String?> showIdeGitCloneDialog(
  BuildContext context, {
  required String parent,
  Future<String?> Function()? pickDirectory,
  IdeGitRunner? runner,
}) => showGeneralDialog<String>(
  context: context,
  barrierDismissible: false,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => IdeGitCloneDialog(
    parent: parent,
    pickDirectory: pickDirectory,
    runner: runner,
  ),
);

class IdeGitCloneDialog extends StatefulWidget {
  const IdeGitCloneDialog({
    super.key,
    required this.parent,
    this.pickDirectory,
    this.runner,
  });

  final String parent;
  final Future<String?> Function()? pickDirectory;
  final IdeGitRunner? runner;

  @override
  State<IdeGitCloneDialog> createState() => _IdeGitCloneDialogState();
}

class _IdeGitCloneDialogState extends State<IdeGitCloneDialog> {
  final TextEditingController _url = TextEditingController();
  late final TextEditingController _directory = TextEditingController(
    text: widget.parent,
  );

  /// The folder named after the URL, until the user names it.
  bool _named = false;
  bool _cloning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url.addListener(_urlChanged);
    _directory.addListener(_directoryChanged);
  }

  @override
  void dispose() {
    _url.dispose();
    _directory.dispose();
    super.dispose();
  }

  /// Where the folder named after the URL goes.
  late String _parent = widget.parent;

  /// The directory being set here, not typed.
  bool _setting = false;

  void _setDirectory() {
    final folder = ideGitCloneFolder(_url.text);
    _setting = true;
    _directory.text = folder.isEmpty ? _parent : p.join(_parent, folder);
    _setting = false;
  }

  void _urlChanged() {
    setState(() => _error = null);
    if (!_named) _setDirectory();
  }

  void _directoryChanged() {
    if (!_setting) _named = true;
    setState(() => _error = null);
  }

  Future<void> _browse() async {
    final picked = await widget.pickDirectory?.call();
    if (picked == null || !mounted) return;
    _parent = picked;
    _named = false;
    _setDirectory();
  }

  Future<void> _clone() async {
    final url = _url.text.trim();
    final directory = _directory.text.trim();
    if (url.isEmpty || directory.isEmpty || _cloning) return;
    setState(() {
      _cloning = true;
      _error = null;
    });
    try {
      await IdeGitService.clone(url, directory, runner: widget.runner);
      if (mounted) Navigator.of(context).pop(directory);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _cloning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final border = colors.get('widget.border') ?? Colors.transparent;
    final width = math.min(560.0, MediaQuery.sizeOf(context).width * .9);
    final ready =
        !_cloning &&
        _url.text.trim().isNotEmpty &&
        _directory.text.trim().isNotEmpty;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 10),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_cloning) Navigator.of(context).pop();
        },
      },
      child: Align(
        alignment: const Alignment(0, -0.4),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: width,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.gitCloneTitle,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IdeActionButton(
                        icon: Codicons.close,
                        tooltip: l10n.dialogCloseDialog,
                        onPressed: _cloning
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  label(l10n.gitCloneUrl),
                  IdeInputBox(
                    controller: _url,
                    autofocus: true,
                    placeholder: 'https://github.com/owner/repository.git',
                    semanticsLabel: l10n.gitCloneUrl,
                    onSubmitted: (_) => unawaited(_clone()),
                  ),
                  label(l10n.gitCloneDirectory),
                  Row(
                    children: [
                      Expanded(
                        child: IdeInputBox(
                          controller: _directory,
                          semanticsLabel: l10n.gitCloneDirectory,
                          onSubmitted: (_) => unawaited(_clone()),
                        ),
                      ),
                      if (widget.pickDirectory != null) ...[
                        const SizedBox(width: 6),
                        IdeButton(
                          label: l10n.gitCloneBrowse,
                          secondary: true,
                          onPressed: _cloning
                              ? null
                              : () => unawaited(_browse()),
                        ),
                      ],
                    ],
                  ),
                  if (_error case final error?)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        error,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors['errorForeground'],
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (_cloning) ...[
                        IdeSpinning(
                          Icon(
                            Codicons.loading,
                            size: 14,
                            color: IdeListColors.description,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.gitCloning,
                          style: TextStyle(
                            fontSize: 12,
                            color: IdeListColors.description,
                          ),
                        ),
                      ],
                      const Spacer(),
                      IdeButton(
                        label: l10n.gitCloneButton,
                        onPressed: ready ? () => unawaited(_clone()) : null,
                      ),
                      const SizedBox(width: 8),
                      IdeButton(
                        label: l10n.commonCancel,
                        secondary: true,
                        onPressed: _cloning
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
