#!/bin/sh
# Builds baocode-browser-host (host.c) into the app's Contents/MacOS and
# signs it as the app is: run by Xcode, a build phase of Runner's.
set -e
src="$PROJECT_DIR/BrowserBridge/host.c"
out="$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/baocode-browser-host"
arch_flags=""
for arch in $ARCHS; do arch_flags="$arch_flags -arch $arch"; done
xcrun clang -O2 -Wall -Wextra $arch_flags \
  -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" -o "$out" "$src" -lproc
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
options=""
if [ "$ENABLE_HARDENED_RUNTIME" = "YES" ]; then options="--options runtime"; fi
codesign --force --sign "$identity" $options --timestamp=none "$out"
