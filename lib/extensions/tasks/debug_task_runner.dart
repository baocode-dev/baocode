/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A launch configuration's tasks: `preLaunchTask` run before the session
// (a background task until its problem matchers say it is ready, a task
// already busy until it is), what to do when it fails or leaves errors
// (`debug.onTaskErrors`: debug anyway, show the errors, abort, or ask and
// maybe remember), the wait notice of a slow one, and the error of a task
// that never says it is done; `postDebugTask` and the restart tasks run
// without the checks.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/browser/debugTaskRunner.ts.

import 'dart:async';
import 'dart:convert';

import 'package:bao_exthost/bao_exthost.dart';

import '../../debug/service/debug_host.dart';
import '../language/marker_service.dart';
import '../window/progress_service.dart';
import '../window/window_ports.dart';
import 'task_service.dart';
import 'tasks.dart';

/// `IRunnerTaskSummary`.
typedef RunnerTaskSummary = ({int? exitCode, bool cancelled});

/// What the runner needs of the window.
abstract interface class DebugTaskRunnerHost {
  Object? setting(String key);
  Future<void> updateUserSetting(String key, Object? value);
  ExtensionDialogs get dialogs;
  ExtensionProgressService? get progress;

  /// Opens the Problems view.
  void openProblems();

  /// The workspace's state (`StorageScope.WORKSPACE`).
  String? storedValue(String key);
  void store(String key, String value);
  Future<Object?> executeCommand(String id, [List<Object?> args = const []]);
}

/// `DebugTaskRunner`.
final class DebugTaskRunner {
  DebugTaskRunner({
    required this.tasks,
    required this.markers,
    required this.host,
  });

  final TaskService tasks;
  final MarkerService markers;
  final DebugTaskRunnerHost host;

  final _cancellations = <Completer<void>>{};

  static const _taskErrorChoiceKey = 'debug.taskerrorchoices';
  static const _debugAnywayLabel = 'Debug Anyway';
  static const _abortLabel = 'Abort';

  /// `cancel`: the tasks started so far are given up on (and terminated).
  void cancel() {
    for (final cancellation in [..._cancellations]) {
      if (!cancellation.isCompleted) cancellation.complete();
    }
    _cancellations.clear();
  }

  /// What the debug service calls: [task] (a label or a task identifier)
  /// in [root], its errors checked unless [checkErrors] is false.
  Future<TaskRunResult> run(
    VsUri? root,
    Object? task, {
    bool checkErrors = true,
  }) async {
    if (checkErrors) return runTaskAndCheckErrors(root, task);
    await runTask(root, task);
    return TaskRunResult.success;
  }

