/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadPower.ts with the answers of
// src/vs/workbench/services/power/browser/powerService.ts
// (`BrowserPowerService`): BaoCode has no access to the system's power
// state, so it answers as VS Code for the Web does — idle state and
// thermal state `unknown`, idle time 0, not on battery, power save
// blockers not started (-1, false) — and never fires the power events.

import 'package:bao_exthost/bao_exthost.dart';

import 'main_thread_context.dart';

final class MainThreadPower extends MainThreadPowerUnsupported {
  const MainThreadPower();

  static RpcActor customer(MainThreadContext context) =>
      MainThreadPowerActor(const MainThreadPower());

  @override
  Future<String> $getSystemIdleState(num idleThreshold) async => 'unknown';

  @override
  Future<num> $getSystemIdleTime() async => 0;

  @override
  Future<String> $getCurrentThermalState() async => 'unknown';

  @override
  Future<bool> $isOnBatteryPower() async => false;

  @override
  Future<num> $startPowerSaveBlocker(String type) async => -1;

  @override
  Future<bool> $stopPowerSaveBlocker(num id) async => false;

  @override
  Future<bool> $isPowerSaveBlockerStarted(num id) async => false;
}
