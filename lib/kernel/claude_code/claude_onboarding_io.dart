import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

import '../../platform/app_paths.dart';
import 'claude_environment.dart';

/// Checked at app startup, before any session starts. An existing true
/// flag needs no write; the rest of Claude Code's state is kept.
Future<bool> prepareClaudeOnboarding({Map<String, String>? environment}) async {
  Directory? aside;
  try {
    final env = environment ?? await ClaudeEnvironment.of();
    final home = AppPaths.home(env);
    final config = [
      env[ClaudeEnvironment.dataPathVariable],
      env['CLAUDE_CONFIG_DIR'],
    ].whereType<String>().where((dir) => dir.isNotEmpty).firstOrNull;
    final String path;
    if (config != null) {
      if (!p.isAbsolute(config)) {
        throw const FormatException('Claude Code config directory is relative');
      }
      path = home.isNotEmpty && p.equals(config, p.join(home, '.claude'))
          ? p.join(home, '.claude.json')
          : p.join(config, '.claude.json');
    } else {
      if (home.isEmpty || !p.isAbsolute(home)) return false;
      path = p.join(home, '.claude.json');
    }

    final source = File(path);
    final type = await FileSystemEntity.type(path, followLinks: false);
    // Replace a link's target, not the link itself.
    final file = type == FileSystemEntityType.link
        ? File(await source.resolveSymbolicLinks())
        : source;
    final existing = type != FileSystemEntityType.notFound;
    final text = existing ? await file.readAsString() : null;
    final decoded = text == null ? <String, Object?>{} : jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Claude Code config must be a JSON object');
    }
    const flag = 'hasCompletedOnboarding';
    if (decoded[flag] == true) return false;
    if (decoded.containsKey(flag) && decoded[flag] != false) {
      throw const FormatException('hasCompletedOnboarding must be a boolean');
    }
    decoded[flag] = true;
    final mode = existing ? (await file.stat()).mode & 0x1ff : 0x180;

    await file.parent.create(recursive: true);
    aside = await file.parent.createTemp('.baocode-onboarding-');
    final replacement = File(p.join(aside.path, '.claude.json'));
    await replacement.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(decoded)}\n',
      flush: true,
    );
    if (!Platform.isWindows) {
      final result = await Process.run('/bin/chmod', [
        mode.toRadixString(8),
        replacement.path,
      ]);
      if (result.exitCode != 0) {
        throw FileSystemException(
          'Could not preserve config permissions',
          path,
        );
      }
    }
    // Claude Code can rewrite this file too. Do not replace a newer copy.
    final currentType = await FileSystemEntity.type(
      file.path,
      followLinks: false,
    );
    if (existing) {
      if (currentType != FileSystemEntityType.file ||
          await file.readAsString() != text) {
        return false;
      }
    } else if (currentType != FileSystemEntityType.notFound) {
      return false;
    }
    await replacement.rename(file.path);
    return true;
  } on FormatException catch (error) {
    // JSON errors can include a source excerpt containing credentials.
    debugPrint('Claude Code onboarding: ${error.message}');
    return false;
  } on Object catch (error) {
    debugPrint('Claude Code onboarding: $error');
    return false;
  } finally {
    if (aside != null) {
      try {
        await aside.delete(recursive: true);
      } on FileSystemException catch (error) {
        debugPrint('Claude Code onboarding cleanup: $error');
      }
    }
  }
}
