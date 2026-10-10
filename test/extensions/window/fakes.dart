// The fakes the window area's tests use: a dialogs port that records what
// it was asked and answers a script, a command executor, a URL host, a
// window focus and an external opener.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/main_thread/main_thread_clipboard.dart';
import 'package:baocode/extensions/window/url_service.dart';
import 'package:baocode/extensions/window/window_ports.dart';

/// [ExtensionDialogs] answering a script; each answer is a button index
/// (null: the cancel button) and whether the checkbox was checked.
final class FakeDialogs implements ExtensionDialogs {
  final List<({int? button, bool checked})> answers = [];
  final List<
    ({
      ExtensionSeverity severity,
      String message,
      String? detail,
      List<String> buttons,
      String? cancel,
      String? checkbox,
    })
  >
  prompts = [];

  @override
  Future<ExtensionDialogAnswer> prompt({
    required ExtensionSeverity severity,
    required String message,
    String? detail,
    required List<String> buttons,
    String? cancel,
    String? checkbox,
  }) async {
    prompts.add((
      severity: severity,
      message: message,
      detail: detail,
      buttons: buttons,
      cancel: cancel,
      checkbox: checkbox,
    ));
    if (answers.isEmpty) return (button: null, checked: false);
    return answers.removeAt(0);
  }
}

/// [ExtensionCommandExecutor] recording what it ran.
final class FakeCommands implements ExtensionCommandExecutor {
  final List<(String, List<Object?>)> runs = [];

  @override
  Future<Object?> executeCommand(String id, [List<Object?> args = const []]) {
    // The install command answers the extension it installed.
    runs.add((id, args));
    return Future.value(id == 'workbench.extensions.installExtension'
        ? 'installed'
        : null);
  }
}

/// [ExtensionUrlHost] over a map of extensions.
final class FakeUrlHost implements ExtensionUrlHost {
  FakeUrlHost(this.windowId);

  @override
  final String windowId;
  final Map<String, Map<String, Object?>> extensions = {};
  final List<String> events = [];

  @override
  Map<String, Object?>? extension(String id) => extensions[id];

  @override
  Future<void> activateByEvent(String event) async => events.add(event);
}

/// [ExtensionWindowFocus] under the test's control.
final class FakeWindowFocus implements ExtensionWindowFocus {
  FakeWindowFocus({this.isFocused = true, this.isActive = true});

  @override
  bool isFocused;
  @override
  bool isActive;
  final _changes = StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get changes => _changes.stream;

  void set({bool? focused, bool? active}) {
    if (focused != null) isFocused = focused;
    if (active != null) isActive = active;
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}

/// [ExtensionExternalOpener] recording the URIs it opened.
final class FakeOpener implements ExtensionExternalOpener {
  final List<Uri> opened = [];

  /// Whether opening succeeds.
  bool succeeds = true;

  @override
  Future<bool> openExternal(Uri uri) async {
    opened.add(uri);
    return succeeds;
  }
}

/// [ExtensionClipboard] in memory.
final class FakeClipboard implements ExtensionClipboard {
  String text = '';

  @override
  Future<String> readText() async => text;

  @override
  Future<void> writeText(String value) async => text = value;
}

/// [ExtensionFilePickers] answering a script.
final class FakePickers implements ExtensionFilePickers {
  List<String>? openResult;
  String? saveResult;
  final List<String> openCalls = [];
  final List<String> saveCalls = [];

  @override
  Future<List<String>?> pickOpen({
    required bool files,
    required bool folders,
    required bool many,
    String? directory,
    String? title,
    String? openLabel,
    Map<String, List<String>> filters = const {},
  }) async {
    openCalls.add('files=$files folders=$folders many=$many dir=$directory');
    return openResult;
  }

  @override
  Future<String?> pickSave({
    String? directory,
    String? name,
    String? title,
    String? saveLabel,
    Map<String, List<String>> filters = const {},
  }) async {
    saveCalls.add('dir=$directory name=$name');
    return saveResult;
  }
}

/// A scan of `IExtensionDescription`s (what `ExtensionHostService.exensions`
/// gives).
Map<String, Object?> extensionDescription(
  String id, {
  String? displayName,
  Map<String, Object?> contributions = const {},
}) {
  final parts = id.split('.');
  return {
    'identifier': {'value': id},
    'publisher': parts.first,
    'name': parts.skip(1).join('.'),
    'displayName': displayName,
    'version': '0.0.1',
    'contributes': contributions,
  };
}

/// A `VsUri` of a file path in the test's temporary directory.
VsUri tempUri(String path) => VsUri.file(path);
