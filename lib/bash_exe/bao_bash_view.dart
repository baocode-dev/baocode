import 'dart:async';

import 'package:flutter/widgets.dart';

import '../ide/ide_button.dart';
import '../kernel/claude_code/claude_core_setting.dart';
import '../l10n/l10n.dart';
import '../settings/pages/settings_widgets.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'bao_bash.dart';

/// [size] bytes, as a download's size reads: `13 MB`.
String _megabytes(int size) => '${(size / (1024 * 1024)).round()} MB';

/// Settings → General → Command Line: BaoCode Bash, whether and which is
/// installed, and the buttons to install, update or remove it.
class BaoBashSetting extends StatefulWidget {
  const BaoBashSetting({super.key, required this.bash});

  final BaoBash bash;

  @override
  State<BaoBashSetting> createState() => _BaoBashSettingState();
}

class _BaoBashSettingState extends State<BaoBashSetting> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.bash.check());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bash = widget.bash;
    return ListenableBuilder(
      listenable: bash,
      builder: (context, _) {
        final installed = bash.installed;
        final latest = bash.latest;
        final progress = bash.progress;
        final error = bash.error;
        return SettingsRow(
          label: installed == null ? l10n.baoBashRecommended : 'BaoCode Bash',
          description: l10n.baoBashDescription,
          below: [
            Text(switch ((installed, progress)) {
              (_, final progress?) => l10n.baoBashDownloading(
                (progress * 100).round(),
              ),
              (final installed?, _) when bash.updateAvailable =>
                '${l10n.baoBashInstalled(installed.version)} '
                    '${l10n.baoBashUpdateAvailable(latest!.version)}',
              (final installed?, _) => l10n.baoBashInstalled(installed.version),
              (null, _) => l10n.baoBashNotInstalled,
            }, style: SettingsText.description),
            if (error != null)
              Text(
                l10n.baoBashFailed(error),
                style: SettingsText.description.copyWith(
                  color: themeColors['errorForeground'],
                ),
              ),
          ],
          trailing: SettingsButtons(
            children: [
              if (installed == null)
                IdeButton(
                  label: switch (latest) {
                    final latest? => l10n.baoBashInstallSize(
                      _megabytes(latest.size),
                    ),
                    null => l10n.baoBashInstall,
                  },
                  onPressed: bash.busy ? null : () => unawaited(bash.install()),
                )
              else ...[
                if (bash.updateAvailable)
                  IdeButton(
                    label: l10n.baoBashUpdate,
                    onPressed: bash.busy
                        ? null
                        : () => unawaited(bash.install()),
                  ),
                IdeButton(
                  label: l10n.baoBashUninstall,
                  secondary: true,
                  onPressed: bash.busy
                      ? null
                      : () => unawaited(bash.uninstall()),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Above every page of the settings dialog: BaoCode Bash recommended, as
/// [BaoBash.showsNotice] says, to those whose agents would run it (the
/// built-in core's: Claude Code's CLI is not given it yet). Install, or
/// Not Now for good; the Command Line setting stays.
class BaoBashNotice extends StatelessWidget {
  const BaoBashNotice({super.key, required this.bash, this.core});

  final BaoBash bash;

  /// The core new sessions run on; the setting's by default.
  final ClaudeCore Function()? core;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: bash,
    builder: (context, _) {
      if (!bash.showsNotice ||
          (core ?? ClaudeCore.current)() != ClaudeCore.builtin) {
        return const SizedBox.shrink();
      }
      final l10n = context.l10n;
      final colors = themeColors;
      final progress = bash.progress;
      final error = bash.error;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          decoration: BoxDecoration(
            color: colors['inputValidation.infoBackground'],
            border: Border.all(color: colors['inputValidation.infoBorder']),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                Codicons.terminal,
                size: 14,
                color: colors['editorInfo.foreground'],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.baoBashNoticeTitle,
                      style: TextStyle(
                        color: colors['foreground'],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      switch ((progress, error)) {
                        (final progress?, _) => l10n.baoBashDownloading(
                          (progress * 100).round(),
                        ),
                        (null, final error?) => l10n.baoBashFailed(error),
                        _ => l10n.baoBashNoticeBody,
                      },
                      style: TextStyle(
                        color: error != null && progress == null
                            ? colors['errorForeground']
                            : colors['descriptionForeground'],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IdeButton(
                label: l10n.baoBashNoticeLater,
                secondary: true,
                onPressed: bash.busy ? null : bash.dismissNotice,
              ),
              const SizedBox(width: 6),
              IdeButton(
                label: l10n.baoBashInstall,
                onPressed: bash.busy ? null : () => unawaited(bash.install()),
              ),
            ],
          ),
        ),
      );
    },
  );
}
