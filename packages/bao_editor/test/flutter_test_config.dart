import 'dart:async';

import 'package:bao_editor/textmate/textmate_syntax.dart';
import 'package:bao_editor/textmate/textmate_worker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'semantics_tree.dart';

/// Every test fails if its semantics updates would break the desktop
/// engines' accessibility tree (a copy of the app's check). Editors
/// tokenize TextMate grammars in the test's isolate, on its fake clock.
/// Each test reads assets afresh: the bundle caches futures, which answer
/// in the zone of the test that made them.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  checkDesktopSemantics();
  textMateWorkerLauncher = () async => TextMateInProcessWorker.create();
  setUp(rootBundle.clear);
  await testMain();
}
