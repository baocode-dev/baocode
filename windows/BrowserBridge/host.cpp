// baocode-browser-host.exe: the native messaging host of BaoCode's browser
// extension (browser_extension/) on Windows, as macos/BrowserBridge/host.c
// is on macOS. The browser starts it for the extension, as
// dev.baocode.browser.json beside it says (the installer's keys point the
// browsers there, see tool/baocode.iss). It passes the extension's
// messages to BaoCode and BaoCode's back: waiting for BaoCode while it is
// not running, and again once it quits.
//
// Dart has no Unix sockets on Windows: BaoCode (lib/browser/
// browser_bridge.dart) listens on 127.0.0.1, at the port its file in the
// user's LocalAppData\BaoCode folder says, baocode-browser.port:
// "<port> <token>" (resolved via SHGetKnownFolderPath so differing TEMP/TMP
// environment variables across launchers never separate the host from BaoCode,
// with a fallback to the temporary folder for older builds). Any program may
// connect there, so the host's hello says the token, which only the user can
// read; BaoCode lets in no one who does not.
//
// Both ways a message is the browser's: its length (4 bytes, this
// machine's order), then that much JSON. The host says what goes on with
// BaoCode in messages of its own: {"type":"bridge","connected":…}. It
// quits once the browser lets it go (its input ends).

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <objbase.h>
#include <shlobj.h>
#include <tlhelp32.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define MAX_MESSAGE (64 * 1024 * 1024)

static SRWLOCK out_lock = SRWLOCK_INIT;
static SRWLOCK socket_lock = SRWLOCK_INIT;
static SOCKET bao = INVALID_SOCKET;  // The socket to BaoCode, while connected.
static const char* origin = "";
static HANDLE input;
static HANDLE output;

// The browser's input and output: pipes, read and written as they are (no
// text mode's line ends).
static bool read_input(void* buffer, uint32_t size) {
  char* p = static_cast<char*>(buffer);
  while (size > 0) {
    DWORD n = 0;
    if (!ReadFile(input, p, size, &n, nullptr) || n == 0) return false;
    p += n;
    size -= n;
  }
  return true;
}

static bool write_output(const void* buffer, uint32_t size) {
  const char* p = static_cast<const char*>(buffer);
  while (size > 0) {
    DWORD n = 0;
    if (!WriteFile(output, p, size, &n, nullptr) || n == 0) return false;
    p += n;
    size -= n;
  }
  return true;
}

static bool receive_all(SOCKET fd, void* buffer, uint32_t size) {
  char* p = static_cast<char*>(buffer);
  while (size > 0) {
    int n = recv(fd, p, static_cast<int>(size), 0);
    if (n <= 0) return false;
    p += n;
    size -= static_cast<uint32_t>(n);
  }
  return true;
}

static bool send_all(SOCKET fd, const void* buffer, uint32_t size) {
  const char* p = static_cast<const char*>(buffer);
  while (size > 0) {
    int n = send(fd, p, static_cast<int>(size), 0);
    if (n <= 0) return false;
    p += n;
    size -= static_cast<uint32_t>(n);
  }
  return true;
}

// A whole message, by [take]: its text (freed by the caller), nullptr once
// the input ends.
template <typename Take>
static char* read_message(Take take, uint32_t* length) {
  if (!take(length, 4) || *length > MAX_MESSAGE) return nullptr;
  char* text = static_cast<char*>(malloc(*length ? *length : 1));
  if (!text) return nullptr;
  if (!take(text, *length)) {
    free(text);
    return nullptr;
  }
  return text;
}

static bool send_message(SOCKET fd, const char* text, uint32_t length) {
  return send_all(fd, &length, 4) && send_all(fd, text, length);
}

// To the extension, whole messages at a time.
static void to_browser(const char* text, uint32_t length) {
  AcquireSRWLockExclusive(&out_lock);
  if (!write_output(&length, 4) || !write_output(text, length)) ExitProcess(0);
  ReleaseSRWLockExclusive(&out_lock);
}

static void tell_browser(bool connected) {
  const char* text = connected ? "{\"type\":\"bridge\",\"connected\":true}"
                               : "{\"type\":\"bridge\",\"connected\":false}";
  to_browser(text, static_cast<uint32_t>(strlen(text)));
}

