import 'dart:convert';

import 'package:bao_remote/lsp.dart';
import 'package:flutter/services.dart';

export 'package:bao_remote/lsp.dart' show MasonPackage, MasonRegistry;

/// The registry bundled as [MasonRegistry.assetPath].
Future<MasonRegistry> loadMasonRegistry({AssetBundle? bundle}) async =>
    MasonRegistry.fromJson(
      jsonDecode(
        await (bundle ?? rootBundle).loadString(MasonRegistry.assetPath),
      ) as Map<String, Object?>,
    );
