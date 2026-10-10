/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The source controls extensions register: each one's resource groups and
// their resources, its input box, its action button, count and status bar
// commands, as the Source Control view shows them.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadSCM.ts (`MainThreadSCMProvider`,
// `MainThreadSCMResourceGroup`, `MainThreadSCMResource`: their features,
// splices and `toJSON`), src/vs/workbench/contrib/scm/common/scmService.ts
// (`SCMInput`: value, placeholder, enablement, visibility, validation) and
// scm.ts (`InputValidationType`).
//
// Deviations:
// - The built-in Git extension's providers (`providerId` `git`) are kept
//   but not shown (`shown`): BaoCode's own Git view shows the repositories
//   (the goal's 五.12). Its API, which other extensions use, is whole.
// - No quick diff, history or artifact providers: their features are kept,
//   never asked for (BaoCode's editor gutter and graph read Git itself).
// - The input box is a plain text field: no `vscode-sourcecontrol:` text
//   model the extension host's language features could see.

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import '../commands/command_contributions.dart';

/// `MarshalledId`s of SCM objects, as commands receive them.
abstract final class ScmMarshalledId {
  static const resource = 3;
  static const resourceGroup = 4;
  static const provider = 5;
}

/// `InputValidationType`.
enum ScmInputValidationType { error, warning, information }

/// A message the input box shows under its text.
typedef ScmInputValidation = ({String message, ScmInputValidationType type});

/// `ISCMInput`: a provider's commit message box.
final class ScmInput extends ChangeNotifier {
  String _value = '';
  String placeholder = '';
  bool _enabled = true;
  bool _visible = true;
  ScmInputValidation? _validation;

  /// Asks the extension to validate text at a cursor offset; null when it
  /// does not validate.
  Future<ScmInputValidation?> Function(String value, int cursor)? validate;

  /// Each change of the value from the view, for the extension host.
  ValueChanged<String>? onUserChange;

  String get value => _value;
  bool get enabled => _enabled;
  bool get visible => _visible;
  ScmInputValidation? get validation => _validation;

  /// `setValue(value, transient)`: from the extension ([fromView] false),
  /// or typed.
  void setValue(String value, {bool fromView = false}) {
    if (value == _value) return;
    _value = value;
    _validation = null;
    if (fromView) onUserChange?.call(value);
    notifyListeners();
  }

  void setPlaceholder(String value) {
    placeholder = value;
    notifyListeners();
  }

  void setEnabled(bool value) {
    _enabled = value;
    notifyListeners();
  }

  void setVisible(bool value) {
    _visible = value;
    notifyListeners();
  }

  void showValidationMessage(ScmInputValidation? validation) {
    _validation = validation;
    notifyListeners();
  }
}

/// `ISCMResourceDecorations`.
typedef ScmResourceDecorations = ({
  ExtensionIcon? icon,
  ExtensionIcon? iconDark,
  String? tooltip,
  bool strikeThrough,
  bool faded,
});

/// `MainThreadSCMResource`.
final class ScmResource {
  ScmResource({
    required this.group,
    required this.handle,
    required this.sourceUri,
    required this.decorations,
    this.contextValue,
    this.command,
  });

  final ScmResourceGroup group;
  final int handle;
  final VsUri sourceUri;
  final ScmResourceDecorations decorations;
  final String? contextValue;
  final Map<String, Object?>? command;

  /// `open`: the extension host runs its command.
  Future<void> open({bool preserveFocus = false}) async =>
      group.provider.openResource?.call(this, preserveFocus);

  /// What a command run on it receives (`toJSON`).
  Map<String, Object?> toArgument() => {
    r'$mid': ScmMarshalledId.resource,
    'sourceControlHandle': group.provider.handle,
    'groupHandle': group.handle,
    'handle': handle,
  };
}

/// `MainThreadSCMResourceGroup`.
final class ScmResourceGroup {
  ScmResourceGroup({
    required this.provider,
    required this.handle,
    required this.id,
    required this.label,
    required this.features,
  });

