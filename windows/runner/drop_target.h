#ifndef RUNNER_DROP_TARGET_H_
#define RUNNER_DROP_TARGET_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <oleidl.h>
#include <shlobj.h>
#include <wrl/client.h>

#include <memory>
#include <string>
#include <vector>

// A file as Flutter takes it (see FileDrops.decode in
// lib/chat/composer/file_drop.dart): its path, and whether it is a folder.
flutter::EncodableValue FileEntry(const std::wstring& path);

// The files at |paths|, as Flutter takes them.
flutter::EncodableList FileEntries(const std::vector<std::wstring>& paths);

// Takes the files other apps drag onto the window (Explorer, an editor…) for
// Flutter, which shows where they would go and puts them there, over the
// `baocode/drop` channel (an IDE window's: `baocode/drop.<its view's id>`;
// as MainFlutterWindow.swift's FileDropView does):
//
//   dragUpdate {x, y, files?}  the pointer is at x, y (Flutter's pixels, from
//                              the view's top left); files on entering.
//                              Flutter answers whether what is under it takes
//                              them, later than the system asks: the system
//                              is told the last answer.
//   dragExit                   the drag left the window
//   drop {x, y, files}         let go
//
// Registered on the Flutter view (RegisterDragDrop), which needs OLE
// (OleInitialize, see main.cpp). A COM object: references counted, the
// window holding one until it goes (see Detach).
class DropTarget : public IDropTarget {
 public:
  DropTarget(flutter::BinaryMessenger* messenger, HWND view,
             const std::string& name = "baocode/drop");

  DropTarget(const DropTarget&) = delete;
  DropTarget& operator=(const DropTarget&) = delete;

  // Stops talking to Flutter, whose engine is going.
  void Detach();

  // IUnknown:
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void** object) override;
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;

  // IDropTarget:
  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* data, DWORD key_state,
                                      POINTL point, DWORD* effect) override;
  HRESULT STDMETHODCALLTYPE DragOver(DWORD key_state, POINTL point,
                                     DWORD* effect) override;
  HRESULT STDMETHODCALLTYPE DragLeave() override;
  HRESULT STDMETHODCALLTYPE Drop(IDataObject* data, DWORD key_state,
                                 POINTL point, DWORD* effect) override;

 private:
  ~DropTarget();

  // Where |point| (the screen's) is, as Flutter counts.
  flutter::EncodableMap Position(POINTL point) const;

  // Tells Flutter where the drag is (and, given, what it carries); its
  // answer goes to |accepting_|.
  void Update(flutter::EncodableMap arguments);

  // What the drag is told it would do, from Flutter's last answer.
  DWORD Effect() const;

  LONG references_ = 1;
  HWND view_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // Flutter's last answer; shared with the answers on their way, which may
  // come after this is gone.
  std::shared_ptr<bool> accepting_ = std::make_shared<bool>(false);

  // Whether the drag carries files (CF_HDROP).
  bool has_files_ = false;

  // Draws the image the source gives its drag over the window, as Explorer
  // does over its own.
  Microsoft::WRL::ComPtr<IDropTargetHelper> helper_;
};

#endif  // RUNNER_DROP_TARGET_H_
