import 'package:flutter/material.dart';

import '../../chat/panels/interaction_panel.dart';
import '../../theme/cursor_theme.dart';

/// The version this build is of, as pubspec.yaml says; kept here rather than
/// read at runtime, which would mean another package for one line. A test
/// holds the two together.
const monadVersion = '1.0.0';

/// Help → About: what the app is, and which build this is.
Future<void> showAboutMonad(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: const Color(0x88000000),
  builder: (context) => const _AboutMonadDialog(),
);

class _AboutMonadDialog extends StatelessWidget {
  const _AboutMonadDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 360,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          color: CursorColors.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: CursorColors.borderStrong),
          boxShadow: const [
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 32,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: CursorColors.accent,
                ),
                SizedBox(width: 9),
                Text(
                  'Monad',
                  style: TextStyle(
                    color: CursorColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  monadVersion,
                  style: TextStyle(
                    color: CursorColors.textFaint,
                    fontSize: 12,
                    fontFamily: CursorFonts.mono,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Agents run Claude Code as a local process; what they do — '
              'messages, tools, diffs and panels — is shown here.',
              style: TextStyle(
                color: CursorColors.textMuted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: PanelButton(
                label: 'Close',
                primary: true,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
