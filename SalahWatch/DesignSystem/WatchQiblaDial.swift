import SwiftUI

/// The Qibla compass at watch size: north and the ticks turn with the watch, the mihrab
/// marker sits at the bearing from true north, and the notch at the top is where the watch
/// points. When the marker reaches the notch the ring turns gold and the watch taps the
/// wrist. Without a usable compass reading it draws no direction, like the iPhone's dial: its
/// centre keeps the bearing, or a dash while the compass calibrates. The dial never mirrors.
struct WatchQiblaDial: View {
  let qibla: WatchQiblaPresentation
  /// The heading the dial turns by, unwrapped so a turn across north takes the short way.
  let heading: Double
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast
  private var theme: WatchTheme { WatchTheme(contrast: contrast) }

  /// The design's diameter. A smaller watch scales the whole dial down.
  static let size: CGFloat = 176

  var body: some View {
    ZStack {
      Circle()
        .fill(theme.dial)
        .padding(6)
      if qibla.showsDirection, let bearing = qibla.bearing {
        ticks
        letters
        Image("IOSQiblaMarker", bundle: AppResources.bundle)
          .resizable()
          .foregroundStyle(theme.accent)
          .frame(width: 26, height: 26)
          .rotationEffect(.degrees(heading - bearing))
          .offset(y: -48)
          .rotationEffect(.degrees(bearing - heading))
        Capsule()
          .fill(theme.accent)
          .frame(width: 2, height: 6)
          .offset(y: -31)
          .rotationEffect(.degrees(bearing - heading))
      }
      if qibla.isAligned || qibla.isAtKaaba {
        Circle().strokeBorder(theme.accent, lineWidth: 2).padding(6)
      }
      Image("IOSQiblaDeviceHeading", bundle: AppResources.bundle)
        .resizable()
        .renderingMode(.template)
        .foregroundStyle(qibla.isAligned ? theme.accent : theme.labelPrimary)
        .frame(width: 12, height: 10)
        .offset(y: -85)
      center
    }
    .frame(width: Self.size, height: Self.size)
    .environment(\.layoutDirection, .leftToRight)
    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: heading)
    .sensoryFeedback(.success, trigger: qibla.isAligned) { _, aligned in aligned }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: qibla.accessibility))
    .accessibilityIdentifier("qibla.dial")
  }

  private var ticks: some View {
    Canvas { context, canvas in
      let middle = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
      for tick in 0..<36 {
        let angle = Double(tick) * .pi / 18 - .pi / 2
        let isMajor = tick.isMultiple(of: 3)
        let outer = 83.0
        let inner = outer - (isMajor ? 7 : 4)
        var path = Path()
        path.move(
          to: CGPoint(x: middle.x + inner * cos(angle), y: middle.y + inner * sin(angle)))
        path.addLine(
          to: CGPoint(x: middle.x + outer * cos(angle), y: middle.y + outer * sin(angle)))
        context.stroke(
          path, with: .color(theme.labelSecondary), lineWidth: isMajor ? 1.5 : 1)
      }
    }
    .rotationEffect(.degrees(-heading))
    .accessibilityHidden(true)
  }

  private var letters: some View {
    ForEach(Array(qibla.cardinalLetters.enumerated()), id: \.offset) { index, letter in
      let angle = Double(index) * 90
      Text(verbatim: letter)
        .watchFootnote2()
        .foregroundStyle(index == 0 ? theme.accentText : theme.labelSecondary)
        .rotationEffect(.degrees(heading - angle))
        .offset(y: -63)
        .rotationEffect(.degrees(angle - heading))
    }
    .accessibilityHidden(true)
  }

  private var center: some View {
    VStack(spacing: 2) {
      if qibla.isAtKaaba {
        Image("IOSQiblaMarker", bundle: AppResources.bundle)
          .resizable()
          .foregroundStyle(theme.accent)
          .frame(width: 26, height: 26)
      } else {
        Text(verbatim: qibla.center)
          .font(.title3)
          .foregroundStyle(qibla.isAligned ? theme.accentText : theme.labelPrimary)
      }
      // When the Qibla is behind the watch, the marker passes under the words, which stay
      // readable on a plate of the dial's color.
      Text(verbatim: qibla.instruction)
        .watchFootnote2()
        .foregroundStyle(qibla.isAligned ? theme.accentText : theme.labelSecondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 3)
        .background(theme.dial, in: .rect(cornerRadius: 4))
        .frame(width: 106)
    }
  }
}
