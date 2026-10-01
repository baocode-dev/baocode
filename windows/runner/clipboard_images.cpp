#include "clipboard_images.h"

#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstring>
#include <cwctype>
#include <optional>
#include <utility>
#include <vector>

#include "utils.h"

namespace {

using Microsoft::WRL::ComPtr;

// A copied image is held in memory while it is read; past this it is not
// what the composer is for (and a bitmap must fit in a DWORD to be read).
constexpr LONGLONG kMaxImageBytes = 64 * 1024 * 1024;

// The media types sent as they are; anything else is encoded as PNG.
std::optional<std::string> MediaTypeFromName(const std::wstring& name) {
  const size_t dot = name.find_last_of(L'.');
  if (dot == std::wstring::npos) {
    return std::nullopt;
  }
  std::wstring extension = name.substr(dot + 1);
  std::transform(extension.begin(), extension.end(), extension.begin(),
                 [](wchar_t letter) { return std::towlower(letter); });
  if (extension == L"png") {
    return "image/png";
  }
  if (extension == L"jpg" || extension == L"jpeg") {
    return "image/jpeg";
  }
  if (extension == L"gif") {
    return "image/gif";
  }
  if (extension == L"webp") {
    return "image/webp";
  }
  return std::nullopt;
}

std::wstring FileNameOf(const std::wstring& path) {
  const size_t slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? path : path.substr(slash + 1);
}

std::vector<uint8_t> ReadFile(const std::wstring& path) {
  const HANDLE file =
      ::CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return {};
  }
  std::vector<uint8_t> bytes;
  LARGE_INTEGER size = {};
  if (::GetFileSizeEx(file, &size) && size.QuadPart > 0 &&
      size.QuadPart <= kMaxImageBytes) {
    bytes.resize(static_cast<size_t>(size.QuadPart));
    DWORD read = 0;
    if (!::ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &read,
                    nullptr) ||
        read != static_cast<DWORD>(bytes.size())) {
      bytes.clear();
    }
  }
  ::CloseHandle(file);
  return bytes;
}

// The imaging factory (WIC) to read and write the images with. COM is
// already initialized for this thread (see main.cpp).
ComPtr<IWICImagingFactory> ImagingFactory() {
  ComPtr<IWICImagingFactory> factory;
  ::CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                     IID_PPV_ARGS(&factory));
  return factory;
}

// What a stream holds, as bytes.
std::vector<uint8_t> BytesFromStream(IStream* stream) {
  STATSTG stat = {};
  if (FAILED(stream->Stat(&stat, STATFLAG_NONAME))) {
    return {};
  }
  const ULONGLONG size = stat.cbSize.QuadPart;
  if (size == 0 || size > static_cast<ULONGLONG>(kMaxImageBytes)) {
    return {};
  }
  HGLOBAL global = nullptr;
  if (FAILED(::GetHGlobalFromStream(stream, &global))) {
    return {};
  }
  const auto* data = static_cast<const uint8_t*>(::GlobalLock(global));
  if (data == nullptr) {
    return {};
  }
  std::vector<uint8_t> bytes(data, data + size);
  ::GlobalUnlock(global);
  return bytes;
}

// |source| as PNG bytes; empty when it cannot be encoded.
std::vector<uint8_t> PngFrom(IWICImagingFactory* factory,
                             IWICBitmapSource* source) {
  if (factory == nullptr) {
    return {};
  }
  // A converter, because the encoder takes the formats it lists and an
  // image may be in any of them. 32bppBGRA keeps an image's alpha.
  ComPtr<IWICFormatConverter> converted;
  if (FAILED(factory->CreateFormatConverter(&converted)) ||
      FAILED(converted->Initialize(source, GUID_WICPixelFormat32bppBGRA,
                                    WICBitmapDitherTypeNone, nullptr, 0.0,
                                    WICBitmapPaletteTypeCustom))) {
    return {};
  }

  ComPtr<IWICBitmapEncoder> encoder;
  if (FAILED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr,
                                    &encoder))) {
    return {};
  }
  ComPtr<IStream> stream;
  if (FAILED(::CreateStreamOnHGlobal(nullptr, TRUE, &stream)) ||
      FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache))) {
    return {};
  }
  ComPtr<IWICBitmapFrameEncode> frame;
  ComPtr<IPropertyBag2> properties;
  if (FAILED(encoder->CreateNewFrame(&frame, &properties)) ||
      FAILED(frame->Initialize(properties.Get()))) {
    return {};
  }
  UINT width = 0;
  UINT height = 0;
  if (FAILED(converted->GetSize(&width, &height)) ||
      FAILED(frame->SetSize(width, height))) {
    return {};
  }
  WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
  if (FAILED(frame->SetPixelFormat(&format)) ||
      FAILED(frame->WriteSource(converted.Get(), nullptr)) ||
      FAILED(frame->Commit()) || FAILED(encoder->Commit())) {
    return {};
  }
  return BytesFromStream(stream.Get());
}

