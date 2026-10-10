#include "open_requests.h"

#include <flutter/method_call.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <utility>

#include "utils.h"

namespace {

// The window class the runner's window has: win32_window.cpp's
// kWindowClassName (other Flutter apps' windows have it too, hence the mark
// below).
constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// The property MarkOpenRequestWindow puts on the window.
constexpr wchar_t kOpenRequestProperty[] = L"BaoCode.OpenRequests";

// How long a second copy of the app waits for the first's window while that
// is still starting, and how often it looks.
constexpr int kWindowWaitMilliseconds = 2000;
constexpr int kWindowLookMilliseconds = 100;

// How long the first copy's window has to take the paths.
constexpr UINT kSendTimeoutMilliseconds = 5000;

// The window of the copy of the app already running for the user: one of
// the runner's class that carries the mark. Null when there is none (yet).
HWND RunningWindow() {
  HWND window = nullptr;
  while ((window = ::FindWindowExW(nullptr, window, kWindowClassName,
                                   nullptr)) != nullptr) {
    if (::GetPropW(window, kOpenRequestProperty) != nullptr) {
      return window;
    }
  }
  return nullptr;
}

// |path| made absolute from the current folder, as the system resolves it;
// empty when it cannot be.
std::wstring FullPath(const wchar_t* path) {
  // Asked with no room, it answers the room needed, the terminator counted;
  // given it, the length written, without.
  const DWORD needed = ::GetFullPathNameW(path, 0, nullptr, nullptr);
  if (needed == 0) {
    return std::wstring();
  }
  std::wstring full(needed, L'\0');
  const DWORD written =
      ::GetFullPathNameW(path, needed, full.data(), nullptr);
  if (written == 0 || written >= needed) {
    return std::wstring();
  }
  full.resize(written);
  return full;
}

// The markers Flutter knows a request by (lib/window/code_args.dart's
// requestMarker, agentRequestMarker, uriRequestMarker): a null, then
// "code", "agent" or "uri".
const std::string& CodeRequestMarker() {
  static const std::string marker("\0code", 5);
  return marker;
}

const std::string& AgentRequestMarker() {
  static const std::string marker("\0agent", 6);
  return marker;
}

const std::string& UriRequestMarker() {
  static const std::string marker("\0uri", 4);
  return marker;
}

// |request| (see IsRequest) as Flutter takes it: its flag the marker.
void AddRequest(flutter::EncodableList& list,
                std::vector<std::string> request) {
  const std::string& flag = request.front();
  list.push_back(flutter::EncodableValue(
      flag == kAgentRequestFlag ? AgentRequestMarker()
      : flag == kUrlRequestFlag ? UriRequestMarker()
                                : CodeRequestMarker()));
  for (size_t index = 1; index < request.size(); index++) {
    list.push_back(flutter::EncodableValue(std::move(request[index])));
  }
}

}  // namespace

bool IsRequest(const std::vector<std::string>& paths) {
  return !paths.empty() && (paths.front() == kCodeRequestFlag ||
                            paths.front() == kAgentRequestFlag ||
                            paths.front() == kUrlRequestFlag);
}

OpenRequests::OpenRequests(flutter::BinaryMessenger* messenger,
                           std::vector<std::string> pending)
    : pending_(std::move(pending)),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "baocode/open",
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        if (method == "takePending") {
          flutter::EncodableList paths;
          for (const std::string& path : pending_) {
            paths.push_back(flutter::EncodableValue(path));
          }
          for (std::vector<std::string>& request : pending_requests_) {
            AddRequest(paths, std::move(request));
          }
          pending_.clear();
          pending_requests_.clear();
          ready_ = true;
          result->Success(flutter::EncodableValue(std::move(paths)));
          return;
        }
        if (method == "stop") {
          ready_ = false;
          result->Success();
          return;
        }
        result->NotImplemented();
      });
}

OpenRequests::~OpenRequests() {
  channel_->SetMethodCallHandler(nullptr);
}

void OpenRequests::Deliver(std::vector<std::string> paths) {
  const bool request = IsRequest(paths);
  if (!ready_) {
    if (request) {
      pending_requests_.push_back(std::move(paths));
    } else {
      pending_.insert(pending_.end(), paths.begin(), paths.end());
    }
    return;
  }
  if (paths.empty()) {
    return;
  }
  flutter::EncodableList list;
  if (request) {
    AddRequest(list, std::move(paths));
  } else {
    for (std::string& path : paths) {
      list.push_back(flutter::EncodableValue(std::move(path)));
    }
  }
  channel_->InvokeMethod(
      "open", std::make_unique<flutter::EncodableValue>(std::move(list)));
}

