/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/progress/browser/progressService.ts
// (`withProgress` by location; `withWindowProgress`: the stack, 150ms
// before it shows and at least 150ms shown, `<title>: <message>` with the
// source in the tooltip; `withNotificationProgress`: title and message,
// percentages from increments, Cancel and the buttons, a delay or at least
// 800ms shown, the window progress while the notification is hidden;
// `withCompositeProgress`/`showOnActivityBar` for views and view
// containers) and src/vs/platform/progress/common/progress.ts.
//
// Deviations: a view or view container id is not checked against the
// registered views (the views show the progress of any id they have);
// `ProgressLocation.Dialog` is not sent by extension hosts and is
// rejected; no Do Not Disturb filter.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../ide/ide_notifications.dart';
import '../../l10n/l10n.dart';

/// `ProgressLocation`.
abstract final class ExtensionProgressLocation {
  static const explorer = 1;
  static const scm = 3;
  static const extensions = 5;
  static const window = 10;
  static const notification = 15;
  static const dialog = 20;

  /// The view containers of the numbered locations.
  static const explorerContainer = 'workbench.view.explorer';
  static const scmContainer = 'workbench.scm';
  static const extensionsContainer = 'workbench.view.extensions';
}

/// `IProgressStep`.
typedef ExtensionProgressStep = ({String? message, num? increment, num? total});

ExtensionProgressStep progressStepFromJson(Map<String, Object?> json) => (
  message: json['message'] as String?,
  increment: json['increment'] as num?,
  total: json['total'] as num?,
);

/// What the status bar shows for window progress (`status.progress`).
typedef ExtensionWindowProgressEntry = ({
  String text,
  String tooltip,

  /// `notifications.showList` for a notification's window progress.
  String? command,
});

/// A view's or view container's progress (`IProgressIndicator`): infinite
/// when [total] is null, else [worked] of it.
final class ExtensionCompositeProgress {
  const ExtensionCompositeProgress({this.total, this.worked = 0, this.title});

  final num? total;
  final num worked;
  final String? title;

  bool get infinite => total == null;
}

/// A running progress of an extension: report steps, then [done].
abstract interface class ExtensionProgressTask {
  void report(ExtensionProgressStep step);
  void done();
}

final class _Task implements ExtensionProgressTask {
  _Task(this._onReport);

  final void Function(ExtensionProgressStep step) _onReport;
  final _done = Completer<void>();
  ExtensionProgressStep? step;

  Future<void> get finished => _done.future;
  bool get isDone => _done.isCompleted;

  @override
  void report(ExtensionProgressStep step) {
    if (isDone) return;
    this.step = step;
    _onReport(step);
  }

  @override
  void done() {
    if (!_done.isCompleted) _done.complete();
  }
}

final class _WindowTask {
  _WindowTask(this.title, this.source, this.command);

  final String? title;
  final String? source;
  final String? command;
  String? message;
}

/// The progress the extensions show: in notifications, in the status bar
/// and on views.
final class ExtensionProgressService extends ChangeNotifier {
  ExtensionProgressService({
    required this.notifications,
    AppLocalizations Function()? l10n,
    this.windowProgressDelay = const Duration(milliseconds: 150),
    this.minWindowProgressShown = const Duration(milliseconds: 150),
    this.minNotificationShown = const Duration(milliseconds: 800),
    this.activityProgressDelay = const Duration(milliseconds: 300),
    this.minActivityProgressShown = const Duration(milliseconds: 300),
  }) : _l10n = l10n ?? (() => englishLocalizations);

  final IdeNotifications notifications;
  final AppLocalizations Function() _l10n;

  /// How long window progress waits before it shows, and how long it stays
  /// (upstream's 150ms both).
  final Duration windowProgressDelay;
  final Duration minWindowProgressShown;

  /// How long a notification progress that was not delayed stays, so it
  /// does not flash up and away (upstream's 800ms).
  final Duration minNotificationShown;

  /// How long a view's activity badge waits before it shows, and stays
  /// (upstream's 300ms both).
  final Duration activityProgressDelay;
  final Duration minActivityProgressShown;

  final List<_WindowTask> _windowStack = [];
  final Map<String, List<ExtensionCompositeProgress>> _composites = {};
  final Map<String, int> _activity = {};
  bool _disposed = false;

  /// The status bar's progress entry; null when none shows.
  ExtensionWindowProgressEntry? get windowEntry {
    for (final task in _windowStack) {
      final title = task.title;
      final message = task.message;
      final source = task.source;
      String text;
      String tooltip;
      if (title != null && title.isNotEmpty && message != null &&
          message.isNotEmpty) {
        text = '$title: $message';
        tooltip = source == null ? text : '[$source] $title: $message';
      } else if (title != null && title.isNotEmpty) {
        text = title;
        tooltip = source == null ? text : '[$source]: $title';
      } else if (message != null && message.isNotEmpty) {
        text = message;
        tooltip = source == null ? text : '[$source]: $message';
      } else {
        continue;
      }
      return (
        text: text,
        tooltip: _stripIcons(tooltip).trim(),
        command: task.command,
      );
    }
    return null;
  }

