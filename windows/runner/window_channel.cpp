#include "window_channel.h"

#include <flutter/method_codec.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <algorithm>
#include <cmath>
#include <cwchar>
#include <deque>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "clipboard_images.h"
#include "context_menu.h"
#include "drag_source.h"
#include "drop_target.h"
#include "win32_window.h"
#include "utils.h"

namespace {

using Microsoft::WRL::ComPtr;

// The arguments of a call, as a map: an empty one when it sent none.
const flutter::EncodableMap& Arguments(const flutter::EncodableValue* value) {
  static const flutter::EncodableMap kNone;
  if (value == nullptr) {
    return kNone;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(value);
  return map == nullptr ? kNone : *map;
}

std::string String(const flutter::EncodableMap& arguments, const char* key) {
  const auto found = arguments.find(flutter::EncodableValue(key));
  if (found == arguments.end()) {
    return std::string();
  }
  const auto* value = std::get_if<std::string>(&found->second);
  return value == nullptr ? std::string() : *value;
}

double Number(const flutter::EncodableMap& arguments, const char* key) {
  const auto found = arguments.find(flutter::EncodableValue(key));
  if (found == arguments.end()) {
    return 0.0;
  }
  if (const auto* value = std::get_if<double>(&found->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int32_t>(&found->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&found->second)) {
    return static_cast<double>(*value);
  }
  return 0.0;
}

bool Boolean(const flutter::EncodableValue* value, bool fallback) {
  if (value == nullptr) {
    return fallback;
  }
  const auto* boolean = std::get_if<bool>(value);
  return boolean == nullptr ? fallback : *boolean;
}

bool Boolean(const flutter::EncodableMap& arguments, const char* key,
             bool fallback) {
  const auto found = arguments.find(flutter::EncodableValue(key));
  if (found == arguments.end()) {
    return fallback;
  }
  return Boolean(&found->second, fallback);
}

std::vector<std::string> Strings(const flutter::EncodableMap& arguments,
                                 const char* key) {
  std::vector<std::string> strings;
  const auto found = arguments.find(flutter::EncodableValue(key));
  if (found == arguments.end()) {
    return strings;
  }
  const auto* list = std::get_if<flutter::EncodableList>(&found->second);
  if (list == nullptr) {
    return strings;
  }
  for (const flutter::EncodableValue& value : *list) {
    if (const auto* string = std::get_if<std::string>(&value)) {
      strings.push_back(*string);
    }
  }
  return strings;
}

// One of the rectangles Flutter reports: its left, top, width and height.
CaptionAreas::Rect RectFrom(const flutter::EncodableMap& map) {
  CaptionAreas::Rect rect;
  rect.left = Number(map, "left");
  rect.top = Number(map, "top");
  rect.width = Number(map, "width");
  rect.height = Number(map, "height");
  return rect;
}

std::vector<CaptionAreas::Rect> Rects(const flutter::EncodableMap& arguments,
                                      const char* key) {
  std::vector<CaptionAreas::Rect> rects;
  const auto found = arguments.find(flutter::EncodableValue(key));
  if (found == arguments.end()) {
    return rects;
  }
  const auto* list = std::get_if<flutter::EncodableList>(&found->second);
  if (list == nullptr) {
    return rects;
  }
  for (const flutter::EncodableValue& value : *list) {
    if (const auto* map = std::get_if<flutter::EncodableMap>(&value)) {
      rects.push_back(RectFrom(*map));
    }
  }
  return rects;
}

// One of the three window buttons, under |key| of the map Flutter reports.
CaptionAreas::Rect ButtonRect(const flutter::EncodableMap& arguments,
                              const char* key) {
  const auto found = arguments.find(flutter::EncodableValue("buttons"));
  if (found == arguments.end()) {
    return CaptionAreas::Rect();
  }
  const auto* buttons = std::get_if<flutter::EncodableMap>(&found->second);
  if (buttons == nullptr) {
    return CaptionAreas::Rect();
  }
  const auto rect = buttons->find(flutter::EncodableValue(key));
  if (rect == buttons->end()) {
    return CaptionAreas::Rect();
  }
  const auto* map = std::get_if<flutter::EncodableMap>(&rect->second);
  return map == nullptr ? CaptionAreas::Rect() : RectFrom(*map);
}

// A command line argument: quoted, so that a path with spaces in it stays
// one argument, and escaped as the program reads its command line back
// (CommandLineToArgvW): backslashes are only literal where no quote follows
// them, which the closing one does — a drive's root, `C:\`, would otherwise
// run on into what comes after it.
std::wstring Quoted(const std::wstring& text) {
  std::wstring quoted = L"\"";
  size_t backslashes = 0;
  for (const wchar_t c : text) {
    if (c == L'\\') {
      ++backslashes;
      continue;
    }
    // Before a quote, each backslash doubled and the quote escaped.
    quoted.append(c == L'"' ? backslashes * 2 + 1 : backslashes, L'\\');
    backslashes = 0;
    quoted += c;
  }
  // Before the closing quote, each doubled.
  quoted.append(backslashes * 2, L'\\');
  return quoted + L"\"";
}

// An argument (quoted already) as cmd.exe is to pass it on unchanged, as
// node's cross-spawn has it: each character cmd makes something of is
// escaped (^), the quotes too — escaped, they start no quoted part, inside
// which % would still be read as a variable.
std::wstring CmdEscaped(const std::wstring& text) {
  constexpr std::wstring_view kSpecial = L"()[]%!^\"`<>&|;, *?";
  std::wstring escaped;
  for (const wchar_t c : text) {
    if (kSpecial.find(c) != std::wstring_view::npos) {
      escaped += L'^';
    }
    escaped += c;
  }
  return escaped;
}

// The environment variable |name|; empty when it is not set.
std::wstring EnvironmentVariable(const wchar_t* name) {
  const DWORD size = ::GetEnvironmentVariableW(name, nullptr, 0);
  if (size == 0) {
    return std::wstring();
  }
  std::wstring value(size, L'\0');
  value.resize(::GetEnvironmentVariableW(name, value.data(), size));
  return value;
}

// The parts of |text| between each |separator|, the empty ones left out.
std::vector<std::wstring> Split(const std::wstring& text, wchar_t separator) {
  std::vector<std::wstring> parts;
  size_t start = 0;
  while (start < text.size()) {
    size_t end = text.find(separator, start);
    if (end == std::wstring::npos) {
      end = text.size();
    }
    if (end > start) {
      parts.push_back(text.substr(start, end - start));
    }
    start = end + 1;
  }
  return parts;
}

bool IsFile(const std::wstring& path) {
  const DWORD attributes = ::GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

// Whether |path| ends in |extension|, in any case.
bool HasExtension(const std::wstring& path, std::wstring_view extension) {
  return path.size() > extension.size() &&
         ::_wcsicmp(path.c_str() + path.size() - extension.size(),
                    extension.data()) == 0;
}

// Where the PATH has the program |name|, as the terminal's lookup has it
// (see _locate in packages/bao_pty/lib/src/pty_windows.dart): with each of
// the PATHEXT's extensions first, then as it is — VS Code's folder has a
// `code` for Unix shells beside the `code.cmd`. Empty when it is not there,
// or |name| is a path.
std::wstring FindOnPath(const std::wstring& name) {
  if (name.find_first_of(L"\\/:") != std::wstring::npos) {
    return std::wstring();
  }
  std::wstring extensions = EnvironmentVariable(L"PATHEXT");
  if (extensions.empty()) {
    extensions = L".COM;.EXE;.BAT;.CMD";
  }
  std::vector<std::wstring> suffixes = Split(extensions, L';');
  suffixes.push_back(std::wstring());
  for (std::wstring folder : Split(EnvironmentVariable(L"PATH"), L';')) {
    // An entry with a semicolon in it comes quoted.
    if (folder.size() >= 2 && folder.front() == L'"' &&
        folder.back() == L'"') {
      folder = folder.substr(1, folder.size() - 2);
    }
    if (folder.empty()) {
      continue;
    }
    if (folder.back() != L'\\' && folder.back() != L'/') {
      folder += L'\\';
    }
    for (const std::wstring& suffix : suffixes) {
      const std::wstring candidate = folder + name + suffix;
      if (IsFile(candidate)) {
        return candidate;
      }
    }
  }
  return std::wstring();
}

// Starts the program at |path| with |arguments| (each quoted), and no
// console window: a `.cmd` or `.bat` (VS Code's `code`, Cursor's `cursor`)
// runs in cmd.exe, whose console flashes up when the shell starts it.
// False when it is neither a program nor a script, or did not start.
bool StartWithoutConsole(const std::wstring& path,
                         const std::vector<std::wstring>& arguments) {
  std::wstring application;
  std::wstring command_line;
  if (HasExtension(path, L".exe") || HasExtension(path, L".com")) {
    command_line = Quoted(path);
    for (const std::wstring& argument : arguments) {
      command_line += L' ' + argument;
    }
  } else if (HasExtension(path, L".cmd") || HasExtension(path, L".bat")) {
    application = EnvironmentVariable(L"ComSpec");
    if (application.empty()) {
      return false;
    }
    // With /s, only the outer quotes of what follows /c go: inside them,
    // the script in quotes of its own, then its arguments escaped.
    command_line = Quoted(application) + L" /d /s /c \"" + Quoted(path);
    for (const std::wstring& argument : arguments) {
      command_line += L' ' + CmdEscaped(argument);
    }
    command_line += L'"';
  } else {
    return false;
  }
  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process = {};
  if (!::CreateProcessW(application.empty() ? nullptr : application.c_str(),
                        command_line.data(), nullptr, nullptr, FALSE,
                        CREATE_NO_WINDOW, nullptr, nullptr, &startup,
                        &process)) {
    return false;
  }
  ::CloseHandle(process.hThread);
  ::CloseHandle(process.hProcess);
  return true;
}

// The work area of the monitor |window| is on: the screen less the taskbar.
// Empty when it cannot be told.
RECT WorkArea(HWND window) {
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  if (!::GetMonitorInfoW(::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                         &info)) {
    return RECT{};
  }
  return info.rcWork;
}

// The paths of what the user picked in |dialog|, once it has closed with
// them.
std::vector<std::wstring> PickedPaths(IFileOpenDialog* dialog) {
  ComPtr<IShellItemArray> items;
  if (FAILED(dialog->GetResults(&items))) {
    return {};
  }
  DWORD count = 0;
  items->GetCount(&count);
  std::vector<std::wstring> paths;
  for (DWORD index = 0; index < count; index++) {
    ComPtr<IShellItem> item;
    PWSTR path = nullptr;
    if (SUCCEEDED(items->GetItemAt(index, &item)) &&
        SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
      paths.emplace_back(path);
      ::CoTaskMemFree(path);
    }
  }
  return paths;
}

// Opens |dialog| in |directory| (UTF-8), when there is one; where the
// system would otherwise (the last folder it was used in).
void OpenIn(IFileDialog* dialog, const std::string& directory) {
  if (directory.empty()) {
    return;
  }
  ComPtr<IShellItem> folder;
  if (SUCCEEDED(::SHCreateItemFromParsingName(
          Utf16FromUtf8(directory).c_str(), nullptr, IID_PPV_ARGS(&folder)))) {
    dialog->SetFolder(folder.Get());
  }
}

// The files the user picked through the system's own panel to open in the
// IDE (Open File…), from |directory| when given: one at most unless
// |multiple|. None when they cancel, or it cannot be shown.
std::vector<std::wstring> PickOpenFiles(HWND window,
                                        const std::string& directory,
                                        bool multiple) {
  ComPtr<IFileOpenDialog> dialog;
  if (FAILED(::CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) {
    return {};
  }
  DWORD options = 0;
  if (SUCCEEDED(dialog->GetOptions(&options))) {
    options |= FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST;
    if (multiple) {
      options |= FOS_ALLOWMULTISELECT;
    }
    dialog->SetOptions(options);
  }
  OpenIn(dialog.Get(), directory);
  if (FAILED(dialog->Show(window))) {
    return {};
  }
  return PickedPaths(dialog.Get());
}

// Where the user chose to save a file (Save As…, an untitled one's Save),
// from |directory| and under |name| when given; the panel asks itself
// before replacing a file. Null when they cancel, or it cannot be shown.
std::optional<std::string> PickSaveFile(HWND window,
                                        const std::string& directory,
                                        const std::string& name) {
  ComPtr<IFileSaveDialog> dialog;
  if (FAILED(::CoCreateInstance(CLSID_FileSaveDialog, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) {
    return std::nullopt;
  }
  DWORD options = 0;
  if (SUCCEEDED(dialog->GetOptions(&options))) {
    dialog->SetOptions(options | FOS_OVERWRITEPROMPT | FOS_FORCEFILESYSTEM);
  }
  OpenIn(dialog.Get(), directory);
  if (!name.empty()) {
    dialog->SetFileName(Utf16FromUtf8(name).c_str());
  }
  if (FAILED(dialog->Show(window))) {
    return std::nullopt;
  }
  ComPtr<IShellItem> file;
  if (FAILED(dialog->GetResult(&file))) {
    return std::nullopt;
  }
  PWSTR path = nullptr;
  if (FAILED(file->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
    return std::nullopt;
  }
  std::optional<std::string> picked = Utf8FromUtf16(path);
  ::CoTaskMemFree(path);
  return picked;
}

// The files the user picked through the system's own panel, to put in the
// composer (Add Context…); none when they cancel, or it cannot be shown.
std::vector<std::wstring> PickFiles(HWND window) {
  ComPtr<IFileOpenDialog> dialog;
  if (FAILED(::CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) {
    return {};
  }
  DWORD options = 0;
  if (SUCCEEDED(dialog->GetOptions(&options))) {
    dialog->SetOptions(options | FOS_ALLOWMULTISELECT | FOS_FORCEFILESYSTEM |
                       FOS_FILEMUSTEXIST);
  }
  dialog->SetOkButtonLabel(L"Add");
  if (FAILED(dialog->Show(window))) {
    return {};
  }
  return PickedPaths(dialog.Get());
}

// The project folder the user picked through the system's own panel; null
// when they cancel, or it cannot be shown.
std::optional<std::string> PickDirectory(HWND window) {
  ComPtr<IFileOpenDialog> dialog;
  if (FAILED(::CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) {
    return std::nullopt;
  }
  DWORD options = 0;
  if (SUCCEEDED(dialog->GetOptions(&options))) {
    dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM |
                       FOS_PATHMUSTEXIST);
  }
  dialog->SetTitle(L"Choose a project folder");
  dialog->SetOkButtonLabel(L"Open");
  // The panel runs its own message loop, which keeps Flutter drawing while
  // it is up.
  if (FAILED(dialog->Show(window))) {
    return std::nullopt;
  }
  ComPtr<IShellItem> folder;
  if (FAILED(dialog->GetResult(&folder))) {
    return std::nullopt;
  }
  PWSTR path = nullptr;
  if (FAILED(folder->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
    return std::nullopt;
  }
  std::optional<std::string> picked = Utf8FromUtf16(path);
  ::CoTaskMemFree(path);
  return picked;
}

struct OpenCompletion {
  uint64_t request_id = 0;
  bool worked = false;
};

// Runs the blocking work of `open`: looks up |app| on PATH and starts it
// without a console, falling back to ShellExecuteW when that does not apply
// (and COM is ready in this apartment).
bool ExecuteOpen(const std::wstring& target, const std::wstring& app,
                 const std::vector<std::wstring>& extras, bool com_ready) {
  std::vector<std::wstring> quoted;
  if (!app.empty()) {
    if (extras.empty()) {
      quoted.push_back(Quoted(target));
    } else {
      for (const std::wstring& extra : extras) {
        quoted.push_back(Quoted(extra));
      }
    }
    const std::wstring found = FindOnPath(app);
    if (!found.empty() && StartWithoutConsole(found, quoted)) {
      return true;
    }
  }
  if (!com_ready) {
    return false;
  }
  const std::wstring& file = app.empty() ? target : app;
  std::wstring parameters;
  for (const std::wstring& argument : quoted) {
    if (!parameters.empty()) {
      parameters += L' ';
    }
    parameters += argument;
  }
  const HINSTANCE opened =
      ::ShellExecuteW(nullptr, L"open", file.c_str(),
                      parameters.empty() ? nullptr : parameters.c_str(),
                      nullptr, SW_SHOWNORMAL);
  // ShellExecute answers a value above 32 when it worked, or an error code
  // under it (33 and up are the codes it means).
  return reinterpret_cast<INT_PTR>(opened) > 32;
}

}  // namespace

// Dedicated STA worker thread for blocking Shell APIs (`revealInFinder` and
// `open`): lazily started, bounded queue, and non-blocking Stop() on window
// teardown so stalling shell extensions or antivirus scans never freeze the
// window's message loop or pile up unbounded detached threads.
class WindowChannel::ShellWorker
    : public std::enable_shared_from_this<WindowChannel::ShellWorker> {
 public:
  ShellWorker() = default;
  ~ShellWorker() {
    if (wake_event_ != nullptr) {
      ::CloseHandle(wake_event_);
    }
  }

  ShellWorker(const ShellWorker&) = delete;
  ShellWorker& operator=(const ShellWorker&) = delete;

  void EnqueueReveal(std::wstring path) {
    if (path.empty()) {
      return;
    }
    HANDLE event = nullptr;
    ::AcquireSRWLockExclusive(&lock_);
    if (stopping_) {
      ::ReleaseSRWLockExclusive(&lock_);
      return;
    }
    for (const Task& queued : queue_) {
      if (queued.kind == Task::Kind::kReveal && queued.target == path) {
        ::ReleaseSRWLockExclusive(&lock_);
        return;
      }
    }
    if (queue_.size() >= kMaxPendingTasks) {
      // Drop the oldest queued reveal rather than an `open` whose Dart Future
      // awaits an answer.
      auto oldest_reveal = std::find_if(
          queue_.begin(), queue_.end(),
          [](const Task& item) { return item.kind == Task::Kind::kReveal; });
      if (oldest_reveal == queue_.end()) {
        ::ReleaseSRWLockExclusive(&lock_);
        return;
      }
      queue_.erase(oldest_reveal);
    }
    Task task;
    task.kind = Task::Kind::kReveal;
    task.target = std::move(path);
    queue_.push_back(std::move(task));
    if (EnsureStartedLocked()) {
      event = wake_event_;
    } else {
      queue_.pop_back();
    }
    ::ReleaseSRWLockExclusive(&lock_);
    if (event != nullptr) {
      ::SetEvent(event);
    }
  }

  bool EnqueueOpen(uint64_t request_id, HWND owner, std::wstring target,
                   std::wstring app, std::vector<std::wstring> extras) {
    HANDLE event = nullptr;
    bool accepted = false;
    ::AcquireSRWLockExclusive(&lock_);
    if (!stopping_ && queue_.size() < kMaxPendingTasks) {
      Task task;
      task.kind = Task::Kind::kOpen;
      task.request_id = request_id;
      task.owner = owner;
      task.target = std::move(target);
      task.app = std::move(app);
      task.extras = std::move(extras);
      queue_.push_back(std::move(task));
      if (EnsureStartedLocked()) {
        event = wake_event_;
        accepted = true;
      } else {
        queue_.pop_back();
      }
    }
    ::ReleaseSRWLockExclusive(&lock_);
    if (event != nullptr) {
      ::SetEvent(event);
    }
    return accepted;
  }

  // Tells the worker to drop queued work and exit without blocking the window
  // thread (which would stall closing if a shell extension is stuck).
  void Stop() {
    HANDLE event = nullptr;
    ::AcquireSRWLockExclusive(&lock_);
    stopping_ = true;
    queue_.clear();
    event = wake_event_;
    ::ReleaseSRWLockExclusive(&lock_);
    if (event != nullptr) {
      ::SetEvent(event);
    }
  }

 private:
  static constexpr size_t kMaxPendingTasks = 16;

  struct Task {
    enum class Kind { kReveal, kOpen };
    Kind kind = Kind::kReveal;
    uint64_t request_id = 0;
    HWND owner = nullptr;
    std::wstring target;
    std::wstring app;
    std::vector<std::wstring> extras;
  };

  bool EnsureStartedLocked() {
    if (started_) {
      return true;
    }
    if (wake_event_ == nullptr) {
      wake_event_ = ::CreateEventW(nullptr, FALSE, FALSE, nullptr);
      if (wake_event_ == nullptr) {
        return false;
      }
    }
    auto* self = new std::shared_ptr<ShellWorker>(shared_from_this());
    const HANDLE thread =
        ::CreateThread(nullptr, 0, &ShellWorker::ThreadEntry, self, 0, nullptr);
    if (thread == nullptr) {
      delete self;
      return false;
    }
    started_ = true;
    ::CloseHandle(thread);
    return true;
  }

  static DWORD WINAPI ThreadEntry(LPVOID param) {
    std::unique_ptr<std::shared_ptr<ShellWorker>> holder(
        static_cast<std::shared_ptr<ShellWorker>*>(param));
    (*holder)->Run();
    return 0;
  }

  void Run() {
    const HRESULT com = ::CoInitializeEx(
        nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    const bool com_ready = SUCCEEDED(com) || com == RPC_E_CHANGED_MODE;

    while (true) {
      Task task;
      bool has_task = false;
      bool stop = false;
      ::AcquireSRWLockExclusive(&lock_);
      if (stopping_) {
        stop = true;
      } else if (!queue_.empty()) {
        task = std::move(queue_.front());
        queue_.pop_front();
        has_task = true;
      }
      ::ReleaseSRWLockExclusive(&lock_);

      if (stop) {
        break;
      }
      if (has_task) {
        Execute(task, com_ready);
        continue;
      }

      const DWORD waited = ::MsgWaitForMultipleObjects(
          1, &wake_event_, FALSE, INFINITE, QS_ALLINPUT);
      if (waited == WAIT_OBJECT_0 + 1) {
        MSG msg = {};
        while (::PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
          ::TranslateMessage(&msg);
          ::DispatchMessageW(&msg);
        }
      } else if (waited != WAIT_OBJECT_0) {
        break;
      }
    }

    if (SUCCEEDED(com)) {
      ::CoUninitialize();
    }
  }

  void Execute(const Task& task, bool com_ready) {
    if (task.kind == Task::Kind::kReveal) {
      if (!com_ready || task.target.empty()) {
        return;
      }
      PIDLIST_ABSOLUTE item = nullptr;
      if (SUCCEEDED(::SHParseDisplayName(task.target.c_str(), nullptr, &item, 0,
                                         nullptr))) {
        ::SHOpenFolderAndSelectItems(item, 0, nullptr, 0);
        ::CoTaskMemFree(item);
      }
      return;
    }

    const bool worked =
        ExecuteOpen(task.target, task.app, task.extras, com_ready);
    auto* completion = new OpenCompletion{task.request_id, worked};
    if (!::PostMessageW(task.owner, WindowChannel::kRunMessage, 0,
                        reinterpret_cast<LPARAM>(completion))) {
      delete completion;
    }
  }

  SRWLOCK lock_ = SRWLOCK_INIT;
  HANDLE wake_event_ = nullptr;
  bool started_ = false;
  bool stopping_ = false;
  std::deque<Task> queue_;
};

void WindowChannel::Run(LPARAM completion, WindowChannel* channel) {
  std::unique_ptr<OpenCompletion> done(
      reinterpret_cast<OpenCompletion*>(completion));
  if (channel != nullptr && done != nullptr) {
    channel->CompleteOpen(done->request_id, done->worked);
  }
}

void WindowChannel::CompleteOpen(uint64_t request_id, bool worked) {
  const auto found = pending_open_results_.find(request_id);
  if (found == pending_open_results_.end()) {
    return;
  }
  auto result = std::move(found->second);
  pending_open_results_.erase(found);
  result->Success(flutter::EncodableValue(worked));
}

WindowChannel::WindowChannel(flutter::BinaryMessenger* messenger, HWND window,
                             HWND view, const std::string& name)
    : window_(window),
      view_(view),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, name,
          &flutter::StandardMethodCodec::GetInstance())),
      shell_worker_(std::make_shared<ShellWorker>()) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });
}

// The engine outlives an IDE window's channel: its handler goes with it.
WindowChannel::~WindowChannel() {
  channel_->SetMethodCallHandler(nullptr);
  if (shell_worker_ != nullptr) {
    shell_worker_->Stop();
  }
}

void WindowChannel::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  const flutter::EncodableMap& arguments = Arguments(call.arguments());

  if (method == "heldModifiers") {
    // The modifiers held now, as the system has them: the app's own may
    // have missed one going up (see held_keys.dart).
    const auto held = [](int key) {
      return flutter::EncodableValue((::GetAsyncKeyState(key) & 0x8000) != 0);
    };
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("shift"), held(VK_SHIFT)},
        {flutter::EncodableValue("control"), held(VK_CONTROL)},
        {flutter::EncodableValue("alt"), held(VK_MENU)},
        {flutter::EncodableValue("meta"),
         flutter::EncodableValue(
             ((::GetAsyncKeyState(VK_LWIN) | ::GetAsyncKeyState(VK_RWIN)) &
              0x8000) != 0)},
    }));
    return;
  }

