import 'package:flutter/material.dart';

import 'agent_kernel.dart';
import 'claude_code/claude_code_kernel.dart';
import 'claude_code/claude_storage.dart';
import 'claude_code/process_transport.dart';

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
      start: startClaudeProcess,
      readHistory: ClaudeStorage.read,
      usageOffBy: claudeUsageOffBy,
    ),
    catalog: const ClaudeStorage(),
  );

  static List<KernelDescriptor> _all = [claudeCode];

  static List<KernelDescriptor> get all => _all;

  /// Replaces the kernels on offer, e.g. with mock ones under test.
  static void use(List<KernelDescriptor> kernels) => _all = kernels;
}
