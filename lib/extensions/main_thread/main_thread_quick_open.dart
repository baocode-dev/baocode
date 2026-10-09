/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadQuickOpen.ts (all six methods),
// with what the extension host sends and expects
// (src/vs/workbench/api/common/extHostQuickOpen.ts): the old
// `showQuickPick` (`$show` then `$setItems`, whose items' `handle`s are
// what its promise resolves with) and `showInput` (`$input` with
// `$validateInput`), and `createQuickPick`/`createInputBox`
// (`$createOrUpdate` per change, `$dispose`).
//
// Deviations: an item's `iconPathDto` is resolved by the widget
// (quickInput) rather than here, since BaoCode draws its own icons;
// `expandItemProps`' `resourceUri` labels (a custom editor's name and the
// label service's `getUriLabel`) are derived from the URI itself, as
// BaoCode has no resource-label service for the file schemes; a `$show`
// whose widget answers `undefined` while its items never arrived leaves
// the promise pending, as upstream's `Promise.race` does.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../window/quick_input/quick_input_filter.dart' show parseLabelWithIcons;
import '../window/quick_input/quick_input_model.dart';
import '../window/quick_input/quick_input_service.dart';
import '../window/window_ports.dart';
import 'main_thread_context.dart';

/// What the actor needs from the app: the quick inputs, the extension's
/// name (for `$validateInput`'s owner) and the icon of a `resourceUri`.
final class ExtensionQuickInputUi {
  const ExtensionQuickInputUi({
    required this.inputs,
    this.ownerOf,
  });

  final ExtensionQuickInputService inputs;

  /// The extension a quick input belongs to (the session's last
  /// `$createOrUpdate` has no extension id, so the workbench tells the
  /// actor instead).
  final ExtensionQuickInputOwner Function()? ownerOf;
}

final class MainThreadQuickOpen extends MainThreadQuickOpenUnsupported {
  MainThreadQuickOpen(
    this._ui,
    this._proxy, {
    MainThreadContext? context,
  }) {
    context?.onDispose(dispose);
  }

  final ExtensionQuickInputUi _ui;
  final ExtHostQuickOpenProxy _proxy;

  /// `$show`/`$input`'s pending answers, by instance.
  final Map<num, _PendingPick> _picks = {};
  final Map<num, Completer<String?>> _inputs = {};

  /// `$createOrUpdate`'s sessions, by id.
  final Map<num, ExtensionQuickInputSession> _sessions = {};

  static RpcActor customer(MainThreadContext context) =>
      MainThreadQuickOpenActor(
        MainThreadQuickOpen(
          ExtensionQuickInputUi(
            inputs: context.service<ExtensionQuickInputService>(),
          ),
          ExtHostQuickOpenProxy(context.rpc),
          context: context,
        ),
      );

  /// Ends every session and pending answer, as the host ends.
  void dispose() {
    for (final pick in _picks.values) {
      pick.abandon();
    }
    _picks.clear();
    for (final input in _inputs.values) {
      if (!input.isCompleted) input.complete(null);
    }
    _inputs.clear();
    for (final session in _sessions.values) {
      unawaited(session.dispose());
    }
    _sessions.clear();
  }

  // --- The old API: showQuickPick and showInput ---------------------------

  @override
  Future<Object?> $show(
    num instance,
    Map<String, Object?> options,
    CancellationToken token,
  ) async {
    final pick = _PendingPick(
      _ui.inputs,
      options: options,
      onItemSelected: (item) => _proxy.$onItemSelected(item.handle),
      onCancel: token.whenCancelled.then((_) {
        _picks.remove(instance)?.abandon();
      }),
    );
    _picks[instance] = pick;
    final answer = await pick.answer;
    _picks.remove(instance);
    if (answer == null) return null;
    if (options['canPickMany'] == true) {
      return [for (final item in answer) item.handle];
    }
    return answer.first.handle;
  }

  @override
  Future<void> $setItems(
    num instance,
    List<Map<String, Object?>> items,
  ) async {
    _picks[instance]?.setItems([
      for (final item in items) quickPickEntryOf(item, _ui),
    ]);
  }

  @override
  Future<void> $setError(num instance, Map<String, Object?> error) async {
    _picks[instance]?.fail(error);
  }

