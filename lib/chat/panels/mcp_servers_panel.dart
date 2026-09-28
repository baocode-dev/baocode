import 'package:flutter/material.dart';

import '../../kernel/kernel_types.dart';
import '../../theme/cursor_theme.dart';
import '../widgets/hover_builder.dart';
import 'interaction_panel.dart';
import 'panel_card.dart';

/// Modal area, opened from the composer: the MCP servers the agent uses,
/// whether each is up, and what to do about one that is not.
class McpServersPanel extends StatelessWidget {
  const McpServersPanel({
    super.key,
    required this.servers,
    required this.onClose,
    required this.onRefresh,
    required this.onSetEnabled,
    required this.onReconnect,
    required this.onSignIn,
  });

  final List<McpServer> servers;
  final VoidCallback onClose;
  final VoidCallback onRefresh;
  final void Function(McpServer server, bool enabled) onSetEnabled;
  final ValueChanged<McpServer> onReconnect;
  final ValueChanged<McpServer> onSignIn;

  @override
  Widget build(BuildContext context) {
    final connected = servers
        .where((server) => server.status == McpServerStatus.connected)
        .length;
    return PanelCard(
      header: Row(
        children: [
          const Text(
            'MCP servers',
            style: TextStyle(
              color: CursorColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          if (servers.isNotEmpty)
            Text(
              '$connected of ${servers.length} connected',
              style: const TextStyle(
                color: CursorColors.textFaint,
                fontSize: 11,
              ),
            ),
          const Spacer(),
          _HeaderIcon(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onTap: onRefresh,
          ),
          const SizedBox(width: 8),
          _HeaderIcon(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            onTap: onClose,
          ),
        ],
      ),
      child: servers.isEmpty
          ? const Padding(
              padding: EdgeInsets.fromLTRB(4, 4, 4, 2),
              child: Text(
                'No MCP servers configured for this project.',
                style: TextStyle(color: CursorColors.textFaint, fontSize: 12),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final server in servers)
                  _ServerRow(
                    server: server,
                    onSetEnabled: (enabled) => onSetEnabled(server, enabled),
                    onReconnect: () => onReconnect(server),
                    onSignIn: () => onSignIn(server),
                  ),
              ],
            ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.server,
    required this.onSetEnabled,
    required this.onReconnect,
    required this.onSignIn,
  });

  final McpServer server;
  final ValueChanged<bool> onSetEnabled;
  final VoidCallback onReconnect;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (server.status) {
      McpServerStatus.connected => (CursorColors.added, 'Connected'),
      McpServerStatus.pending => (CursorColors.textMuted, 'Connecting…'),
      McpServerStatus.failed => (CursorColors.removed, 'Failed'),
      McpServerStatus.needsAuth => (const Color(0xFFE2C08D), 'Needs sign-in'),
      McpServerStatus.disabled => (CursorColors.textFaint, 'Disabled'),
    };
    final details = [
      ?server.scope,
      if (server.tools.isNotEmpty)
        '${server.tools.length} ${server.tools.length == 1 ? 'tool' : 'tools'}',
      if (server.version case final version?) 'v$version',
    ].join(' · ');
    final action = switch (server.status) {
      McpServerStatus.failed => PanelButton(
        label: 'Reconnect',
        onTap: onReconnect,
      ),
      McpServerStatus.needsAuth => PanelButton(
        label: 'Sign in',
        primary: true,
        onTap: onSignIn,
      ),
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 5, 0, 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        server.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CursorColors.text,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(label, style: TextStyle(color: color, fontSize: 11.5)),
                  ],
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    style: const TextStyle(
                      color: CursorColors.textFaint,
                      fontSize: 11.5,
                    ),
                  ),
                if (server.error case final error?
                    when server.status == McpServerStatus.failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      error,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CursorColors.textMuted,
                        fontFamily: CursorFonts.mono,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action],
          const SizedBox(width: 8),
          Tooltip(
            message: server.status == McpServerStatus.disabled
                ? 'Enable'
                : 'Disable',
            waitDuration: const Duration(milliseconds: 500),
            child: Transform.scale(
              scale: 0.7,
              child: Switch(
                value: server.status != McpServerStatus.disabled,
                onChanged: server.status == McpServerStatus.pending
                    ? null
                    : onSetEnabled,
                activeThumbColor: CursorColors.textPrimary,
                activeTrackColor: CursorColors.accent,
                inactiveThumbColor: CursorColors.textMuted,
                inactiveTrackColor: CursorColors.border,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: Icon(
            icon,
            size: 15,
            color: hovered ? CursorColors.text : CursorColors.textMuted,
          ),
        ),
      ),
    );
  }
}