// The parent of [pid], as the processes' snapshot has it; 0 when none.
static DWORD parent_of(HANDLE snapshot, DWORD pid) {
  PROCESSENTRY32 entry = {};
  entry.dwSize = sizeof entry;
  for (BOOL found = Process32First(snapshot, &entry); found;
       found = Process32Next(snapshot, &entry)) {
    if (entry.th32ProcessID == pid) return entry.th32ParentProcessID;
  }
  return 0;
}

// [pid]'s executable, in [wide] (a path), [length] its characters.
static bool image_path(DWORD pid, wchar_t* wide, DWORD* length) {
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return false;
  const BOOL ok = QueryFullProcessImageNameW(process, 0, wide, length);
  CloseHandle(process);
  return ok != FALSE && *length > 0;
}

// The browser's executable, as the process that started this one runs it:
// the folder says which browser it is (a fork's chrome.exe is not
// Chrome's). Windows starts the host through cmd.exe, whose parent is the
// browser: the chain is walked up to it. "" when it is not to be had.
static void browser_path(char* buffer, size_t size) {
  buffer[0] = 0;
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return;
  DWORD pid = GetCurrentProcessId();
  wchar_t wide[1024];
  for (int up = 0; up < 4; up++) {
    pid = parent_of(snapshot, pid);
    if (pid == 0) break;
    DWORD length = static_cast<DWORD>(sizeof wide / sizeof wide[0]);
    if (!image_path(pid, wide, &length)) break;
    const wchar_t* name = wcsrchr(wide, L'\\');
    name = name ? name + 1 : wide;
    if (_wcsicmp(name, L"cmd.exe") == 0 ||
        _wcsicmp(name, L"conhost.exe") == 0) {
      continue;
    }
    const int n = WideCharToMultiByte(CP_UTF8, 0, wide, static_cast<int>(length),
                                      buffer, static_cast<int>(size - 1),
                                      nullptr, nullptr);
    if (n > 0) buffer[n] = 0;
    break;
  }
  CloseHandle(snapshot);
}

// [text] as it goes in JSON: its quotes and backslashes escaped (a path
// has no control characters in it).
static void escape_json(const char* text, char* out, size_t size) {
  size_t j = 0;
  for (const char* p = text; *p && j + 3 < size; p++) {
    if (*p == '"' || *p == '\\') out[j++] = '\\';
    out[j++] = *p;
  }
  out[j] = 0;
}

// BaoCode's port and token, from [path]: false while there is none (BaoCode
// is not running) or it is not whole yet.
static bool read_port_file(const wchar_t* path,
                           unsigned* port,
                           char* token,
                           size_t size) {
  HANDLE file = CreateFileW(
      path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  char text[256];
  DWORD got = 0;
  const BOOL ok = ReadFile(file, text, static_cast<DWORD>(sizeof text - 1),
                           &got, nullptr);
  CloseHandle(file);
  if (!ok) return false;
  text[got] = 0;
  char* end = nullptr;
  const unsigned long value = strtoul(text, &end, 10);
  if (end == text || *end != ' ' || value == 0 || value > 65535) return false;
  // The token is hex: nothing in it needs escaping in the hello's JSON.
  const char* given = end + 1;
  const size_t length = strspn(given, "0123456789abcdef");
  if (length == 0 || length >= size || given[length] != 0) return false;
  memcpy(token, given, length);
  token[length] = 0;
  *port = static_cast<unsigned>(value);
  return true;
}

static SOCKET connect_bao(unsigned port) {
  SOCKET fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (fd == INVALID_SOCKET) return INVALID_SOCKET;
  sockaddr_in address = {};
  address.sin_family = AF_INET;
  address.sin_port = htons(static_cast<u_short>(port));
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (connect(fd, reinterpret_cast<sockaddr*>(&address),
              static_cast<int>(sizeof address)) != 0) {
    closesocket(fd);
    return INVALID_SOCKET;
  }
  return fd;
}

static SOCKET connect_port_file(const wchar_t* path, char* token, size_t size) {
  unsigned port = 0;
  if (!read_port_file(path, &port, token, size)) return INVALID_SOCKET;
  return connect_bao(port);
}

// Connects to BaoCode using LocalAppData\BaoCode\baocode-browser.port (the
// user's own known folder, immune to TEMP/TMP differences across launchers),
// falling back to %TEMP%\baocode-browser.port for older BaoCode builds.
static SOCKET connect_known_bao(char* token, size_t size) {
  PWSTR local = nullptr;
  const HRESULT hr =
      SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local);
  if (SUCCEEDED(hr) && local && local[0] != 0) {
    wchar_t path[1024];
    const int n = swprintf_s(path, sizeof path / sizeof path[0],
                             L"%ls\\BaoCode\\baocode-browser.port", local);
    CoTaskMemFree(local);
    if (n > 0) {
      SOCKET fd = connect_port_file(path, token, size);
      if (fd != INVALID_SOCKET) return fd;
    }
  } else if (local) {
    CoTaskMemFree(local);
  }
  wchar_t temp[MAX_PATH + 32];
  const DWORD n = GetTempPathW(MAX_PATH + 1, temp);
  if (n > 0 && n <= MAX_PATH && wcscat_s(temp, L"baocode-browser.port") == 0) {
    return connect_port_file(temp, token, size);
  }
  return INVALID_SOCKET;
}

