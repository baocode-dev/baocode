/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadQuickOpen.ts (`$show` with
// `$setItems`/`$setError` resolving the promise the widget's answer
// completes, `$input` with `$validateInput`, `$createOrUpdate`'s sessions
// and the events they report with `$onDidChangeActive`/`$onDidChangeSelection`/
// `$onDidAccept`/`$onDidChangeValue`/`$onDidTriggerButton`/
// `$onDidTriggerItemButton`/`$onDidHide`, `$dispose`) and
// src/vs/platform/quickinput/browser/quickInputController.ts (one quick
// input at a time; the one showing hides when another shows).

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'quick_input_model.dart';

/// Which extension a quick input belongs to, for its UI (the app's
/// notifications show a source; a quick input shows none upstream).
final class ExtensionQuickInputOwner {
  const ExtensionQuickInputOwner({required this.extensionId, this.name = ''});

  final String extensionId;
  final String name;
}

/// The quick inputs of a session: what the actor's sessions are built on.
final class ExtensionQuickInputService extends ChangeNotifier
    implements ExtensionQuickInputHost {
  /// The one showing; null when none does.
  ExtensionQuickInput? get current => _current;
  ExtensionQuickInput? _current;

  /// Told as one shows (the workbench layers its widget over its content).
  VoidCallback? onShow;

  /// Told as one hides.
  VoidCallback? onHide;

  @override
  void showInput(ExtensionQuickInput input) {
    if (_current == input) return;
    final previous = _current;
    _current = input;
    // The one before hides as another shows, as quickInputService does.
    if (previous != null) {
      previous.didHide(ExtensionQuickInputHideReason.other);
    }
    notifyListeners();
    onShow?.call();
  }

  @override
  void hideInput(
    ExtensionQuickInput input,
    ExtensionQuickInputHideReason reason,
  ) {
    if (_current != input) return;
    _current = null;
    notifyListeners();
    onHide?.call();
  }

  /// Hides the one showing (the workbench's own quick input opens).
  void hideCurrent([ExtensionQuickInputHideReason reason =
      ExtensionQuickInputHideReason.other]) {
    final current = _current;
    if (current == null) return;
    current.didHide(reason);
    _current = null;
    notifyListeners();
    onHide?.call();
  }
}

/// One `createQuickPick`/`createInputBox` session
/// (`MainThreadQuickOpen.$createOrUpdate`'s).
final class ExtensionQuickInputSession {
  ExtensionQuickInputSession({
    required this.id,
    required this.type,
    required this.input,
    required this.owner,
    this.onDidAccept,
    this.onDidHide,
    this.onDidChangeValue,
    this.onDidChangeActive,
    this.onDidChangeSelection,
    this.onDidTriggerButton,
    this.onDidTriggerItemButton,
  }) {
    final subscriptions = <StreamSubscription<Object?>>[];
    subscriptions.add(
      input.onDidAccept.listen((_) => onDidAccept?.call(id)),
    );
    subscriptions.add(
      input.onDidHide.listen((reason) {
        onDidHide?.call(id);
        // A hidden session is done, as upstream's `onDidHide` implies: the
        // extension host disposes it.
        unawaited(dispose());
      }),
    );
    subscriptions.add(
      input.onDidChangeValue.listen((value) => onDidChangeValue?.call(id, value)),
    );
    subscriptions.add(
      input.onDidTriggerButton.listen(
        (button) => onDidTriggerButton?.call(id, button),
      ),
    );
    final pick = input;
    if (pick is ExtensionQuickPick) {
      subscriptions.add(
        pick.onDidChangeActive.listen(
          (items) => onDidChangeActive?.call(id, items),
        ),
      );
      subscriptions.add(
        pick.onDidChangeSelection.listen(
          (items) => onDidChangeSelection?.call(id, items),
        ),
      );
      subscriptions.add(
        pick.onDidTriggerItemButton.listen(
          (event) => onDidTriggerItemButton?.call(id, event.item, event.button),
        ),
      );
    }
    _subscriptions = subscriptions;
  }

  /// The extension host's session id.
  final int id;

  /// `'quickPick'` or `'inputBox'`.
  final String type;
  final ExtensionQuickInput input;
  final ExtensionQuickInputOwner owner;

  final void Function(int id)? onDidAccept;
  final void Function(int id)? onDidHide;
  final void Function(int id, String value)? onDidChangeValue;
  final void Function(int id, List<ExtensionQuickPickItem> items)?
  onDidChangeActive;
  final void Function(int id, List<ExtensionQuickPickItem> items)?
  onDidChangeSelection;
  final void Function(int id, ExtensionQuickInputButton button)?
  onDidTriggerButton;
  final void Function(
    int id,
    ExtensionQuickPickItem item,
    ExtensionQuickInputButton button,
  )?
  onDidTriggerItemButton;

  late final List<StreamSubscription<Object?>> _subscriptions;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    input.dispose();
  }
}
