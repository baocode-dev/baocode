/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/output/browser/outputServices.ts (`OutputService`:
// channels, the active channel, `showChannel`, a disposed active channel
// replaced by the first one while the view shows, `getLogLevel`/
// `setLogLevel` of log channels, `canSetLogLevel`),
// src/vs/workbench/api/browser/mainThreadOutputService.ts (the channel id
// pool, `setVisibleChannel`, `$reveal`, `$close`),
// src/vs/workbench/contrib/logs/common/logs.contribution.ts
// (`LogOutputChannels`: a log channel for each registered logger that is
// not hidden; id, label, extension), src/vs/platform/log/common/log.ts
// (`AbstractLoggerService`: registered loggers, visibility, per-logger and
// default log levels, `createLogger`'s id), and
// src/vs/workbench/api/browser/mainThreadConsole.ts / mainThreadErrors.ts
// (what the extension host's console and errors become).
//
// Deviations: one service per workspace (upstream's id pool is per
// window); loggers' `when` and `group` are not evaluated (extensions'
// loggers have neither); `workbench.view.showQuietly` is not read; the
// active channel is not stored across runs; the extension host's console
// goes to an "Extension Host" channel of the panel (and its errors to the
// app's error log) instead of the developer tools.

import 'dart:async';
import 'dart:collection';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import '../../host/init_data.dart' show ExtHostLogLevel;
import 'extension_host_console.dart';
import 'extension_output_channel.dart';
import 'output_file_tailer.dart';
import 'output_log_writer.dart';

export '../../host/init_data.dart' show ExtHostLogLevel;
export 'extension_output_channel.dart';

/// What [ExtensionOutputService] reports to the app's error log: the
/// signature of `ErrorLog.record` (lib/platform/error_log.dart).
typedef ExtensionErrorRecorder =
    void Function(
      Object error,
      StackTrace? stack, {
      required String source,
      String? context,
    });

/// A logger the extension host registered (`ILoggerResource`).
final class ExtensionLoggerResource {
  ExtensionLoggerResource({
    required this.resource,
    required this.id,
    this.name,
    this.logLevel,
    this.hidden = false,
    this.when,
    this.extensionId,
  });

  /// `UriDto<ILoggerResource>` as `$registerLogger` sends it.
  factory ExtensionLoggerResource.fromJson(Map<String, Object?> json) {
    final level = json['logLevel'];
    return ExtensionLoggerResource(
      resource: VsUri.revive((json['resource']! as Map).cast()),
      id: '${json['id']}',
      name: json['name'] as String?,
      logLevel: level is int && level >= 0 && level <= 5
          ? ExtHostLogLevel.values[level]
          : null,
      hidden: json['hidden'] == true,
      when: json['when'] as String?,
      extensionId: json['extensionId'] as String?,
    );
  }

  final VsUri resource;
  final String id;
  final String? name;

  /// Set for this logger; null: the default.
  ExtHostLogLevel? logLevel;
  bool hidden;
  final String? when;
  final String? extensionId;
}

/// A workspace's output channels and the extension host's loggers, as the
/// Output panel shows them.
final class ExtensionOutputService extends ChangeNotifier {
  ExtensionOutputService({
    this.recordError,
    this.onRevealPanel,
    this.onClosePanel,
    String extensionHostLabel = 'Extension Host',
    this.defaultLogLevel = ExtHostLogLevel.info,
    this.maxChannelBytes = OutputFileTailer.defaultMaxBytes,
    this.pollInterval = const Duration(milliseconds: 500),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    extensionHostChannel = ExtensionOutputChannel.memory(
      id: extensionHostChannelId,
      label: extensionHostLabel,
      maxBytes: maxChannelBytes,
    );
    _add(extensionHostChannel);
    panelVisible.addListener(_onVisibility);
  }

  /// The id of the channel of the extension host's console and errors.
  static const extensionHostChannelId = 'extHostConsole';

  /// Where errors of the extension host are recorded (`ErrorLog.record`).
  final ExtensionErrorRecorder? recordError;

  /// Asks the workbench to show the Output panel (`$reveal`, a channel's
  /// `show()`): it then sets [panelVisible]. When null, [panelVisible] is
  /// set here.
  void Function(bool preserveFocus)? onRevealPanel;

  /// Asks the workbench to hide the Output panel (`$close`).
  VoidCallback? onClosePanel;

  final int maxChannelBytes;
  final Duration pollInterval;
  final DateTime Function() _clock;

  /// Whether the Output panel shows: set by the workbench.
  final panelVisible = ValueNotifier<bool>(false);

  /// Whether the panel scrolls to new output (not `scrollLock`).
  final followTail = ValueNotifier<bool>(true);

  /// The levels a log channel's lines are shown at (the view's filters).
  final shownLevels = ValueNotifier<Set<ExtHostLogLevel>>({
    ExtHostLogLevel.trace,
    ExtHostLogLevel.debug,
    ExtHostLogLevel.info,
    ExtHostLogLevel.warning,
    ExtHostLogLevel.error,
  });

  late final ExtensionOutputChannel extensionHostChannel;

  final _channels = <String, ExtensionOutputChannel>{};
  final _idPool = <String, int>{};
  ExtensionOutputChannel? _active;
  bool _disposed = false;

  /// All channels, in the order they came.
  List<ExtensionOutputChannel> get channels => List.unmodifiable(
    _channels.values,
  );

  ExtensionOutputChannel? channel(String id) => _channels[id];

  ExtensionOutputChannel? get activeChannel => _active;

  /// The channel the extension host is told is visible.
  String? get visibleChannelId => panelVisible.value ? _active?.id : null;

  // --- Channels ---------------------------------------------------------

  /// `$register`: an extension's channel whose content is [file]; its id
  /// (`extension-output-<extensionId>-#<n>-<label>`).
  String registerExtensionChannel(
    String label,
    VsUri file,
    String? languageId,
    String extensionId,
  ) {
    final count = (_idPool[extensionId] ?? 0) + 1;
    _idPool[extensionId] = count;
    final id = 'extension-output-$extensionId-#$count-$label';
    _add(
      ExtensionOutputChannel.file(
        id: id,
        label: label,
        file: file,
        log: false,
        languageId: languageId,
        extensionId: extensionId,
        maxBytes: maxChannelBytes,
        pollInterval: pollInterval,
      ),
    );
    return id;
  }

  /// A channel of the workbench's own (as Tasks), whose content is what
  /// is appended to it; the one there when [id] is registered already.
  ExtensionOutputChannel registerWorkbenchChannel(String id, String label) {
    final existing = _channels[id];
    if (existing != null) return existing;
    final channel = ExtensionOutputChannel.memory(
      id: id,
      label: label,
      log: false,
      maxBytes: maxChannelBytes,
    );
    _add(channel);
    return channel;
  }

  void _add(ExtensionOutputChannel channel) {
    final replaced = _channels[channel.id];
    _channels[channel.id] = channel;
    if (replaced != null) {
      replaced.dispose();
      if (_active == replaced) _active = null;
    }
    // `onDidRegisterChannel`: the first channel becomes the active one.
    if (_active == null) {
      _setActive(channel);
    } else {
      notifyListeners();
    }
  }

  /// `$update`: an append is read now when shown; a clear or a replace
  /// needs [till].
  void updateChannel(String id, OutputChannelUpdateMode mode, [int? till]) {
    final channel = _channels[id];
    if (channel == null) return;
    if (mode == OutputChannelUpdateMode.append) {
      channel.update(mode);
    } else if (till != null) {
      channel.update(mode, till);
    }
  }

  /// `showChannel`: makes [id] the active channel and shows the panel.
  void showChannel(String id, {bool preserveFocus = false}) {
    final channel = _channels[id];
    if (channel == null) return;
    if (_active != channel) _setActive(channel);
    final reveal = onRevealPanel;
    if (reveal != null) {
      reveal(preserveFocus);
    } else {
      panelVisible.value = true;
    }
  }

  /// The panel's channel dropdown.
  void setActiveChannel(String id) {
    final channel = _channels[id];
    if (channel != null && channel != _active) _setActive(channel);
  }

  /// `$close`: hides the panel when it shows [id].
  void closeChannel(String id) {
    if (!panelVisible.value || _active?.id != id) return;
    final close = onClosePanel;
    if (close != null) {
      close();
    } else {
      panelVisible.value = false;
    }
  }

  /// `$dispose`: removes the channel; when it was the active one, the
  /// first left takes its place while the panel shows (else none).
  void disposeChannel(String id) {
    final channel = _channels.remove(id);
    if (channel == null) return;
    channel.dispose();
    if (_active == channel) {
      final first = _channels.values.firstOrNull;
      _active = null;
      if (first != null && panelVisible.value) {
        _setActive(first);
        return;
      }
      _pushVisibleChannel();
    }
    notifyListeners();
  }

  /// Clear Output on the active channel.
  void clearActive() => _active?.clear();

  void _setActive(ExtensionOutputChannel? channel) {
    final previous = _active;
    _active = channel;
    previous?.setShown(false);
    _updateShown();
    _pushVisibleChannel();
    notifyListeners();
  }

  void _onVisibility() {
    if (panelVisible.value && _active == null && _channels.isNotEmpty) {
      _setActive(_channels.values.first);
      return;
    }
    _updateShown();
    _pushVisibleChannel();
  }

  void _updateShown() => _active?.setShown(panelVisible.value);

  // --- The extension host's view of it ----------------------------------

  final _visibleChannelListeners = <void Function(String?)>[];
  final _logLevelListeners = <void Function(ExtHostLogLevel, VsUri?)>[];
  String? _pushed;
  bool _pushedOnce = false;

  /// Calls [push] with the visible channel's id now and whenever it
  /// changes (`setVisibleChannel` → `$setVisibleChannel`); returns what
  /// stops it.
  VoidCallback addVisibleChannelListener(void Function(String? id) push) {
    _visibleChannelListeners.add(push);
    push(visibleChannelId);
    return () => _visibleChannelListeners.remove(push);
  }

  void _pushVisibleChannel() {
    final id = visibleChannelId;
    if (_pushedOnce && id == _pushed) return;
    _pushedOnce = true;
    _pushed = id;
    for (final push in List.of(_visibleChannelListeners)) {
      push(id);
    }
  }

  /// Calls [push] with each log level change: the default one (no
  /// resource), or a logger's (`onDidChangeLogLevel` → `$setLogLevel`);
  /// returns what stops it.
  VoidCallback addLogLevelListener(
    void Function(ExtHostLogLevel level, VsUri? resource) push,
  ) {
    _logLevelListeners.add(push);
    return () => _logLevelListeners.remove(push);
  }

  void _pushLogLevel(ExtHostLogLevel level, [VsUri? resource]) {
    for (final push in List.of(_logLevelListeners)) {
      push(level, resource);
    }
  }

  // --- Loggers ------------------------------------------------------------

  final _loggers = <VsUri, ExtensionLoggerResource>{};
  final _writers = <VsUri, OutputLogWriter>{};
  ExtHostLogLevel defaultLogLevel;

  Iterable<ExtensionLoggerResource> get registeredLoggers => _loggers.values;

  ExtensionLoggerResource? registeredLogger(VsUri resource) =>
      _loggers[resource];

  /// `registerLogger`: a logger already known only changes its
  /// visibility.
  void registerLogger(ExtensionLoggerResource logger) {
    final existing = _loggers[logger.resource];
    if (existing != null) {
      if (existing.hidden != logger.hidden) {
        setLoggerVisibility(logger.resource, !logger.hidden);
      }
      // A level the user set before the extension host restarted.
      final level = existing.logLevel;
      if (level != null && level != logger.logLevel) {
        _pushLogLevel(level, logger.resource);
      }
      return;
    }
    _loggers[logger.resource] = logger;
    if (!logger.hidden) _registerLogChannel(logger);
  }

  /// `deregisterLogger`.
  void deregisterLogger(VsUri resource) {
    final existing = _loggers.remove(resource);
    if (existing == null) return;
    unawaited(_writers.remove(resource)?.dispose());
    _deregisterLogChannel(existing);
  }

  /// `setVisibility`.
  void setLoggerVisibility(VsUri resource, bool visible) {
    final logger = _loggers[resource];
    if (logger == null || visible == !logger.hidden) return;
    logger.hidden = !visible;
    if (visible) {
      _registerLogChannel(logger);
    } else {
      _deregisterLogChannel(logger);
    }
  }

  void _registerLogChannel(ExtensionLoggerResource logger) {
    final existing = _channels[logger.id];
    if (existing != null && existing.file == logger.resource) return;
    _add(
      ExtensionOutputChannel.file(
        id: logger.id,
        label: logger.name ?? logger.id,
        file: logger.resource,
        log: true,
        extensionId: logger.extensionId,
        maxBytes: maxChannelBytes,
        pollInterval: pollInterval,
      ),
    );
  }

  void _deregisterLogChannel(ExtensionLoggerResource logger) =>
      disposeChannel(logger.id);

  /// `createLogger` for `$createLogger`: the extension host logs to
  /// [resource] through `$log`, written here.
  void createLogger(VsUri resource, Map<String, Object?>? options) {
    final level = switch (options?['logLevel']) {
      'always' => ExtHostLogLevel.trace,
      final int l when l >= 0 && l <= 5 => ExtHostLogLevel.values[l],
      _ => null,
    };
    final id = switch (options?['id']) {
      final String id => id,
      _ => stringHash(resource.toString(), 0).toRadixString(16),
    };
    if (!_writers.containsKey(resource) && resource.scheme == 'file') {
      _writers[resource] = OutputLogWriter(
        resource.fsPath(),
        level: level ?? logLevelOf(resource),
        always: options?['logLevel'] == 'always',
        donotUseFormatters: options?['donotUseFormatters'] == true,
        clock: _clock,
      );
    }
    registerLogger(
      ExtensionLoggerResource(
        resource: resource,
        id: id,
        name: options?['name'] as String?,
        logLevel: level,
        hidden: options?['hidden'] == true,
        when: options?['when'] as String?,
        extensionId: options?['extensionId'] as String?,
      ),
    );
  }

  /// Whether `$createLogger` made a logger for [resource].
  bool hasLogger(VsUri resource) => _writers.containsKey(resource);

  /// `$log`: `[level, message]` pairs.
  void log(VsUri resource, List<List<Object?>> messages) {
    final writer = _writers[resource];
    if (writer == null) {
      throw StateError('Create the logger before logging');
    }
    for (final message in messages) {
      if (message.length < 2) continue;
      final level = message[0];
      if (level is! int || level < 0 || level > 5) continue;
      writer.log(ExtHostLogLevel.values[level], '${message[1]}');
    }
  }

  /// `$flush`.
  Future<void> flushLogger(VsUri resource) {
    final writer = _writers[resource];
    if (writer == null) {
      throw StateError('Create the logger before flushing');
    }
    return writer.flush();
  }

  // --- Log levels -------------------------------------------------------

  /// `getLogLevel(resource)`.
  ExtHostLogLevel logLevelOf(VsUri resource) =>
      _loggers[resource]?.logLevel ?? defaultLogLevel;

  /// `setLogLevel(level)`: loggers without their own level follow.
  void setDefaultLogLevel(ExtHostLogLevel level) {
    defaultLogLevel = level;
    for (final MapEntry(:key, :value) in _writers.entries) {
      if (_loggers[key]?.logLevel == null) value.level = level;
    }
    _pushLogLevel(level);
    notifyListeners();
  }

  /// `setLogLevel(resource, level)`: the default level is stored as none.
  void setLogLevel(VsUri resource, ExtHostLogLevel level) {
    final logger = _loggers[resource];
    if (logger == null || level == logger.logLevel) return;
    logger.logLevel = level == defaultLogLevel ? null : level;
    _writers[resource]?.level = level;
    _pushLogLevel(level, resource);
    notifyListeners();
  }

  /// `canSetLogLevel`: log channels with a logger.
  bool canSetLogLevel(ExtensionOutputChannel channel) =>
      channel.log && channel.file != null;

  /// `getLogLevel(channel)`; null for a channel that is not a log's.
  ExtHostLogLevel? channelLogLevel(ExtensionOutputChannel channel) {
    final file = channel.file;
    if (!channel.log || file == null) return null;
    return logLevelOf(file);
  }

  /// `setLogLevel(channel, level)`.
  void setChannelLogLevel(
    ExtensionOutputChannel channel,
    ExtHostLogLevel level,
  ) {
    final file = channel.file;
    if (channel.log && file != null) setLogLevel(file, level);
  }

  // --- The extension host's console and errors --------------------------

  /// `$logExtensionHostMessage`: to the Extension Host channel; errors to
  /// the error log too (`logRemoteEntryIfError`).
  void logExtensionHostMessage(Map<String, Object?> entry) {
    final parsed = RemoteConsoleEntry.fromJson(entry);
    _appendEntry(parsed.level, parsed.format('Extension Host'));
    final error = parsed.errorMessage;
    if (error != null) {
      recordError?.call(
        error,
        null,
        source: 'Extension Host',
        context: 'console.error',
      );
    }
  }

  /// `$onUnexpectedError`.
  void onUnexpectedError(Object? err) {
    final error = ExtensionHostError.fromWire(err);
    _appendEntry(ExtHostLogLevel.error, '[Extension Host] ${error.describe()}');
    final stack = error.frames;
    recordError?.call(
      error,
      stack == null ? null : StackTrace.fromString(stack),
      source: 'Extension Host',
    );
  }

  void _appendEntry(ExtHostLogLevel level, String message) {
    if (_disposed) return;
    final name = switch (level) {
      ExtHostLogLevel.trace => 'trace',
      ExtHostLogLevel.debug => 'debug',
      ExtHostLogLevel.warning => 'warning',
      ExtHostLogLevel.error => 'error',
      _ => 'info',
    };
    extensionHostChannel.append('${_timestamp()} [$name] $message\n');
  }

  String _timestamp() {
    final t = _clock();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
        '.${t.millisecond.toString().padLeft(3, '0')}';
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    panelVisible.removeListener(_onVisibility);
    for (final channel in _channels.values) {
      channel.dispose();
    }
    _channels.clear();
    for (final writer in _writers.values) {
      unawaited(writer.dispose());
    }
    _writers.clear();
    _visibleChannelListeners.clear();
    _logLevelListeners.clear();
    panelVisible.dispose();
    followTail.dispose();
    shownLevels.dispose();
    super.dispose();
  }
}

/// `stringHash` (base/common/hash.ts): what `createLogger` names a logger
/// without an id by.
int stringHash(String s, int hashVal) {
  int numberHash(int val, int initial) =>
      (((initial << 5) - initial) + val).toSigned(32);
  var h = numberHash(149417, hashVal);
  for (final unit in s.codeUnits) {
    h = numberHash(unit, h);
  }
  return h;
}
