import 'package:flutter/widgets.dart';

/// Where the display language setting is kept: VS Code keeps it as
/// argv.json's `locale`. [read] is synchronous, so the kept choice is known
/// before the first frame: load the store first.
abstract interface class LocaleStorage {
  /// The kept setting (as [AppLocale.setting]), or null for the system's.
  String? read();

  Future<void> write(String? locale);
}

/// A [LocaleStorage] that keeps the setting in memory, for tests and when
/// nothing is kept.
class MemoryLocaleStorage implements LocaleStorage {
  MemoryLocaleStorage([this._locale]);

  String? _locale;

  @override
  String? read() => _locale;

  @override
  Future<void> write(String? locale) async => _locale = locale;
}

/// The display language setting, with VS Code's `locale` values: null
/// follows the system, else [english] or [simplifiedChinese]. The app
/// rebuilds on it, so a change applies at once.
class AppLocale extends ChangeNotifier {
  AppLocale({LocaleStorage? storage})
    : _storage = storage ?? MemoryLocaleStorage() {
    _setting = normalize(_storage.read());
    // A store that notifies (argv.json, edited by hand) is followed.
    if (_storage case final Listenable store) store.addListener(_reread);
  }

  final LocaleStorage _storage;
  String? _setting;

  void _reread() {
    final kept = normalize(_storage.read());
    if (kept == _setting) return;
    _setting = kept;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_storage case final Listenable store) store.removeListener(_reread);
    super.dispose();
  }

  static const english = 'en';
  static const simplifiedChinese = 'zh-cn';

  /// The languages the app is translated into, as settings.
  static const settings = [english, simplifiedChinese];

  /// The locales the app supports, for `MaterialApp.supportedLocales`: the
  /// system's is resolved to one of these (English when none matches).
  static const supportedLocales = [Locale('en'), Locale('zh', 'CN')];

  /// Null follows the system.
  String? get setting => _setting;

  /// For `MaterialApp.locale`: null follows the system.
  Locale? get locale => localeOf(_setting);

  /// Chooses [setting] (null: follow the system) and keeps it.
  Future<void> select(String? setting) async {
    final next = normalize(setting);
    if (next == _setting) return;
    _setting = next;
    notifyListeners();
    await _storage.write(next);
  }

  static Locale? localeOf(String? setting) => switch (normalize(setting)) {
    english => const Locale('en'),
    simplifiedChinese => const Locale('zh', 'CN'),
    _ => null,
  };

  /// A kept value as a setting: VS Code's values are case-insensitive
  /// (`zh-CN`), and a language the app lacks follows the system.
  static String? normalize(String? value) {
    final lower = value?.trim().toLowerCase().replaceAll('_', '-');
    if (lower == null || lower.isEmpty) return null;
    if (lower == 'en' || lower.startsWith('en-')) return english;
    if (lower == 'zh' ||
        lower == 'zh-cn' ||
        lower == 'zh-sg' ||
        lower.startsWith('zh-hans')) {
      return simplifiedChinese;
    }
    return null;
  }

  /// The supported locale the system's languages resolve to, as the app
  /// shows it when following the system.
  static Locale systemLocale([List<Locale>? preferred]) =>
      basicLocaleListResolution(
        preferred ?? WidgetsBinding.instance.platformDispatcher.locales,
        supportedLocales,
      );
}

/// Gives the app's [AppLocale] to what is under it (the settings dialog),
/// rebuilding its dependents when the setting changes.
class AppLocaleScope extends InheritedNotifier<AppLocale> {
  const AppLocaleScope({
    super.key,
    required AppLocale super.notifier,
    required super.child,
  });

  static AppLocale? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLocaleScope>()?.notifier;

  static AppLocale of(BuildContext context) => maybeOf(context)!;
}