// The (first) picture in |bytes|, for any image WIC can read; null for
// anything else. It reads |bytes| as it is used: they must outlive it.
ComPtr<IWICBitmapFrameDecode> FrameFromBytes(
    IWICImagingFactory* factory, const std::vector<uint8_t>& bytes) {
  ComPtr<IWICStream> stream;
  if (factory == nullptr || bytes.empty() ||
      bytes.size() > static_cast<size_t>(kMaxImageBytes) ||
      FAILED(factory->CreateStream(&stream))) {
    return nullptr;
  }
  // The decoder reads under it, which is why the bytes are not const.
  auto* data = const_cast<BYTE*>(bytes.data());
  if (FAILED(stream->InitializeFromMemory(data,
                                          static_cast<DWORD>(bytes.size())))) {
    return nullptr;
  }
  ComPtr<IWICBitmapDecoder> decoder;
  if (FAILED(factory->CreateDecoderFromStream(stream.Get(), nullptr,
                                              WICDecodeMetadataCacheOnDemand,
                                              &decoder))) {
    return nullptr;
  }
  ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(decoder->GetFrame(0, &frame))) {
    return nullptr;
  }
  return frame;
}

// Any image WIC can read, as PNG.
std::vector<uint8_t> PngFromBytes(const std::vector<uint8_t>& bytes) {
  ComPtr<IWICImagingFactory> factory = ImagingFactory();
  ComPtr<IWICBitmapFrameDecode> frame = FrameFromBytes(factory.Get(), bytes);
  if (frame == nullptr) {
    return {};
  }
  return PngFrom(factory.Get(), frame.Get());
}

// |source| as a device-independent bitmap with alpha, what CF_DIBV5 holds:
// a BITMAPV5HEADER, then 32-bit BGRA rows, the bottom one first, as readers
// of the clipboard expect. Empty when it cannot be converted.
std::vector<uint8_t> DibV5From(IWICImagingFactory* factory,
                               IWICBitmapSource* source) {
  if (factory == nullptr) {
    return {};
  }
  ComPtr<IWICFormatConverter> converted;
  if (FAILED(factory->CreateFormatConverter(&converted)) ||
      FAILED(converted->Initialize(source, GUID_WICPixelFormat32bppBGRA,
                                    WICBitmapDitherTypeNone, nullptr, 0.0,
                                    WICBitmapPaletteTypeCustom))) {
    return {};
  }
  UINT width = 0;
  UINT height = 0;
  if (FAILED(converted->GetSize(&width, &height)) || width == 0 ||
      height == 0) {
    return {};
  }
  const UINT stride = width * 4;
  const ULONGLONG size = static_cast<ULONGLONG>(stride) * height;
  if (size > static_cast<ULONGLONG>(kMaxImageBytes)) {
    return {};
  }
  // Read top row first, as WIC gives them, then laid in bottom up.
  std::vector<uint8_t> rows(static_cast<size_t>(size));
  if (FAILED(converted->CopyPixels(nullptr, stride,
                                   static_cast<UINT>(size), rows.data()))) {
    return {};
  }

  std::vector<uint8_t> dib(sizeof(BITMAPV5HEADER) + rows.size());
  BITMAPV5HEADER header = {};
  header.bV5Size = sizeof(BITMAPV5HEADER);
  header.bV5Width = static_cast<LONG>(width);
  header.bV5Height = static_cast<LONG>(height);
  header.bV5Planes = 1;
  header.bV5BitCount = 32;
  header.bV5Compression = BI_BITFIELDS;
  header.bV5SizeImage = static_cast<DWORD>(size);
  header.bV5RedMask = 0x00FF0000;
  header.bV5GreenMask = 0x0000FF00;
  header.bV5BlueMask = 0x000000FF;
  header.bV5AlphaMask = 0xFF000000;
  header.bV5CSType = LCS_sRGB;
  header.bV5Intent = LCS_GM_IMAGES;
  std::memcpy(dib.data(), &header, sizeof(header));
  uint8_t* pixels = dib.data() + sizeof(header);
  for (UINT row = 0; row < height; row++) {
    std::memcpy(pixels + static_cast<size_t>(height - 1 - row) * stride,
                rows.data() + static_cast<size_t>(row) * stride, stride);
  }
  return dib;
}

