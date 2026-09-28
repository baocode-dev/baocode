#include "caption_areas.h"

#include <windows.h>

#include <vector>

namespace {

// The rectangle in the window's own pixels, from the app's.
RECT Scaled(const CaptionAreas::Rect& rect, double scale) {
  RECT scaled = {};
  scaled.left = static_cast<LONG>(rect.left * scale);
  scaled.top = static_cast<LONG>(rect.top * scale);
  scaled.right = static_cast<LONG>((rect.left + rect.width) * scale);
  scaled.bottom = static_cast<LONG>((rect.top + rect.height) * scale);
  return scaled;
}

bool Holds(const RECT& rect, POINT point) {
  return point.x >= rect.left && point.x < rect.right && point.y >= rect.top &&
         point.y < rect.bottom;
}

}  // namespace

void CaptionAreas::Set(double scale,
                       double height,
                       std::vector<Rect> controls,
                       Rect minimize,
                       Rect maximize,
                       Rect close) {
  height_ = static_cast<int>(height * scale);
  controls_.clear();
  controls_.reserve(controls.size());
  for (const Rect& control : controls) {
    controls_.push_back(Scaled(control, scale));
  }
  minimize_ = Scaled(minimize, scale);
  maximize_ = Scaled(maximize, scale);
  close_ = Scaled(close, scale);
}

std::optional<LRESULT> CaptionAreas::ButtonAt(POINT point) const {
  if (empty()) {
    return std::nullopt;
  }
  if (Holds(minimize_, point)) {
    return HTMINBUTTON;
  }
  if (Holds(maximize_, point)) {
    return HTMAXBUTTON;
  }
  if (Holds(close_, point)) {
    return HTCLOSE;
  }
  return std::nullopt;
}

bool CaptionAreas::Contains(POINT point) const {
  return !empty() && point.y >= 0 && point.y < height_;
}

bool CaptionAreas::IsControl(POINT point) const {
  for (const RECT& control : controls_) {
    if (Holds(control, point)) {
      return true;
    }
  }
  return false;
}
