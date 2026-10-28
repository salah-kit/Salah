import SwiftUI

/// The Qibla page: the bearing from the place chosen on the iPhone, and where to turn with
/// the watch's compass. The compass runs only while the page shows on a raised wrist.
struct WatchQiblaView: View {
  @Environment(WatchAppRuntime.self) private var runtime
  @Environment(IOSAppStore.self) private var store
  @Environment(\.scenePhase) private var scenePhase
  @State private var unwrappedHeading = 0.0
  @State private var previousHeading: Double?
  @State private var isShowing = false

  /// How far the dial reaches past the page's top and bottom margins.
  private static let overhang: CGFloat = 14

  private var qibla: WatchQiblaPresentation {
    WatchQiblaPresentation(
      bearing: store.qiblaBearing, distanceKilometers: store.qiblaDistanceKilometers,
      heading: runtime.fixedHeading ?? runtime.heading.heading, locale: store.locale)
  }

  var body: some View {
    let qibla = qibla
    GeometryReader { geometry in
      // On a 46 mm watch the design's dial reaches past the page's margins above and below;
      // a smaller watch scales the whole dial down to reach as far and fit its width.
      let diameter = min(
        WatchQiblaDial.size, geometry.size.width, geometry.size.height + 2 * Self.overhang)
      WatchQiblaDial(qibla: qibla, heading: unwrappedHeading)
        .scaleEffect(diameter / WatchQiblaDial.size)
        .frame(width: diameter, height: diameter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background { WatchSkyBackground(phase: store.display?.phase ?? .neutral) }
    .navigationTitle(Text(verbatim: WatchCopy(locale: store.locale)("Qibla", "القبلة")))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      isShowing = true
      updateCompass()
      follow(qibla.dialHeading)
    }
    .onDisappear {
      isShowing = false
      updateCompass()
    }
    .onChange(of: scenePhase) { updateCompass() }
    .onChange(of: qibla.dialHeading) { _, value in follow(value) }
    // The page's identifier stays its own; its parts keep theirs.
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("screen.qibla")
  }

  /// A Debug journey fixes the reading, and the compass rests while it does.
  private func updateCompass() {
    if isShowing, scenePhase == .active, runtime.fixedHeading == nil {
      runtime.heading.start()
    } else {
      runtime.heading.stop()
    }
  }

  /// Turns the dial the short way across north.
  private func follow(_ heading: Double) {
    guard let previousHeading else {
      unwrappedHeading = heading
      previousHeading = heading
      return
    }
    unwrappedHeading += WatchQiblaPresentation.shortestTurn(from: previousHeading, to: heading)
    self.previousHeading = heading
  }
}