// |bytes| in movable global memory, for SetClipboardData; null when there is
// no memory for them.
HGLOBAL GlobalFrom(const std::vector<uint8_t>& bytes) {
  HGLOBAL global = ::GlobalAlloc(GMEM_MOVEABLE, bytes.size());
  if (global == nullptr) {
    return nullptr;
  }
  void* data = ::GlobalLock(global);
  if (data == nullptr) {
    ::GlobalFree(global);
    return nullptr;
  }
  std::memcpy(data, bytes.data(), bytes.size());
  ::GlobalUnlock(global);
  return global;
}

// Puts |bytes| on the open clipboard as |format|; whether it took them (it
// owns them then).
bool SetClipboardBytes(UINT format, const std::vector<uint8_t>& bytes) {
  HGLOBAL global = GlobalFrom(bytes);
  if (global == nullptr) {
    return false;
  }
  if (::SetClipboardData(format, global) == nullptr) {
    ::GlobalFree(global);
    return false;
  }
  return true;
}

// The image data the clipboard holds as a bitmap, wrapped in the file
// header its format starts with: a device-independent bitmap, which is the
// body of a BMP file.
std::vector<uint8_t> BmpFileFromDib(const uint8_t* dib, size_t size) {
  if (size < sizeof(BITMAPINFOHEADER)) {
    return {};
  }
  const auto* header = reinterpret_cast<const BITMAPINFOHEADER*>(dib);
  if (header->biSize < sizeof(BITMAPINFOHEADER) ||
      static_cast<size_t>(header->biSize) > size) {
    return {};
  }
  size_t body = header->biSize;
  if (header->biBitCount <= 8) {
    const DWORD colors =
        header->biClrUsed != 0 ? header->biClrUsed : (1u << header->biBitCount);
    body += colors * sizeof(RGBQUAD);
  } else if (header->biSize == sizeof(BITMAPINFOHEADER) &&
             header->biCompression == BI_BITFIELDS) {
    // Color masks follow the header for BI_BITFIELDS (and the older
    // BI_ALPHABITFIELDS, which is not in every SDK).
    body += 3 * sizeof(DWORD);
  }
  if (body > size) {
    return {};
  }

  BITMAPFILEHEADER file = {};
  file.bfType = 0x4D42;  // "BM"
  file.bfOffBits = static_cast<DWORD>(sizeof(BITMAPFILEHEADER) + body);
  file.bfSize = static_cast<DWORD>(sizeof(BITMAPFILEHEADER) + size);

  std::vector<uint8_t> bytes(sizeof(BITMAPFILEHEADER) + size);
  std::memcpy(bytes.data(), &file, sizeof(file));
  std::memcpy(bytes.data() + sizeof(file), dib, size);
  return bytes;
}

// The image at |path|: its bytes as they are when they are already a
// format the Flutter side takes, else as PNG; nothing when it is not an
// image.
std::optional<ClipboardImage> ImageFromFile(const std::wstring& path) {
  const std::wstring name = FileNameOf(path);
  std::vector<uint8_t> bytes = ReadFile(path);
  if (bytes.empty()) {
    return std::nullopt;
  }
  if (const std::optional<std::string> media_type = MediaTypeFromName(name)) {
    return ClipboardImage{std::move(bytes), *media_type,
                          Utf8FromUtf16(name.c_str())};
  }
  std::vector<uint8_t> png = PngFromBytes(bytes);
  if (png.empty()) {
    return std::nullopt;
  }
  return ClipboardImage{std::move(png), "image/png", Utf8FromUtf16(name.c_str())};
}

// The image data on the clipboard (CF_DIBV5 or CF_DIB), as PNG.
std::vector<ClipboardImage> ImagesFromClipboardData() {
  for (const UINT format : {CF_DIBV5, CF_DIB}) {
    const HANDLE handle = ::GetClipboardData(format);
    if (handle == nullptr) {
      continue;
    }
    const auto* data = static_cast<const uint8_t*>(::GlobalLock(handle));
    if (data == nullptr) {
      continue;
    }
    const SIZE_T size = ::GlobalSize(handle);
    const std::vector<uint8_t> file = BmpFileFromDib(data, size);
    ::GlobalUnlock(handle);
    if (file.empty()) {
      continue;
    }
    std::vector<uint8_t> png = PngFromBytes(file);
    if (!png.empty()) {
      return {ClipboardImage{std::move(png), "image/png", std::string()}};
    }
  }
  return {};
}

// The files a copy put on the clipboard, when it copied files.
std::vector<std::wstring> DroppedNames(HDROP drop) {
  const UINT count = ::DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  std::vector<std::wstring> names;
  for (UINT index = 0; index < count; index++) {
    const UINT length = ::DragQueryFileW(drop, index, nullptr, 0);
    std::vector<wchar_t> name(static_cast<size_t>(length) + 1, L'\0');
    if (::DragQueryFileW(drop, index, name.data(), length + 1) == 0) {
      continue;
    }
    names.emplace_back(name.data());
  }
  return names;
}