  /// The progress of a view or view container [id] (the newest).
  ExtensionCompositeProgress? progressOf(String id) => _composites[id]?.last;

  /// Whether the activity bar shows progress on view container [id].
  bool hasActivityProgress(String id) => (_activity[id] ?? 0) > 0;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// `withProgress` for an extension: [location] a `ProgressLocation` or a
  /// view or view container id; [onCancel] gets the button's index (null
  /// for Cancel). Throws [ArgumentError] for a location it cannot show.
  ExtensionProgressTask start({
    required Object location,
    String? title,
    String? source,
    num? total,
    Object? cancellable,
    List<String> buttons = const [],
    bool urgent = false,
    Duration? delay,
    void Function(int? choice)? onCancel,
    List<IdeNotificationAction> secondaryActions = const [],
  }) {
    switch (location) {
      case final String id:
        return _composite(id, title, delay);
      case ExtensionProgressLocation.notification:
        return _notification(
          title: title,
          source: source,
          cancellable: cancellable,
          buttons: buttons,
          urgent: urgent,
          silent: false,
          delay: delay,
          onCancel: onCancel,
          secondaryActions: secondaryActions,
        );
      case ExtensionProgressLocation.window:
        // Without a command, a silent notification: in the status bar
        // first, brought to the front by a click.
        return _notification(
          title: title,
          source: source,
          cancellable: cancellable,
          buttons: buttons,
          urgent: false,
          silent: true,
          // The window progress a Window location shows carries its
          // source; the one a notification falls back to does not
          // (upstream's `createWindowProgress` passes none).
          windowSource: source,
          delay: delay ?? const Duration(milliseconds: 150),
          onCancel: onCancel,
          secondaryActions: secondaryActions,
        );
      case ExtensionProgressLocation.explorer:
        return _composite(
          ExtensionProgressLocation.explorerContainer,
          title,
          delay,
        );
      case ExtensionProgressLocation.scm:
        return _composite(ExtensionProgressLocation.scmContainer, title, delay);
      case ExtensionProgressLocation.extensions:
        return _composite(
          ExtensionProgressLocation.extensionsContainer,
          title,
          delay,
        );
      default:
        throw ArgumentError('Bad progress location: $location');
    }
  }

  // --- Window --------------------------------------------------------------

  /// `withWindowProgress`: shows after its delay, for at least its
  /// minimum.
  void _windowProgress(
    _WindowTask task,
    Future<void> finished,
  ) {
    var shown = false;
    void show() {
      shown = true;
      _windowStack.insert(0, task);
      _changed();
      unawaited(
        Future.wait([Future<void>.delayed(minWindowProgressShown), finished])
            .whenComplete(() {
              _windowStack.remove(task);
              _changed();
            }),
      );
    }

    if (windowProgressDelay <= Duration.zero) {
      show();
      return;
    }
    final timer = Timer(windowProgressDelay, show);
    unawaited(
      finished.whenComplete(() {
        if (!shown) timer.cancel();
      }),
    );
  }

  // --- Notification --------------------------------------------------------

