// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/services/LogService.ts (c58ea36).
//
// Without a logger option, upstream logs to the console; here `print`, one
// line per message with the optional params appended.

import '../lifecycle.dart';
import 'services.dart';

typedef _LogType = void Function(String message, List<Object?> optionalParams);

const Map<String, int> _optionsKeyToLogLevel = <String, int>{
  'trace': LogLevelEnum.trace,
  'debug': LogLevelEnum.debug,
  'info': LogLevelEnum.info,
  'warn': LogLevelEnum.warn,
  'error': LogLevelEnum.error,
  'off': LogLevelEnum.off,
};

const String _logPrefix = 'xterm.js: ';

void _console(String message, List<Object?> optionalParams) {
  // ignore: avoid_print
  print([message, ...optionalParams].join(' '));
}

class LogService extends Disposable implements ILogService {
  LogService(this._optionsService) {
    _updateLogLevel();
    register(
      _optionsService.onSpecificOptionChange<Object?>(
        'logLevel',
        (_) => _updateLogLevel(),
      ),
    );
  }

  final IOptionsService _optionsService;

  int _logLevel = LogLevelEnum.off;
  @override
  int get logLevel => _logLevel;

  void _updateLogLevel() {
    // Upstream's lookup of an unknown level is undefined, which no `<=`
    // comparison passes.
    _logLevel =
        _optionsKeyToLogLevel[_optionsService.rawOptions.logLevel] ??
        LogLevelEnum.off + 1;
  }

  List<Object?> _evalLazyOptionalParams(List<Object?> optionalParams) {
    return <Object?>[
      for (final param in optionalParams)
        param is Object? Function() ? param() : param,
    ];
  }

  void _log(_LogType type, String message, List<Object?> optionalParams) {
    type(
      (_optionsService.options.logger != null ? '' : _logPrefix) + message,
      _evalLazyOptionalParams(optionalParams),
    );
  }

  @override
  void trace(
    String message, [
    List<Object?> optionalParams = const <Object?>[],
  ]) {
    if (_logLevel <= LogLevelEnum.trace) {
      _log(
        _optionsService.options.logger?.trace ?? _console,
        message,
        optionalParams,
      );
    }
  }

  @override
  void debug(
    String message, [
    List<Object?> optionalParams = const <Object?>[],
  ]) {
    if (_logLevel <= LogLevelEnum.debug) {
      _log(
        _optionsService.options.logger?.debug ?? _console,
        message,
        optionalParams,
      );
    }
  }

  @override
  void info(
    String message, [
    List<Object?> optionalParams = const <Object?>[],
  ]) {
    if (_logLevel <= LogLevelEnum.info) {
      _log(
        _optionsService.options.logger?.info ?? _console,
        message,
        optionalParams,
      );
    }
  }

  @override
  void warn(
    String message, [
    List<Object?> optionalParams = const <Object?>[],
  ]) {
    if (_logLevel <= LogLevelEnum.warn) {
      _log(
        _optionsService.options.logger?.warn ?? _console,
        message,
        optionalParams,
      );
    }
  }

  @override
  void error(
    String message, [
    List<Object?> optionalParams = const <Object?>[],
  ]) {
    if (_logLevel <= LogLevelEnum.error) {
      _log(
        _optionsService.options.logger?.error ?? _console,
        message,
        optionalParams,
      );
    }
  }
}
