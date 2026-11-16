import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import 'hover_builder.dart';

/// Lucide's icons it shows.
const _copyIcon = 'assets/icons/lucide-copy.svg';
const _checkIcon = 'assets/icons/lucide-check.svg';

/// A faint icon that copies [text], a check for a moment after: a reply's,
/// say, or a picture's prompt. [tooltip] says what it copies.
class CopyButton extends StatefulWidget {
  const CopyButton({super.key, required this.text, required this.tooltip});

  final String text;
  final String tooltip;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _copied = false;
  Timer? _copiedTimer;

  void _copy() {
    unawaited(Clipboard.setData(ClipboardData(text: widget.text)));
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IdeHover(
      message: _copied ? context.l10n.turnCopied : widget.tooltip,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: _copy,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: hovered ? AppColors.hover : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: SvgPicture.asset(
              _copied ? _checkIcon : _copyIcon,
              width: 13,
              height: 13,
              colorFilter: ColorFilter.mode(
                hovered || _copied ? AppColors.text : AppColors.textFaint,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
