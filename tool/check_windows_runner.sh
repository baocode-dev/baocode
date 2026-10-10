#!/usr/bin/env bash
# Compiles and links the Windows runner (windows/runner, the generated plugin
# registrant and Flutter's C++ client wrapper) on macOS or Linux with
# mingw-w64, against the headers in the Flutter SDK's engine source. What it
# checks is that the runner compiles and that every symbol it needs is one
# flutter_windows.dll or a plugin's DLL exports; it does not run anything, and
# it is not MSVC (whose /W4 /WX may warn where GCC does not).
#
# The DLLs come from Windows builds only, so they are import libraries here:
# each name the link asks for must be declared FLUTTER_EXPORT in the engine's
# windows headers (public or flutter_windows_internal.h), or be a plugin's
# FLUTTER_PLUGIN_EXPORT, or the check fails.
#
#   brew install mingw-w64
#   tool/check_windows_runner.sh

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

cxx=x86_64-w64-mingw32-g++
command -v "$cxx" >/dev/null || { echo "$cxx not found (brew install mingw-w64)" >&2; exit 2; }

flutter_root="${FLUTTER_ROOT:-$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")}"
engine="$flutter_root/engine/src/flutter/shell/platform"
[ -d "$engine/windows/client_wrapper" ] || { echo "no engine source under $flutter_root" >&2; exit 2; }

out="$(mktemp -d "${TMPDIR:-/tmp}/baocode-windows-runner.XXXXXX")"
trap 'rm -rf "$out"' EXIT

# The layout of Flutter's Windows artifacts: the public headers, and the
# client wrapper's headers all in one flutter/ folder.
mkdir -p "$out/inc/flutter" "$out/wrap/include" "$out/plug" "$out/obj"
cp "$engine"/common/client_wrapper/include/flutter/*.h \
  "$engine"/windows/client_wrapper/include/flutter/*.h "$out/inc/flutter/"
cp "$engine"/windows/public/*.h "$engine"/common/public/*.h "$out/inc/"
cp "$engine"/common/client_wrapper/*.h "$out/wrap/"
ln -s "$out/inc/flutter" "$out/wrap/include/flutter"

# The plugins' headers, from the packages pub resolved.
plugins=()
while IFS= read -r line; do plugins+=("$line"); done < <(
  sed -n 's/^#include <\([a-z_]*\)\/.*/\1/p' windows/flutter/generated_plugin_registrant.cc)
for plugin in "${plugins[@]}"; do
  dir="$(python3 -I -c '
