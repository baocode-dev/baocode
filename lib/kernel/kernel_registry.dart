import 'package:flutter/material.dart';

import '../icons/kernel_badge.dart';
import '../remote/remote_claude.dart';
import 'agent_kernel.dart';
import 'antigravity/antigravity_catalog.dart';
import 'antigravity/antigravity_kernel.dart';
import 'claude_code/claude_code_kernel.dart';

/// The kernels the user can pick from. Another kernel is an adapter and a
/// line here.
abstract final class KernelRegistry {
  static final KernelDescriptor claudeCode = KernelDescriptor(
    id: 'claude-code',
    label: 'Claude Code',
    icon: Icons.auto_awesome_rounded,
    description: 'Anthropic’s coding agent',
    create: (context) => ClaudeCodeKernel(
      claudeCode,
      context,
      // On the project's host: this machine, or a remote one's.
      start: startClaude,
      readHistory: readClaudeHistory,
      readHistoryPage: readClaudeHistoryPage,
      readGoal: readClaudeGoal,
      forkSession: forkClaudeSession,
      usageOffBy: () => claudeUsageOffByAt(context.cwd),
      rejectTooOld: rejectTooOldClaude,
    ),
    catalog: const ClaudeCatalog(),
  );

  /// Google's Antigravity CLI (`agy`), over ACP: this machine's projects
  /// alone.
  static final KernelDescriptor antigravity = KernelDescriptor(
    id: 'antigravity',
    label: 'Antigravity',
    icon: Icons.rocket_launch_outlined,
    description: 'Google’s coding agent',
    create: (context) => AntigravityKernel(antigravity, context),
    catalog: const AntigravityCatalog(),
    iconBuilder: (size) => AntigravityBadge(size: size),
  );

  static List<KernelDescriptor> _all = [claudeCode, antigravity];

  static List<KernelDescriptor> get all => _all;

  /// Replaces the kernels on offer, e.g. with mock ones under test.
  static void use(List<KernelDescriptor> kernels) => _all = kernels;
}
