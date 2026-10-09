// The window area's ports: what its services need from the workbench (a
// command service, modal dialogs, file pickers, the system's opener), as
// interfaces the workbench implements (see window_adapters.dart for the
// adapters on BaoCode's own widgets).

import 'dart:async';

/// VS Code's `Severity` (base/common/severity.ts): what the extension host
/// sends for messages, validation and progress.
enum ExtensionSeverity {
  ignore,
  info,
  warning,
  error;

  /// From its wire value (`Severity.Ignore` = 0 … `Severity.Error` = 3);
  /// anything else is [info].
  static ExtensionSeverity fromWire(Object? value) => switch (value) {
    0 => ignore,
    2 => warning,
    3 => error,
    _ => info,
  };
}

/// Runs commands by id (VS Code's `ICommandService.executeCommand`): the
/// workbench's commands, and the extension host's (`$executeContributedCommand`,
/// after activating `onCommand:<id>`).
abstract interface class ExtensionCommandExecutor {
  Future<Object?> executeCommand(String id, [List<Object?> args = const []]);
}

/// What a modal dialog was answered with: the index of the button chosen
/// among the given buttons, or null for the cancel button (also Escape or a
/// click outside); and whether its checkbox was checked.
typedef ExtensionDialogAnswer = ({int? button, bool checked});

/// Modal dialogs (VS Code's `IDialogService.prompt`/`confirm`).
abstract interface class ExtensionDialogs {
  /// Shows [message] with [detail] under it, [buttons] then [cancel] (none
  /// when null), and a [checkbox] when given.
  Future<ExtensionDialogAnswer> prompt({
    required ExtensionSeverity severity,
    required String message,
    String? detail,
    required List<String> buttons,
    String? cancel,
    String? checkbox,
  });
}

/// The system's file pickers (VS Code's `IFileDialogService`).
abstract interface class ExtensionFilePickers {
  /// Absolute paths chosen; null when cancelled.
  Future<List<String>?> pickOpen({
    required bool files,
    required bool folders,
    required bool many,
    String? directory,
    String? title,
    String? openLabel,
    Map<String, List<String>> filters,
  });

  /// The absolute path chosen; null when cancelled.
  Future<String?> pickSave({
    String? directory,
    String? name,
    String? title,
    String? saveLabel,
    Map<String, List<String>> filters,
  });
}

/// Opens what is outside the app: a URL in the browser, a file in its
/// default app.
abstract interface class ExtensionExternalOpener {
  Future<bool> openExternal(Uri uri);
}

/// The app window's focus as `vscode.window.state` reads it.
abstract interface class ExtensionWindowFocus {
  /// Whether the window has the system's focus.
  bool get isFocused;

  /// Whether the user used the window recently (`isActive`).
  bool get isActive;

  /// Fires when either changes.
  Stream<void> get changes;
}
