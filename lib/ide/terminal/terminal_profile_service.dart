/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The terminal profiles a new terminal can start, and the default one, as
// VS Code's terminal profile service keeps them: detected (see
// terminal_profiles.dart), again when the user's profiles change in
// settings.json, the default read from and written to it.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/browser/terminalProfileService.ts
// (`availableProfiles`, `getDefaultProfileName`, `refreshAvailableProfiles`)
// and terminalProfileQuickpick.ts (the profile picks, `_createProfileQuickPickItem`).
//
// Deviations: detected the first time they are asked for, not as the
// workbench starts (the app's detection reads the disk and the login
// shell's environment); with no default profile set, the default is the
// profile that is the user's shell, which the dropdown names as upstream
// names a set one; contributed (extension) profiles do not exist; a
// detected profile made the default is named in settings.json, not copied
// into the user's profiles.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../l10n/app_localizations.dart';
import '../ide_quick_input.dart';
import 'terminal_instance.dart';
import 'terminal_profiles.dart';
import 'terminal_shell.dart';

class TerminalProfileService extends ChangeNotifier {
  TerminalProfileService(this.backend, {TerminalOs? os})
    : os = os ?? terminalOsOf(defaultTargetPlatform) {
    _configured = _configuredJson;
    backend.settings?.addListener(_settingsChanged);
  }

  final TerminalBackend backend;
  final TerminalOs os;

  List<TerminalProfile> _profiles = const [];
  TerminalShell? _systemShell;
  Future<void>? _detecting;
  bool _detected = false;
  String? _configured;

  /// The profiles there are, once [refresh] found them (none before).
  List<TerminalProfile> get availableProfiles => _profiles;

  /// Finds the profiles, the first time and after the user's changed;
  /// at once otherwise.
  Future<void> refresh() {
    if (_detected) return Future.value();
    return _detecting ??= _detect();
  }

  Future<void> _detect() async {
    final configured = _configured;
    try {
      final found = await backend.detectProfiles(
        configured: backend.settings?[terminalProfilesKey(os)],
      );
      _profiles = found.profiles;
      _systemShell = found.systemShell;
    } on Object {
      _profiles = const [];
    } finally {
      _detecting = null;
    }
    // Changed meanwhile: found again when next asked.
    _detected = configured == _configured;
    notifyListeners();
  }

  /// The default profile set in settings.json: null when none is.
  String? get defaultProfileSetting =>
      switch (backend.settings?[terminalDefaultProfileKey(os)]) {
        final String name when name.isNotEmpty => name,
        _ => null,
      };

  /// The default profile's name (see [terminalDefaultProfileName]).
  String? get defaultProfileName => terminalDefaultProfileName(
    _profiles,
    setting: defaultProfileSetting,
    systemShell: _systemShell,
  );

  /// The shell a terminal starts with no profile set, once found.
  TerminalShell? get systemShell => _systemShell;

  TerminalProfile? profileNamed(String name) {
    for (final profile in _profiles) {
      if (profile.name == name) return profile;
    }
    return null;
  }

  /// What a new terminal with no profile given starts: the default
  /// profile set's shell, once found; null (not waited for) when none is
  /// set, for the user's shell.
  Future<TerminalShell?>? defaultShell() {
    final name = defaultProfileSetting;
    if (name == null) return null;
    return refresh().then((_) => profileNamed(name)?.shell);
  }

  /// Whether a default profile can be set: settings.json is there.
  bool get canSetDefault => backend.settings != null;

  /// Makes [profile] the default (Select Default Profile), in settings.json.
  Future<void> setDefaultProfile(TerminalProfile profile) async {
    await backend.settings?.update(terminalDefaultProfileKey(os), profile.name);
    notifyListeners();
  }

  String get _configuredJson =>
      jsonEncode(backend.settings?[terminalProfilesKey(os)]);

  void _settingsChanged() {
    final configured = _configuredJson;
    if (configured != _configured) {
      _configured = configured;
      _detected = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    backend.settings?.removeListener(_settingsChanged);
    super.dispose();
  }
}

/// The profiles' order in the New Terminal dropdown
/// (terminalMenus.ts `getTerminalActionBarArgs`): those of the settings,
/// the default first, the others by name.
List<TerminalProfile> terminalDropdownProfiles(
  List<TerminalProfile> profiles,
  String? defaultName,
) {
  final listed = [
    for (final profile in profiles)
      if (!profile.isAutoDetected) profile,
  ]..sort((a, b) => a.name.compareTo(b.name));
  final index = listed.indexWhere((profile) => profile.name == defaultName);
  if (index > 0) listed.insert(0, listed.removeAt(index));
  return listed;
}

/// A quick pick of [profiles] (terminalProfileQuickpick.ts): those of the
/// settings, then those detected, each with its shell's path and arguments;
/// [defaultName]'s active as it shows.
IdeQuickPick terminalProfilePick({
  required List<TerminalProfile> profiles,
  required String? defaultName,
  required String placeholder,
  required ValueChanged<TerminalProfile> onPick,
  required AppLocalizations l10n,
}) {
  IdeQuickPickItem item(TerminalProfile profile) => IdeQuickPickItem(
    label: profile.name,
    description: [
      profile.path,
      for (final arg in profile.args)
        arg.contains(' ') ? '"${arg.replaceAll('"', r'\"')}"' : arg,
    ].join(' '),
    onAccept: () => onPick(profile),
  );
  final configured = [
    for (final profile in profiles)
      if (!profile.isAutoDetected) item(profile),
  ];
  final detected = [
    for (final profile in profiles)
      if (profile.isAutoDetected) item(profile),
  ];
  final defaultIndex = profiles
      .where((profile) => !profile.isAutoDetected)
      .toList()
      .indexWhere((profile) => profile.name == defaultName);
  return IdeQuickPick(
    placeholder: placeholder,
    matchOnDescription: true,
    sortByLabel: false,
    activeItems: defaultIndex < 0 ? null : [configured[defaultIndex]],
    items: [
      if (configured.isNotEmpty) ...[
        IdeQuickPickSeparator(l10n.termProfilesGroup),
        ...configured,
      ],
      if (detected.isNotEmpty) ...[
        IdeQuickPickSeparator(l10n.termProfilesDetected),
        ...detected,
      ],
    ],
    onDidAccept: (item) => item?.onAccept?.call(),
  );
}
