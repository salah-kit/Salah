import SalahCore
import SalahUI
import SwiftUI

/// The Notifications pane's prayer picker: a segmented control across the form's width,
/// the selected segment in the gold fill, and a muted bell on each prayer with every alert
/// off. macOS draws its own segmented picker without the bells, so this one is drawn here
/// and reads to accessibility as radio buttons in a group named "Prayer".
struct PrayerPicker: View {
  @Binding var selection: NotificationTarget
  /// Each segment's target, name and whether it's muted, in order.
  let segments: [(target: NotificationTarget, name: String, isMuted: Bool)]

  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    let palette = SalahPalette(isDark: scheme == .dark, increasedContrast: contrast == .increased)
    HStack(spacing: 0) {
      ForEach(Array(segments.enumerated()), id: \.element.target) { index, segment in
        if index > 0 {
          // No hairline beside the selected segment, as macOS draws its segments.
          let touchesSelection =
            segment.target == selection || segments[index - 1].target == selection
          Rectangle()
            .fill(palette.separator.color)
            .frame(width: 1, height: 12)
            .opacity(touchesSelection ? 0 : 1)
        }
        segmentButton(segment, palette: palette)
      }
    }
    .padding(2)
    .frame(height: 24)
    // The arrow keys move the selection, as in macOS's own segmented control.
    .focusable()
    .onMoveCommand { direction in
      let forward: Bool
      switch direction {
      case .right: forward = layoutDirection == .leftToRight
      case .left: forward = layoutDirection == .rightToLeft
      default: return
      }
      guard let index = segments.firstIndex(where: { $0.target == selection }) else { return }
      let next = index + (forward ? 1 : -1)
      if segments.indices.contains(next) { selection = segments[next].target }
    }
    .background(
      palette.fillTertiary.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
    .accessibilityRepresentation {
      Picker("settings.notif.prayer", selection: $selection) {
        ForEach(segments, id: \.target) { segment in
          Text(verbatim: segment.name).tag(segment.target)
        }
      }
      // A radio group, as macOS reads its own segmented picker, laid out as the segments.
      .pickerStyle(.radioGroup)
      .horizontalRadioGroupLayout()
      .labelsHidden()
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .contain)
    }
  }

  private func segmentButton(
    _ segment: (target: NotificationTarget, name: String, isMuted: Bool),
    palette: SalahPalette
  ) -> some View {
    let isSelected = segment.target == selection
    return Button {
      selection = segment.target
    } label: {
      HStack(spacing: 4) {
        if segment.isMuted {
          Image(systemName: "bell.slash")
            .font(.system(size: 10))
        }
        Text(verbatim: segment.name)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      .font(.body)
      .foregroundStyle((isSelected ? palette.labelOnAccent : palette.labelPrimary).color)
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background {
        if isSelected {
          RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.accentFill.color)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusable(false)
  }
}
