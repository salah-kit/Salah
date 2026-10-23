import AppKit
import SalahCore
import SalahUI
import SwiftUI

/// The Notifications pane's prayer picker: macOS's segmented control, across the form's
/// width, drawn in the design's colors. The selected segment takes the gold fill, and each
/// prayer with every alert off shows a muted bell. Being macOS's own control, it reads to
/// VoiceOver as a radio group named "Prayer" and moves with the arrow keys.
struct PrayerPicker: NSViewRepresentable {
  @Binding var selection: NotificationTarget
  /// Each segment's target, name and whether it's muted, in order.
  let segments: [(target: NotificationTarget, name: String, isMuted: Bool)]

  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSSegmentedControl {
    let control = NSSegmentedControl()
    control.cell = PrayerSegmentedCell()
    control.trackingMode = .selectOne
    control.segmentDistribution = .fillEqually
    control.target = context.coordinator
    control.action = #selector(Coordinator.selectionChanged(_:))
    control.setAccessibilityLabel(localizedString("settings.notif.prayer", locale: .app))
    return control
  }

  func updateNSView(_ control: NSSegmentedControl, context: Context) {
    context.coordinator.parent = self
    control.segmentCount = segments.count
    for (index, segment) in segments.enumerated() {
      control.setLabel(segment.name, forSegment: index)
      control.setImage(segment.isMuted ? Self.mutedBell : nil, forSegment: index)
    }
    control.selectedSegment = segments.firstIndex { $0.target == selection } ?? -1
    control.userInterfaceLayoutDirection =
      layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
    if let cell = control.cell as? PrayerSegmentedCell {
      cell.palette = SalahPalette(
        isDark: scheme == .dark, increasedContrast: contrast == .increased)
    }
    control.needsDisplay = true
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context
  ) -> CGSize? {
    CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: 24)
  }

  private static let mutedBell = NSImage(
    systemSymbolName: "bell.slash", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))

  @MainActor
  final class Coordinator: NSObject {
    var parent: PrayerPicker

    init(_ parent: PrayerPicker) { self.parent = parent }

    @objc func selectionChanged(_ sender: NSSegmentedControl) {
      let index = sender.selectedSegment
      guard parent.segments.indices.contains(index) else { return }
      parent.selection = parent.segments[index].target
    }
  }
}

/// Draws the picker as the design does: the tertiary fill, the selected segment in the
/// gold fill with dark text, and hairlines between unselected segments.
final class PrayerSegmentedCell: NSSegmentedCell {
  var palette = SalahPalette(isDark: false)

  override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
    palette.fillTertiary.nsColor.setFill()
    NSBezierPath(roundedRect: cellFrame, xRadius: 8, yRadius: 8).fill()
    let inner = cellFrame.insetBy(dx: 2, dy: 2)
    let width = inner.width / CGFloat(max(segmentCount, 1))
    let isRightToLeft = controlView.userInterfaceLayoutDirection == .rightToLeft
    for index in 0..<segmentCount {
      let slot = isRightToLeft ? segmentCount - 1 - index : index
      let frame = NSRect(
        x: inner.minX + CGFloat(slot) * width, y: inner.minY, width: width, height: inner.height)
      drawSegment(index, inFrame: frame, with: controlView)
      // A hairline before each slot but the first, unless the selection touches it.
      let before = isRightToLeft ? index + 1 : index - 1
      if slot > 0, index != selectedSegment, before != selectedSegment {
        palette.separator.nsColor.setFill()
        NSRect(x: frame.minX - 0.5, y: frame.midY - 6, width: 1, height: 12).fill()
      }
    }
  }

  override func drawSegment(_ segment: Int, inFrame frame: NSRect, with controlView: NSView) {
    let isSelected = segment == selectedSegment
    if isSelected {
      palette.accentFill.nsColor.setFill()
      NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()
    }
    let color = (isSelected ? palette.labelOnAccent : palette.labelPrimary).nsColor
    // The muted bell is secondary beside the name, as the design draws it.
    let bellColor = (isSelected ? palette.labelOnAccent : palette.labelSecondary).nsColor
    let title = NSAttributedString(
      string: label(forSegment: segment) ?? "",
      attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color])
    let titleSize = title.size()
    let bell = image(forSegment: segment)
    let bellWidth = bell.map { $0.size.width + 4 } ?? 0
    let contentWidth = min(titleSize.width + bellWidth, frame.width - 16)
    let start = frame.midX - contentWidth / 2
    let isRightToLeft = controlView.userInterfaceLayoutDirection == .rightToLeft
    var titleX = start
    if let bell {
      // The bell leads the name: on its left, or on its right in right-to-left.
      let bellX = isRightToLeft ? start + contentWidth - bell.size.width : start
      bell.tinted(bellColor).draw(
        in: NSRect(
          x: bellX, y: frame.midY - bell.size.height / 2, width: bell.size.width,
          height: bell.size.height),
        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
      if !isRightToLeft { titleX += bellWidth }
    }
    title.draw(
      with: NSRect(
        x: titleX, y: frame.midY - titleSize.height / 2, width: contentWidth - bellWidth,
        height: titleSize.height),
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
  }
}

extension ThemeColor {
  /// The color for AppKit drawing.
  fileprivate var nsColor: NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: opacity)
  }
}

extension NSImage {
  /// A copy of a template symbol in `color`.
  fileprivate func tinted(_ color: NSColor) -> NSImage {
    NSImage(size: size, flipped: false) { rect in
      self.draw(in: rect)
      color.set()
      rect.fill(using: .sourceAtop)
      return true
    }
  }
}
