// Draws the macOS disk image's window background: the app on the left, a
// hand-drawn arrow, the Applications folder on the right (create-dmg puts both icons
// where tool/build_macos.dart says), and what to do, in Chinese and
// English. Run from the repository after changing it:
//
//   swift tool/dmg_background.swift
//
// It writes macos/packaging/dmg-background.tiff, 1x and 2x in one file so
// that Retina screens get the sharp one.
import AppKit

/// The window's content, in points; the icons' centres (from its top left)
/// are tool/build_macos.dart's.
let size = NSSize(width: 660, height: 400)
let appCentre = NSPoint(x: 165, y: 145)
let applicationsCentre = NSPoint(x: 495, y: 145)
let iconSize: CGFloat = 128

/// Ink: the app icon's gold, deepened to read on the light background.
let inkLight = NSColor(srgbRed: 0.91, green: 0.67, blue: 0.25, alpha: 1)
let inkDark = NSColor(srgbRed: 0.77, green: 0.50, blue: 0.13, alpha: 1)

/// A pen stroke along [curve] (0 to 1): [width] at its widest, thinner at
/// both ends, its edges wobbling a little as a hand's do ([seed] varies
/// them). Rounded where it starts and ends: the outline, then a dot for
/// each end (apart, as they wind the other way and would cut holes in it).
func stroke(_ curve: (CGFloat) -> NSPoint, width: CGFloat, seed: CGFloat) -> [NSBezierPath] {
  let steps = 120
  var left: [NSPoint] = []
  var right: [NSPoint] = []
  var ends: [(NSPoint, CGFloat)] = []
  for i in 0...steps {
    let t = CGFloat(i) / CGFloat(steps)
    let p = curve(t)
    let ahead = curve(min(1, t + 0.005))
    let behind = curve(max(0, t - 0.005))
    let length = max(hypot(ahead.x - behind.x, ahead.y - behind.y), 0.0001)
    let normal = NSPoint(
      x: -(ahead.y - behind.y) / length, y: (ahead.x - behind.x) / length)
    // Pressed hardest a third of the way in, lifted at the end.
    let pressure = 0.6 + 0.4 * sin(.pi * pow(t, 0.75))
    let wobble = 1 + 0.10 * sin(t * 13 + seed) + 0.05 * sin(t * 37 + seed * 3)
    let half = width * pressure * wobble / 2
    left.append(NSPoint(x: p.x + normal.x * half, y: p.y + normal.y * half))
    right.append(NSPoint(x: p.x - normal.x * half, y: p.y - normal.y * half))
    if i == 0 || i == steps { ends.append((p, half)) }
  }
  let path = NSBezierPath()
  path.move(to: left[0])
  for point in left.dropFirst() { path.line(to: point) }
  for point in right.reversed() { path.line(to: point) }
  path.close()
  return [path] + ends.map { centre, radius in
    NSBezierPath(ovalIn: NSRect(
      x: centre.x - radius, y: centre.y - radius,
      width: radius * 2, height: radius * 2))
  }
}

func cubic(_ a: NSPoint, _ b: NSPoint, _ c: NSPoint, _ d: NSPoint) -> (CGFloat) -> NSPoint {
  { t in
    let u = 1 - t
    let x = u * u * u * a.x + 3 * u * u * t * b.x + 3 * u * t * t * c.x + t * t * t * d.x
    let y = u * u * u * a.y + 3 * u * u * t * b.y + 3 * u * t * t * c.y + t * t * t * d.y
    return NSPoint(x: x, y: y)
  }
}

func draw(scale: CGFloat) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  rep.size = size
  NSGraphicsContext.saveGraphicsState()
  // From the top left, as Finder places the icons: flipped, for text too.
  let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
  // (Already in points: the rep's size scales it.)
  cg.translateBy(x: 0, y: size.height)
  cg.scaleBy(x: 1, y: -1)
  NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

  // Light: Finder writes the icons' names in black over a background
  // picture, whatever the system's appearance.
  NSGradient(
    starting: NSColor(srgbRed: 0.985, green: 0.980, blue: 0.968, alpha: 1),
    ending: NSColor(srgbRed: 0.945, green: 0.933, blue: 0.910, alpha: 1)
  )!.draw(in: NSRect(origin: .zero, size: size), angle: -90)

  // The arrow: a stroke arching from the app to the folder, as far from
  // each icon's edge, and a head of two strokes.
  let gap: CGFloat = 24
  let start = NSPoint(x: appCentre.x + iconSize / 2 + gap, y: appCentre.y + 6)
  let tip = NSPoint(x: applicationsCentre.x - iconSize / 2 - gap, y: appCentre.y - 2)
  // Arching up, and coming in nearly level, for the head to point at the
  // folder.
  let control1 = NSPoint(x: start.x + 45, y: start.y - 34)
  let control2 = NSPoint(x: tip.x - 55, y: tip.y - 10)
  var strokes = stroke(cubic(start, control1, control2, tip), width: 6, seed: 0.7)
  // Back along the stroke's last stretch, turned either way.
  let back = atan2(control2.y - tip.y, control2.x - tip.x)
  for (turn, length, seed) in [(0.62, 23.0, 2.1), (-0.55, 20.0, 4.3)] as [(CGFloat, CGFloat, CGFloat)] {
    let angle = back + turn
    let end = NSPoint(x: tip.x + cos(angle) * length, y: tip.y + sin(angle) * length)
    // Bowed a little, as a flick of the pen.
    let bow = NSPoint(
      x: (tip.x + end.x) / 2 + sin(angle) * 1.5,
      y: (tip.y + end.y) / 2 - cos(angle) * 1.5)
    strokes += stroke(cubic(tip, bow, bow, end), width: 5.5, seed: seed)
  }
  let ink = NSRect(
    x: start.x - 8, y: start.y - 60, width: tip.x - start.x + 16, height: 100)
  for path in strokes {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(starting: inkLight, ending: inkDark)!.draw(in: ink, angle: 0)
    NSGraphicsContext.restoreGraphicsState()
  }

  func line(_ text: String, fontSize: CGFloat, weight: NSFont.Weight, white: CGFloat, top: CGFloat) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributed = NSAttributedString(string: text, attributes: [
      .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
      .foregroundColor: NSColor(white: white, alpha: 1),
      .paragraphStyle: paragraph,
    ])
    attributed.draw(
      in: NSRect(x: 0, y: top, width: size.width, height: fontSize * 1.6))
  }
  line("将 BaoCode 拖到 Applications 文件夹即可完成安装",
       fontSize: 14, weight: .medium, white: 0.24, top: 285)
  line("Drag BaoCode to the Applications folder to install",
       fontSize: 12, weight: .regular, white: 0.50, top: 309)

  NSGraphicsContext.restoreGraphicsState()
  return rep
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  .deletingLastPathComponent()
let folder = root.appendingPathComponent("macos/packaging")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let output = folder.appendingPathComponent("dmg-background.tiff")
let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in:
  [draw(scale: 1), draw(scale: 2)], using: .lzw, factor: 0)!
try tiff.write(to: output)
// A preview to look at, not shipped (the .tiff is what create-dmg takes).
let preview = draw(scale: 2).representation(using: .png, properties: [:])!
try preview.write(to: URL(fileURLWithPath: "/tmp/dmg-background@2x.png"))
print("Wrote \(output.path)")