// BaoCode's messages, to the browser; connecting again each time BaoCode
// comes back.
static DWORD WINAPI from_bao(void*) {
  for (;;) {
    char token[128];
    SOCKET fd = connect_known_bao(token, sizeof token);
    if (fd == INVALID_SOCKET) {
      Sleep(1000);
      continue;
    }
    // Who it is: the extension's origin, as the browser gave it; the
    // token, which says the host is one the user started; and the
    // browser's own executable, which tells one from another.
    char path[1024];
    char escaped[2048];
    browser_path(path, sizeof path);
    escape_json(path, escaped, sizeof escaped);
    char hello[4096];
    const int n = snprintf(hello, sizeof hello,
                           "{\"type\":\"hello\",\"origin\":\"%s\","
                           "\"token\":\"%s\",\"path\":\"%s\"}",
                           origin, token, escaped);
    if (n <= 0 || n >= static_cast<int>(sizeof hello) ||
        !send_message(fd, hello, static_cast<uint32_t>(n))) {
      closesocket(fd);
      Sleep(1000);
      continue;
    }
    AcquireSRWLockExclusive(&socket_lock);
    bao = fd;
    ReleaseSRWLockExclusive(&socket_lock);
    tell_browser(true);
    for (;;) {
      uint32_t length;
      char* text = read_message(
          [fd](void* buffer, uint32_t size) {
            return receive_all(fd, buffer, size);
          },
          &length);
      if (!text) break;
      to_browser(text, length);
      free(text);
    }
    AcquireSRWLockExclusive(&socket_lock);
    bao = INVALID_SOCKET;
    ReleaseSRWLockExclusive(&socket_lock);
    closesocket(fd);
    tell_browser(false);
    Sleep(1000);
  }
}

int main(int argc, char** argv) {
  // The browser's: the extension's origin first, then a window's handle
  // (--parent-window=…).
  for (int i = 1; i < argc; i++) {
    if (strncmp(argv[i], "chrome-extension://", 19) == 0) {
      // Quotes and backslashes have no place in an origin: none is let in
      // the JSON it goes into.
      if (!strpbrk(argv[i], "\"\\")) origin = argv[i];
      break;
    }
  }
  input = GetStdHandle(STD_INPUT_HANDLE);
  output = GetStdHandle(STD_OUTPUT_HANDLE);
  WSADATA wsa;
  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return 1;
  tell_browser(false);
  HANDLE thread = CreateThread(nullptr, 0, from_bao, nullptr, 0, nullptr);
  if (!thread) return 1;
  CloseHandle(thread);
  // The extension's messages, to BaoCode: dropped while it is not there
  // (the extension knows, told above).
  for (;;) {
    uint32_t length;
    char* text = read_message(read_input, &length);
    if (!text) ExitProcess(0);
    AcquireSRWLockExclusive(&socket_lock);
    if (bao != INVALID_SOCKET && !send_message(bao, text, length)) {
      // Gone: its reader sees it too, and says so.
      shutdown(bao, SD_BOTH);
    }
    ReleaseSRWLockExclusive(&socket_lock);
    free(text);
  }
}
