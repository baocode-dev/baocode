/// The `window.*` settings of settings.json, as VS Code names them (and
/// `window.ideWindows`, the app's own: whether the IDE has windows at
/// all): how folders and files open (in a window of their own or not),
/// which windows come back at launch, how big a new one is and whether
/// closing one asks first.
library;

/// `window.openFoldersInNewWindow`, `window.openFilesInNewWindow`: whether
/// a folder or file opened from within a window (Open Folder…, Open File…,
/// Open Recent) takes a window of its own. `off` (the default): a folder
/// replaces the window it was opened from, unless ⌘/Ctrl is held; a file
/// opens in the window it was opened from. VS Code's `default` is the same.
enum OpenInNewWindow {
  defaultMode('default'),
  on('on'),
  off('off');

  const OpenInNewWindow(this.setting);

  final String setting;

  static OpenInNewWindow parse(Object? value) =>
      values.where((mode) => mode.setting == value).firstOrNull ?? off;
}

/// `window.ideWindows`: where the IDE (the Fast Ide) shows.
enum IdeWindows {
  /// In windows of its own, one per folder, as VS Code's (the default).
  separate,

  /// In the main window, in the chat's place: one folder at a time.
  mainWindow;

  static IdeWindows parse(Object? value) =>
      values.where((mode) => mode.name == value).firstOrNull ?? separate;
}

/// `window.restoreWindows`: the IDE windows that open again at launch.
enum RestoreWindows {
  /// All of them, the empty ones too.
  all,

  /// The one last in front (the default).
  one,

  /// Those with a folder.
  folders,

  /// None.
  none;

  static RestoreWindows parse(Object? value) =>
      values.where((mode) => mode.name == value).firstOrNull ?? one;
}

/// `window.newWindowDimensions`: the size of a new window.
enum NewWindowDimensions {
  /// Centered on the screen, at the app's default size.
  defaultSize('default'),

  /// As the window in front, a little down and to the right of it.
  inherit('inherit'),
  maximized('maximized'),
  fullscreen('fullscreen');

  const NewWindowDimensions(this.setting);

  final String setting;

  static NewWindowDimensions parse(Object? value) =>
      values.where((mode) => mode.setting == value).firstOrNull ?? defaultSize;
}

/// `window.confirmBeforeClose`: whether closing a window asks first, even
/// with nothing unsaved; `keyboardOnly` asks when a shortcut closed it.
enum ConfirmBeforeClose {
  never,
  keyboardOnly,
  always;

  static ConfirmBeforeClose parse(Object? value) =>
      values.where((mode) => mode.name == value).firstOrNull ?? never;

  /// Whether a window closed [byKeyboard] (or not) is asked about.
  bool asks({required bool byKeyboard}) => switch (this) {
    never => false,
    keyboardOnly => byKeyboard,
    always => true,
  };
}

/// `terminal.integrated.confirmOnExit`: whether closing a window whose
/// terminals still run something asks first.
enum TerminalConfirmOnExit {
  never,
  always,
  hasChildProcesses;

  static TerminalConfirmOnExit parse(Object? value) =>
      values.where((mode) => mode.name == value).firstOrNull ?? never;
}

/// The window settings, read from settings.json's values each time they
/// are wanted (they apply from the next window opened or closed).
class WindowSettings {
  const WindowSettings({
    this.ideWindows = IdeWindows.separate,
    this.openFoldersInNewWindow = OpenInNewWindow.off,
    this.openFilesInNewWindow = OpenInNewWindow.off,
    this.restoreWindows = RestoreWindows.one,
    this.newWindowDimensions = NewWindowDimensions.defaultSize,
    this.confirmBeforeClose = ConfirmBeforeClose.never,
    this.terminalConfirmOnExit = TerminalConfirmOnExit.never,
  });

  static const ideWindowsKey = 'window.ideWindows';
  static const openFoldersKey = 'window.openFoldersInNewWindow';
  static const openFilesKey = 'window.openFilesInNewWindow';
  static const restoreWindowsKey = 'window.restoreWindows';
  static const newWindowDimensionsKey = 'window.newWindowDimensions';
  static const confirmBeforeCloseKey = 'window.confirmBeforeClose';
  static const terminalConfirmOnExitKey = 'terminal.integrated.confirmOnExit';

  factory WindowSettings.parse(Map<String, Object?> values) => WindowSettings(
    ideWindows: IdeWindows.parse(values[ideWindowsKey]),
    openFoldersInNewWindow: OpenInNewWindow.parse(values[openFoldersKey]),
    openFilesInNewWindow: OpenInNewWindow.parse(values[openFilesKey]),
    restoreWindows: RestoreWindows.parse(values[restoreWindowsKey]),
    newWindowDimensions: NewWindowDimensions.parse(
      values[newWindowDimensionsKey],
    ),
    confirmBeforeClose: ConfirmBeforeClose.parse(values[confirmBeforeCloseKey]),
    terminalConfirmOnExit: TerminalConfirmOnExit.parse(
      values[terminalConfirmOnExitKey],
    ),
  );

  final IdeWindows ideWindows;
  final OpenInNewWindow openFoldersInNewWindow;
  final OpenInNewWindow openFilesInNewWindow;
  final RestoreWindows restoreWindows;
  final NewWindowDimensions newWindowDimensions;
  final ConfirmBeforeClose confirmBeforeClose;
  final TerminalConfirmOnExit terminalConfirmOnExit;

  /// Whether a folder opened from within a window takes a new one: [held]
  /// is whether ⌘ (Ctrl) was held as it was picked.
  bool folderInNewWindow({bool held = false}) =>
      switch (openFoldersInNewWindow) {
        OpenInNewWindow.on => true,
        OpenInNewWindow.off || OpenInNewWindow.defaultMode => held,
      };

  /// Whether a file opened from within a window takes a new one.
  bool fileInNewWindow({bool held = false}) => switch (openFilesInNewWindow) {
    OpenInNewWindow.on => true,
    OpenInNewWindow.off || OpenInNewWindow.defaultMode => held,
  };
}