  final ScmProvider provider;
  final int handle;
  final String id;
  String label;
  Map<String, Object?> features;
  final List<ScmResource> resources = [];

  bool get hideWhenEmpty => features['hideWhenEmpty'] == true;
  String? get contextValue => features['contextValue'] as String?;

  Map<String, Object?> toArgument() => {
    r'$mid': ScmMarshalledId.resourceGroup,
    'sourceControlHandle': provider.handle,
    'groupHandle': handle,
  };
}

/// `MainThreadSCMProvider`: one source control.
final class ScmProvider extends ChangeNotifier {
  ScmProvider({
    required this.handle,
    required this.providerId,
    required this.label,
    this.parentHandle,
    this.rootUri,
    this.icon,
    this.isHidden = false,
    this.name,
  });

  final int handle;
  final int? parentHandle;

  /// The extension's id for it (`git`, `jj`…).
  final String providerId;
  final String label;
  final VsUri? rootUri;
  final ExtensionIcon? icon;
  final bool isHidden;

  /// Its folder's name, when it has a root.
  final String? name;

  final ScmInput input = ScmInput();

  /// Runs a resource's command in the extension host
  /// (`$executeResourceCommand`).
  Future<void> Function(ScmResource resource, bool preserveFocus)? openResource;

  final List<ScmResourceGroup> groups = [];
  final Map<int, ScmResourceGroup> _groupsByHandle = {};
  Map<String, Object?> features = const {};

  /// Shown in the Source Control view: all but the built-in Git
  /// extension's, which BaoCode's own view stands for.
  bool get shown => providerId != 'git' && isHidden != true;

  Map<String, Object?>? get acceptInputCommand =>
      (features['acceptInputCommand'] as Map?)?.cast();
  String? get contextValue => features['contextValue'] as String?;
  int? get count => (features['count'] as num?)?.toInt();
  String get commitTemplate => features['commitTemplate'] as String? ?? '';
  Map<String, Object?>? get actionButton =>
      (features['actionButton'] as Map?)?.cast();
  List<Map<String, Object?>> get statusBarCommands => [
    for (final c in (features['statusBarCommands'] as List?) ?? const [])
      if (c is Map) c.cast(),
  ];

  /// The resources of all groups.
  int get resourceCount =>
      groups.fold(0, (sum, group) => sum + group.resources.length);

  Map<String, Object?> toArgument() => {
    r'$mid': ScmMarshalledId.provider,
    'handle': handle,
  };

  ScmResourceGroup? group(int handle) => _groupsByHandle[handle];

  /// `$updateSourceControl`: the features given replace the ones held;
  /// those not given stay.
  void updateFeatures(Map<String, Object?> update) {
    final oldTemplate = commitTemplate;
    features = {...features, ...update};
    // As scmInput.ts: the template replaces an empty input, or the old
    // template still there.
    if (update['commitTemplate'] case final String template
        when input.value.isEmpty || input.value == oldTemplate) {
      input.setValue(template);
    }
    notifyListeners();
  }

  /// `$registerGroups`.
  void registerGroups(List<List<Object?>> raw) {
    for (final entry in raw) {
      final group = ScmResourceGroup(
        provider: this,
        handle: (entry[0]! as num).toInt(),
        id: entry[1]! as String,
        label: entry[2]! as String,
        features: ((entry[3] as Map?) ?? const {}).cast(),
      );
      _groupsByHandle[group.handle] = group;
      groups.add(group);
    }
    notifyListeners();
  }

  void updateGroup(int handle, Map<String, Object?> update) {
    final group = _groupsByHandle[handle];
    if (group == null) return;
    group.features = {...group.features, ...update};
    notifyListeners();
  }

  void updateGroupLabel(int handle, String label) {
    final group = _groupsByHandle[handle];
    if (group == null) return;
    group.label = label;
    notifyListeners();
  }

