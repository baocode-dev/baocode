/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The app side of `MainThreadExtensionService`: every extension of every
// running host with how its activation went, for a "Running Extensions"
// view. Ported from the model of VS Code
// 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/extensions/browser/abstractRuntimeExtensionsEditor.ts
// (`IRuntimeExtension.status.activationTimes` is the histogram
// `RawActivationTimes`: codeLoadingTime, activateCallTime,
// activateResolvedTime, activationReason, startup; `ActivationTimes`.
// `getSyncTime` = codeLoadingTime + activateCallTime; `elements.sort` puts
// the slowest activation first), src/vs/workbench/services/extensions/common/extensions.ts
// (`IRuntimeExtensionDescription`, `ExtensionActivationReason`) and
// src/vs/workbench/services/extensions/electron-browser/runtimeExtensionsEditor.ts.
//
// Deviations: activation profiles (the CPU profile of a slow activation)
// and freeze reports are not collected; extensions record the `onDid*`
// errors they raise here rather than through the extension host's own
// error reporting.

import 'package:flutter/foundation.dart';

/// `ExtensionActivationReason`: what asked for the extension.
final class ExtensionActivationReason {
  const ExtensionActivationReason({
    required this.startup,
    required this.extensionId,
    required this.activationEvent,
  });

  /// It activated as the window started (`*`, `onStartupFinished`).
  final bool startup;

  /// The extension that asked for it, or itself.
  final String extensionId;

  /// The activation event (`onLanguage:typescript`, `*`…).
  final String activationEvent;

  factory ExtensionActivationReason.fromJson(Map<String, Object?> json) =>
      ExtensionActivationReason(
        startup: json['startup'] == true,
        extensionId: switch (json['extensionId']) {
          final Map<Object?, Object?> id => '${id['value']}',
          final String id => id,
          _ => '',
        },
        activationEvent: '${json['activationEvent'] ?? ''}',
      );

  /// `[extensionId] activated by [activationEvent]` (upstream's hover).
  String get description => startup
      ? 'Startup Activation'
      : 'Activated by $activationEvent on $extensionId';

  /// The event without its arguments, e.g. `onLanguage`.
  String get kind => activationEvent.split(':').first;
}

/// `ActivationTimes`: how long the three phases took, in milliseconds.
final class ExtensionActivationTimes {
  const ExtensionActivationTimes({
    required this.codeLoadingTime,
    required this.activateCallTime,
    required this.activateResolvedTime,
    required this.reason,
  });

  final num codeLoadingTime;
  final num activateCallTime;
  final num activateResolvedTime;
  final ExtensionActivationReason reason;

  /// `getSyncTime`.
  num get syncTime => codeLoadingTime + activateCallTime;

  /// `getTotalTime`.
  num get totalTime => activateCallTime + activateResolvedTime;
}

/// Why an extension is not running (`ExtensionActivationError`), or the
/// errors it raised while running.
sealed class ExtensionRuntimeError {
  const ExtensionRuntimeError(this.message, this.stack);

  final String message;
  final String? stack;

  /// A one-line summary for the view.
  String get summary => message;
}

/// It failed to activate.
final class ExtensionActivationError extends ExtensionRuntimeError {
  const ExtensionActivationError(super.message, super.stack, {this.missing});

  /// `MissingExtensionDependency.dependency`.
  final String? missing;
}

/// It raised an error while running (`$onExtensionRuntimeError`).
final class ExtensionRuntimeException extends ExtensionRuntimeError {
  const ExtensionRuntimeException(super.message, super.stack);
}

/// One extension of a running host (`IRuntimeExtension`).
final class RunningExtension {
  RunningExtension({
    required this.id,
    required this.name,
    required this.hostId,
    this.version = '',
    this.activationTimes,
  });

  final String id;
  final String name;

  /// Which host runs it (`window` for a local one).
  final String hostId;
  final String version;

