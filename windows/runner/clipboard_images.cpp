#include "clipboard_images.h"

#include <windows.h>
#include <shellapi.h>
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

// Any image WIC can read, as PNG.
std::vector<uint8_t> PngFromBytes(const std::vector<uint8_t>& bytes) {
  if (bytes.empty()) {
    return {};
  }
  ComPtr<IWICImagingFactory> factory = ImagingFactory();
  ComPtr<IWICStream> stream;
  if (factory == nullptr || FAILED(factory->CreateStream(&stream))) {
    return {};
  }
  // The decoder reads under it, which is why the bytes are not const.
  auto* data = const_cast<BYTE*>(bytes.data());
  if (FAILED(stream->InitializeFromMemory(data,
                                          static_cast<DWORD>(bytes.size())))) {
    return {};
  }
  ComPtr<IWICBitmapDecoder> decoder;
  if (FAILED(factory->CreateDecoderFromStream(stream.Get(), nullptr,
                                              WICDecodeMetadataCacheOnDemand,
                                              &decoder))) {
    return {};
  }
  ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(decoder->GetFrame(0, &frame))) {
    return {};
  }
  return PngFrom(factory.Get(), frame.Get());
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
