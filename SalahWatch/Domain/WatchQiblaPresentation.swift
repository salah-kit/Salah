import Foundation
import SalahCore

/// The watch compass's reading: unavailable, calibrating, or a true-north heading.
nonisolated enum WatchHeading: Equatable, Sendable {
  /// No compass, or no heading yet.
  case unavailable
  /// The watch can't use location, so Core Location can't correct to true north.
  case needsLocation
  /// The reading isn't accurate enough to point at the Qibla.
  case calibrating
  case ready(trueHeading: Double)

  /// A heading Core Location reported: usable only within 15° of true north.
  static func reading(trueHeading: Double, accuracy: Double) -> Self {
    guard trueHeading.isFinite, accuracy.isFinite, trueHeading >= 0, accuracy >= 0,
      accuracy <= 15
    else { return .calibrating }
    return .ready(trueHeading: trueHeading.truncatingRemainder(dividingBy: 360))
  }
}

/// What the Qibla dial shows: the bearing from the place the iPhone chose, and where to turn
/// with the watch's compass. A compass never substitutes magnetic north or a sample heading.
nonisolated struct WatchQiblaPresentation: Equatable, Sendable {
  /// Degrees from true north to the Kaaba; `nil` at the Kaaba or its antipode.
  var bearing: Double?
  /// The distance to the Kaaba, which tells the two apart.
  var distanceKilometers: Double?
  var heading: WatchHeading
  var locale: Locale

  /// Within this many degrees of the bearing, the watch faces the Qibla.
  static let alignment = 3.0

  private var copy: WatchCopy { WatchCopy(locale: locale) }

  var isAtKaaba: Bool { bearing == nil && (distanceKilometers ?? .infinity) < 0.001 }

  /// The degrees to turn, right positive, on the shortest arc; `nil` without a heading.
  var turn: Double? {
    guard let bearing, case .ready(let heading) = heading else { return nil }
    return Self.shortestTurn(from: heading, to: bearing)
  }

  var isAligned: Bool { turn.map { abs($0) <= Self.alignment } ?? false }

  /// The heading the dial turns by: the compass's, or north up when the watch has none.
  var dialHeading: Double {
    if case .ready(let heading) = heading { return heading }
    return 0
  }

  /// Whether the dial draws its ticks, letters and marker: always but while calibrating,
  /// when the marker would point nowhere.
  var showsDial: Bool { heading != .calibrating && bearing != nil }

  /// The bearing in the dial's centre: "119°", or "—" while calibrating or without one.
  var center: String {
    guard let bearing, heading != .calibrating else { return "—" }
    return Self.degrees(bearing, locale: locale)
  }

  var instruction: String {
    guard bearing != nil else {
      return isAtKaaba
        ? copy("You are at the Kaaba", "أنت عند الكعبة")
        : copy("No single Qibla direction", "لا يوجد اتجاه واحد للقبلة")
    }
    switch heading {
    case .unavailable:
      return copy("Compass unavailable", "البوصلة غير متاحة")
    case .needsLocation:
      return copy("The compass needs your location", "تحتاج البوصلة إلى موقعك")
    case .calibrating:
      return copy("Move your device in a figure 8", "حرّك الجهاز على شكل ٨")
    case .ready:
      guard let turn else { return copy("Compass unavailable", "البوصلة غير متاحة") }
      if isAligned { return copy("Facing the Qibla", "أنت باتجاه القبلة") }
      let degrees = Self.degrees(abs(turn), locale: locale)
      return turn >= 0
        ? copy.format("Turn %@ right", "استدر %@ يمينًا", degrees)
        : copy.format("Turn %@ left", "استدر %@ يسارًا", degrees)
    }
  }

  /// The dial for VoiceOver: "Qibla 119°. Turn 26° right." Without a bearing the dial shows a
  /// dash, which VoiceOver would read as a word.
  var accessibility: String {
    let title = copy("Qibla", "القبلة")
    return [center == "—" ? title : title + " " + center, instruction].joined(separator: ". ")
  }

  /// The cardinal letters, north first: N E S W, or ش ق ج غ in Arabic.
  var cardinalLetters: [String] {
    [copy("N", "ش"), copy("E", "ق"), copy("S", "ج"), copy("W", "غ")]
  }

  /// Keeps the turn instruction and the dial's animation across north on the shortest arc.
  static func shortestTurn(from heading: Double, to bearing: Double) -> Double {
    guard heading.isFinite, bearing.isFinite else { return 0 }
    let difference = (bearing - heading).truncatingRemainder(dividingBy: 360)
    if difference > 180 { return difference - 360 }
    if difference < -180 { return difference + 360 }
    return difference
  }

  /// Whole degrees in the language's digits: "119°", "١١٩°".
  static func degrees(_ value: Double, locale: Locale) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.maximumFractionDigits = 0
    formatter.usesGroupingSeparator = false
    return (formatter.string(from: NSNumber(value: value.rounded())) ?? "—") + "°"
  }
}
