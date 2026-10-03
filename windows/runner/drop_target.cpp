#include "drop_target.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <shellapi.h>

#include <utility>

#include "clipboard_images.h"
#include "utils.h"

namespace {

// The files a drag carries; none when it carries no CF_HDROP (text, a
// browser's image, an attachment still to be written).
std::vector<std::wstring> FilesIn(IDataObject* data) {
  if (data == nullptr) {
    return {};
  }
  FORMATETC format = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM medium = {};
  if (FAILED(data->GetData(&format, &medium))) {
    return {};
  }
  std::vector<std::wstring> paths =
      DroppedFilePaths(static_cast<HDROP>(medium.hGlobal));
  ::ReleaseStgMedium(&medium);
  return paths;
}

}  // namespace

flutter::EncodableValue FileEntry(const std::wstring& path) {
  const DWORD attributes = ::GetFileAttributesW(path.c_str());
  flutter::EncodableMap entry;
  entry[flutter::EncodableValue("path")] =
      flutter::EncodableValue(Utf8FromUtf16(path.c_str()));
  entry[flutter::EncodableValue("directory")] = flutter::EncodableValue(
      attributes != INVALID_FILE_ATTRIBUTES &&
      (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0);
  return flutter::EncodableValue(std::move(entry));
}

flutter::EncodableList FileEntries(const std::vector<std::wstring>& paths) {
  flutter::EncodableList entries;
  for (const std::wstring& path : paths) {
    entries.push_back(FileEntry(path));
  }
  return entries;
}

DropTarget::DropTarget(flutter::BinaryMessenger* messenger, HWND view,
                       const std::string& name)
    : view_(view),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, name,
          &flutter::StandardMethodCodec::GetInstance())) {
  ::CoCreateInstance(CLSID_DragDropHelper, nullptr, CLSCTX_INPROC_SERVER,
                     IID_PPV_ARGS(&helper_));
}

DropTarget::~DropTarget() = default;

void DropTarget::Detach() {
  channel_ = nullptr;
}

HRESULT DropTarget::QueryInterface(REFIID id, void** object) {
  if (object == nullptr) {
    return E_POINTER;
  }
  if (id == IID_IUnknown || id == IID_IDropTarget) {
    *object = static_cast<IDropTarget*>(this);
    AddRef();
    return S_OK;
  }
  *object = nullptr;
  return E_NOINTERFACE;
}

ULONG DropTarget::AddRef() {
  return static_cast<ULONG>(::InterlockedIncrement(&references_));
}

ULONG DropTarget::Release() {
  const LONG count = ::InterlockedDecrement(&references_);
  if (count == 0) {
    delete this;
  }
  return static_cast<ULONG>(count);
}

flutter::EncodableMap DropTarget::Position(POINTL point) const {
  POINT client = {point.x, point.y};
  ::ScreenToClient(view_, &client);
  const double scale = ::FlutterDesktopGetDpiForHWND(view_) / 96.0;
  flutter::EncodableMap position;
  position[flutter::EncodableValue("x")] =
      flutter::EncodableValue(client.x / scale);
  position[flutter::EncodableValue("y")] =
      flutter::EncodableValue(client.y / scale);
  return position;
}

void DropTarget::Update(flutter::EncodableMap arguments) {
  if (channel_ == nullptr) {
    return;
  }
  std::shared_ptr<bool> accepting = accepting_;
  channel_->InvokeMethod(
      "dragUpdate",
      std::make_unique<flutter::EncodableValue>(std::move(arguments)),
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          [accepting](const flutter::EncodableValue* answer) {
            const bool* taken =
                answer == nullptr ? nullptr : std::get_if<bool>(answer);
            *accepting = taken != nullptr && *taken;
          },
          nullptr, nullptr));
}

DWORD DropTarget::Effect() const {
  return has_files_ && *accepting_ ? DROPEFFECT_COPY : DROPEFFECT_NONE;
}

HRESULT DropTarget::DragEnter(IDataObject* data, DWORD /*key_state*/,
                              POINTL point, DWORD* effect) {
  const std::vector<std::wstring> files = FilesIn(data);
  has_files_ = !files.empty();
  *accepting_ = false;
  if (has_files_) {
    flutter::EncodableMap arguments = Position(point);
    arguments[flutter::EncodableValue("files")] =
        flutter::EncodableValue(FileEntries(files));
    Update(std::move(arguments));
  }
  *effect = Effect();
  if (helper_ != nullptr) {
    POINT at = {point.x, point.y};
    helper_->DragEnter(view_, data, &at, *effect);
  }
  return S_OK;
}

HRESULT DropTarget::DragOver(DWORD /*key_state*/, POINTL point,
                             DWORD* effect) {
  // Asked again and again while the drag rests too, which brings Flutter's
  // answer to the last question in.
  if (has_files_) {
    Update(Position(point));
  }
  *effect = Effect();
  if (helper_ != nullptr) {
    POINT at = {point.x, point.y};
    helper_->DragOver(&at, *effect);
  }
  return S_OK;
}

HRESULT DropTarget::DragLeave() {
  if (has_files_ && channel_ != nullptr) {
    channel_->InvokeMethod("dragExit", nullptr);
  }
  has_files_ = false;
  *accepting_ = false;
  if (helper_ != nullptr) {
    helper_->DragLeave();
  }
  return S_OK;
}

HRESULT DropTarget::Drop(IDataObject* data, DWORD /*key_state*/,
                         POINTL point, DWORD* effect) {
  const std::vector<std::wstring> files = FilesIn(data);
  const bool taken = !files.empty() && *accepting_;
  if (channel_ != nullptr) {
    if (taken) {
      flutter::EncodableMap arguments = Position(point);
      arguments[flutter::EncodableValue("files")] =
          flutter::EncodableValue(FileEntries(files));
      channel_->InvokeMethod(
          "drop", std::make_unique<flutter::EncodableValue>(std::move(arguments)));
    } else if (has_files_) {
      channel_->InvokeMethod("dragExit", nullptr);
    }
  }
  has_files_ = false;
  *accepting_ = false;
  *effect = taken ? DROPEFFECT_COPY : DROPEFFECT_NONE;
  if (helper_ != nullptr) {
    POINT at = {point.x, point.y};
    helper_->Drop(data, &at, *effect);
  }
  return S_OK;
}
