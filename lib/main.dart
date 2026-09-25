import 'package:flutter/material.dart';

import 'chat/chat_screen.dart';
import 'theme/cursor_theme.dart';

void main() {
  runApp(const MonadApp());
}

class MonadApp extends StatelessWidget {
  const MonadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monad',
      debugShowCheckedModeBanner: false,
      theme: buildCursorTheme(),
      home: const ChatScreen(),
    );
  }
}