  /// `runTaskAndCheckErrors`.
  Future<TaskRunResult> runTaskAndCheckErrors(
    VsUri? root,
    Object? taskId,
  ) async {
    try {
      final summary = await runTask(root, taskId);
      if (summary != null && (summary.exitCode == null || summary.cancelled)) {
        // Debugging or the pre-launch task was cancelled.
        return TaskRunResult.failure;
      }
      final errorCount = taskId != null
          ? markers
                .read(
                  MarkerReadOptions(
                    severities: MarkerSeverity.error.value,
                    take: 2,
                  ),
                )
                .length
          : 0;
      final successExitCode = summary != null && summary.exitCode == 0;
      final failureExitCode = summary != null && summary.exitCode != 0;
      final onTaskErrors = (host.setting('debug') as Map?)?['onTaskErrors'];
      if (successExitCode ||
          onTaskErrors == 'debugAnyway' ||
          (errorCount == 0 && !failureExitCode)) {
        return TaskRunResult.success;
      }
      if (onTaskErrors == 'showErrors') {
        host.openProblems();
        return TaskRunResult.failure;
      }
      if (onTaskErrors == 'abort') return TaskRunResult.failure;

      final taskLabel = taskId is String
          ? taskId
          : taskId is Map
          ? '${taskId['name'] ?? ''}'
          : '';
      final message = errorCount > 1
          ? "Errors exist after running preLaunchTask '$taskLabel'."
          : errorCount == 1
          ? "Error exists after running preLaunchTask '$taskLabel'."
          : summary?.exitCode != null
          ? "The preLaunchTask '$taskLabel' terminated with exit code "
                '${summary!.exitCode}.'
          : "The preLaunchTask '$taskLabel' terminated.";
      final answer = await host.dialogs.prompt(
        severity: ExtensionSeverity.warning,
        message: message,
        buttons: const [_debugAnywayLabel, 'Show Errors'],
        cancel: _abortLabel,
        checkbox: 'Remember my choice in user settings',
      );
      final debugAnyway = answer.button == 0;
      final abort = answer.button == null;
      if (answer.checked) {
        await host.updateUserSetting(
          'debug.onTaskErrors',
          debugAnyway
              ? 'debugAnyway'
              : abort
              ? 'abort'
              : 'showErrors',
        );
      }
      if (abort) return TaskRunResult.failure;
      if (debugAnyway) return TaskRunResult.success;
      host.openProblems();
      return TaskRunResult.failure;
    } catch (error) {
      final message = _messageOf(error);
      final Map<String, Object?> choices;
      try {
        choices = (jsonDecode(
          host.storedValue(_taskErrorChoiceKey) ?? '{}',
        ) as Map).cast();
      } on Object {
        return TaskRunResult.failure;
      }
      int? choice;
      if (choices[message] case final int remembered) {
        choice = remembered;
      } else {
        final answer = await host.dialogs.prompt(
          severity: ExtensionSeverity.error,
          message: message,
          buttons: const [_debugAnywayLabel, 'Configure Task'],
          cancel: 'Cancel',
          checkbox: 'Remember my choice for this task',
        );
        // DebugAnyway 0, ConfigureTask 1, Cancel 2.
        choice = answer.button ?? 2;
        if (answer.checked) {
          choices[message] = choice;
          host.store(_taskErrorChoiceKey, jsonEncode(choices));
        }
      }
      if (choice == 1) {
        await host.executeCommand('workbench.action.tasks.configureTaskRunner');
      }
      return choice == 0 ? TaskRunResult.success : TaskRunResult.failure;
    }
  }

  static String _messageOf(Object error) => switch (error) {
    final TaskError e => e.message,
    final StateError e => e.message,
    final String s => s,
    _ => '$error',
  };