std::vector<std::string> OpenPathsFromCommandLine() {
  std::vector<std::string> paths;
  int count = 0;
  wchar_t** arguments = ::CommandLineToArgvW(::GetCommandLineW(), &count);
  if (arguments == nullptr) {
    return paths;
  }
  // The first is the app itself. From code.cmd, the arguments go as they
  // came: the flag, the folder, then what was typed (empty ones left out,
  // as WM_COPYDATA's payload would lose them).
  if (count > 1 && Utf8FromUtf16(arguments[1]) == kCodeRequestFlag) {
    for (int index = 1; index < count; index++) {
      std::string argument = Utf8FromUtf16(arguments[index]);
      if (!argument.empty()) {
        paths.push_back(std::move(argument));
      }
    }
    ::LocalFree(arguments);
    return paths;
  }
  // From the `baocode` URL protocol (`--open-url -- <uri>`): the flag, then
  // the URI, not a path.
  if (count > 1 && Utf8FromUtf16(arguments[1]) == kUrlRequestFlag) {
    paths.push_back(kUrlRequestFlag);
    for (int index = 2; index < count; index++) {
      std::string argument = Utf8FromUtf16(arguments[index]);
      if (!argument.empty() && argument != "--") {
        paths.push_back(std::move(argument));
      }
    }
    ::LocalFree(arguments);
    return paths;
  }
  // From Open with BaoCode, its flag first: the paths, as below, go to an
  // agent.
  const bool agent =
      count > 1 && Utf8FromUtf16(arguments[1]) == kAgentRequestFlag;
  if (agent) {
    paths.push_back(kAgentRequestFlag);
  }
  for (int index = agent ? 2 : 1; index < count; index++) {
    const wchar_t* argument = arguments[index];
    if (argument[0] == L'\0' || argument[0] == L'-') {
      continue;
    }
    const std::wstring full = FullPath(argument);
    if (full.empty()) {
      continue;
    }
    std::string path = Utf8FromUtf16(full.c_str());
    if (!path.empty()) {
      paths.push_back(std::move(path));
    }
  }
  ::LocalFree(arguments);
  return paths;
}

void MarkOpenRequestWindow(HWND window, bool marked) {
  if (marked) {
    ::SetPropW(window, kOpenRequestProperty,
               reinterpret_cast<HANDLE>(static_cast<INT_PTR>(1)));
  } else {
    ::RemovePropW(window, kOpenRequestProperty);
  }
}

bool ForwardToRunningWindow(const std::vector<std::string>& paths) {
  // The paths one after another, each ended by a null.
  std::string payload;
  for (const std::string& path : paths) {
    payload += path;
    payload.push_back('\0');
  }
  for (int waited = 0;; waited += kWindowLookMilliseconds) {
    if (const HWND window = RunningWindow()) {
      // The window comes to the front for what it is handed: this copy,
      // which the user just started, has the right to put a window there,
      // and gives it to the one running.
      DWORD process = 0;
      ::GetWindowThreadProcessId(window, &process);
      ::AllowSetForegroundWindow(process != 0 ? process : ASFW_ANY);
      COPYDATASTRUCT data = {};
      data.dwData = kOpenRequestData;
      data.cbData = static_cast<DWORD>(payload.size());
      data.lpData = payload.empty() ? nullptr : payload.data();
      DWORD_PTR answer = 0;
      return ::SendMessageTimeoutW(window, WM_COPYDATA, 0,
                                   reinterpret_cast<LPARAM>(&data),
                                   SMTO_ABORTIFHUNG, kSendTimeoutMilliseconds,
                                   &answer) != 0;
    }
    if (waited >= kWindowWaitMilliseconds) {
      return false;
    }
    ::Sleep(kWindowLookMilliseconds);
  }
}

std::vector<std::string> OpenRequestPaths(const COPYDATASTRUCT& data) {
  std::vector<std::string> paths;
  if (data.dwData != kOpenRequestData || data.lpData == nullptr) {
    return paths;
  }
  const char* bytes = static_cast<const char*>(data.lpData);
  std::string path;
  for (DWORD index = 0; index < data.cbData; index++) {
    if (bytes[index] != '\0') {
      path.push_back(bytes[index]);
      continue;
    }
    if (!path.empty()) {
      paths.push_back(std::move(path));
    }
    path.clear();
  }
  if (!path.empty()) {
    paths.push_back(std::move(path));
  }
  return paths;
}
