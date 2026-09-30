import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import 'terminal_colors.dart';
import 'terminal_instance.dart';

/// A terminal's screen in the panel, and the keyboard's way into it
/// ([TerminalInstance.focusNode]).
///
/// A placeholder until the emulator's renderer takes its place: it shows
/// why the process ended, as VS Code writes it into the terminal (an
/// inverse ` * `, then the message), and otherwise only says the screen is
/// not drawn yet. The renderer is to draw the instance's screen here, send
/// the keys it takes to [TerminalInstance.write], and give the grid its
/// size fits to [TerminalInstance.resize].
class TerminalView extends StatelessWidget {
  const TerminalView(this.instance, {super.key});

  final TerminalInstance instance;

  /// `.xterm { padding-left: 20px }`, and Modern UI's 8px above and below.
  static const padding = EdgeInsets.fromLTRB(20, 8, 20, 8);

  static const _style = TextStyle(
    fontFamily: CursorFonts.mono,
    fontSize: 12,
    height: 1.4,
    color: TerminalColors.foreground,
  );

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: instance.focusNode,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => instance.focus(),
      child: ColoredBox(
        color: TerminalColors.background,
        child: Padding(
          padding: padding,
          child: Align(
            alignment: Alignment.topLeft,
            child: ListenableBuilder(
              listenable: instance,
              builder: (context, _) {
                final message = instance.exitMessage;
                return message == null
                    ? Text(
                        'The terminal display is not available yet.',
                        style: _style.copyWith(color: CursorColors.textFaint),
                      )
                    : Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: ' * ',
                              style: _style.copyWith(
                                color: TerminalColors.background,
                                backgroundColor: TerminalColors.foreground,
                              ),
                            ),
                            TextSpan(text: '  $message '),
                          ],
                        ),
                        style: _style,
                      );
              },
            ),
          ),
        ),
      ),
    ),
  );
}
