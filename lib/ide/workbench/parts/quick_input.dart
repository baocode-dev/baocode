// The quick input over the workbench (upstream's `QuickInputController`
// widget): built again as the QuickInputService opens or closes it, not
// with the window.

import 'package:flutter/widgets.dart';

import '../../ide_quick_input.dart';
import '../../services/quick_input.dart';

class QuickInputPart extends StatelessWidget {
  const QuickInputPart({super.key, required this.service, this.top = 0});

  final QuickInputService service;

  /// Below the title bar, where the workbench draws one.
  final double top;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      if (!service.isOpen) return const SizedBox.shrink();
      return Positioned.fill(
        top: top,
        child: switch (service.model) {
          final IdeQuickPick pick => IdeQuickInput.pick(
            key: service.key,
            pick: pick,
            onClose: service.close,
          ),
          final IdeQuickInputBox box => IdeQuickInput.input(
            key: service.key,
            inputBox: box,
            onClose: service.close,
          ),
          _ => IdeQuickInput(
            key: service.key,
            initialText: service.text!,
            itemsFor: service.picks,
            placeholderFor: service.placeholder,
            onClose: service.close,
            refresh: service.refresh,
            itemActivation: service.activation,
            quickNavigate: service.navigateChords,
            hideInput: service.hideInput,
          ),
        },
      );
    },
  );
}
