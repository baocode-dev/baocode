; The Windows installer for BaoCode, compiled by tool/build_windows.dart.
;
; It is compiled with three /D defines, all required:
;   BundleDir  the Release bundle to pack (the folder holding baocode.exe)
;   AppVersion the version pubspec.yaml carries, as it writes it (1.0.0+1)
;   OutDir     where to write the installer (build/installers)
;
; Output: BaoCode-<version>-setup.exe

#ifndef BundleDir
  #error BundleDir is not defined: pass /DBundleDir=<release bundle folder>
#endif
#ifndef AppVersion
  #error AppVersion is not defined: pass /DAppVersion=<version from pubspec.yaml>
#endif
#ifndef OutDir
  #error OutDir is not defined: pass /DOutDir=<folder for the installer>
#endif

; The part of the version Windows records, without the build number pubspec
; adds after "+".
#define VersionNumber Copy(AppVersion, 1, Pos("+", AppVersion) - 1)
#if Pos("+", AppVersion) == 0
  #undef VersionNumber
  #define VersionNumber AppVersion
#endif

[Setup]
; Base of the identity Windows uses for the installed app. It must not change
; between versions, or an upgrade installs beside the old one instead of over
; it.
AppId={{6fdd732b-95c6-4c37-af6f-ff574358deb5}
AppName=BaoCode
AppVersion={#VersionNumber}
AppPublisher=BaoCode
AppVerName=BaoCode {#VersionNumber}
DefaultDirName={autopf}\BaoCode
DefaultGroupName=BaoCode
UninstallDisplayName=BaoCode
UninstallDisplayIcon={app}\baocode.exe
OutputBaseFilename=BaoCode-{#VersionNumber}-setup
OutputDir={#OutDir}
; What Explorer shows for the installer itself. Windows wants four numbers,
; where pubspec's version has three.
VersionInfoVersion={#VersionNumber}.0
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; The app is 64-bit only (flutter build windows is x64 here).
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Installing under Program Files needs elevation; per-user is offered instead
; on a machine where the user cannot elevate.
PrivilegesRequiredOverridesAllowed=dialog
DisableProgramGroupPage=yes
; A running BaoCode is asked to close (it quits on WM_ENDSESSION, see
; windows/runner/flutter_window.cpp), and ended if it does not: a version
; from before that, or one stuck, would otherwise hold Setup at "Closing
; applications..." for good.
CloseApplications=force

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; \
  GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "addtopath"; Description: "Add BaoCode to the PATH"; \
  GroupDescription: "Other:"; Flags: unchecked
Name: "contextmenu"; \
  Description: "Add ""Open with BaoCode"" and ""Open with Fast Ide"" to Explorer's context menu"; \
  GroupDescription: "Other:"

[Files]
; The whole bundle: baocode.exe, the engine and plugin DLLs, and data\ (the
; AOT app.so and flutter_assets) which sit beside the executable.
Source: "{#BundleDir}\*"; DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\BaoCode"; Filename: "{app}\baocode.exe"
Name: "{group}\{cm:UninstallProgram,BaoCode}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\BaoCode"; Filename: "{app}\baocode.exe"; Tasks: desktopicon

[Registry]
; Only when asked for. Which hive follows the install mode: a per-machine
; install writes the machine's PATH (HKLM), a per-user one the user's (HKCU).
; Writing HKCU while installing as admin would put the entry in whichever
; account elevated, which is not necessarily the one that runs the app.
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; \
  ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; \
  Tasks: addtopath; Check: IsAdminInstallMode and NeedsAddPath(ExpandConstant('{app}'), True)
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; \
  ValueData: "{olddata};{app}"; Tasks: addtopath; \
  Check: (not IsAdminInstallMode) and NeedsAddPath(ExpandConstant('{app}'), False)

; Explorer's context menu, on a file, a folder and a folder's background,
; each in a new window: Open with BaoCode, a new agent in a narrow window of
; its own (a file in its composer; see AppWindows.openAgent), and Open with
; Fast Ide, as `code -n` opens it (the path its own working folder: it is
; absolute). HKA is the install mode's hive (HKLM per machine, HKCU per
; user). Windows 11 lists them under "Show more options". Unticked on a
; reinstall, they go.
Root: HKA; Subkey: "Software\Classes\*\shell\BaoCode"; ValueType: string; \
  ValueName: ""; ValueData: "{code:MenuLabel|BaoCode}"; Tasks: contextmenu; \
  Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\*\shell\BaoCode"; ValueType: string; \
  ValueName: "Icon"; ValueData: """{app}\baocode.exe"""; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\*\shell\BaoCode\command"; \
  ValueType: string; ValueName: ""; \
  ValueData: """{app}\baocode.exe"" --baocode-agent ""%1"""; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\shell\BaoCode"; \
  ValueType: string; ValueName: ""; ValueData: "{code:MenuLabel|BaoCode}"; \
  Tasks: contextmenu; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Directory\shell\BaoCode"; \
  ValueType: string; ValueName: "Icon"; ValueData: """{app}\baocode.exe"""; \
  Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\shell\BaoCode\command"; \
  ValueType: string; ValueName: ""; \
  ValueData: """{app}\baocode.exe"" --baocode-agent ""%V"""; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\BaoCode"; \
  ValueType: string; ValueName: ""; ValueData: "{code:MenuLabel|BaoCode}"; \
  Tasks: contextmenu; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\BaoCode"; \
  ValueType: string; ValueName: "Icon"; ValueData: """{app}\baocode.exe"""; \
  Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\BaoCode\command"; \
  ValueType: string; ValueName: ""; \
  ValueData: """{app}\baocode.exe"" --baocode-agent ""%V"""; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\*\shell\BaoCodeFastIde"; \
  ValueType: string; ValueName: ""; ValueData: "{code:MenuLabel|Fast Ide}"; \
  Tasks: contextmenu; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\*\shell\BaoCodeFastIde"; \
  ValueType: string; ValueName: "Icon"; ValueData: """{app}\baocode.exe"""; \
  Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\*\shell\BaoCodeFastIde\command"; \
  ValueType: string; ValueName: ""; \
  ValueData: """{app}\baocode.exe"" --baocode-cli ""%1"" -n ""%1"""; \
  Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\shell\BaoCodeFastIde"; \
  ValueType: string; ValueName: ""; ValueData: "{code:MenuLabel|Fast Ide}"; \
  Tasks: contextmenu; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Directory\shell\BaoCodeFastIde"; \
  ValueType: string; ValueName: "Icon"; ValueData: """{app}\baocode.exe"""; \
  Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\shell\BaoCodeFastIde\command"; \
  ValueType: string; ValueName: ""; \
  ValueData: """{app}\baocode.exe"" --baocode-cli ""%V"" -n ""%V"""; \
  Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\BaoCodeFastIde"; \
  ValueType: string; ValueName: ""; ValueData: "{code:MenuLabel|Fast Ide}"; \
  Tasks: contextmenu; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\BaoCodeFastIde"; \
  ValueType: string; ValueName: "Icon"; ValueData: """{app}\baocode.exe"""; \
  Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\BaoCodeFastIde\command"; \
  ValueType: string; ValueName: ""; \
  ValueData: """{app}\baocode.exe"" --baocode-cli ""%V"" -n ""%V"""; \
  Tasks: contextmenu
; Unticked: what an earlier install added goes.
Root: HKA; Subkey: "Software\Classes\*\shell\BaoCode"; ValueType: none; \
  Tasks: not contextmenu; Flags: deletekey
Root: HKA; Subkey: "Software\Classes\Directory\shell\BaoCode"; ValueType: none; \
  Tasks: not contextmenu; Flags: deletekey
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\BaoCode"; \
  ValueType: none; Tasks: not contextmenu; Flags: deletekey
Root: HKA; Subkey: "Software\Classes\*\shell\BaoCodeFastIde"; ValueType: none; \
  Tasks: not contextmenu; Flags: deletekey
Root: HKA; Subkey: "Software\Classes\Directory\shell\BaoCodeFastIde"; \
  ValueType: none; Tasks: not contextmenu; Flags: deletekey
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\BaoCodeFastIde"; \
  ValueType: none; Tasks: not contextmenu; Flags: deletekey

[Run]
Filename: "{app}\baocode.exe"; Description: "{cm:LaunchProgram,BaoCode}"; \
  Flags: nowait postinstall skipifsilent

[Code]
// The context menu's labels (see [Registry]): "Open with BaoCode", in
// Chinese where Windows is. Written as code points, so the script's encoding
// does not matter.
function MenuLabel(Param: String): String;
begin
  if (GetUILanguage and $3FF) = $04 then
    Result := #$7528 + ' ' + Param + ' ' + #$6253#$5F00
  else
    Result := 'Open with ' + Param;
end;

// Whether {app} is already on the PATH the install will write, so a reinstall
// does not append it a second time. Machine reads the machine's PATH, user the
// user's, matching [Registry] above.
function NeedsAddPath(Param: string; Machine: Boolean): Boolean;
var
  Path: String;
  Subkey: String;
  RootKey: Integer;
begin
  if Machine then
  begin
    RootKey := HKEY_LOCAL_MACHINE;
    Subkey := 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';
  end
  else
  begin
    RootKey := HKEY_CURRENT_USER;
    Subkey := 'Environment';
  end;

  if not RegQueryStringValue(RootKey, Subkey, 'Path', Path) then
  begin
    Result := True;
    Exit;
  end;
  Result := Pos(';' + Uppercase(Param) + ';', ';' + Uppercase(Path) + ';') = 0;
end;
