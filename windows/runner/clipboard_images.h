#ifndef RUNNER_CLIPBOARD_IMAGES_H_
#define RUNNER_CLIPBOARD_IMAGES_H_

#include <windows.h>

#include <cstdint>
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

// Puts the image in |bytes| (of |media_type|) on the clipboard, owned by
// |owner|: as a bitmap with alpha (CF_DIBV5, which Windows offers as CF_DIB
// too) and as PNG, what apps paste a picture from. False when it is no image
// WIC can read, or the clipboard is not to be had.
bool WriteClipboardImage(HWND owner, const std::vector<uint8_t>& bytes,
                         const std::string& media_type);

#endif  // RUNNER_CLIPBOARD_IMAGES_H_
