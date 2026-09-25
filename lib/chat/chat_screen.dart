import 'package:flutter/material.dart';

import '../theme/cursor_theme.dart';
import 'chat_history_view.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, this.title = 'Optimize virtual list scrolling'});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Transparent Flutter-owned title bar under the native traffic lights.
          Container(
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: CursorColors.border)),
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: CursorColors.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Expanded(child: ChatHistoryView()),
        ],
      ),
    );
  }
}
