#ifndef RUNNER_LOG_FOLDER_H_
#define RUNNER_LOG_FOLDER_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

// Where the app's logs go: the data folder's logs\, beside Flutter's
// errors.log (see lib/platform/error_log.dart) — window.log (see
// Win32Window::SizeContent) and the hang reports (see hang_watchdog.h).
//
// Only Flutter knows the data folder, which the user can move (the
// BAOCODE_DATA_DIR variable, ~/.baocode/config-dir.json). It names the
// folder over `baocode/logs` as it starts:
//
//   setFolder (path)  the logs folder, absolute
//
// and the folder is kept (HKCU\Software\BaoCode, LogsFolder) for what is
// written before that, in a later run or by another copy of the app (see
// hang_watchdog::ReportRunningCopy); %APPDATA%\baocode\logs, the data
// folder's default place, before the first time.
namespace log_folder {

// Answers `baocode/logs` on |messenger| for as long as the channel is kept.
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> Listen(
    flutter::BinaryMessenger* messenger);

// The folder, made if need be; empty if there is none. From any thread.
std::wstring Path();

}  // namespace log_folder

#endif  // RUNNER_LOG_FOLDER_H_