  @override
  Future<String?> $input(
    Map<String, Object?>? options,
    bool validateInput,
    CancellationToken token,
  ) async {
    if (token.isCancellationRequested) return null;
    final completer = Completer<String?>();
    final box = ExtensionInputBox(_ui.inputs)
      ..title = _string(options?['title'])
      ..placeholder = _string(options?['placeHolder'])
      ..prompt = _string(options?['prompt'])
      ..password = options?['password'] == true
      ..ignoreFocusOut = options?['ignoreFocusOut'] == true
      ..value = '${options?['value'] ?? ''}';
    if (options?['valueSelection'] case final List<Object?> selection
        when selection.length == 2) {
      box.valueSelection = (
        (selection[0] as num).toInt(),
        (selection[1] as num).toInt(),
      );
    }
    void complete(String? value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    final subscriptions = <StreamSubscription<Object?>>[
      box.onDidAccept.listen((_) => complete(box.value)),
      box.onDidHide.listen((_) => complete(null)),
      if (validateInput)
        box.onDidChangeValue.listen((value) {
          unawaited(_validate(box, value));
        }),
    ];
    if (validateInput) unawaited(_validate(box, box.value));
    box.show();
    await completer.future;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    box.dispose();
    return completer.isCompleted ? await completer.future : null;
  }

  /// `IQuickInputService.InputBox`'s validation: the host answers with a
  /// string or `{content, severity}`.
  Future<void> _validate(ExtensionInputBox box, String value) async {
    Object? result;
    try {
      result = await _proxy.$validateInput(value);
    } on Object {
      return;
    }
    if (box.isDisposed) return;
    switch (result) {
      case null:
        box.validationMessage = null;
        box.severity = ExtensionSeverity.ignore;
      case final String message:
        box.validationMessage = message;
        box.severity = ExtensionSeverity.error;
      case final Map<Object?, Object?> message:
        box.validationMessage = message['content'] as String?;
        box.severity = ExtensionSeverity.fromWire(message['severity']);
      default:
        box.validationMessage = null;
    }
  }

  // --- The object API: createQuickPick and createInputBox -----------------

  @override
  Future<void> $createOrUpdate(Map<String, Object?> params) async {
    final id = params['id'];
    if (id is! num) return;
    final owner =
        _ui.ownerOf?.call() ??
        const ExtensionQuickInputOwner(extensionId: '');
    var session = _sessions[id];
    if (session == null) {
      final type = params['type'] == 'inputBox' ? 'inputBox' : 'quickPick';
      final input = type == 'quickPick'
          ? ExtensionQuickPick(_ui.inputs)
          : ExtensionInputBox(_ui.inputs);
      session = ExtensionQuickInputSession(
        id: id.toInt(),
        type: type,
        input: input,
        owner: owner,
        onDidAccept: (id) => _proxy.$onDidAccept(id),
        onDidHide: (id) {
          _sessions.remove(id);
          unawaited(_proxy.$onDidHide(id).catchError((Object _) {}));
        },
        onDidChangeValue: (id, value) =>
            unawaited(_proxy.$onDidChangeValue(id, value).catchError((Object _) {})),
        onDidChangeActive: (id, items) => unawaited(
          _proxy
              .$onDidChangeActive(id, [for (final item in items) item.handle])
              .catchError((Object _) {}),
        ),
        onDidChangeSelection: (id, items) => unawaited(
          _proxy
              .$onDidChangeSelection(id, [for (final item in items) item.handle])
              .catchError((Object _) {}),
        ),
        onDidTriggerButton: (id, button) => unawaited(
          _proxy
              .$onDidTriggerButton(id, button.handle, button.checked)
              .catchError((Object _) {}),
        ),
        onDidTriggerItemButton: (id, item, button) => unawaited(
          _proxy
              .$onDidTriggerItemButton(id, item.handle, button.handle, button.checked)
              .catchError((Object _) {}),
        ),
      );
      _sessions[id] = session;
    }
    _apply(session, params);
    return;
  }

  /// The properties of [params] onto [session]'s input, as upstream's loop
  /// over them does (`items`, `activeItems`, `selectedItems`, `buttons`
  /// and `visible` are the special ones).
  void _apply(ExtensionQuickInputSession session, Map<String, Object?> params) {
    final input = session.input;
    for (final MapEntry(:key, :value) in params.entries) {
      switch (key) {
        case 'id' || 'type':
          break;
        case 'visible':
          if (value == true) {
            input.show();
          } else {
            input.hide();
          }
        case 'title':
          input.title = value as String?;
        case 'enabled':
          input.enabled = value != false;
        case 'busy':
          input.busy = value == true;
        case 'ignoreFocusOut':
          input.ignoreFocusOut = value == true;
        case 'step':
          input.step = (value as num?)?.toInt();
        case 'totalSteps':
          input.totalSteps = (value as num?)?.toInt();
        case 'validationMessage':
          input.validationMessage = value as String?;
        case 'severity':
          input.severity = ExtensionSeverity.fromWire(value);
        case 'buttons':
          input.buttons = [
            for (final button in value as List? ?? const [])
              quickInputButtonOf(button as Map),
          ];
        default:
          if (input is ExtensionQuickPick) {
            _applyToPick(input, key, value);
          } else if (input is ExtensionInputBox) {
            _applyToInputBox(input, key, value);
          }
      }
    }
  }

  void _applyToPick(ExtensionQuickPick pick, String key, Object? value) {
    switch (key) {
      case 'value':
        pick.value = '${value ?? ''}';
      case 'valueSelection':
        if (value case final List<Object?> selection when selection.length == 2) {
          pick.valueSelection = (
            (selection[0] as num).toInt(),
            (selection[1] as num).toInt(),
          );
        }
      case 'placeholder':
        pick.placeholder = value as String?;
      case 'prompt':
        pick.prompt = value as String?;
      case 'canSelectMany':
        pick.canSelectMany = value == true;
      case 'matchOnDescription':
        pick.matchOnDescription = value == true;
      case 'matchOnDetail':
        pick.matchOnDetail = value == true;
      case 'matchOnLabel':
        pick.matchOnLabel = value != false;
      case 'sortByLabel':
        pick.sortByLabel = value != false;
      case 'keepScrollPosition':
        pick.keepScrollPosition = value == true;
      case 'items':
        pick.items = [
          for (final item in value as List? ?? const [])
            quickPickEntryOf(item as Map<String, Object?>, _ui),
        ];
      case 'activeItems':
        pick.activeItems = [
          for (final handle in value as List? ?? const [])
            ?_itemOf(pick, (handle as num).toInt()),
        ];
      case 'selectedItems':
        pick.selectedItems = [
          for (final handle in value as List? ?? const [])
            ?_itemOf(pick, (handle as num).toInt()),
        ];
    }
  }

  void _applyToInputBox(ExtensionInputBox box, String key, Object? value) {
    switch (key) {
      case 'value':
        box.value = '${value ?? ''}';
      case 'valueSelection':
        if (value case final List<Object?> selection when selection.length == 2) {
          box.valueSelection = (
            (selection[0] as num).toInt(),
            (selection[1] as num).toInt(),
          );
        }
      case 'placeholder':
        box.placeholder = value as String?;
      case 'password':
        box.password = value == true;
      case 'prompt':
        box.prompt = value as String?;
    }
  }

  ExtensionQuickPickItem? _itemOf(ExtensionQuickPick pick, int handle) {
    for (final entry in pick.items) {
      if (entry is ExtensionQuickPickItem && entry.handle == handle) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<void> $dispose(num id) async {
    await _sessions.remove(id)?.dispose();
  }
}

/// `$show`'s answer: the items it showed and what was picked.
final class _PendingPick {
  _PendingPick(
    this._inputs, {
    required this.options,
    required this.onItemSelected,
    required this.onCancel,
  }) {
    onCancel.catchError((Object _) {});
  }

  final ExtensionQuickInputService _inputs;
  final Map<String, Object?> options;
  final void Function(ExtensionQuickPickItem item) onItemSelected;
  final Future<void> onCancel;

  final _completer = Completer<List<ExtensionQuickPickItem>?>();
  ExtensionQuickPick? _pick;
  List<ExtensionQuickPickEntry>? _entries;
  bool _abandoned = false;

  /// The answer: the items picked, or null when dismissed.
  Future<List<ExtensionQuickPickItem>?> get answer => _completer.future;

  void setItems(List<ExtensionQuickPickEntry> entries) {
    if (_abandoned) return;
    _entries = entries;
    _show();
  }

  void fail(Map<String, Object?> error) {
    if (_abandoned || _completer.isCompleted) return;
    _completer.completeError(
      StateError('${error['message'] ?? 'Quick input failed'}'),
    );
  }

  void abandon() {
    if (_abandoned) return;
    _abandoned = true;
    _pick?.dispose();
    _pick = null;
    if (!_completer.isCompleted) _completer.complete(null);
  }

  void _show() {
    final entries = _entries;
    if (entries == null || _pick != null || _abandoned) return;
    final canPickMany = options['canPickMany'] == true;
    final pick = _pick = ExtensionQuickPick(_inputs)
      ..title = options['title'] as String?
      ..placeholder = options['placeHolder'] as String?
      ..prompt = options['prompt'] as String?
      ..canSelectMany = canPickMany
      ..matchOnDescription = options['matchOnDescription'] == true
      ..matchOnDetail = options['matchOnDetail'] == true
      ..items = entries;
    final picked = [
      for (final entry in entries)
        if (entry is ExtensionQuickPickItem && entry.picked) entry,
    ];
    if (picked.isNotEmpty) {
      if (canPickMany) {
        pick.selectedItems = picked;
      } else {
        pick.activeItems = picked;
      }
    }
    pick.onDidChangeActive.listen((items) {
      if (items.isNotEmpty) onItemSelected(items.first);
    });
    void complete(List<ExtensionQuickPickItem>? items) {
      if (_completer.isCompleted) return;
      _completer.complete(items);
    }

    pick.onDidAccept.listen((_) {
      final items = canPickMany ? pick.selectedItems : pick.activeItems;
      complete(items.isEmpty ? null : items);
      pick.dispose();
    });
    pick.onDidHide.listen((_) {
      complete(null);
      pick.dispose();
    });
    pick.show();
  }
}

/// A quick pick item as the extension host sends it (`expandItemProps`
/// included: a `resourceUri` without a label gets one from the URI).
ExtensionQuickPickEntry quickPickEntryOf(
  Map<String, Object?> item,
  ExtensionQuickInputUi ui,
) {
  if (item['type'] == 'separator') {
    return ExtensionQuickPickSeparator(item['label'] as String?);
  }
  var label = item['label'] as String? ?? '';
  var description = item['description'] as String?;
  final resourceUri = item['resourceUri'];
  if (resourceUri != null && label.isEmpty) {
    final uri = VsUri.tryRevive(resourceUri);
    if (uri != null) {
      final segments = uri.path.split('/').where((s) => s.isNotEmpty).toList();
      label = segments.isEmpty ? uri.authority : segments.last;
      description ??= segments.length > 1
          ? segments.sublist(0, segments.length - 1).join('/')
          : uri.authority;
    }
  }
  return ExtensionQuickPickItem(
    handle: (item['handle'] as num?)?.toInt() ?? -1,
    label: label,
    description: description,
    detail: item['detail'] as String?,
    icon: quickInputIconOf(item['iconPathDto']),
    picked: item['picked'] == true,
    alwaysShow: item['alwaysShow'] == true,
    buttons: [
      for (final button in item['buttons'] as List? ?? const [])
        quickInputButtonOf(button as Map),
    ],
    tooltip: switch (item['tooltip']) {
      final String tooltip => tooltip,
      final Map<Object?, Object?> markdown => markdown['value'] as String?,
      _ => null,
    },
  );
}

/// An `IconPathDto` as the widget's icon: `{id, color?}` is a codicon, a
/// URI (or `{light, dark}`) an image.
ExtensionQuickInputIcon? quickInputIconOf(Object? icon) {
  if (icon is! Map<Object?, Object?>) return null;
  if (icon['id'] is String) return ExtensionThemeIcon(icon['id']! as String);
  if (icon.containsKey('dark') || icon.containsKey('light')) {
    final dark = VsUri.tryRevive(icon['dark']);
    final light = VsUri.tryRevive(icon['light']);
    if (dark == null && light == null) return null;
    return ExtensionImageIcon(
      dark: dark?.fsPath() ?? light!.fsPath(),
      light: light?.fsPath() ?? dark!.fsPath(),
    );
  }
  final revived = VsUri.tryRevive(icon);
  return revived == null ? null : ExtensionResourceIcon(revived.fsPath());
}

/// A `TransferQuickInputButton` as the widget's button.
ExtensionQuickInputButton quickInputButtonOf(Map<Object?, Object?> button) {
  final icon = quickInputIconOf(button['iconPathDto']);
  return ExtensionQuickInputButton(
    handle: (button['handle'] as num?)?.toInt() ?? -1,
    icon: icon,
    tooltip: button['tooltip'] as String?,
    location: ExtensionQuickInputButtonLocation.fromWire(button['location']),
    checked: switch (button['toggle']) {
      final Map<Object?, Object?> toggle => toggle['checked'] == true,
      _ => null,
    },
  );
}

String? _string(Object? value) => value is String ? value : null;

/// The label without its icons, for logs and tests.
String quickPickSearchLabel(String label) => parseLabelWithIcons(label).text;
