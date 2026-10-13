// Renders the Salah app icon: a brass mihrab (pointed prayer-niche arch) holding a crescent
// moon, on the midnight "Nocturne" squircle of the macOS icon grid. The icon is one vector
// drawing in a 1024 x 1024 design space, rendered to every size of the macOS AppIcon set.
//
// Run from the repository root:
//   swift Scripts/render-app-icon.swift Salah/Assets.xcassets/AppIcon.appiconset
//
// Uses only Apple's system frameworks (CoreGraphics, ImageIO): no dependencies, fonts or
// artwork files. The output is deterministic: re-running it writes the same bytes.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

private func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}

private let midnightTop = color(0.075, 0.094, 0.180)
private let midnightBottom = color(0.027, 0.035, 0.078)
private let brassLight = color(0.98, 0.83, 0.50)
private let brass = color(0.88, 0.69, 0.29)
private let brassDeep = color(0.62, 0.45, 0.12)

// MARK: - Geometry (design space, 1024 x 1024, y grows downward)

private let canvas: CGFloat = 1024
private let body = CGRect(x: 100, y: 100, width: 824, height: 824)
private let bodyCornerRadius: CGFloat = 185.4

/// A rounded rectangle with continuous (curvature-matched) corners, like the macOS icon shape.
private func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
  let r = min(radius, min(rect.width, rect.height) / 2 / 1.528_665)
  func tl(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: rect.minX + x * r, y: rect.minY + y * r)
  }
  func tr(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: rect.maxX - x * r, y: rect.minY + y * r)
  }
  func br(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: rect.maxX - x * r, y: rect.maxY - y * r)
  }
  func bl(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: rect.minX + x * r, y: rect.maxY - y * r)
  }

  // One corner as seen from its two edges; `p(along, across)` maps into that corner.
  func corner(_ path: CGMutablePath, _ p: (CGFloat, CGFloat) -> CGPoint, swap: Bool) {
    func q(_ a: CGFloat, _ b: CGFloat) -> CGPoint { swap ? p(b, a) : p(a, b) }
    path.addCurve(to: q(0.669_934, 0.065_496), control1: q(1.088_493, 0), control2: q(0.868_407, 0))
    path.addLine(to: q(0.631_494, 0.074_911))
    path.addCurve(
      to: q(0.074_912, 0.631_494), control1: q(0.372_824, 0.169_059),
      control2: q(0.169_060, 0.372_824)
    )
    path.addCurve(to: q(0, 1.528_665), control1: q(0, 0.868_407), control2: q(0, 1.088_493))
  }

  let path = CGMutablePath()
  path.move(to: tl(1.528_665, 0))
  path.addLine(to: tr(1.528_665, 0))
  corner(path, tr, swap: false)
  path.addLine(to: br(0, 1.528_665))
  corner(path, br, swap: true)
  path.addLine(to: bl(1.528_665, 0))
  corner(path, bl, swap: false)
  path.addLine(to: tl(0, 1.528_665))
  corner(path, tl, swap: true)
  path.closeSubpath()
  return path
}

/// A two-centred pointed arch standing on a flat base. Each side is an arc of `radius` whose
/// centre sits on the springing line, `centerOffset` across the axis from it, so arches that
/// share `centerOffset` are concentric.
private func pointedArch(
  centerX: CGFloat, centerOffset: CGFloat, radius: CGFloat, spring: CGFloat, base: CGFloat
) -> CGPath {
  let halfWidth = radius - centerOffset
  let leftCenter = CGPoint(x: centerX + centerOffset, y: spring)
  let rightCenter = CGPoint(x: centerX - centerOffset, y: spring)
  let apexY = spring - (radius * radius - centerOffset * centerOffset).squareRoot()
  let leftEnd = atan2(apexY - spring, centerX - leftCenter.x)
  let rightStart = atan2(apexY - spring, centerX - rightCenter.x)

  let path = CGMutablePath()
  path.move(to: CGPoint(x: centerX - halfWidth, y: base))
  path.addLine(to: CGPoint(x: centerX - halfWidth, y: spring))
  path.addArc(
    center: leftCenter, radius: radius, startAngle: .pi, endAngle: leftEnd, clockwise: false)
  path.addArc(
    center: rightCenter, radius: radius, startAngle: rightStart, endAngle: 0, clockwise: false)
  path.addLine(to: CGPoint(x: centerX + halfWidth, y: base))
  return path
}

private let archAxis: CGFloat = 512
private let archCenterOffset: CGFloat = 120
private let archSpring: CGFloat = 540
private let nicheRadius: CGFloat = 320
private let floorTop: CGFloat = 800

/// The solid niche, standing on the floor.
private let niche: CGPath = {
  let path = CGMutablePath()
  path.addPath(
    pointedArch(
      centerX: archAxis, centerOffset: archCenterOffset, radius: nicheRadius, spring: archSpring,
      base: floorTop))
  path.closeSubpath()
  return path
}()

