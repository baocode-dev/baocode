import '../../kernel/agent_kernel.dart';
import '../../kernel/kernel_types.dart';
import '../../l10n/l10n.dart';

/// [option], one of [kernel]'s approvals, in the app's language: kernels
/// name them in English. Those not known here stay as they are, and the
/// modes (Agent, Ask, Plan) are named as they are in every language.
KernelOption localizedKernelOption(
  AppLocalizations l10n,
  String kernel,
  KernelChoiceKind kind,
  KernelOption option,
) {
  final text = switch ((kernel, kind, option.id)) {
    // Antigravity's auto asks before what cannot be undone, not blocks it.
    ('antigravity', KernelChoiceKind.permission, 'auto') => (
      l10n.composerApprovalAuto,
      l10n.composerApprovalAgyAutoDetail,
    ),
    // Its others are as Claude Code's.
    ('claude-code' || 'antigravity', KernelChoiceKind.permission, 'default') =>
      (l10n.composerApprovalDefault, l10n.composerApprovalDefaultDetail),
    (
      'claude-code' || 'antigravity',
      KernelChoiceKind.permission,
      'acceptEdits',
    ) =>
      (
        l10n.composerApprovalAcceptEdits,
        l10n.composerApprovalAcceptEditsDetail,
      ),
    ('claude-code', KernelChoiceKind.permission, 'auto') => (
      l10n.composerApprovalAuto,
      l10n.composerApprovalAutoDetail,
    ),
    ('claude-code', KernelChoiceKind.permission, 'dontAsk') => (
      l10n.composerApprovalDontAsk,
      l10n.composerApprovalDontAskDetail,
    ),
    (
      'claude-code' || 'antigravity',
      KernelChoiceKind.permission,
      'bypassPermissions',
    ) =>
      (l10n.composerApprovalFullAccess, l10n.composerApprovalFullAccessDetail),
    _ => null,
  };
  if (text == null) return option;
  return KernelOption(
    option.id,
    text.$1,
    option.icon,
    text.$2,
    caution: option.caution,
    iconBuilder: option.iconBuilder,
  );
}