  if (method == "setAlwaysOnTop") {
    // Pinned: above other apps' windows, as a floating window should be.
    const bool on_top = Boolean(call.arguments(), false);
    ::SetWindowPos(window_, on_top ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    result->Success();
    return;
  }

  if (method == "setWindowBlur") {
    Win32Window::SetWindowBlur(Boolean(call.arguments(), false));
    result->Success();
    return;
  }

  if (method == "setAppearance") {
    Win32Window::SetDarkAppearance(Boolean(call.arguments(), false));
    result->Success();
    return;
  }

  if (method == "pickDirectory") {
    const std::optional<std::string> path = PickDirectory(window_);
    if (path.has_value()) {
      result->Success(flutter::EncodableValue(*path));
    } else {
      result->Success();
    }
    return;
  }

  if (method == "canPaste") {
    result->Success(flutter::EncodableValue(ClipboardHasContent()));
    return;
  }

  if (method == "readPasteboardImages") {
    flutter::EncodableList images;
    for (const ClipboardImage& image : ClipboardImages()) {
      flutter::EncodableMap encoded;
      encoded[flutter::EncodableValue("bytes")] =
          flutter::EncodableValue(image.bytes);
      encoded[flutter::EncodableValue("type")] =
          flutter::EncodableValue(image.media_type);
      if (!image.name.empty()) {
        encoded[flutter::EncodableValue("name")] =
            flutter::EncodableValue(image.name);
      }
      images.push_back(flutter::EncodableValue(std::move(encoded)));
    }
    result->Success(flutter::EncodableValue(std::move(images)));
    return;
  }

  if (method == "readPasteboardFiles") {
    result->Success(flutter::EncodableValue(FileEntries(ClipboardFilePaths())));
    return;
  }

  if (method == "writePasteboardFiles") {
    std::vector<std::wstring> paths;
    if (const auto* list = call.arguments() == nullptr
                               ? nullptr
                               : std::get_if<flutter::EncodableList>(
                                     call.arguments())) {
      for (const flutter::EncodableValue& value : *list) {
        if (const auto* path = std::get_if<std::string>(&value)) {
          paths.push_back(Utf16FromUtf8(*path));
        }
      }
    }
    result->Success(flutter::EncodableValue(WriteClipboardFiles(window_, paths)));
    return;
  }

  if (method == "startFileDrag") {
    // Files dragged in the app, out of the window: on as Explorer drags them.
    std::vector<std::wstring> paths;
    const auto found = arguments.find(flutter::EncodableValue("paths"));
    if (found != arguments.end()) {
      if (const auto* list = std::get_if<flutter::EncodableList>(&found->second)) {
        for (const flutter::EncodableValue& value : *list) {
          if (const auto* path = std::get_if<std::string>(&value)) {
            paths.push_back(Utf16FromUtf8(*path));
          }
        }
      }
    }
    Microsoft::WRL::ComPtr<IDataObject> data = FileDataObject(paths);
    if (data == nullptr || !LeftButtonDown()) {
      result->Success(flutter::EncodableValue(false));
      return;
    }
    // Answered first: the drag has its own message loop, until let go.
    result->Success(flutter::EncodableValue(true));
    DragFilesOut(view_, data.Get());
    return;
  }

  if (method == "readImageFile") {
    const auto* path = call.arguments() == nullptr
                           ? nullptr
                           : std::get_if<std::string>(call.arguments());
    std::optional<ClipboardImage> image =
        path == nullptr ? std::nullopt : ImageAtPath(Utf16FromUtf8(*path));
    if (!image.has_value()) {
      result->Success();
      return;
    }
    flutter::EncodableMap encoded;
    encoded[flutter::EncodableValue("bytes")] =
        flutter::EncodableValue(std::move(image->bytes));
    encoded[flutter::EncodableValue("type")] =
        flutter::EncodableValue(image->media_type);
    encoded[flutter::EncodableValue("name")] =
        flutter::EncodableValue(image->name);
    result->Success(flutter::EncodableValue(std::move(encoded)));
    return;
  }

  if (method == "pickFiles") {
    result->Success(flutter::EncodableValue(FileEntries(PickFiles(window_))));
    return;
  }

  if (method == "pickOpenFiles") {
    flutter::EncodableList paths;
    for (const std::wstring& path :
         PickOpenFiles(window_, String(arguments, "directory"),
                       Boolean(arguments, "multiple", true))) {
      paths.push_back(flutter::EncodableValue(Utf8FromUtf16(path.c_str())));
    }
    result->Success(flutter::EncodableValue(std::move(paths)));
    return;
  }

  if (method == "pickSaveFile") {
    const std::optional<std::string> path = PickSaveFile(
        window_, String(arguments, "directory"), String(arguments, "name"));
    if (path.has_value()) {
      result->Success(flutter::EncodableValue(*path));
    } else {
      result->Success();
    }
    return;
  }

  if (method == "writePasteboardMarkdown") {
    result->Success(flutter::EncodableValue(WriteClipboardMarkdown(
        window_, Utf16FromUtf8(String(arguments, "text")),
        String(arguments, "copy"))));
    return;
  }

  if (method == "readPasteboardMarkdown") {
    if (std::optional<std::string> copy = ClipboardMarkdown()) {
      result->Success(flutter::EncodableValue(std::move(*copy)));
    } else {
      result->Success();
    }
    return;
  }

  if (method == "writePasteboardImage") {
    const auto found = arguments.find(flutter::EncodableValue("bytes"));
    const auto* bytes =
        found == arguments.end()
            ? nullptr
            : std::get_if<std::vector<uint8_t>>(&found->second);
    result->Success(flutter::EncodableValue(
        bytes != nullptr &&
        WriteClipboardImage(window_, *bytes, String(arguments, "type"))));
    return;
  }

  if (method == "showContextMenu") {
    std::vector<ContextMenuItem> items;
    const auto found = arguments.find(flutter::EncodableValue("items"));
    if (found != arguments.end()) {
      if (const auto* list = std::get_if<flutter::EncodableList>(&found->second)) {
        for (const flutter::EncodableValue& value : *list) {
          const auto* map = std::get_if<flutter::EncodableMap>(&value);
          if (map == nullptr) {
            continue;
          }
          ContextMenuItem item;
          item.separator = Boolean(*map, "separator", false);
          item.id = String(*map, "id");
          item.label = String(*map, "label");
          item.key = String(*map, "key");
          item.enabled = Boolean(*map, "enabled", true);
          items.push_back(std::move(item));
        }
      }
    }
    // The position is in Flutter's own pixels, from the top left of the
    // client area; the menu opens at the screen point under it.
    const double scale = Scale();
    POINT at = {static_cast<LONG>(Number(arguments, "x") * scale),
                static_cast<LONG>(Number(arguments, "y") * scale)};
    ::ClientToScreen(window_, &at);
    const std::optional<std::string> chosen = ShowContextMenu(window_, at, items);
    if (chosen.has_value()) {
      result->Success(flutter::EncodableValue(*chosen));
    } else {
      result->Success();
    }
    return;
  }

  if (method == "revealInFinder") {
    // The folder opened in File Explorer with the item selected, as
    // Electron's shell.showItemInFolder does it.
    //
    // Answered at once, then run on the channel's STA shell worker: the
    // shell's extensions are loaded into this process as it parses the path
    // and calls File Explorer, and one that stalls (a cloud folder's, a
    // drive's) holds whoever asked for seconds on end without answering a
    // message — a Windows report shows 14 s in SHOpenFolderAndSelectItems.
    // The windows' thread is Flutter's, and runs the app's Dart code too.
    const auto* path = call.arguments() == nullptr
                           ? nullptr
                           : std::get_if<std::string>(call.arguments());
    const std::wstring wide =
        path == nullptr ? std::wstring() : Utf16FromUtf8(*path);
    const bool asked = !wide.empty();
    result->Success(flutter::EncodableValue(asked));
    if (asked) {
      shell_worker_->EnqueueReveal(wide);
    }
    return;
  }

  if (method == "open") {
    Open(arguments, std::move(result));
    return;
  }

  if (method == "setHitTestAreas") {
    // Flutter drew its header: this is where its pieces are, in the app's
    // own pixels. The window scales them to its own as it hit-tests them
    // (see CaptionAreas).
    areas_.Set(Number(arguments, "height"), Rects(arguments, "controls"),
               ButtonRect(arguments, "minimize"),
               ButtonRect(arguments, "maximize"),
               ButtonRect(arguments, "close"));
    result->Success();
    return;
  }

  if (method == "windowRoom") {
    // How much wider and taller the window can get on its monitor's work
    // area (see growWindow), in Flutter's pixels: none while maximized or
    // full screen.
    double width = 0.0;
    double height = 0.0;
    RECT frame;
    if (!::IsZoomed(window_) && !FullScreen() &&
        ::GetWindowRect(window_, &frame)) {
      const RECT work = WorkArea(window_);
      const double scale = Scale();
      width = (std::max)(0L, (work.right - work.left) -
                                 (frame.right - frame.left)) /
              scale;
      height = (std::max)(0L, (work.bottom - work.top) -
                                  (frame.bottom - frame.top)) /
               scale;
    }
    flutter::EncodableMap room;
    room[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
    room[flutter::EncodableValue("height")] = flutter::EncodableValue(height);
    result->Success(flutter::EncodableValue(std::move(room)));
    return;
  }

  if (method == "dragWindow") {
    // Moved by the pointer held down on Flutter's own strip (the stash's
    // panel, which marks no header): the system's move, as its title bar
    // would start. The press is let go inside it, unseen by the view, which
    // is told of it after for Flutter's gesture to end.
    result->Success();
    if (::GetAsyncKeyState(VK_LBUTTON) & 0x8000) {
      ::ReleaseCapture();
      // In front as it moves (see ViewWindow's caption press).
      ::SetWindowPos(window_, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
      ::SendMessageW(window_, WM_SYSCOMMAND, SC_MOVE | HTCAPTION, 0);
      if (view_ != nullptr) {
        POINT point = {};
        ::GetCursorPos(&point);
        ::ScreenToClient(view_, &point);
        ::PostMessageW(view_, WM_LBUTTONUP, 0, MAKELPARAM(point.x, point.y));
      }
    }
    return;
  }

  if (method == "growWindow") {
    // Room for conversations side by side (see chat_grid_view.dart).
    Grow(Number(arguments, "width"), Number(arguments, "height"));
    result->Success();
    return;
  }

  if (method == "toggleFullScreen") {
    // Answered with whether it is now.
    Win32Window* window = Win32Window::GetThisFromHandle(window_);
    if (window == nullptr) {
      result->Success(flutter::EncodableValue(false));
      return;
    }
    window->SetFullScreen(!window->IsFullScreen());
    result->Success(flutter::EncodableValue(window->IsFullScreen()));
    return;
  }

  if (method == "windowCommand") {
    const auto* name = call.arguments() == nullptr
                           ? nullptr
                           : std::get_if<std::string>(call.arguments());
    const std::string command = name == nullptr ? std::string() : *name;
    if (command == "minimize") {
      ::ShowWindow(window_, SW_MINIMIZE);
    } else if (command == "maximize") {
      // Either way round, as the button itself does: the system's own click
      // on it goes through DefWindowProc and lands in the same place.
      ::ShowWindow(window_, ::IsZoomed(window_) ? SW_RESTORE : SW_MAXIMIZE);
    } else if (command == "close") {
      ::PostMessageW(window_, WM_CLOSE, 0, 0);
    }
    result->Success();
    return;
  }

  result->NotImplemented();
}

bool WindowChannel::FullScreen() const {
  const Win32Window* window = Win32Window::GetThisFromHandle(window_);
  return window != nullptr && window->IsFullScreen();
}

void WindowChannel::Grow(double width, double height) {
  RECT frame;
  if (::IsZoomed(window_) || ::IsIconic(window_) || FullScreen() ||
      !::GetWindowRect(window_, &frame)) {
    return;
  }
  const RECT work = WorkArea(window_);
  const double scale = Scale();
  const LONG frame_width = frame.right - frame.left;
  const LONG frame_height = frame.bottom - frame.top;
  // As much larger as asked, but no larger than the work area (unless it
  // was already).
  const LONG new_width = (std::max)(
      frame_width,
      (std::min)(frame_width + static_cast<LONG>(std::ceil(width * scale)),
                 work.right - work.left));
  const LONG new_height = (std::max)(
      frame_height,
      (std::min)(frame_height + static_cast<LONG>(std::ceil(height * scale)),
                 work.bottom - work.top));
  // The top left stays, unless the window would go past the work area's
  // right or bottom edge, where it moves back onto it.
  LONG left = frame.left;
  LONG top = frame.top;
  if (left + new_width > work.right) {
    left = (std::max)(work.left, work.right - new_width);
  }
  if (top + new_height > work.bottom) {
    top = (std::max)(work.top, work.bottom - new_height);
  }
  ::SetWindowPos(window_, nullptr, left, top, new_width, new_height,
                 SWP_NOZORDER | SWP_NOACTIVATE);
}

double WindowChannel::Scale() const {
  return ::FlutterDesktopGetDpiForHWND(window_) / 96.0;
}

void WindowChannel::ReportHover(LRESULT hit) {
  std::optional<std::string> hovered;
  switch (hit) {
    case HTMINBUTTON:
      hovered = "minimize";
      break;
    case HTMAXBUTTON:
      hovered = "maximize";
      break;
    case HTCLOSE:
      hovered = "close";
      break;
    default:
      break;
  }
  if (hovered == hovered_) {
    return;
  }
  hovered_ = hovered;
  channel_->InvokeMethod(
      "captionHover",
      std::make_unique<flutter::EncodableValue>(hovered.value_or(std::string())));
}

void WindowChannel::ReportMaximized(bool maximized) {
  if (maximized == maximized_) {
    return;
  }
  maximized_ = maximized;
  channel_->InvokeMethod(
      "maximized", std::make_unique<flutter::EncodableValue>(maximized));
}

void WindowChannel::Open(
    const flutter::EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::wstring target = Utf16FromUtf8(String(arguments, "target"));
  if (target.empty()) {
    result->Success(flutter::EncodableValue(false));
    return;
  }
  // Named an app: the command the Flutter side uses (`code`, `wt`…), found
  // on the PATH as a terminal would, and started without a console (see
  // StartWithoutConsole); the shell is left to find it when that does not
  // do. When the Flutter side also passes arguments, those are the whole of
  // what the app is given (e.g. `wt -d folder`); otherwise the target is
  // what it opens. Without an app, the target itself is what opens, in
  // whatever the system opens it with (a URL, a folder, a file).
  //
  // Run on the channel's STA shell worker so PATH scans, CreateProcessW, or
  // ShellExecuteW never block Flutter's UI/message thread; the boolean result
  // is posted back and answered on this thread.
  const std::wstring app = Utf16FromUtf8(String(arguments, "app"));
  std::vector<std::wstring> extras;
  for (const std::string& extra : Strings(arguments, "arguments")) {
    extras.push_back(Utf16FromUtf8(extra));
  }
  const uint64_t request_id = ++next_open_id_;
  pending_open_results_.emplace(request_id, std::move(result));
  if (!shell_worker_->EnqueueOpen(request_id, window_, target, app,
                                  std::move(extras))) {
    CompleteOpen(request_id, false);
  }
}
