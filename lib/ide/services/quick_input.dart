// The window's quick input (upstream `IQuickInputService` with
// `QuickAccessController.show`, src/vs/platform/quickinput/browser/
// quickAccess.ts: `quickNavigateConfiguration`, `itemActivation`,
// `hideInput`): open with a quick access's text, or with a pick or an
// input box a feature made; and where the keyboard goes back as it
// closes.

import 'package:flutter/widgets.dart';

import '../../keybindings/key_chord.dart';
import '../../keybindings/keybinding_service.dart';
import '../../l10n/l10n.dart';
import '../ide_quick_input.dart';
import '../workbench/contributions.dart';
import '../workbench/quick_access.dart';

class QuickInputService extends ChangeNotifier {
  QuickInputService({
    required this.host,
    required this.registry,
    required this._focusWorkbench,
  });

  final WorkbenchHost host;
  final QuickAccessRegistry registry;

  /// The keyboard to the editor, or the workbench without one: where it
  /// goes as the quick input closes, what had it gone.
  final VoidCallback _focusWorkbench;

  /// The quick access's text it opened with (its prefix picks the
  /// provider); null while closed or showing [model].
  String? get text => _text;
  String? _text;

  /// The quick pick (e.g. the color themes) or input box it shows
  /// instead.
  IdeQuickInputModel? get model => _model;
  IdeQuickInputModel? _model;

  /// The quick input's widget; another for each opening.
  GlobalKey<IdeQuickInputState> get key => _key;
  GlobalKey<IdeQuickInputState> _key = GlobalKey();
  IdeQuickInputState? get input => _key.currentState;

  /// How [text] opens (see [IdeQuickInput.itemActivation],
  /// [IdeQuickInput.quickNavigate], [IdeQuickInput.hideInput]).
  IdeQuickPickFocus get activation => _activation;
  IdeQuickPickFocus _activation = IdeQuickPickFocus.first;
  List<KeyChord>? get navigateChords => _navigateChords;
  List<KeyChord>? _navigateChords;
  bool get hideInput => _hideInput;
  bool _hideInput = false;

  /// What the rows follow while they show (the providers').
  Listenable get refresh => Listenable.merge([
    for (final provider in registry.providers) provider.refresh?.call(),
  ]);

  FocusNode? _focusBefore;

  bool get isOpen => _text != null || _model != null;

  /// Opens with [prefix] (`>` commands, `:` go to line, `edt ` editors,
  /// none for files), or switches the open one to it.
  ///
  /// With [quickNavigate] (upstream `quickNavigateConfiguration`),
  /// releasing a modifier of those chords accepts, and the input is
  /// hidden unless a quick input shows already; [itemActivation] is the
  /// row active first (the second by default with [quickNavigate]).
  void show(
    String prefix, {
    IdeQuickPickFocus? itemActivation,
    List<KeyChord>? quickNavigate,
  }) {
    registry.providerFor(prefix)?.onShow?.call();
    final shown = isOpen;
    if (_text != null && itemActivation == null && quickNavigate == null) {
      input?.setText(prefix);
      return;
    }
    _open(() {
      _text = prefix;
      _activation =
          itemActivation ??
          (quickNavigate != null
              ? IdeQuickPickFocus.second
              : IdeQuickPickFocus.first);
      _navigateChords = quickNavigate;
      _hideInput = quickNavigate != null && !shown;
    });
  }

  /// [show] for the command [command] with a quick navigation: releasing
  /// its modifier accepts, the input hidden unless a quick input shows
  /// already.
  void quickNavigate(
    String command,
    String prefix, {
    IdeQuickPickFocus? itemActivation,
  }) => show(
    prefix,
    itemActivation: itemActivation,
    quickNavigate: singleChordsOf(command),
  );

  /// Opens [model], a quick pick or an input box, in place of what it
  /// shows.
  void showModel(IdeQuickInputModel model) => _open(() => _model = model);

  void _open(VoidCallback open) {
    final replaced = _model;
    if (!isOpen) _focusBefore = FocusManager.instance.primaryFocus;
    _key = GlobalKey();
    _text = null;
    _model = null;
    _activation = IdeQuickPickFocus.first;
    _navigateChords = null;
    _hideInput = false;
    open();
    notifyListeners();
    // Upstream hides the quick input that another one replaces.
    replaced?.onDidHide?.call();
  }

  /// Closed: the keyboard back where it was.
  void close() {
    final model = _model;
    if (!isOpen) return;
    _text = null;
    _model = null;
    notifyListeners();
    final previous = _focusBefore;
    _focusBefore = null;
    if (previous != null &&
        previous.context != null &&
        previous.canRequestFocus) {
      previous.requestFocus();
    } else {
      _focusWorkbench();
    }
    model?.onDidHide?.call();
  }

  /// The rows for [text], its provider's.
  List<IdeQuickPickItem> picks(String text) {
    final context = host.context;
    final provider = registry.providerFor(text);
    if (context == null || provider == null) return const [];
    return provider.picks(context, text.substring(provider.prefix.length));
  }

  /// What the input says while [text] has nothing after its prefix.
  String placeholder(String text) {
    final context = host.context;
    final placeholder = registry.providerFor(text)?.placeholder;
    if (context == null || placeholder == null) return '';
    return placeholder(context.l10n);
  }

  /// The quick input's context keys (upstream `inQuickInput`,
  /// `quickInputType`…, and the providers' own); null for others.
  Object? contextKey(String key) {
    final open = isOpen;
    switch (key) {
      case 'inQuickOpen' || 'inQuickInput':
        return open;
      case 'quickInputType':
        if (!open) return null;
        return _model is IdeQuickInputBox ? 'inputBox' : 'quickPick';
      case 'cursorAtEndOfQuickInputBox':
        return open && (input?.cursorAtEnd ?? false);
    }
    if (!registry.providers.any((provider) => provider.contextKey == key)) {
      return null;
    }
    final text = _text;
    if (text == null) return false;
    return registry.providerFor(input?.text ?? text)?.contextKey == key;
  }

  @override
  void dispose() {
    _model?.onDidHide?.call();
    super.dispose();
  }
}

/// The single chords [command] is bound to (upstream
/// `lookupKeybindings`, whose chords `registerQuickNavigation` reads).
List<KeyChord> singleChordsOf(String command) => [
  for (final item in KeybindingService.instance.resolver().lookupKeybindings(
    command,
  ))
    if (item.keys case final keys? when keys.chords.length == 1)
      keys.chords.single,
];
