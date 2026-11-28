import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../customize/plugin_ui_slots.dart';
import '../../ide/ide_hover.dart';
import '../../theme/app_theme.dart';
import '../widgets/hover_builder.dart';

/// Declarative `abovePrompt` plugin controls in the composer toolbar.
class PluginSlotBar extends StatefulWidget {
  const PluginSlotBar({super.key, this.project, this.runner});
  final String? project;
  final PluginUiSlotRunner? runner;
  @override
  State<PluginSlotBar> createState() => _PluginSlotBarState();
}

class _PluginSlotBarState extends State<PluginSlotBar> {
  late final PluginUiSlotRunner _runner = widget.runner ?? PluginUiSlotRunner();
  List<PluginUiSlot> _slots = const [];
  final Map<int, bool> _values = {};
  final Set<int> _busy = {};
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(PluginSlotBar old) {
    super.didUpdateWidget(old);
    if (old.project != widget.project || old.runner != widget.runner) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final gen = ++_gen;
    final slots = await _runner.loadAbovePrompt(project: widget.project);
    final vals = <int, bool>{
      for (final (i, s) in slots.indexed)
        if (s.kind == PluginSlotKind.toggle)
          i: await _runner.readToggleState(s),
    };
    if (!mounted || gen != _gen) return;
    setState(() {
      _slots = slots;
      _values
        ..clear()
        ..addAll(vals);
    });
  }

  Future<void> _activate(int i) async {
    if (_busy.contains(i)) return;
    final s = _slots[i];
    setState(() => _busy.add(i));
    try {
      if (s.kind == PluginSlotKind.toggle) {
        final next = !(_values[i] ?? false);
        if ((next ? s.onAction : s.offAction) case final act?) {
          await _runner.runAction(act);
        }
        final v = s.stateFile != null ? await _runner.readToggleState(s) : next;
        if (mounted) setState(() => _values[i] = v);
      } else if (s.action case final act?) {
        await _runner.runAction(act);
      }
    } on Object {
      // Keep bar responsive if local endpoint or file is unavailable.
    } finally {
      if (mounted) setState(() => _busy.remove(i));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_slots.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (final (i, s) in _slots.indexed) _pill(s, i)],
      ),
    );
  }

  Widget _pill(PluginUiSlot s, int i) {
    final toggle = s.kind == PluginSlotKind.toggle;
    final on = _values[i] ?? false;
    final active = toggle && on;
    final busy = _busy.contains(i);
    final a = AppColors.accent;
    final fill = active
        ? Color.alphaBlend(a.withValues(alpha: 0.16), AppColors.bubbleFill)
        : AppColors.bubbleFill;
    final hover = Color.alphaBlend(AppColors.bubbleHover, fill);
    final border = active
        ? a.withValues(alpha: 0.45)
        : AppColors.bubbleBorder();
    final fg = active || !toggle ? AppColors.text : AppColors.textMuted;
    final dot = on ? a : AppColors.textFaint;
    return Padding(
      padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
      child: IdeHover(
        message: s.pluginName,
        child: HoverBuilder(
          cursor: busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
          builder: (_, hovered) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) {},
            onTap: busy ? null : () => unawaited(_activate(i)),
            child: Container(
              height: 22,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: hovered && !busy ? hover : fill,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: border),
              ),
              child: Text.rich(
                TextSpan(
                  style: TextStyle(color: fg, fontSize: 11.5),
                  children: [
                    if (toggle)
                      TextSpan(
                        text: '● ',
                        style: TextStyle(color: dot, fontSize: 8.5),
                      ),
                    TextSpan(text: s.labelFor(on: on)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
