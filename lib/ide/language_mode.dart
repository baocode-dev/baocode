import 'dart:async';

import 'package:bao_editor/monaco/flutter/language_overrides.dart';
import 'package:flutter/widgets.dart';

import '../l10n/l10n.dart';
import '../settings/user_settings.dart';
import '../window/app_windows.dart' show WindowDelegate;
import 'ide_quick_input.dart';
import 'ide_status_bar.dart' show IdeLanguageNames;

/// Where the languages picked for files are kept ([EditorLanguageOverrides]):
/// in the app's global storage, path to language id.
const languageModesKey = 'editor.languageModes';

/// Reads the languages picked for files from [storage], and keeps them
/// there as they change, for the app's whole run.
void keepLanguageModes(GlobalStorage storage) {
  final overrides = EditorLanguageOverrides.instance;
  overrides.load(storage.get<Map<Object?, Object?>>(languageModesKey));
  overrides.addListener(() {
    final picks = overrides.toJson();
    unawaited(
      storage
          .set(languageModesKey, picks.isEmpty ? null : picks)
          .catchError(
            (Object error) => debugPrint('$languageModesKey not kept: $error'),
          ),
    );
  });
}

/// Change Language Mode for [path] (VS Code's): Auto Detect (by its name
/// and first line) first, then every language; the one picked is [path]'s
/// from then on, in every editor showing it, and kept.
IdeQuickPick languageModePick(
  AppLocalizations l10n,
  String path, {
  VoidCallback? onPicked,
}) {
  final overrides = EditorLanguageOverrides.instance;
  final current = overrides.of(path);
  void pick(String? languageId) {
    overrides.set(path, languageId);
    onPicked?.call();
  }

  final auto = IdeQuickPickItem(
    label: l10n.languageModeAuto,
    onAccept: () => pick(null),
  );
  final plain = IdeQuickPickItem(
    label: IdeLanguageNames.nameOf(EditorLanguageOverrides.plainText),
    description: '(${EditorLanguageOverrides.plainText})',
    onAccept: () => pick(EditorLanguageOverrides.plainText),
  );
  IdeQuickPickItem? active = current == null
      ? auto
      : current == EditorLanguageOverrides.plainText
      ? plain
      : null;
  final languages = <IdeQuickPickItem>[];
  for (final language in IdeLanguageNames.all) {
    final item = IdeQuickPickItem(
      label: language.name,
      description: '(${language.id})',
      onAccept: () => pick(language.id),
    );
    if (language.id == current) active = item;
    languages.add(item);
  }
  return IdeQuickPick(
    items: [auto, plain, const IdeQuickPickSeparator(), ...languages],
    placeholder: l10n.languageModePlaceholder,
    sortByLabel: false,
    matchOnDescription: true,
    activeItems: [?active],
    onDidAccept: (item) => item?.onAccept?.call(),
  );
}

/// Shows [languageModePick] for [path] over the window [context] is in;
/// nothing where there is no window to show it over.
Future<void> changeLanguageMode(
  BuildContext context,
  String path, {
  VoidCallback? onPicked,
}) async {
  WindowDelegate? window;
  context.visitAncestorElements((element) {
    if (element is StatefulElement && element.state is WindowDelegate) {
      window = element.state as WindowDelegate;
      return false;
    }
    return true;
  });
  final l10n = context.l10n;
  await IdeLanguageNames.load();
  window?.showQuickPick(languageModePick(l10n, path, onPicked: onPicked));
}
