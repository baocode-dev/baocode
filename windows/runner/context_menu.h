#ifndef RUNNER_CONTEXT_MENU_H_
#define RUNNER_CONTEXT_MENU_H_

#include <windows.h>

#include <optional>
#include <string>
#include <vector>

// An item of the menu Flutter asked for (see NativeMenuItem in
// lib/workspace/window_controls.dart): a separator, or an entry that answers
// its |id|.
struct ContextMenuItem {
  bool separator = false;
  std::string id;
  std::string label;
  // The letter of its shortcut, shown as the system writes it here
  // (Ctrl+X); empty for none.
  std::string key;
  bool enabled = true;
};

// Shows the menu at |at|, in screen pixels, over |window| and answers the
// chosen item's id: null for none, and for a menu with nothing in it.
std::optional<std::string> ShowContextMenu(
    HWND window, POINT at, const std::vector<ContextMenuItem>& items);

#endif  // RUNNER_CONTEXT_MENU_H_
