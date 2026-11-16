import 'dart:async';

import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/widgets.dart';

import '../chat/panels/interaction_panel.dart' show PanelButton;
import '../ide/ide_button.dart';
import '../ide/ide_menu.dart';
import '../l10n/l10n.dart';
import '../settings/pages/settings_dropdown.dart';
import '../settings/pages/settings_widgets.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/editor_launcher.dart' show openExternal;
import 'bao_bash.dart';

/// [size] bytes, as a download's size reads: `13 MB`.
String _megabytes(int size) => '${(size / (1024 * 1024)).round()} MB';

/// Where BaoCode Bash's source is.
final _repository = Uri.parse('https://github.com/baocode-dev/bash-exe');

/// [shell]'s name in the list.
String windowsShellName(BuildContext context, WindowsShell shell) =>
    switch (shell) {
      WindowsShell.baoBash => context.l10n.baoBashRecommended,
      WindowsShell.gitBash => 'Git Bash',
      WindowsShell.cmd => 'cmd',
      WindowsShell.powershell => 'PowerShell',
      WindowsShell.custom => context.l10n.commandLineShellCustom,
    };

/// Settings → General → Command Line (Windows): the shell agents run
/// commands in, picked from a list (Git Bash where it is installed); under
/// it BaoCode Bash's version, download and updates when it is the one
/// picked, or the file of a custom one.
class CommandLineSettings extends StatefulWidget {
  const CommandLineSettings({super.key, required this.bash, this.open});

  final BaoBash bash;

  /// Opens a link; the browser when not given.
  final void Function(Uri url)? open;

  @override
  State<CommandLineSettings> createState() => _CommandLineSettingsState();
}

class _CommandLineSettingsState extends State<CommandLineSettings> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.bash.check());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.bash,
    builder: (context, _) {
      final bash = widget.bash;
      final shown = bash.shown;
      return SettingsCard(
        children: [
          _shellRow(context, bash, shown),
          if (shown == WindowsShell.baoBash) _baoBashRow(context, bash),
          if (shown == WindowsShell.custom)
            SettingsRow(
              label: context.l10n.commandLineCustomPath,
              description: context.l10n.commandLineCustomPathDescription,
              trailing: SettingsTextField(
                value: bash.customPath ?? '',
                hint: r'C:\path\to\bash.exe',
                semanticLabel: context.l10n.commandLineCustomPath,
                width: 260,
                onSubmitted: (path) => unawaited(bash.setCustomPath(path)),
              ),
            ),
        ],
      );
    },
  );

  Widget _shellRow(BuildContext context, BaoBash bash, WindowsShell shown) {
    final l10n = context.l10n;
    final inUse = bash.inUse;
    final name = windowsShellName(context, shown);
    return SettingsRow(
      label: l10n.commandLineShell,
      description: l10n.commandLineShellDescription,
      below: [
        SelectableText(
          inUse.shell == shown
              ? l10n.commandLineShellInUse(inUse.executable)
              : l10n.commandLineShellFallback(name, inUse.executable),
          style: SettingsText.path,
        ),
      ],
      trailing: SettingsDropdown(
        current: name,
        semanticLabel: '${l10n.commandLineShell}: $name',
        entries: () => [
          for (final shell in WindowsShell.values)
            if (shell != WindowsShell.gitBash || bash.gitBash != null)
              IdeMenuAction(
                windowsShellName(context, shell),
                checked: shell == shown,
                onSelected: () => unawaited(bash.choose(shell)),
              ),
        ],
      ),
    );
  }

  Widget _baoBashRow(BuildContext context, BaoBash bash) {
    final l10n = context.l10n;
    final installed = bash.installed;
    final latest = bash.latest;
    final progress = bash.progress;
    final error = bash.error;
    return SettingsRow(
      label: 'BaoCode Bash',
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
        _Link(
          label: l10n.baoBashSource,
          url: _repository,
          open: widget.open ?? (url) => unawaited(openExternal('$url')),
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
                onPressed: bash.busy ? null : () => unawaited(bash.install()),
              ),
            IdeButton(
              label: l10n.baoBashUninstall,
              secondary: true,
              onPressed: bash.busy ? null : () => unawaited(bash.uninstall()),
            ),
          ],
        ],
      ),
    );
  }
}

/// A link under a setting: `label` with the address, opened on a click.
class _Link extends StatelessWidget {
  const _Link({required this.label, required this.url, required this.open});

  final String label;
  final Uri url;
  final void Function(Uri url) open;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: () => open(url),
      child: Text.rich(
        TextSpan(
          text: '$label ',
          style: SettingsText.description,
          children: [
            TextSpan(
              text: '${url.host}${url.path}',
              style: TextStyle(color: themeColors['textLink.foreground']),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Over the composer, on Windows: BaoCode Bash recommended to whoever
/// runs commands in neither it nor Git Bash ([BaoBash.showsHint]).
/// Install and Use picks it and downloads it, the progress shown here;
/// Not Now puts it off for good (Settings → General still picks it).
class BaoBashHint extends StatelessWidget {
  const BaoBashHint({super.key, required this.bash});

  final BaoBash bash;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: bash,
    builder: (context, _) {
      if (!bash.showsHint) return const SizedBox.shrink();
      final l10n = context.l10n;
      final accent = AppColors.accent;
      final progress = bash.progress;
      final error = bash.error;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: .35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Codicons.terminal, size: 15, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.baoBashNoticeTitle,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 2),
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
                            ? themeColors['errorForeground']
                            : AppColors.textMuted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PanelButton(
                label: l10n.baoBashNoticeLater,
                onTap: bash.busy ? null : bash.dismissHint,
              ),
              const SizedBox(width: 6),
              PanelButton(
                label: l10n.baoBashHintInstall,
                primary: true,
                onTap: bash.busy
                    ? null
                    : () => unawaited(bash.choose(WindowsShell.baoBash)),
              ),
            ],
          ),
        ),
      );
    },
  );
}