  ExtensionProgressTask _notification({
    required String? title,
    required String? source,
    required Object? cancellable,
    required List<String> buttons,
    required bool urgent,
    required bool silent,
    String? windowSource,
    required Duration? delay,
    required void Function(int? choice)? onCancel,
    required List<IdeNotificationAction> secondaryActions,
  }) {
    IdeNotification? handle;
    Timer? showTimer;
    String? titleAndMessage;
    num? worked;
    Completer<void>? windowProgress;
    _WindowTask? windowTask;
    late final _Task task;

    void cancel([int? choice]) {
      onCancel?.call(choice);
      task.done();
    }

    void stopWindowProgress() {
      windowProgress?.complete();
      windowProgress = null;
      windowTask = null;
    }

    void startWindowProgress() {
      stopWindowProgress();
      final done = windowProgress = Completer<void>();
      final window = windowTask = _WindowTask(
        title == null ? null : _plainLinks(title),
        windowSource,
        'notifications.showList',
      );
      final message = task.step?.message;
      if (message != null) window.message = _plainLinks(message);
      _windowProgress(window, done.future);
    }

    void visibilityChanged() {
      final current = handle;
      if (current == null) return;
      final visible = notifications.centerVisible ||
          notifications.isToast(current);
      if (!visible && !task.isDone) {
        if (windowProgress == null) startWindowProgress();
      } else {
        stopWindowProgress();
      }
    }

    IdeNotificationProgress progressFor(num? increment) =>
        increment != null && increment >= 0
        ? IdeNotificationProgress(math.min(worked ?? 0, 100).toDouble())
        : const IdeNotificationProgress.infinite();

    IdeNotification create(String message, num? increment) {
      final l10n = _l10n();
      final primary = <IdeNotificationAction>[
        for (final (index, button) in buttons.indexed)
          IdeNotificationAction(button, () => cancel(index)),
        if (cancellable == true || cancellable is String)
          IdeNotificationAction(
            cancellable is String ? cancellable : l10n.commonCancel,
            cancel,
          ),
      ];
      final notification = notifications.notify(
        IdeSeverity.info,
        _stripIcons(message),
        source: source,
        primary: primary,
        secondary: secondaryActions,
        sticky: urgent,
        silent: silent,
        progress: progressFor(increment),
        onClose: () {
          notifications.removeListener(visibilityChanged);
          stopWindowProgress();
        },
      );
      notifications.addListener(visibilityChanged);
      // A silent progress has no toast to hide: its window progress shows
      // at once (upstream's `onVisibilityChange(false)`).
      if (silent) startWindowProgress();
      return notification;
    }

    void update(ExtensionProgressStep? step) {
      if (step?.message != null && title != null) {
        titleAndMessage = '$title: ${step!.message}';
      } else {
        titleAndMessage = title ?? step?.message;
      }
      if (step?.increment case final increment?) {
        worked = (worked ?? 0) + increment;
      }
      final message = titleAndMessage;
      if (handle == null && message != null) {
        if (delay != null && delay > Duration.zero) {
          showTimer ??= Timer(delay, () {
            if (task.isDone) return;
            handle = create(titleAndMessage!, step?.increment ?? worked);
          });
        } else {
          handle = create(message, step?.increment);
        }
      }
      final current = handle;
      if (current != null) {
        notifications.update(
          current,
          message: message == null ? null : _stripIcons(message),
          progress: step?.increment != null
              ? progressFor(step!.increment)
              : null,
        );
      }
      final window = windowTask;
      if (window != null && step?.message != null) {
        window.message = _plainLinks(step!.message!);
        _changed();
      }
    }

    task = _Task(update);
    update(null);
    final started = DateTime.now();
    unawaited(
      task.finished.then((_) async {
        if(delay == null || delay <= Duration.zero) {
          // Shown for a minimum, so it does not flash up and away.
          final shown = DateTime.now().difference(started);
          if (shown < minNotificationShown) {
            await Future<void>.delayed(minNotificationShown - shown);
          }
        }
        showTimer?.cancel();
        final current = handle;
        if (current != null) notifications.close(current);
        stopWindowProgress();
      }),
    );
    return task;
  }

  // --- Views and view containers ------------------------------------------

  ExtensionProgressTask _composite(String id, String? title, Duration? delay) {
    var progress = ExtensionCompositeProgress(title: title);
    var shown = false;
    void show() {
      if (shown) return;
      shown = true;
      (_composites[id] ??= []).add(progress);
      _changed();
    }

    void replace(ExtensionCompositeProgress next) {
      final list = _composites[id];
      final index = list?.indexOf(progress) ?? -1;
      progress = next;
      if (index >= 0) {
        list![index] = next;
        _changed();
      }
    }

    final showTimer = delay != null && delay > Duration.zero
        ? Timer(delay, show)
        : null;
    if (showTimer == null) show();
    // The activity bar's progress badge, after 300ms (or the delay), for
    // at least 300ms.
    var activityShown = false;
    DateTime? activitySince;
    final activityTimer = Timer(
      delay != null && delay > Duration.zero ? delay : activityProgressDelay,
      () {
        activityShown = true;
        activitySince = DateTime.now();
        _activity[id] = (_activity[id] ?? 0) + 1;
        _changed();
      },
    );

    final task = _Task((step) {
      final increment = step.increment;
      if (increment != null) {
        replace(
          ExtensionCompositeProgress(
            total: step.total ?? progress.total ?? 100,
            worked: progress.worked + increment,
            title: title,
          ),
        );
      }
    });
    unawaited(
      task.finished.then((_) async {
        showTimer?.cancel();
        activityTimer.cancel();
        final list = _composites[id];
        if (list != null && list.remove(progress) && list.isEmpty) {
          _composites.remove(id);
        }
        _changed();
        if (activityShown) {
          final since = DateTime.now().difference(activitySince!);
          if (since < minActivityProgressShown) {
            await Future<void>.delayed(minActivityProgressShown - since);
          }
          final count = (_activity[id] ?? 1) - 1;
          if (count <= 0) {
            _activity.remove(id);
          } else {
            _activity[id] = count;
          }
          _changed();
        }
      }),
    );
    return task;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final _icons = RegExp(r'\$\([a-z0-9-]+(~[a-z]+)?\)');

/// `stripIcons`.
String _stripIcons(String text) =>
    text.replaceAll(_icons, '').replaceAll(RegExp(r'  +'), ' ');

/// `parseLinkedText(text).toString()`: Markdown links as their labels.
String _plainLinks(String text) => text.replaceAllMapped(
  RegExp(r'\[([^\]]*)\]\(((?:https?|command|file):[^\)\s]*)(?: "[^"]*")?\)'),
  (match) => match[1]!,
);