/// The open frame around the niche (a concentric arch) and the floor they stand on. Below 32 px
/// the frame and floor would be sub-pixel lines, so the icon keeps just the niche; from 32 px
/// up, the frame and the gap inside it are each at least one device pixel wide.
private func frameAndFloor(pixel: CGFloat) -> CGPath? {
  guard pixel <= canvas / 32 else { return nil }
  let width = max(24, pixel)
  let gap = max(30, pixel)
  let radius = nicheRadius + gap + width / 2
  let arch = pointedArch(
    centerX: archAxis, centerOffset: archCenterOffset, radius: radius, spring: archSpring,
    base: floorTop)
  let path = CGMutablePath()
  path.addPath(
    arch.copy(strokingWithWidth: width, lineCap: .butt, lineJoin: .miter, miterLimit: 10))
  let reach = radius - archCenterOffset + width / 2 + 26
  path.addRect(CGRect(x: archAxis - reach, y: floorTop, width: reach * 2, height: width))
  return path
}

// The crescent is a disc minus an offset disc, with its horns turned up and to the right.
private let moonCenter = CGPoint(x: 500, y: 508)
private let moonRadius: CGFloat = 130
private let moonBite = CGPoint(x: moonCenter.x + 62, y: moonCenter.y - 46)
private let moonBiteRadius: CGFloat = 102

// MARK: - Drawing

private func linearGradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
  CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
}

private func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
  CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
}

private func drawIcon(in context: CGContext, pixelSize: CGFloat) {
  let scale = pixelSize / canvas
  // One device pixel, in design units.
  let pixel = 1 / scale

  context.translateBy(x: 0, y: pixelSize)
  context.scaleBy(x: scale, y: -scale)

  let bodyPath = continuousRoundedRect(body, radius: bodyCornerRadius)
  let night = linearGradient([midnightTop, midnightBottom], [0, 1])
  let nightStart = CGPoint(x: 512, y: body.minY)
  let nightEnd = CGPoint(x: 512, y: body.maxY)

  // Soft drop shadow in the margin. Shadow offsets and blur are in device pixels.
  context.saveGState()
  context.setShadow(
    offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale,
    color: color(0, 0, 0, 0.35))
  context.addPath(bodyPath)
  context.setFillColor(midnightBottom)
  context.fillPath()
  context.restoreGState()

  // Midnight body, with a faint lamp-glow behind the mihrab.
  context.saveGState()
  context.addPath(bodyPath)
  context.clip()
  context.drawLinearGradient(night, start: nightStart, end: nightEnd, options: [])
  let glow = CGGradient(
    colorsSpace: sRGB,
    colors: [color(0.88, 0.69, 0.29, 0.20), color(0.88, 0.69, 0.29, 0)] as CFArray,
    locations: [0, 1])!
  context.drawRadialGradient(
    glow, startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
    endCenter: CGPoint(x: 512, y: 470), endRadius: 430, options: [])

  // At 16 px, where the frame drops out, the niche and crescent grow into its place so the
  // crescent stays more than a pixel thick.
  let frame = frameAndFloor(pixel: pixel)
  var grow = CGAffineTransform.identity
  if frame == nil {
    grow = CGAffineTransform(translationX: 512, y: 512).scaledBy(x: 1.2, y: 1.2)
      .translatedBy(x: -512, y: -512)
  }

  // Brass mihrab, lit from above.
  context.saveGState()
  context.addPath(niche.copy(using: &grow)!)
  if let frame { context.addPath(frame) }
  context.clip()
  let metal = linearGradient([brassLight, brass, brassDeep], [0, 0.45, 1])
  context.drawLinearGradient(
    metal, start: CGPoint(x: 512, y: 170), end: CGPoint(x: 512, y: 840), options: [])
  context.restoreGState()

  // Crescent cut out of the niche, showing the night behind it.
  context.saveGState()
  context.addPath(CGPath(ellipseIn: circle(moonCenter, moonRadius), transform: &grow))
  context.clip()
  context.addRect(CGRect(x: 0, y: 0, width: canvas, height: canvas))
  context.addPath(CGPath(ellipseIn: circle(moonBite, moonBiteRadius), transform: &grow))
  context.clip(using: .evenOdd)
  context.drawLinearGradient(night, start: nightStart, end: nightEnd, options: [])
  context.restoreGState()

  context.restoreGState()

  // Light rim inside the body edge, so the dark icon holds its shape on a dark Dock. It is at
  // least one device pixel wide.
  context.saveGState()
  context.addPath(bodyPath)
  context.clip()
  context.addPath(bodyPath)
  context.setLineWidth(max(5, pixel) * 2)
  context.setStrokeColor(color(1, 1, 1, 0.16))
  context.strokePath()
  context.restoreGState()
}

private func renderPNG(pixelSize: Int, to url: URL) throws {
  let size = CGFloat(pixelSize)
  guard
    let context = CGContext(
      data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0,
      space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { throw RenderError.context }
  context.setAllowsAntialiasing(true)
  context.setShouldAntialias(true)
  context.interpolationQuality = .high
  drawIcon(in: context, pixelSize: size)

  guard let image = context.makeImage() else { throw RenderError.image }
  guard
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { throw RenderError.destination(url.path) }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { throw RenderError.write(url.path) }
}

private enum RenderError: Error {
  case context
  case image
  case destination(String)
  case write(String)
}

// MARK: - Main

private let outputs: [(name: String, pixels: Int)] = [
  ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
  ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
  ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
  ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
  ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
  FileHandle.standardError.write(
    Data("usage: swift Scripts/render-app-icon.swift <AppIcon.appiconset>\n".utf8))
  exit(2)
}
let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
for output in outputs {
  let url = directory.appendingPathComponent(output.name)
  try renderPNG(pixelSize: output.pixels, to: url)
  print("wrote \(output.name) (\(output.pixels) px)")
}