  /// `runTask`: null when there is no task or it ran already and is idle.
  Future<RunnerTaskSummary?> runTask(VsUri? root, Object? taskId) async {
    if (taskId == null) return null;
    if (root == null) {
      throw TaskError(
        "Task '${taskId is String ? taskId : (taskId as Map)['type']}' can "
        'not be referenced from a launch configuration that is in a '
        'different workspace folder.',
      );
    }
    final task = await tasks.getTask(root, taskId);
    if (task == null) {
      throw TaskError(
        taskId is String
            ? "Could not find the task '$taskId'."
            : 'Could not find the specified task.',
        code: 'taskNotFound',
      );
    }

    // A task without a problem matcher may never say it is done
    // (microsoft/vscode#35340).
    var taskStarted = false;
    String keyOf(Task t) => t.getKey() ?? t.getMapKey();
    final taskKey = keyOf(task);
    final subscriptions = <StreamSubscription<TaskEvent>>[];
    final timers = <Timer>[];
    ExtensionProgressTask? waiting;

    final inactive = Completer<RunnerTaskSummary?>();
    late final StreamSubscription<TaskEvent> inactiveSubscription;
    inactiveSubscription = tasks.onDidStateChange.listen((e) {
      // A background task goes inactive when it is safe to launch; one the
      // user terminates goes inactive too, after its process ended without
      // an exit code, which tells them apart.
      if ((e.kind == TaskEventKind.inactive ||
              (e.kind == TaskEventKind.processEnded && e.exitCode == null)) &&
          keyOf(e.task!) == taskKey) {
        unawaited(inactiveSubscription.cancel());
        taskStarted = true;
        if (!inactive.isCompleted) {
          inactive.complete(
            e.kind == TaskEventKind.processEnded
                ? (exitCode: e.exitCode, cancelled: false)
                : null,
          );
        }
      }
    });
    subscriptions.add(inactiveSubscription);

    late final StreamSubscription<TaskEvent> activeSubscription;
    activeSubscription = tasks.onDidStateChange.listen((e) {
      if ((e.kind == TaskEventKind.active ||
              e.kind == TaskEventKind.dependsOnStarted) &&
          keyOf(e.task!) == taskKey) {
        // A slow task that is active is fine: no error after the wait.
        unawaited(activeSubscription.cancel());
        taskStarted = true;
      }
    });
    subscriptions.add(activeSubscription);

    final result = Completer<RunnerTaskSummary?>();
    void resolve(RunnerTaskSummary? value) {
      if (!result.isCompleted) result.complete(value);
    }

    void reject(Object error) {
      if (!result.isCompleted) result.completeError(error);
    }

    var acquired = false;
    void didAcquireInput() {
      if (acquired) return;
      acquired = true;
      final background = task.configurationProperties.isBackground ?? false;
      timers.add(
        Timer(Duration(seconds: background ? 5 : 10), () {
          if (!taskStarted) {
            reject(
              TaskError(
                "The task '${taskId is String ? taskId : jsonEncode(taskId)}' "
                "has not exited and doesn't have a 'problemMatcher' defined. "
                'Make sure to define a problem matcher for watch tasks.',
              ),
            );
          }
        }),
      );
      final hideWarning =
          (host.setting('debug') as Map?)?['hideSlowPreLaunchWarning'] == true;
      if (!hideWarning) {
        timers.add(
          Timer(const Duration(seconds: 10), () {
            final progress = host.progress;
            if (progress == null || result.isCompleted) return;
            final canConfigure = task.isCustom || task.isConfiguring;
            waiting = progress.start(
              location: ExtensionProgressLocation.notification,
              title:
                  "Waiting for preLaunchTask '"
                  "${task.configurationProperties.name}'...",
              buttons: [
                _debugAnywayLabel,
                if (canConfigure) 'Configure Task',
                _abortLabel,
              ],
              onCancel: (choice) {
                if (choice == null) return;
                if (choice == 0) {
                  resolve((exitCode: 0, cancelled: false));
                } else {
                  resolve((exitCode: null, cancelled: true));
                  unawaited(
                    tasks.terminate(task).then((_) {}, onError: (_) {}),
                  );
                  if (canConfigure && choice == 1) {
                    unawaited(
                      host.executeCommand(
                        'workbench.action.tasks.configureTaskRunner',
                      ),
                    );
                  }
                }
              },
            );
          }),
        );
      }
    }

    late final StreamSubscription<TaskEvent> acquiredSubscription;
    acquiredSubscription = tasks.onDidStateChange.listen((e) {
      if (e.kind == TaskEventKind.acquiredInput && keyOf(e.task!) == taskKey) {
        unawaited(acquiredSubscription.cancel());
        didAcquireInput();
      }
    });
    subscriptions.add(acquiredSubscription);

    final cancellation = Completer<void>();
    _cancellations.add(cancellation);
    unawaited(
      cancellation.future.then((_) {
        resolve((exitCode: null, cancelled: true));
        unawaited(tasks.terminate(task).then((_) {}, onError: (_) {}));
      }),
    );

    Future<RunnerTaskSummary?> taskDone() async {
      if (tasks.getActiveTasks().any((t) => keyOf(t) == taskKey)) {
        didAcquireInput();
        // Busy: wait until it is not.
        if (tasks.getBusyTasks().any((t) => keyOf(t) == taskKey)) {
          taskStarted = true;
          return inactive.future;
        }
        // Running already and idle: nothing to do.
        return null;
      }
      final run = tasks.run(task);
      if (task.configurationProperties.isBackground ?? false) {
        unawaited(run.then((_) {}, onError: (Object _) {}));
        return inactive.future;
      }
      final summary = await run;
      return summary == null
          ? null
          : (exitCode: summary.exitCode, cancelled: false);
    }

    unawaited(
      taskDone().then((value) {
        taskStarted = true;
        resolve(value);
      }, onError: reject),
    );

    try {
      return await result.future;
    } finally {
      _cancellations.remove(cancellation);
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
      for (final timer in timers) {
        timer.cancel();
      }
      waiting?.done();
    }
  }
}
