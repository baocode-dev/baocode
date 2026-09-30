// No isolates on the web, and no Oniguruma either (textmate_worker.dart).

import 'textmate_worker.dart';

Future<TextMateWorkerChannel?> spawnTextMateWorker() async => null;
