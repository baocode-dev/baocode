#ifndef RUNNER_CAPTION_AREAS_H_
#define RUNNER_CAPTION_AREAS_H_

#include <windows.h>

#include <optional>
#include <vector>

// Where the header Flutter draws put its pieces (see
// lib/workspace/window_header/), as Flutter reports them: in its own logical
// pixels, taken to the window's physical ones at each hit test, at the dpi
// the window has then (a move to another monitor changes it, and nothing of
// the header's layout).
//
// The window hit-tests them: the three window buttons are the system's (so a
// click minimizes, maximizes or closes it, with the system's animations and
// Snap Layouts), what Flutter kept is Flutter's, and the rest of the strip
// drags the window.
class CaptionAreas {
 public:
  // A rectangle as Flutter reports it: in the app's own pixels, from the top
  // left of the window.
  struct Rect {
    double left = 0;
    double top = 0;
    double width = 0;
    double height = 0;
  };

  // What Flutter reported.
  void Set(double height,
           std::vector<Rect> controls,
           Rect minimize,
           Rect maximize,
           Rect close);

  // Whether Flutter has reported anything: until it has (the first frames, a
  // host without the channel), the window has no header of its own.
  bool empty() const { return height_ <= 0; }

  // Which of the window's buttons |point| (client pixels, at |scale|, the
  // window's dpi over 96) is on, or nullopt; the code is what the window
  // answers WM_NCHITTEST with.
  std::optional<LRESULT> ButtonAt(POINT point, double scale) const;

  // Whether |point| is in the header at all.
  bool Contains(POINT point, double scale) const;

  // Whether |point| is one of the pieces Flutter kept: a click there is
  // Flutter's, not the window's to drag itself by.
  bool IsControl(POINT point, double scale) const;

 private:
  std::vector<Rect> controls_;
  Rect minimize_;
  Rect maximize_;
  Rect close_;
  double height_ = 0;
};

#endif  // RUNNER_CAPTION_AREAS_H_
