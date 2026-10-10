/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadTheming.ts: the color theme's
// type (`light`, `dark`, `hcDark`, `hcLight`) as the session starts and
// whenever the theme changes.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import '../../theme/workbench_theme.dart';
import 'main_thread_context.dart';

final class MainThreadTheming extends MainThreadThemingUnsupported {
  MainThreadTheming(
    this._themeType,
    this._proxy, {
    required Listenable changes,
    MainThreadContext? context,
  }) {
    var last = _themeType();
    void changed() {
      final type = _themeType();
      if (type == last) return;
      last = type;
      unawaited(_proxy.$onColorThemeChange(type).catchError((Object _) {}));
    }

    changes.addListener(changed);
    context?.onDispose(() => changes.removeListener(changed));
    unawaited(_proxy.$onColorThemeChange(last).catchError((Object _) {}));
  }

  final String Function() _themeType;
  final ExtHostThemingProxy _proxy;

  static RpcActor customer(MainThreadContext context) {
    final theme =
        context.maybeService<WorkbenchThemeService>() ??
        WorkbenchThemeService.instance;
    return MainThreadThemingActor(
      MainThreadTheming(
        () => theme.colors.type.value,
        ExtHostThemingProxy(context.rpc),
        changes: theme,
        context: context,
      ),
    );
  }
}