  void unregisterGroup(int handle) {
    final group = _groupsByHandle.remove(handle);
    if (group == null) return;
    groups.remove(group);
    notifyListeners();
  }

  /// `$spliceGroupResourceStates`: `[groupHandle, [[start, deleteCount,
  /// rawResources]]]`, each group's splices applied last to first.
  void spliceResourceStates(List<List<Object?>> splices) {
    for (final entry in splices) {
      final group = _groupsByHandle[(entry[0]! as num).toInt()];
      if (group == null) continue;
      final groupSplices = (entry[1]! as List).reversed;
      for (final splice in groupSplices.cast<List<Object?>>()) {
        final start = (splice[0]! as num).toInt();
        final deleteCount = (splice[1]! as num).toInt();
        final resources = [
          for (final raw in (splice[2]! as List).cast<List<Object?>>())
            _resource(group, raw),
        ];
        final end = (start + deleteCount).clamp(start, group.resources.length);
        group.resources.replaceRange(
          start.clamp(0, group.resources.length),
          end,
          resources,
        );
      }
    }
    notifyListeners();
  }

  ScmResource _resource(ScmResourceGroup group, List<Object?> raw) {
    // [handle, sourceUri, icons, tooltip, strikeThrough, faded,
    //  contextValue, command, multiDiffOriginal, multiDiffModified]
    final icons = raw.length > 2 ? raw[2] as List? : null;
    final icon = scmIcon(icons?.elementAtOrNull(0));
    final iconDark = scmIcon(icons?.elementAtOrNull(1)) ?? icon;
    final contextValue = raw.elementAtOrNull(6) as String?;
    return ScmResource(
      group: group,
      handle: (raw[0]! as num).toInt(),
      sourceUri: VsUri.tryRevive(raw[1])!,
      decorations: (
        icon: icon,
        iconDark: iconDark,
        tooltip: raw.elementAtOrNull(3) as String?,
        strikeThrough: raw.elementAtOrNull(4) == true,
        faded: raw.elementAtOrNull(5) == true,
      ),
      contextValue: contextValue == null || contextValue.isEmpty
          ? null
          : contextValue,
      command: (raw.elementAtOrNull(7) as Map?)?.cast(),
    );
  }
}

/// `getIconFromIconDto`: a ThemeIcon (`{id}`), an image's URI, or
/// `{light, dark}` URIs.
ExtensionIcon? scmIcon(Object? dto) {
  if (dto is VsUri) return ImageIcon(dark: dto);
  if (dto is! Map) return null;
  if (dto['id'] case final String id when !dto.containsKey('scheme')) {
    return ThemeIconRef(id);
  }
  if (dto.containsKey('light') && dto.containsKey('dark')) {
    final dark = VsUri.tryRevive(dto['dark']);
    if (dark == null) return null;
    return ImageIcon(dark: dark, light: VsUri.tryRevive(dto['light']));
  }
  return switch (VsUri.tryRevive(dto)) {
    final uri? => ImageIcon(dark: uri),
    null => null,
  };
}

/// `ISCMService`: the source controls of a workspace's extension host.
final class ScmService extends ChangeNotifier {
  final Map<int, ScmProvider> _providers = {};

  /// Every provider, in registration order, those not shown included.
  List<ScmProvider> get providers => [..._providers.values];

  /// The ones the Source Control view shows.
  List<ScmProvider> get shownProviders => [
    for (final p in _providers.values)
      if (p.shown) p,
  ];

  ScmProvider? provider(int handle) => _providers[handle];

  bool _disposed = false;

  void register(ScmProvider provider) {
    if (_disposed) return;
    _providers[provider.handle] = provider;
    provider.addListener(notifyListeners);
    notifyListeners();
  }

  void unregister(int handle) {
    final provider = _providers.remove(handle);
    if (provider == null) return;
    provider.removeListener(notifyListeners);
    provider.dispose();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final handle in [..._providers.keys]) {
      unregister(handle);
    }
    super.dispose();
  }
}
