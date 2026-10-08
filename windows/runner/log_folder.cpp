#include "log_folder.h"

#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <windows.h>

#include <mutex>
#include <vector>

#include "utils.h"

namespace log_folder {
namespace {

constexpr wchar_t kSettingsKey[] = L"Software\\BaoCode";
constexpr wchar_t kFolderValue[] = L"LogsFolder";

std::mutex g_mutex;

// The folder Flutter named this run; empty until it does.
std::wstring g_folder;

// The folder kept by the run before; empty if none.
std::wstring KeptFolder() {
  DWORD size = 0;
  if (::RegGetValueW(HKEY_CURRENT_USER, kSettingsKey, kFolderValue,
                     RRF_RT_REG_SZ, nullptr, nullptr,
                     &size) != ERROR_SUCCESS ||
      size < sizeof(wchar_t)) {
    return std::wstring();
  }
  std::vector<wchar_t> folder(size / sizeof(wchar_t) + 1, L'\0');
  size = static_cast<DWORD>(folder.size() * sizeof(wchar_t));
  if (::RegGetValueW(HKEY_CURRENT_USER, kSettingsKey, kFolderValue,
                     RRF_RT_REG_SZ, nullptr, folder.data(),
                     &size) != ERROR_SUCCESS) {
    return std::wstring();
  }
  return std::wstring(folder.data());
}

// %APPDATA%\baocode\logs; empty if there is no %APPDATA%.
std::wstring DefaultFolder() {
  wchar_t app_data[MAX_PATH];
  const DWORD length =
      ::GetEnvironmentVariableW(L"APPDATA", app_data, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return std::wstring();
  }
  return std::wstring(app_data) + L"\\baocode\\logs";
}

// Whether |folder| is there, made if need be — with the folders above it:
// the data folder may not be there yet.
bool Made(const std::wstring& folder) {
  const int made = ::SHCreateDirectoryExW(nullptr, folder.c_str(), nullptr);
  return made == ERROR_SUCCESS || made == ERROR_ALREADY_EXISTS ||
         made == ERROR_FILE_EXISTS;
}

void SetFolder(const std::wstring& folder) {
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_folder = folder;
  }
  ::RegSetKeyValueW(HKEY_CURRENT_USER, kSettingsKey, kFolderValue, REG_SZ,
                    folder.c_str(),
                    static_cast<DWORD>((folder.size() + 1) * sizeof(wchar_t)));
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> Listen(
    flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "baocode/logs", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != "setFolder") {
          result->NotImplemented();
          return;
        }
        const auto* path = call.arguments() == nullptr
                               ? nullptr
                               : std::get_if<std::string>(call.arguments());
        if (path != nullptr && !path->empty()) {
          SetFolder(Utf16FromUtf8(*path));
        }
        result->Success();
      });
  return channel;
}

std::wstring Path() {
  std::wstring named;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    named = g_folder;
  }
  if (named.empty()) {
    named = KeptFolder();
  }
  if (!named.empty() && Made(named)) {
    return named;
  }
  // None named yet, or the one named is out of reach (a drive gone).
  const std::wstring fallback = DefaultFolder();
  if (!fallback.empty() && fallback != named && Made(fallback)) {
    return fallback;
  }
  return std::wstring();
}

}  // namespace log_folder
