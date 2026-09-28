import 'package:flutter/material.dart';

import '../agent_kernel.dart';
import '../claude_code/claude_code_kernel.dart';
import '../claude_code/mock_claude_code_transport.dart';
import '../codex/codex_kernel.dart';
import '../codex/mock_codex_transport.dart';

/// Kernels over scripted transports: the real adapters, fed recorded
/// protocol, for tests and demos. Not offered in the app.
abstract final class MockKernels {
  static final KernelDescriptor claudeCode = KernelDescriptor(
    id: 'claude-code',
    label: 'Claude Code',
    icon: Icons.auto_awesome_rounded,
    description: 'Anthropic’s coding agent',
    create: (context) => ClaudeCodeKernel(
      claudeCode,
      context,
      start: MockClaudeCodeTransport.start,
    ),
  );

  static final KernelDescriptor codex = KernelDescriptor(
    id: 'codex',
    label: 'Codex',
    icon: Icons.data_object_rounded,
    description: 'OpenAI’s coding agent',
    create: (_) => CodexKernel(codex, MockCodexTransport()),
  );

  static final List<KernelDescriptor> all = [claudeCode, codex];
}
