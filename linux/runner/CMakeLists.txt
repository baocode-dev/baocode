cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "clipboard.cc"
  "login_window.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
pkg_check_modules(FONTCONFIG REQUIRED IMPORTED_TARGET fontconfig)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::FONTCONFIG)

# WebKitGTK, for the channel build's login window (login_window.cc): only in
# the channel build (BAOCODE_CHANNEL=true in the environment, as
# tool/package_linux_deb.sh --channel's package depends on it), which needs
# libwebkit2gtk-4.1-dev to build. The standard build does without it, and
# without the library on the system.
if("$ENV{BAOCODE_CHANNEL}" STREQUAL "true")
  pkg_check_modules(WEBKIT REQUIRED IMPORTED_TARGET webkit2gtk-4.1>=2.40)
  target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::WEBKIT)
  target_compile_definitions(${BINARY_NAME} PRIVATE HAVE_WEBKIT)
endif()

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
