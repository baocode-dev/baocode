#ifndef RUNNER_CLIPBOARD_IMAGES_H_
#define RUNNER_CLIPBOARD_IMAGES_H_

#include <windows.h>

#include <shellapi.h>

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

// An image the clipboard holds, as the Flutter side takes it (see
// ImageAttachment in lib/chat/chat_models.dart).
struct ClipboardImage {
  std::vector<uint8_t> bytes;
  std::string media_type;
  // What it was called; empty for one that came as data, not as a file.
  std::string name;
};

// Whether the clipboard holds anything to paste: text, files or an image.
bool ClipboardHasContent();

// The images on the clipboard: copied image files, or, when there is no text
// to paste, copied image data (a screenshot, an image from a browser). Text
// wins over image data: apps put a picture of copied text (e.g. cells) beside
// it.
std::vector<ClipboardImage> ClipboardImages();

// The files copied to the clipboard (in Explorer, or the IDE's explorer).
std::vector<std::wstring> ClipboardFilePaths();

// Puts |paths| on the clipboard as files, owned by |owner|, as Explorer copies
// them (CF_HDROP, to be copied rather than moved): pasted there they are
// copied, pasted in the composer they are referred to. False when the
// clipboard is not to be had.
bool WriteClipboardFiles(HWND owner, const std::vector<std::wstring>& paths);

// The files a drop (or the clipboard) holds as CF_HDROP.
std::vector<std::wstring> DroppedFilePaths(HDROP drop);

// The image file at |path| as the composer takes one (the formats it does not
// send as they are encoded as PNG); nullopt when it is no image WIC reads.
std::optional<ClipboardImage> ImageAtPath(const std::wstring& path);

// Puts the image in |bytes| (of |media_type|) on the clipboard, owned by
// |owner|: as a bitmap with alpha (CF_DIBV5, which Windows offers as CF_DIB
// too) and as PNG, what apps paste a picture from. False when it is no image
// WIC can read, or the clipboard is not to be had.
bool WriteClipboardImage(HWND owner, const std::vector<uint8_t>& bytes,
                         const std::string& media_type);

#endif  // RUNNER_CLIPBOARD_IMAGES_H_
