// Builds the macOS distribution: the Release .app, and the .dmg that ships
// it. Run from anywhere in the repository:
//
//   dart run tool/build_macos.dart                build, then package
//   dart run tool/build_macos.dart --skip-build   package what is built
//
// The disk image lands in build/installers/.
//
// NOT WRITTEN YET — this is a placeholder, to be finished on a Mac. It exits
// with a failure so it can never be mistaken for a working build. The
// constants below are already what the script needs; what to do with them is
// the TODO at the end of main, which also names the pieces of
// tool/build_windows.dart to move over rather than reinvent.
import 'dart:io';

/// Where the .app flutter leaves behind goes, and where the disk image is
/// written. Under build/, which the repository already ignores and flutter
/// clean already removes.
// ignore: unused_element
const _bundleRelative = 'build/macos/Build/Products/Release/BaoCode.app';
// ignore: unused_element
const _installersRelative = 'build/installers';

/// What has to be in the .app for it to start. As on Windows, a build that
/// failed late still leaves an .app behind that looks complete — these are
/// what tell the difference. The names come from the Runner target; check
/// them against a real build before trusting them.
// ignore: unused_element
const _required = [
  'Contents/MacOS/BaoCode',
  'Contents/Frameworks/FlutterMacOS.framework',
  'Contents/Frameworks/App.framework',
  // The terminal's native half (bao_pty's hook/build.dart builds it).
  'Contents/Frameworks/bao_pty.framework',
  'Contents/Resources/flutter_assets',
];

Future<void> main(List<String> arguments) async {
  if (!Platform.isMacOS) {
    _fail(
      'This builds the macOS disk image, and only runs on macOS.\n'
      'On Windows, use tool/build_windows.dart.',
    );
  }

  // TODO(macos): implement, then delete this comment block and the _fail
  // below.
  //
  // The script mirrors tool/build_windows.dart. Move these over from it
  // rather than writing them twice — they are platform-independent:
  //   _readVersion   pubspec.yaml's 1.0.0+1 → (full, marketing, build)
  //   _checkBundle   stops if the bundle is missing any of _required
  //   _run           Process.run, printing the command, failing on non-zero
  //   _step, _fail   progress lines and a non-zero exit
  //
  // Then, in order:
  //
  //   1. Unless --skip-build: `flutter build macos --release`.
  //      (_run passes runInShell only for `flutter`, a .bat on Windows;
  //      on macOS there is no .bat, so it can be dropped.)
  //
  //   2. _checkBundle on the .app against _required. The failure mode is the
  //      same as on Windows and worth catching for the same reason: a build
  //      that died late leaves an .app that looks whole and will not start.
  //
  //   3. Read the version with _readVersion, and make the disk image's name
  //      and its volume name agree with it, as the installer's do on Windows.
  //
  //   4. Create the image:
  //        hdiutil create -volname "BaoCode <marketing>" \
  //          -srcfolder <the .app> -ov -format UDZO \
  //          build/installers/BaoCode-<marketing>.dmg
  //      hdiutil is part of macOS. It gives a bare folder in a window; for a
  //      background picture and an Applications shortcut (the usual look),
  //      `brew install create-dmg` and drive that instead. Pick one — this
  //      is the only part with a real choice in it.
  //
  //   5. Signing and notarising. Without both, Gatekeeper refuses the app on
  //      anyone else's machine ("BaoCode is damaged and can't be opened"),
  //      and the .dmg is only good for people who can run
  //      `xattr -d com.apple.quarantine` on it. Both need an Apple Developer
  //      account ($99/year) and a "Developer ID Application" certificate:
  //        codesign --deep --force --options runtime \
  //          --entitlements macos/Runner/Release.entitlements \
  //          --sign "Developer ID Application: <name> (<team>)" <the .app>
  //        xcrun notarytool submit <the .dmg> --wait \
  //          --apple-id <id> --team-id <team> --password <app-specific>
  //        xcrun stapler staple <the .dmg>
  //      Sign before making the image, staple after: the ticket goes on the
  //      .dmg, and the .app inside it has to be signed already.
  //
  //      Not --deep, though: it would give the Finder extension
  //      (Contents/PlugIns/FinderExtension.appex) the app's entitlements,
  //      sandbox off, and the system refuses to load an extension that is
  //      not sandboxed. Sign the extension first, with its own, then the app
  //      around it:
  //        codesign --force --options runtime \
  //          --entitlements macos/FinderExtension/FinderExtension.entitlements \
  //          --sign "Developer ID Application: <name> (<team>)" \
  //          <the .app>/Contents/PlugIns/FinderExtension.appex
  //      (the frameworks under Contents/Frameworks, signed without
  //      entitlements, before the app too).
  //
  //      --entitlements is not optional here. macos/Runner/Release.entitlements
  //      turns the sandbox OFF, which this app needs: it runs the Claude Code
  //      CLI as a child process and reads its sessions under ~/.claude, and a
  //      sandboxed app can do neither. Signing without it would silently
  //      re-enable the sandbox and the app would fail at runtime, not at
  //      build time. Do not take the Xcode default of DebugProfile's
  //      entitlements either: that one adds allow-jit and network.server,
  //      which are for debugging.
  //
  // One thing in the checked-in project has to be fixed before step 5, and
  // it is not the script's job:
  //
  //   - macos/Runner.xcodeproj/project.pbxproj sets MARKETING_VERSION = 1.0,
  //     where pubspec.yaml says 1.0.0. Info.plist reads $(MARKETING_VERSION),
  //     so the .app would report 1.0 while the disk image is named 1.0.0.
  //     Either raise it to match, or have this script check the two agree so
  //     the drift cannot go unnoticed.
  _fail(
    'tool/build_macos.dart has not been written yet. The TODO in it lists\n'
    'what to do; it is meant to be finished on a Mac.',
  );
}

Never _fail(String message) {
  stderr.writeln('\n$message');
  exit(1);
}