import json, sys
from urllib.parse import urlparse, unquote
for p in json.load(open(".dart_tool/package_config.json"))["packages"]:
    if p["name"] == sys.argv[1]:
        print(unquote(urlparse(p["rootUri"]).path))' "$plugin")"
  [ -n "$dir" ] || { echo "$plugin is not resolved (flutter pub get)" >&2; exit 2; }
  mkdir -p "$out/plug/$plugin"
  cp "$dir/windows/include/$plugin"/*.h "$out/plug/$plugin/"
done

# windows/CMakeLists.txt's definitions.
flags=(-std=c++17 -DUNICODE -D_UNICODE -DNOMINMAX -D_HAS_EXCEPTIONS=0
  '-DFLUTTER_VERSION="0.0.0"' -DFLUTTER_VERSION_MAJOR=0 -DFLUTTER_VERSION_MINOR=0
  -DFLUTTER_VERSION_PATCH=0 -DFLUTTER_VERSION_BUILD=0
  -I"$out/inc" -I"$out/inc/flutter" -I"$out/plug" -I"$out/wrap"
  -Iwindows -Iwindows/flutter -Iwindows/runner)

failed=0
compile() { # <source> <object> [flags...]
  local source="$1" object="$2"
  shift 2
  if ! "$cxx" "${flags[@]}" "$@" -c "$source" -o "$out/obj/$object" 2>"$out/obj/$object.log"; then
    echo "FAIL $source" >&2
    cat "$out/obj/$object.log" >&2
    failed=1
  else
    echo "ok   $source"
  fi
}

for source in windows/runner/*.cpp windows/flutter/generated_plugin_registrant.cc; do
  compile "$source" "$(basename "${source%.*}").o" -Wall -Wextra -Wno-unused-parameter
done
for source in "$engine"/common/client_wrapper/{core_implementations,standard_codec,plugin_registrar}.cc \
  "$engine"/windows/client_wrapper/{flutter_engine,flutter_view_controller}.cc; do
  compile "$source" "wrapper_$(basename "${source%.*}").o" -w
done

# Runner.rc, its paths with forward slashes for windres.
sed 's#\\\\#/#g' windows/runner/Runner.rc >"$out/Runner.rc"
if (cd windows/runner && x86_64-w64-mingw32-windres -I. \
  '-DFLUTTER_VERSION=\"0.0.0\"' -DFLUTTER_VERSION_MAJOR=0 -DFLUTTER_VERSION_MINOR=0 \
  -DFLUTTER_VERSION_PATCH=0 -DFLUTTER_VERSION_BUILD=0 \
  "$out/Runner.rc" -O coff -o "$out/obj/runner_rc.o"); then
  echo "ok   windows/runner/Runner.rc"
else
  echo "FAIL windows/runner/Runner.rc" >&2
  failed=1
fi
[ "$failed" = 0 ] || exit 1

# windows/runner/CMakeLists.txt's libraries, and what MinGW needs besides.
libs=(-ldwmapi -lole32 -lshell32 -lwindowscodecs -lwinmm -ldbghelp -luuid -loleaut32)

# What the DLLs must give: the names left over without them.
"$cxx" -municode -mwindows -o "$out/BaoCode.exe" "$out"/obj/*.o "${libs[@]}" 2>"$out/link.log" || true
grep -oE "undefined reference to \`[^']+'" "$out/link.log" |
  sed "s/undefined reference to \`//; s/'\$//; s/^__imp_//" | sort -u >"$out/undefined.txt"

python3 -I - "$out" "$engine" "${plugins[@]}" <<'EOF'
import glob, re, sys
out, engine, plugins = sys.argv[1], sys.argv[2], sys.argv[3:]
def exported(paths, macro):
    names = set()
    for path in paths:
        names |= set(re.findall(macro + r'[^;(]*?\b(\w+)\s*\(', open(path).read(), re.S))
    return names
flutter = exported(glob.glob(engine + '/windows/public/*.h') + glob.glob(engine + '/common/public/*.h')
                   + [engine + '/windows/flutter_windows_internal.h'], 'FLUTTER_EXPORT')
dlls = {'flutter_windows': [], **{p: [] for p in plugins}}
plugin_exports = {p: exported(glob.glob(f'{out}/plug/{p}/*.h'), 'FLUTTER_PLUGIN_EXPORT') for p in plugins}
unknown = []
for name in open(out + '/undefined.txt').read().split():
    if name in flutter:
        dlls['flutter_windows'].append(name)
    elif owner := next((p for p, names in plugin_exports.items() if name in names), None):
        dlls[owner].append(name)
    else:
        unknown.append(name)
if unknown:
    sys.exit('not exported by any DLL: ' + ', '.join(unknown))
for dll, names in dlls.items():
    library = dll if dll == 'flutter_windows' else dll + '_plugin'
    with open(f'{out}/{dll}.def', 'w') as f:
        f.write(f'LIBRARY {library}.dll\nEXPORTS\n' + ''.join(n + '\n' for n in names))
    print(f'{len(names):3} from {library}.dll')
EOF

imports=()
for def in "$out"/*.def; do
  name="$(basename "${def%.def}")"
  x86_64-w64-mingw32-dlltool -d "$def" -l "$out/lib$name.dll.a"
  imports+=("-l$name.dll")
done
"$cxx" -municode -mwindows -o "$out/BaoCode.exe" "$out"/obj/*.o -L"$out" "${imports[@]}" "${libs[@]}"
echo "linked: $(file -b "$out/BaoCode.exe")"
