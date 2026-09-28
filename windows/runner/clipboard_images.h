#ifndef RUNNER_CLIPBOARD_IMAGES_H_
#define RUNNER_CLIPBOARD_IMAGES_H_

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

#endif  // RUNNER_CLIPBOARD_IMAGES_H_