bool HasText() {
  return ::IsClipboardFormatAvailable(CF_UNICODETEXT) != FALSE ||
         ::IsClipboardFormatAvailable(CF_TEXT) != FALSE;
}

}  // namespace

bool ClipboardHasContent() {
  return HasText() || ::IsClipboardFormatAvailable(CF_HDROP) != FALSE ||
         ::IsClipboardFormatAvailable(CF_DIB) != FALSE ||
         ::IsClipboardFormatAvailable(CF_DIBV5) != FALSE;
}

std::vector<ClipboardImage> ClipboardImages() {
  std::vector<ClipboardImage> images;
  if (!::OpenClipboard(nullptr)) {
    return images;
  }
  if (auto* drop = static_cast<HDROP>(::GetClipboardData(CF_HDROP))) {
    for (const std::wstring& name : DroppedNames(drop)) {
      if (std::optional<ClipboardImage> image = ImageFromFile(name)) {
        images.push_back(std::move(*image));
      }
    }
  }
  if (images.empty() && !HasText()) {
    images = ImagesFromClipboardData();
  }
  ::CloseClipboard();
  return images;
}

std::vector<std::wstring> ClipboardFilePaths() {
  std::vector<std::wstring> paths;
  if (!::OpenClipboard(nullptr)) {
    return paths;
  }
  if (auto* drop = static_cast<HDROP>(::GetClipboardData(CF_HDROP))) {
    paths = DroppedNames(drop);
  }
  ::CloseClipboard();
  return paths;
}

bool WriteClipboardFiles(HWND owner, const std::vector<std::wstring>& paths) {
  if (paths.empty()) {
    return false;
  }
  // DROPFILES, then each path with its null, then one more null.
  size_t characters = 1;
  for (const std::wstring& path : paths) {
    characters += path.size() + 1;
  }
  std::vector<uint8_t> bytes(sizeof(DROPFILES) + characters * sizeof(wchar_t),
                             0);
  auto* header = reinterpret_cast<DROPFILES*>(bytes.data());
  header->pFiles = sizeof(DROPFILES);
  header->fWide = TRUE;
  auto* names = reinterpret_cast<wchar_t*>(bytes.data() + sizeof(DROPFILES));
  for (const std::wstring& path : paths) {
    std::copy(path.begin(), path.end(), names);
    names += path.size() + 1;
  }
  // Copied, not cut: Explorer's paste copies them.
  const DWORD effect = DROPEFFECT_COPY;
  std::vector<uint8_t> effect_bytes(sizeof(effect));
  std::memcpy(effect_bytes.data(), &effect, sizeof(effect));
  static const UINT kDropEffect =
      ::RegisterClipboardFormatW(CFSTR_PREFERREDDROPEFFECT);
  // Owned by a window: with none, EmptyClipboard leaves it to no one and
  // SetClipboardData fails.
  if (!::OpenClipboard(owner)) {
    return false;
  }
  ::EmptyClipboard();
  const bool written = SetClipboardBytes(CF_HDROP, bytes);
  SetClipboardBytes(kDropEffect, effect_bytes);
  ::CloseClipboard();
  return written;
}

std::vector<std::wstring> DroppedFilePaths(HDROP drop) {
  return DroppedNames(drop);
}

std::optional<ClipboardImage> ImageAtPath(const std::wstring& path) {
  return ImageFromFile(path);
}

bool WriteClipboardImage(HWND owner, const std::vector<uint8_t>& bytes,
                         const std::string& media_type) {
  ComPtr<IWICImagingFactory> factory = ImagingFactory();
  ComPtr<IWICBitmapFrameDecode> frame = FrameFromBytes(factory.Get(), bytes);
  if (frame == nullptr) {
    return false;
  }
  const std::vector<uint8_t> dib = DibV5From(factory.Get(), frame.Get());
  if (dib.empty()) {
    return false;
  }
  const std::vector<uint8_t> png =
      media_type == "image/png" ? bytes : PngFrom(factory.Get(), frame.Get());
  // Owned by a window: with none, EmptyClipboard leaves it to no one and
  // SetClipboardData fails.
  if (!::OpenClipboard(owner)) {
    return false;
  }
  ::EmptyClipboard();
  const bool written = SetClipboardBytes(CF_DIBV5, dib);
  if (!png.empty()) {
    static const UINT kPng = ::RegisterClipboardFormatW(L"PNG");
    SetClipboardBytes(kPng, png);
  }
  ::CloseClipboard();
  return written;
}
