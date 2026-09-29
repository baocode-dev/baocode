#include "caption_areas.h"

#include <windows.h>

#include <utility>
#include <vector>

namespace {

// Whether |rect| (the app's pixels) holds |point| (the window's, at |scale|).
bool Holds(const CaptionAreas::Rect& rect, POINT point, double scale) {
  const double x = point.x / scale;
  const double y = point.y / scale;
  return x >= rect.left && x < rect.left + rect.width && y >= rect.top &&
         y < rect.top + rect.height;
}

}  // namespace

void CaptionAreas::Set(double height,
                       std::vector<Rect> controls,
                       Rect minimize,
                       Rect maximize,
                       Rect close) {
  height_ = height;
  controls_ = std::move(controls);
  minimize_ = minimize;
  maximize_ = maximize;
  close_ = close;
}

std::optional<LRESULT> CaptionAreas::ButtonAt(POINT point,
                                              double scale) const {
  if (empty()) {
    return std::nullopt;
  }
  if (Holds(minimize_, point, scale)) {
    return HTMINBUTTON;
  }
  if (Holds(maximize_, point, scale)) {
    return HTMAXBUTTON;
  }
  if (Holds(close_, point, scale)) {
    return HTCLOSE;
  }
  return std::nullopt;
}

bool CaptionAreas::Contains(POINT point, double scale) const {
  return !empty() && point.y >= 0 && point.y / scale < height_;
}

bool CaptionAreas::IsControl(POINT point, double scale) const {
  for (const Rect& control : controls_) {
    if (Holds(control, point, scale)) {
      return true;
    }
  }
  return false;
}
