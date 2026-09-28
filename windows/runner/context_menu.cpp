#include "context_menu.h"

#include <string>
#include <vector>

#include "utils.h"

namespace {

// The label with its shortcut on it, as Windows menus show one: a tab
// between the two, which right-aligns what follows it.
std::wstring LabelWithShortcut(const ContextMenuItem& item) {
  std::wstring text = Utf16FromUtf8(item.label);
  if (!item.key.empty()) {
    text += L'\t';
    text += L"Ctrl+";
    text += Utf16FromUtf8(item.key);
  }
  return text;
}

}  // namespace

std::optional<std::string> ShowContextMenu(
    HWND window, POINT at, const std::vector<ContextMenuItem>& items) {
  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) {
    return std::nullopt;
  }

  // Command ids count from 1: 0 is what TrackPopupMenu answers when
  // nothing was chosen.
  std::vector<std::string> ids;
  int command = 1;
  for (const ContextMenuItem& item : items) {
    if (item.separator) {
      ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      continue;
    }
    UINT flags = MF_STRING;
    if (!item.enabled) {
      flags |= MF_GRAYED;
    }
    const std::wstring label = LabelWithShortcut(item);
    ::AppendMenuW(menu, flags, static_cast<UINT_PTR>(command), label.c_str());
    ids.push_back(item.id);
    command++;
  }

  if (ids.empty()) {
    ::DestroyMenu(menu);
    return std::nullopt;
  }

  // The window owns the menu while it is up, so a click elsewhere puts it
  // away (and the popup's coordinates are screen ones, which is what |at|
  // already is).
  ::SetForegroundWindow(window);
  const int chosen = ::TrackPopupMenuEx(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_LEFTALIGN | TPM_TOPALIGN, at.x,
      at.y, window, nullptr);
  ::DestroyMenu(menu);

  if (chosen <= 0 || static_cast<size_t>(chosen) > ids.size()) {
    return std::nullopt;
  }
  return ids[static_cast<size_t>(chosen) - 1];
}