  /// Set once it acted (`$onWillActivateExtension` marks it activating).
  ExtensionActivationTimes? activationTimes;

  /// It is being activated now.
  bool activating = false;

  /// It has a runtime error.
  final List<ExtensionRuntimeError> errors = [];

  ExtensionActivationError? get activationError =>
      errors.whereType<ExtensionActivationError>().firstOrNull;

  List<ExtensionRuntimeException> get runtimeErrors =>
      errors.whereType<ExtensionRuntimeException>().toList();

  /// `activationTimes ? syncTime : null` — null while activating.
  num? get syncTime => activationTimes?.syncTime;

  /// `status === 'activating'`.
  bool get isActivating => activating && activationTimes == null;
}

/// Every running extension of the app, as the "Running Extensions" view
/// shows them.
final class ExtensionRuntimeService extends ChangeNotifier {
  final Map<String, RunningExtension> _extensions = {};

  /// By extension id.
  List<RunningExtension> get extensions => _extensions.values.toList();

  /// As the view lists them (`elements.sort`): the slowest activation
  /// first, extensions without an activation time among them; then, for
  /// equal times, by name.
  List<RunningExtension> sorted() {
    final list = extensions;
    list.sort((a, b) {
      final aTime = a.syncTime;
      final bTime = b.syncTime;
      if (aTime == null && bTime == null) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      final byTime = bTime.compareTo(aTime);
      return byTime != 0
          ? byTime
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  /// The extensions that failed to activate or raised errors.
  List<RunningExtension> get withErrors =>
      [for (final extension in extensions) if (extension.errors.isNotEmpty) extension];

  RunningExtension? extension(String id) => _extensions[id];

  RunningExtension _of(String id, String name, String hostId) =>
      _extensions[id] ??= RunningExtension(
        id: id,
        name: name.isNotEmpty ? name : id,
        hostId: hostId,
      );

  /// `$onWillActivateExtension`.
  void willActivate(String id, String name, String hostId) {
    final extension = _of(id, name, hostId);
    extension.activating = true;
    notifyListeners();
  }

  /// `$onDidActivateExtension`.
  void didActivate(
    String id,
    String name,
    String hostId, {
    required num codeLoadingTime,
    required num activateCallTime,
    required num activateResolvedTime,
    required ExtensionActivationReason reason,
  }) {
    final extension = _of(id, name, hostId);
    extension.activating = false;
    extension.activationTimes = ExtensionActivationTimes(
      codeLoadingTime: codeLoadingTime,
      activateCallTime: activateCallTime,
      activateResolvedTime: activateResolvedTime,
      reason: reason,
    );
    notifyListeners();
  }

  /// `$onExtensionActivationError`.
  void activationError(String id, String name, String hostId, ExtensionRuntimeError error) {
    final extension = _of(id, name, hostId);
    extension.activating = false;
    extension.errors.add(error);
    notifyListeners();
  }

  /// `$onExtensionRuntimeError`.
  void runtimeError(
    String id,
    String name,
    String hostId,
    ExtensionRuntimeError error,
  ) {
    _of(id, name, hostId).errors.add(error);
    notifyListeners();
  }

  /// Forgets a host's extensions as it ends.
  void removeHost(String hostId) {
    _extensions.removeWhere((_, extension) => extension.hostId == hostId);
    notifyListeners();
  }

  /// Forgets what an extension raised, so the view can be cleared.
  void clearErrors(String id) {
    _extensions[id]?.errors.clear();
    notifyListeners();
  }
}

/// A `SerializedError` as the app reads it.
({String message, String? stack}) serializedError(Object? data) {
  if (data is Map) {
    final message = data['message'];
    final stack = data['stack'];
    return (
      message: message is String && message.isNotEmpty
          ? message
          : '${data['name'] ?? 'Error'}',
      stack: stack is String ? stack : null,
    );
  }
  return (message: '$data', stack: null);
}
