cmake_minimum_required(VERSION 3.14)

# baocode_wer.dll, Windows Error Reporting's module for the app's fast
# fails (wer_module.cpp), beside baocode.exe. It writes the reports the
# runner does (crash_report.cpp).
add_library(baocode_wer SHARED
  "wer_module.cpp"
  "../runner/crash_report.cpp"
)
apply_standard_settings(baocode_wer)
target_compile_options(baocode_wer PRIVATE /utf-8)
target_compile_definitions(baocode_wer PRIVATE "NOMINMAX"
  "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_link_libraries(baocode_wer PRIVATE "dbghelp.lib")

# The C runtime linked in: Windows Error Reporting's process, which loads
# the module, looks for the DLLs it needs beside itself (System32), where
# the VC++ runtime may be missing or older than the build's. These flags
# are this folder's alone (the property, where CMake takes the runtime from
# it instead: policy CMP0091 new as the project begins).
set_property(TARGET baocode_wer PROPERTY
  MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
foreach(config DEBUG RELEASE PROFILE RELWITHDEBINFO MINSIZEREL)
  string(REPLACE "/MDd" "/MTd" CMAKE_CXX_FLAGS_${config} "${CMAKE_CXX_FLAGS_${config}}")
  string(REPLACE "/MD" "/MT" CMAKE_CXX_FLAGS_${config} "${CMAKE_CXX_FLAGS_${config}}")
endforeach()
