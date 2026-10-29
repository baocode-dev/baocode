# Windows text rendering engine patch

`windows_text.patch` changes how Flutter's Impeller engine (the default on
Windows since 3.47) rasterizes and blends text, so that it gets closer to
Chrome's text on Windows. It applies to the `flutter/flutter` repository at
the tag the app builds with (`FLUTTER_VERSION` in
`.github/workflows/release.yml`, now 3.47.5).

## What stock Flutter does on Windows

- Glyphs are rasterized by Skia through DirectWrite into an A8 atlas, in
  grayscale (no ClearType).
- Every alpha glyph is drawn as dark text (`GlyphProperties::ComputeTone`
  only tells light from dark on macOS). So Skia's mask gamma preblend, which
  depends on the text's luminance, always treats text as black, and light
  text on a dark theme comes out thin and washed out.
- The glyph shader makes up for it with an exponent on coverage that goes
  from 1.0 for black text to 2.2 for white, an approximation meant for
  FreeType on Linux.
- Skia's text contrast is 0.5; Chrome on Windows uses 1.0, or the user's
  ClearType Text Tuner values when they have run it.

## What the patch changes (Windows only)

| | stock | patched |
|---|---|---|
| light text gets light glyphs | no | yes, as on macOS |
| shader gamma | on | off |
| Skia text contrast | 0.5 | 1.0, or ClearType tuning |
| Skia text gamma | sRGB | sRGB, or ClearType tuning |

The ClearType tuning is read the way Chrome reads it: only when
`HKCU\SOFTWARE\Microsoft\Avalon.Graphics\DISPLAYn` exists for the primary
display, from DirectWrite's default rendering params.

Files:

- `impeller/typographer/windows_text_tuning.{h,cc}` (new): the settings.
- `impeller/typographer/font_glyph_pair.h`: `ComputeTone` on Windows.
- `impeller/typographer/backends/skia/typographer_context_skia.cc`: glyph
  surfaces get `SkSurfaceProps` with the contrast and gamma.
- `impeller/entity/contents/text_contents.cc`: the shader gamma default.
- `impeller/typographer/typographer_unittests.cc`: the light/dark cache key
  test expects two glyphs on Windows too.

## Comparing without rebuilding

The engine reads these once at startup, in debug and release alike, and
logs what it ended up with (`Windows text: ...`):

| variable | |
|---|---|
| `FLUTTER_WIN_TEXT=off` | exactly stock Flutter |
| `FLUTTER_WIN_TEXT_LIGHT_GLYPHS=0\|1` | light glyphs |
| `FLUTTER_WIN_TEXT_SHADER_GAMMA=0\|1` | shader gamma |
| `FLUTTER_WIN_TEXT_CONTRAST=0..1` | Skia text contrast |
| `FLUTTER_WIN_TEXT_GAMMA=0..4` | Skia text gamma; 0 is sRGB |

The individual ones apply on top of `FLUTTER_WIN_TEXT=off` too.

```powershell
$env:FLUTTER_WIN_TEXT = 'off'; .\baocode.exe          # stock
Remove-Item Env:FLUTTER_WIN_TEXT; .\baocode.exe       # patched
$env:FLUTTER_WIN_TEXT_CONTRAST = '0.75'; .\baocode.exe
```

## Building

On Windows, once:

1. [depot_tools](https://commondatastorage.googleapis.com/chrome-infra-docs/flat/depot_tools/docs/html/depot_tools_tutorial.html#_setting_up)
   unzipped and first on `PATH`.
2. Visual Studio 2022 with "Desktop development with C++", and the Windows
   SDK's "Debugging Tools for Windows" (Settings → Apps → Windows Software
   Development Kit → Modify). If depot_tools can't find Visual Studio, set
   `GYP_MSVS_OVERRIDE_PATH` to its install folder.
3. Long paths: `git config --global core.longpaths true`, and
   `LongPathsEnabled = 1` under
   `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem`.

Then, from the app's folder:

```powershell
powershell -ExecutionPolicy Bypass -File tool\engine\build_windows_engine.ps1
```

It clones Flutter at the tag into `C:\src\flutter-wintext` (`-FlutterDir`),
syncs the engine's dependencies (tens of GB, the first time takes long),
applies the patch and builds `out\host_debug`. `-Mode release` or `-Mode both`
builds `out\host_release` as well. `-SkipSync` skips `gclient sync` on later
runs.

## Running

A plain `flutter run -d windows` uses the stock engine. Run with the patched
checkout's tool and the local engine:

```powershell
C:\src\flutter-wintext\bin\flutter.bat run -d windows `
  --local-engine=host_debug --local-engine-host=host_debug
```

For a release build:

```powershell
C:\src\flutter-wintext\bin\flutter.bat build windows --release `
  --local-engine=host_release --local-engine-host=host_release
```

or copy `engine\src\out\host_release\flutter_windows.dll` over the one next to
`baocode.exe` in a stock build of the same tag. Only that DLL differs; the
Dart snapshot is the same because the tag (and so the Dart SDK) is.

## Shipping

`flutter_windows.dll` here is that release build: Flutter 3.47.5 with
`windows_text.patch` as of f36847d, built with
`build_windows_engine.ps1 -Mode release`; SHA-256
`d20feefdf335b0e3ae92f4e2f1b1892b5bd9d4c80b194b14b8bb87b34b9591d5`.
It is not shipped now: the app draws with Skia on Windows, as on macOS
(`windows/runner/main.cpp`), and the patch only changes Impeller's text, so
`tool/build_windows.dart` (and so the release workflow) keeps Flutter's engine.
`dart run tool/build_windows.dart --patched-engine` puts this one in the bundle
in place of Flutter's, after checking the hashes it keeps: the bundle's must be
the stock engine of the same Flutter. It only matters with Impeller
(`BAOCODE_IMPELLER=1`).

When `FLUTTER_VERSION` changes, the check stops a `--patched-engine` build.
Then:

1. `build_windows_engine.ps1 -Tag <new version> -Mode release` (the patch may
   need its context refreshed).
2. Copy `engine\src\out\host_release\flutter_windows.dll` here.
3. Update `_stockEngineSha256` (the new stock release DLL) and
   `_patchedEngineSha256` in `tool/build_windows.dart`.
