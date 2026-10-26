import SwiftUI

/// How tvOS draws a focused item, for Salah's own rows: a white platter in both appearances,
/// grown 4 pt on every side and lifted with a soft shadow. Focus is never color alone, and
/// the platter's own light appearance keeps its text dark.
struct TVPlatterButtonStyle: ButtonStyle {
  var cornerRadius: CGFloat = TVMetrics.rowRadius
  /// The fill and rim of the unfocused item, such as the next prayer's gold wash.
  var background: Color = .clear
  var rim: Color? = nil

  func makeBody(configuration: Configuration) -> some View {
    PlatterBody(configuration: configuration, style: self)
  }

  private struct PlatterBody: View {
    let configuration: Configuration
    let style: TVPlatterButtonStyle
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
      configuration.label
        // The focused platter is always light, as tvOS's own are.
        .environment(\.colorScheme, isFocused ? .light : colorSchemeOutside)
        .background {
          ZStack {
            if isFocused {
              shape
                .fill(TVTheme.platter)
                .environment(\.colorScheme, .light)
                .shadow(color: TVTheme.shadowAmbient, radius: 3, y: 2)
                .shadow(color: TVTheme.shadowKey, radius: 24, y: 20)
                .padding(-TVMetrics.focusGrowth)
            } else {
              shape.fill(style.background)
              if let rim = style.rim { shape.strokeBorder(rim, lineWidth: 3) }
            }
          }
        }
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isFocused)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }

    @Environment(\.colorScheme) private var colorSchemeOutside
  }
}
