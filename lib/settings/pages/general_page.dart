import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_menu.dart';
import '../../kernel/commit_attribution.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../user_settings.dart';
import 'settings_dropdown.dart';

/// Settings → General: who the commits and pull requests agents write
/// credit (`chat.commitAttribution` in settings.json). A choice is written
/// at once; the default is not written.
class GeneralSettingsPage extends StatelessWidget {
  const GeneralSettingsPage({super.key, this.settings});

  /// settings.json; none under test, where choices are not kept.
  final UserSettings? settings;

  static String attributionName(BuildContext context, CommitAttribution value) {
    final l10n = context.l10n;
    return switch (value) {
      CommitAttribution.baocode => 'BaoCode',
      CommitAttribution.agent => l10n.generalSettingsAttributionAgent,
      CommitAttribution.none => l10n.generalSettingsAttributionNone,
    };
  }

  static String _attributionDetail(
    BuildContext context,
    CommitAttribution value,
  ) {
    final l10n = context.l10n;
    return switch (value) {
      CommitAttribution.baocode => CommitAttribution.baoCodeCommit,
      CommitAttribution.agent => l10n.generalSettingsAttributionAgentDetail,
      CommitAttribution.none => l10n.generalSettingsAttributionNoneDetail,
    };
  }

  void _select(CommitAttribution value) {
    final settings = this.settings;
    if (settings == null) return;
    unawaited(
      settings
          .update(
            CommitAttribution.settingKey,
            value == CommitAttribution.fallback ? null : value.name,
          )
          .catchError((Object error) {
            // A settings file that does not parse is left as it is; its
            // error is shown.
            debugPrint('${CommitAttribution.settingKey} not kept: $error');
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = this.settings;
    return ListenableBuilder(
      listenable: settings ?? Listenable.merge(const []),
      builder: (context, _) {
        final current = CommitAttribution.parse(
          settings?[CommitAttribution.settingKey],
        );
        final name = attributionName(context, current);
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          children: [
            Text(
              l10n.generalSettingsTitle,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.generalSettingsCommitAttribution,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.generalSettingsCommitAttributionDescription,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SettingsDropdown(
                current: name,
                semanticLabel: l10n.generalSettingsCommitAttributionLabel(name),
                entries: () => [
                  for (final value in CommitAttribution.values)
                    IdeMenuAction(
                      attributionName(context, value),
                      checked: value == current,
                      onSelected: () => _select(value),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _attributionDetail(context, current),
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        );
      },
    );
  }
}
