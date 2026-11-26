import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../platform/app_paths.dart';
import '../platform/data_dir.dart';

/// The conversation a new user first sees: the showcase's turns, kept as
/// Claude Code keeps a session (tool/welcome_demo/export_test.dart writes
/// them) and read as any other, nothing run. In [Welcome.folder], a project
/// made for them; what they send there starts a conversation of their own.
abstract final class WelcomeDemo {
  /// Where its turns were played: put in place of, as it is set up, the
  /// folder the user has it in.
  static const folder = '/BAOCODE_WELCOME';

  /// Its id: not one Claude Code keeps, so never resumed nor deleted there.
  static const sessionId = 'baocode-welcome-demo';

  /// The languages it is written in, the first the one for any other.
  static const locales = ['en', 'zh'];

  static String asset(String locale) => 'assets/welcome/demo.$locale.jsonl';

  /// [locale]'s, else the first of [locales].
  static String localeFor(String localeName) {
    final language = localeName.split(RegExp('[_-]')).first;
    return locales.contains(language) ? language : locales.first;
  }

  /// [text], as exported, with [folder] in place of [WelcomeDemo.folder]:
  /// within JSON strings, so spelled as one (a Windows path's backslashes).
  static String place(String text, String folder) {
    final spelled = jsonEncode(folder);
    return text.replaceAll(
      WelcomeDemo.folder,
      spelled.substring(1, spelled.length - 1),
    );
  }
}

/// Sets up what a new user first sees: a folder to work in, and the demo
/// conversation kept where it is read from.
abstract class Welcome {
  const Welcome();

  /// `~/BaoCode`, on this machine.
  factory Welcome.io() = _IoWelcome;

  /// The folder new users start in, made if it was not.
  Future<String> folder();

  /// The demo's file, written for [folder] in [localeName]'s language;
  /// null where it could not be.
  Future<String?> demo(String folder, String localeName);
}

class _IoWelcome extends Welcome {
  _IoWelcome();

  @override
  Future<String> folder() async {
    final dir = Directory(
      p.join(AppPaths.home(Platform.environment), 'BaoCode'),
    );
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> demo(String folder, String localeName) async {
    try {
      final locale = WelcomeDemo.localeFor(localeName);
      final text = await rootBundle.loadString(WelcomeDemo.asset(locale));
      final file = File(
        p.join(DataDirectory.current.stateDir, 'welcome', 'demo.$locale.jsonl'),
      );
      await file.parent.create(recursive: true);
      await file.writeAsString(WelcomeDemo.place(text, folder));
      return file.path;
    } on Object {
      return null;
    }
  }
}
