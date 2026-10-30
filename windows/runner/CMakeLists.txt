cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "app_windows.cpp"
  "attention.cpp"
  "caption_areas.cpp"
  "clipboard_images.cpp"
  "context_menu.cpp"
  "drag_source.cpp"
  "drop_target.cpp"
  "flutter_window.cpp"
  "hang_watchdog.cpp"
  "log_folder.cpp"
  "login_window.cpp"
  "main.cpp"
  "open_requests.cpp"
  "stash_channel.cpp"
  "stash_ocr.cpp"
  "utils.cpp"
  "view_window.cpp"
  "win32_window.cpp"
  "window_channel.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Source files are UTF-8 (comments may use non-ASCII). Without this, MSVC on a
# Chinese locale misreads them as GBK and /WX turns C4819 into a failed build.
target_compile_options(${BINARY_NAME} PRIVATE /utf-8)

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# The DEV-badged icon for Debug builds (Runner.rc). A generator expression,
# not CMAKE_BUILD_TYPE: Visual Studio's generator builds every configuration
# from one cache, where CMAKE_BUILD_TYPE is empty.
target_compile_definitions(${BINARY_NAME} PRIVATE "$<$<CONFIG:Debug>:BAOCODE_DEV_ICON>")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" "ole32.lib"
  "shell32.lib" "uuid.lib" "windowscodecs.lib" "winmm.lib" "dbghelp.lib"
  "runtimeobject.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# The WebView2 SDK, for the channel build's login window (login_window.cpp):
# NuGet's package, fetched once into the build folder, its loader linked in
# (no WebView2Loader.dll to ship). The runtime is the system's (Windows 11
# has it; the Evergreen installer elsewhere).
set(WEBVIEW2_VERSION "1.0.4191.47")
set(WEBVIEW2_SHA256 "f492bbf547d0da329553b6727435b677579b1e9f91cc9e4a1ad029366d5f23d0")
set(WEBVIEW2_DIR "${CMAKE_BINARY_DIR}/webview2-${WEBVIEW2_VERSION}")
if(NOT EXISTS "${WEBVIEW2_DIR}/build/native/include/WebView2.h")
  file(DOWNLOAD
    "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/${WEBVIEW2_VERSION}"
    "${WEBVIEW2_DIR}.nupkg"
    EXPECTED_HASH SHA256=${WEBVIEW2_SHA256}
    TLS_VERIFY ON)
  file(MAKE_DIRECTORY "${WEBVIEW2_DIR}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xf "${WEBVIEW2_DIR}.nupkg"
    WORKING_DIRECTORY "${WEBVIEW2_DIR}")
endif()
if(CMAKE_GENERATOR_PLATFORM MATCHES "ARM64" OR CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|arm64|aarch64")
  set(WEBVIEW2_ARCH "arm64")
else()
  set(WEBVIEW2_ARCH "x64")
endif()
target_include_directories(${BINARY_NAME} PRIVATE "${WEBVIEW2_DIR}/build/native/include")
target_link_libraries(${BINARY_NAME} PRIVATE
  "${WEBVIEW2_DIR}/build/native/${WEBVIEW2_ARCH}/WebView2LoaderStatic.lib"
  "version.lib" "shlwapi.lib")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
