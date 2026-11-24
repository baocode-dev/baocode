cmake_minimum_required(VERSION 3.14)
project(browser_bridge LANGUAGES CXX)

# baocode-browser-host.exe, the browsers' native messaging host (host.cpp).
# It goes beside baocode.exe with dev.baocode.browser.json, the manifest
# the browsers find it by: the installer's keys point there (see
# tool/baocode.iss), and its "path", relative, is the host beside it.
add_executable(baocode-browser-host "host.cpp")
apply_standard_settings(baocode-browser-host)
target_compile_options(baocode-browser-host PRIVATE /utf-8)
target_compile_definitions(baocode-browser-host PRIVATE
  "NOMINMAX" "WIN32_LEAN_AND_MEAN" "_WIN32_WINNT=0x0600")
target_link_libraries(baocode-browser-host PRIVATE
  "ws2_32.lib" "shell32.lib" "ole32.lib")
