import SalahCore
import SwiftUI
import UIKit

/// A compass never substitutes magnetic north or a sample heading for a true-north reading.
struct IOSQiblaView: View {
  @Environment(IOSAppStore.self) private var store
  @Environment(IOSLocationService.self) private var location
  @Environment(\.openURL) private var openURL
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.scenePhase) private var scenePhase
  @State private var unwrappedHeading = 0.0
  @State private var previousHeading: Double?

  private var copy: IOSPrayerScreenCopy { IOSPrayerScreenCopy(locale: store.locale) }
  private var hasLocation: Bool { store.preferences.location != nil }
  private var heading: Double? {
    guard case .ready(let heading, _) = location.heading else { return nil }
    return heading
  }
  private var turn: Double? {
    guard let bearing = store.qiblaBearing, let heading else { return nil }
    return IOSQiblaPresentation.shortestTurn(from: heading, to: bearing)
  }
  private var aligned: Bool { turn.map { abs($0) <= 3 } ?? false }
  private var wideLayout: Bool { sizeClass == .regular && !typeSize.isAccessibilitySize }

  var body: some View {
    IOSDisplayGeometryReader { geometry in
      if let pages = geometry.pages {
        foldPages(pages, geometry: geometry)
      } else {
        ScrollView {
          if wideLayout {
            let factsWidth = min(420, geometry.size.width * 0.38)
            let dialSize = min(480, max(300, geometry.size.width - factsWidth - 136))
            HStack(alignment: .center, spacing: 40) {
              dial(diameter: dialSize)
                .frame(maxWidth: .infinity)
              factsColumn
                .frame(width: factsWidth)
            }
            .padding(.horizontal, 48)
            .padding(.top, 24)
            .padding(.bottom, 32)
          } else {
            VStack(alignment: .leading, spacing: 16) {
              dial(diameter: 300)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 8)
              locationDetails
            }
            .frame(maxWidth: 620)
            .padding(.leading, geometry.insets.leading)
            .padding(.trailing, geometry.insets.trailing)
            .padding(.top, max(8, geometry.topMargin))
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
          }
        }
      }
    }
    .background { IOSSkyBackground(phase: store.display?.phase ?? .neutral) }
    .background { IOSHeadingReferenceView(location: location).allowsHitTesting(false) }
    .navigationTitle(copy("Qibla", "القبلة"))
    .navigationBarTitleDisplayMode(.large)
    .toolbar(wideLayout ? .hidden : .visible, for: .navigationBar)
    .onAppear {
      location.startHeading()
      updateHeading(heading)
    }
    .onDisappear { location.stopHeading() }
    .onChange(of: heading) { _, value in updateHeading(value) }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { location.startHeading() } else { location.stopHeading() }
    }
    .accessibilityIdentifier("qibla.screen")
  }

  /// On iPhone Duo's inner display the dial keeps one page and its facts the other, clear of the
  /// fold, flat or folded. The pages' container takes the screen's identifier, so the dial keeps
  /// its own.
  private func foldPages(_ pages: IOSFoldPages, geometry: IOSDisplayGeometry) -> some View {
    foldPageStack(pages, geometry: geometry)
      .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private func foldPageStack(_ pages: IOSFoldPages, geometry: IOSDisplayGeometry) -> some View {
    let gap = pages.second.lowerBound - pages.first.upperBound
    switch pages.axis {
    case .vertical:
      HStack(spacing: 0) {
        dial(
          diameter: min(
            440, pages.first.length - 32, geometry.size.height - geometry.topMargin - 48)
        )
        .frame(width: pages.first.length, height: geometry.size.height)
        Spacer(minLength: 0).frame(width: gap)
        ScrollView {
          factsColumn
            .padding(.top, max(24, geometry.topMargin))
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .frame(width: pages.second.length)
      }
      .padding(.leading, pages.first.lowerBound)
      .frame(width: geometry.size.width, alignment: .leading)
    case .horizontal:
      VStack(spacing: 0) {
        dial(diameter: min(440, pages.first.length - 48, geometry.contentWidth))
          .frame(width: geometry.size.width, height: pages.first.length)
        Spacer(minLength: 0).frame(height: gap)
        ScrollView {
          factsColumn
            .frame(width: geometry.contentWidth, alignment: .leading)
            .padding(.leading, geometry.insets.leading)
            .padding(.trailing, geometry.insets.trailing)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .frame(height: pages.second.length)
      }
      .padding(.top, pages.first.lowerBound)
      .frame(height: geometry.size.height, alignment: .top)
    }
  }

  /// Wide layouts hide the navigation bar and title the facts themselves.
  private var factsColumn: some View {
    VStack(alignment: .leading, spacing: 16) {
      if wideLayout {
        Text(verbatim: copy("Qibla", "القبلة"))
          .font(.largeTitle.bold())
          .accessibilityAddTraits(.isHeader)
      }
      locationDetails
    }
  }

  private func dial(diameter: CGFloat) -> some View {
    IOSQiblaDial(
      bearing: store.qiblaBearing, heading: unwrappedHeading,
      showsDirection: heading != nil && store.qiblaBearing != nil,
      aligned: aligned, center: centerTitle, instruction: instruction,
      locale: store.locale
    )
    .scaleEffect(diameter / 300)
    .frame(width: diameter, height: diameter)
    .accessibilityIdentifier(hasLocation ? "qibla.heading" : "qibla.placeholder")
    .sensoryFeedback(.success, trigger: aligned) { _, now in now }
  }

  @ViewBuilder
  private var locationDetails: some View {
    if hasLocation {
      facts
      Button {
        showLocation()
      } label: {
        Label(
          store.preferences.location?.name ?? copy("Your location", "موقعك"),
          systemImage: "location.fill"
        )
        .font(.subheadline.weight(.semibold))
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.capsule)
      .controlSize(.small)
      .tint(.primary)
      .accessibilityIdentifier("qibla.location")
      guidance
    } else {
      recovery
    }
  }

  private var centerTitle: String {
    guard hasLocation, heading != nil, let bearing = store.qiblaBearing else { return "—" }
    return number(bearing.rounded()) + "°"
  }

  private var instruction: String {
    guard hasLocation else { return copy("Qibla needs your location", "تحتاج القبلة إلى موقعك") }
    guard store.qiblaBearing != nil else {
      if let distance = store.qiblaDistanceKilometers, distance < 0.001 {
        return copy("You are at the Kaaba", "أنت عند الكعبة")
      }
      return copy("No single Qibla direction", "لا يوجد اتجاه واحد للقبلة")
    }
    switch location.heading {
    case .calibrating:
      return copy("Move your device in a figure 8", "حرّك الجهاز على شكل ٨")
    case .unavailable:
      return copy("Compass unavailable", "البوصلة غير متاحة")
    case .ready:
      guard let turn else { return copy("Compass unavailable", "البوصلة غير متاحة") }
      if aligned { return copy("Facing the Qibla", "أنت باتجاه القبلة") }
      let degrees = number(abs(turn).rounded()) + "°"
      return turn >= 0
        ? String(format: copy("Turn %@ right", "استدر %@ يمينًا"), degrees)
        : String(format: copy("Turn %@ left", "استدر %@ يسارًا"), degrees)
    }
  }

  private var facts: some View {
    let layout =
      typeSize.isAccessibilitySize || wideLayout
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    return layout {
      fact(
        copy("Qibla", "القبلة"),
        value: store.qiblaBearing.map { number($0, fractionDigits: 2) + "°" } ?? "—",
        detail: copy("from true north", "من الشمال الحقيقي"))
      fact(
        copy("To the Kaaba", "إلى الكعبة"),
        value: store.qiblaDistanceKilometers.map {
          number($0.rounded(), grouping: true) + " " + copy("km", "كم")
        } ?? "—",
        detail: copy("great-circle distance", "المسافة على الدائرة العظمى"))
    }
    .accessibilityIdentifier("qibla.facts")
  }

  private func fact(_ title: String, value: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: title).font(.footnote).foregroundStyle(IOSTheme.labelSecondary)
      Text(verbatim: value).font(wideLayout ? .title.bold() : .title2.bold()).foregroundStyle(
        IOSTheme.labelPrimary)
      Text(verbatim: detail).font(.caption).foregroundStyle(IOSTheme.labelSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(
      IOSTheme.groupedSecondary, in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var guidance: some View {
    switch location.heading {
    case .ready:
      Text(
        verbatim: copy(
          "Hold your device flat, away from metal and magnets. The Qibla is measured from true north.",
          "أمسك الجهاز بشكل مسطّح وبعيدًا عن المعادن والمغناطيس. يُقاس اتجاه القبلة من الشمال الحقيقي."
        )
      )
      .font(.footnote)
      .foregroundStyle(IOSTheme.labelSecondary)
      .padding(.horizontal, 4)
    case .calibrating:
      Text(
        verbatim: copy(
          "Move your device in a figure 8, away from metal and magnets, to improve compass accuracy.",
          "حرّك الجهاز على شكل ٨ بعيدًا عن المعادن والمغناطيس لتحسين دقة البوصلة.")
      )
      .font(.footnote)
      .foregroundStyle(IOSTheme.labelSecondary)
      .padding(.horizontal, 4)
      .accessibilityIdentifier("qibla.calibrating")
    case .unavailable:
      VStack(alignment: .leading, spacing: 12) {
        Text(
          verbatim: copy(
            "Your location’s Qibla bearing is shown above. A true-north compass reading is not available on this device.",
            "يظهر اتجاه القبلة لموقعك أعلاه. لا تتوفر قراءة بوصلة من الشمال الحقيقي على هذا الجهاز."
          )
        )
        .font(.footnote)
        .foregroundStyle(IOSTheme.labelSecondary)
        .accessibilityIdentifier("qibla.unavailable")
        if location.authorizationStatus == .notDetermined {
          Button(copy("Allow Location Access", "السماح بالوصول إلى الموقع")) {
            requestLocation()
          }
          .buttonStyle(.glass)
          .accessibilityIdentifier("qibla.allowLocation")
        } else if location.authorizationStatus == .denied
          || location.authorizationStatus == .restricted
        {
          openSettingsButton
        }
      }
    }
  }

  private var recovery: some View {
    VStack(spacing: 8) {
      Text(
        verbatim: copy(
          "Allow location access, or choose a city for its Qibla bearing.",
          "اسمح بالوصول إلى الموقع، أو اختر مدينة لمعرفة اتجاه القبلة فيها.")
      )
      .font(.footnote)
      .foregroundStyle(IOSTheme.labelSecondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      if location.authorizationStatus == .notDetermined {
        Button {
          requestLocation()
        } label: {
          Text(verbatim: copy("Allow Location Access", "السماح بالوصول إلى الموقع"))
            .foregroundStyle(IOSTheme.labelOnAccent)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(IOSTheme.accentFill)
        .accessibilityIdentifier("qibla.allowLocation")
      } else {
        openSettingsButton
      }
      Button(copy("Choose a City", "اختيار مدينة")) { showLocation() }
        .frame(maxWidth: .infinity)
        .controlSize(.large)
        .accessibilityIdentifier("qibla.chooseCity")
    }
  }

  private var openSettingsButton: some View {
    Button {
      openURL(URL(string: UIApplication.openSettingsURLString)!)
    } label: {
      Text(verbatim: copy("Open Settings", "فتح الإعدادات"))
        .foregroundStyle(IOSTheme.labelOnAccent)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.glassProminent)
    .controlSize(.large)
    .tint(IOSTheme.accentFill)
    .accessibilityIdentifier("qibla.openSettings")
  }

  private func number(_ value: Double, fractionDigits: Int = 0, grouping: Bool = false) -> String {
    let formatter = NumberFormatter()
    formatter.locale = store.locale
    formatter.minimumFractionDigits = fractionDigits
    formatter.maximumFractionDigits = fractionDigits
    formatter.usesGroupingSeparator = grouping
    return formatter.string(from: NSNumber(value: value)) ?? "—"
  }

  private func updateHeading(_ value: Double?) {
    guard let value else {
      previousHeading = nil
      return
    }
    if let previousHeading {
      unwrappedHeading += IOSQiblaPresentation.shortestTurn(from: previousHeading, to: value)
    } else {
      unwrappedHeading = value
    }
    previousHeading = value
  }

  private func showLocation() { store.handle(url: URL(string: "salah://location")!) }

  private func requestLocation() {
    if !hasLocation { store.updatePreferences { $0.useCurrentLocation = true } }
    location.requestLocation()
  }
}

nonisolated enum IOSQiblaPresentation {
  /// Keeps both turn instructions and the animated north crossing on the shortest arc.
  static func shortestTurn(from heading: Double, to bearing: Double) -> Double {
    guard heading.isFinite, bearing.isFinite else { return 0 }
    let difference = (bearing - heading).truncatingRemainder(dividingBy: 360)
    if difference > 180 { return difference - 360 }
    if difference < -180 { return difference + 360 }
    return difference
  }
}

private struct IOSQiblaDial: View {
  let bearing: Double?
  let heading: Double
  let showsDirection: Bool
  let aligned: Bool
  let center: String
  let instruction: String
  let locale: Locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var cardinalPoints: [(String, Double)] {
    let copy = IOSPrayerScreenCopy(locale: locale)
    return [
      (copy("N", "ش"), 0), (copy("E", "ق"), 90), (copy("S", "ج"), 180), (copy("W", "غ"), 270),
    ]
  }

  var body: some View {
    ZStack {
      Circle()
        .fill(IOSTheme.groupedSecondary)
        .padding(6)
      if showsDirection {
        Canvas { context, size in
          let middle = CGPoint(x: size.width / 2, y: size.height / 2)
          for tick in 0..<36 {
            let angle = Double(tick) * .pi / 18 - .pi / 2
            let isMajor = tick.isMultiple(of: 3)
            let outer = 142.0
            let inner = outer - (isMajor ? 12 : 6)
            var path = Path()
            path.move(
              to: CGPoint(x: middle.x + inner * cos(angle), y: middle.y + inner * sin(angle)))
            path.addLine(
              to: CGPoint(x: middle.x + outer * cos(angle), y: middle.y + outer * sin(angle)))
            context.stroke(path, with: .color(IOSTheme.labelSecondary), lineWidth: isMajor ? 2 : 1)
          }
        }
        .rotationEffect(.degrees(-heading))
        ForEach(Array(cardinalPoints.enumerated()), id: \.offset) { index, point in
          Text(verbatim: point.0)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(index == 0 ? IOSTheme.accentText : IOSTheme.labelSecondary)
            .rotationEffect(.degrees(heading - point.1))
            .offset(y: -120)
            .rotationEffect(.degrees(point.1 - heading))
        }
        if let bearing {
          Image("IOSQiblaMarker")
            .resizable()
            .foregroundStyle(IOSTheme.accent)
            .frame(width: 40, height: 40)
            .rotationEffect(.degrees(heading - bearing))
            .offset(y: -96)
            .rotationEffect(.degrees(bearing - heading))
          Rectangle()
            .fill(IOSTheme.accent)
            .frame(width: 2, height: 24)
            .offset(y: -66)
            .rotationEffect(.degrees(bearing - heading))
        }
      }
      if aligned {
        Circle().strokeBorder(IOSTheme.accent, lineWidth: 3).padding(6)
      }
      Image("IOSQiblaDeviceHeading")
        .resizable()
        .renderingMode(.template)
        .foregroundStyle(aligned ? IOSTheme.accent : IOSTheme.labelPrimary)
        .frame(width: 19.7912, height: 16.0528)
        .offset(y: -144.7)
      VStack(spacing: 2) {
        Text(verbatim: center)
          .font(.system(size: 28, weight: .semibold, design: .rounded))
          .foregroundStyle(aligned ? IOSTheme.accentText : IOSTheme.labelPrimary)
        Text(verbatim: instruction)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(aligned ? IOSTheme.accentText : IOSTheme.labelSecondary)
          .multilineTextAlignment(.center)
          .frame(width: 150)
      }
      .padding(.top, 2)
    }
    .frame(width: 300, height: 300)
    .environment(\.layoutDirection, .leftToRight)
    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: heading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      IOSPrayerScreenCopy(locale: locale)("Qibla", "القبلة") + " " + center + ". " + instruction)
  }
}

/// Core Location measures heading from the top of the interface showing the dial: on iOS 27 from
/// the real view, and before that from its window scene's interface orientation, which a device
/// lying flat or held in an unsupported orientation doesn't change.
private struct IOSHeadingReferenceView: UIViewRepresentable {
  let location: IOSLocationService

  func makeCoordinator() -> Coordinator { Coordinator(location: location) }

  func makeUIView(context: Context) -> ReferenceView {
    let view = ReferenceView()
    view.isUserInteractionEnabled = false
    view.location = location
    location.setHeadingReferenceView(view)
    return view
  }

  func updateUIView(_ view: ReferenceView, context: Context) {
    view.location = location
    location.setHeadingReferenceView(view)
  }

  static func dismantleUIView(_ view: ReferenceView, coordinator: Coordinator) {
    view.location = nil
    coordinator.location.setHeadingReferenceView(nil)
  }

  final class Coordinator {
    let location: IOSLocationService
    init(location: IOSLocationService) { self.location = location }
  }

  /// Follows its scene's interface orientation from the moment it's shown, including rotations
  /// made while Qibla was hidden.
  final class ReferenceView: UIView {
    weak var location: IOSLocationService?
    private var geometryObservation: NSKeyValueObservation?

    override func didMoveToWindow() {
      super.didMoveToWindow()
      geometryObservation = window?.windowScene?.observe(\.effectiveGeometry, options: .initial) {
        [weak self] scene, _ in
        Task { @MainActor in
          self?.location?.setHeadingOrientation(scene.effectiveGeometry.interfaceOrientation)
        }
      }
    }
  }
}
