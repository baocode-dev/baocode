import 'dart:math' as math;
import 'dart:ui';

/// Where a window is on the desktop and how: in the system's coordinates
/// (from the top left of the main screen; points on macOS, pixels on
/// Windows), as the window reports it and takes it back.
class WindowFrame {
  const WindowFrame(
    this.bounds, {
    this.maximized = false,
    this.fullscreen = false,
    this.screen,
  });

  /// Its normal place and size (not maximized, not full screen).
  final Rect bounds;
  final bool maximized;
  final bool fullscreen;

  /// The screen it is on, as the system names it.
  final String? screen;

  static WindowFrame? fromJson(Object? json) {
    if (json is! Map) return null;
    double? number(String key) => (json[key] as num?)?.toDouble();
    final x = number('x'), y = number('y');
    final width = number('width'), height = number('height');
    if (x == null || y == null || width == null || height == null) {
      return null;
    }
    if (width <= 0 || height <= 0) return null;
    return WindowFrame(
      Rect.fromLTWH(x, y, width, height),
      maximized: json['maximized'] == true,
      fullscreen: json['fullscreen'] == true,
      screen: json['screen'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
    'x': bounds.left,
    'y': bounds.top,
    'width': bounds.width,
    'height': bounds.height,
    if (maximized) 'maximized': true,
    if (fullscreen) 'fullscreen': true,
    'screen': ?screen,
  };

  WindowFrame copyWith({
    Rect? bounds,
    bool? maximized,
    bool? fullscreen,
    String? screen,
  }) => WindowFrame(
    bounds ?? this.bounds,
    maximized: maximized ?? this.maximized,
    fullscreen: fullscreen ?? this.fullscreen,
    screen: screen ?? this.screen,
  );

  /// How much of the title bar must stay on a screen for the window to
  /// count as on it, and be dragged back.
  static const minVisible = Size(120, 40);

  /// This frame, on one of [screens] (their usable areas): where it was,
  /// if enough of it is still on its screen (or, without names, any), else
  /// moved onto the screen it was on (the first, if that is gone) and made
  /// to fit it.
  WindowFrame fit(List<ScreenArea> screens) {
    if (screens.isEmpty) return this;
    final named = screens.where((s) => s.id == screen).firstOrNull;
    if (_visibleOn(named == null ? screens : [named])) {
      return named == null ? this : copyWith(screen: named.id);
    }
    if (named == null && _visibleOn(screens)) return this;
    final target = named ?? _nearest(screens);
    final area = target.area;
    final width = math.min(bounds.width, area.width);
    final height = math.min(bounds.height, area.height);
    final left = bounds.left.clamp(area.left, area.right - width).toDouble();
    final top = bounds.top.clamp(area.top, area.bottom - height).toDouble();
    return copyWith(
      bounds: Rect.fromLTWH(left, top, width, height),
      screen: target.id,
    );
  }

  /// Whether the top of the window (where it is dragged by) shows on one
  /// of [screens].
  bool _visibleOn(List<ScreenArea> screens) {
    final title = Rect.fromLTWH(
      bounds.left,
      bounds.top,
      bounds.width,
      minVisible.height,
    );
    for (final screen in screens) {
      final shown = title.intersect(screen.area);
      if (shown.width >= math.min(minVisible.width, bounds.width) &&
          shown.height >= math.min(minVisible.height, bounds.height) &&
          bounds.top >= screen.area.top) {
        return true;
      }
    }
    return false;
  }

  ScreenArea _nearest(List<ScreenArea> screens) {
    final center = bounds.center;
    ScreenArea? best;
    var distance = double.infinity;
    for (final screen in screens) {
      final d = (screen.area.center - center).distanceSquared;
      if (d < distance) {
        distance = d;
        best = screen;
      }
    }
    return best!;
  }

  /// A frame for a new window [beside] another: down and to the right of
  /// it, as VS Code cascades them (back to its top left where that would
  /// leave its screen).
  WindowFrame cascade(List<ScreenArea> screens) {
    const step = 30.0;
    final moved = copyWith(bounds: bounds.shift(const Offset(step, step)));
    final screen =
        screens.where((s) => s.id == this.screen).firstOrNull ??
        screens.firstOrNull;
    if (screen == null) return moved;
    if (moved.bounds.right > screen.area.right ||
        moved.bounds.bottom > screen.area.bottom) {
      return copyWith(
        bounds: Rect.fromLTWH(
          screen.area.left,
          screen.area.top,
          bounds.width,
          bounds.height,
        ),
      ).fit(screens);
    }
    return moved;
  }

  @override
  bool operator ==(Object other) =>
      other is WindowFrame &&
      other.bounds == bounds &&
      other.maximized == maximized &&
      other.fullscreen == fullscreen &&
      other.screen == screen;

  @override
  int get hashCode => Object.hash(bounds, maximized, fullscreen, screen);

  @override
  String toString() =>
      'WindowFrame($bounds${maximized ? ', maximized' : ''}'
      '${fullscreen ? ', fullscreen' : ''}${screen == null ? '' : ', $screen'})';
}

/// A screen's usable area (without the menu bar, the Dock or the taskbar),
/// in the same coordinates as [WindowFrame].
class ScreenArea {
  const ScreenArea(this.id, this.area);

  final String id;
  final Rect area;

  static ScreenArea? fromJson(Object? json) {
    if (json is! Map) return null;
    double? number(String key) => (json[key] as num?)?.toDouble();
    final x = number('x'), y = number('y');
    final width = number('width'), height = number('height');
    if (x == null || y == null || width == null || height == null) {
      return null;
    }
    return ScreenArea('${json['id']}', Rect.fromLTWH(x, y, width, height));
  }
}
