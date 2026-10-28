import Foundation
import SalahCore
import SalahTimes
import Testing

@Suite("The watch's Qibla dial")
@MainActor
struct WatchQiblaTests {
  init() { WatchTestResources.use() }

  /// London's bearing, from SalahTimes, as the design shows it: 119°.
  private let londonBearing = Qibla.direction(
    from: Coordinates(latitude: 51.5072, longitude: -0.1276))!

  private func qibla(
    _ heading: WatchHeading, bearing: Double? = nil, distance: Double? = 4_794,
    locale: Locale = Locale(identifier: "en")
  ) -> WatchQiblaPresentation {
    WatchQiblaPresentation(
      bearing: bearing ?? londonBearing, distanceKilometers: distance, heading: heading,
      locale: locale)
  }

  @Test func saysWhichWayToTurn() {
    let right = qibla(.ready(trueHeading: 93))
    #expect(right.center == "119°")
    #expect(right.instruction == "Turn 26° right")
    #expect(!right.isAligned)
    #expect(right.accessibility == "Qibla 119°. Turn 26° right")
    #expect(qibla(.ready(trueHeading: 150)).instruction == "Turn 31° left")
  }

  @Test func facesTheQiblaWithinThreeDegrees() {
    let aligned = qibla(.ready(trueHeading: 121))
    #expect(aligned.isAligned)
    #expect(aligned.instruction == "Facing the Qibla")
    #expect(!qibla(.ready(trueHeading: 115)).isAligned)
  }

  @Test func turnsTheShortWayAcrossNorth() {
    #expect(WatchQiblaPresentation.shortestTurn(from: 350, to: 10) == 20)
    #expect(WatchQiblaPresentation.shortestTurn(from: 10, to: 350) == -20)
    #expect(WatchQiblaPresentation.shortestTurn(from: 0, to: 180) == 180)
  }

  /// Without a usable compass the dial still gives the bearing, but no direction: turned to
  /// north it would point the wrong way.
  @Test func keepsTheBearingWithoutACompass() {
    let none = qibla(.unavailable)
    #expect(none.center == "119°")
    #expect(!none.showsDirection)
    #expect(!qibla(.needsLocation).showsDirection)
    #expect(qibla(.ready(trueHeading: 93)).showsDirection)
    #expect(none.instruction == "Compass unavailable")
    #expect(qibla(.needsLocation).instruction == "The compass needs your location")
  }

  @Test func asksForCalibrationWhenTheReadingIsPoor() {
    #expect(WatchHeading.reading(trueHeading: 93, accuracy: 20) == .calibrating)
    #expect(WatchHeading.reading(trueHeading: -1, accuracy: 5) == .calibrating)
    #expect(WatchHeading.reading(trueHeading: 453, accuracy: 5) == .ready(trueHeading: 93))
    let calibrating = qibla(.calibrating)
    #expect(calibrating.center == "—")
    #expect(!calibrating.showsDirection)
    #expect(calibrating.dialHeading == 0)
    #expect(calibrating.instruction == "Move your device in a figure 8")
    // VoiceOver doesn't read the dash.
    #expect(calibrating.accessibility == "Qibla. Move your device in a figure 8")
  }

  @Test func atTheKaabaThereIsNoDirection() {
    let kaaba = WatchQiblaPresentation(
      bearing: nil, distanceKilometers: 0, heading: .ready(trueHeading: 0),
      locale: Locale(identifier: "en"))
    #expect(kaaba.isAtKaaba)
    #expect(kaaba.instruction == "You are at the Kaaba")
    let antipode = WatchQiblaPresentation(
      bearing: nil, distanceKilometers: 20_000, heading: .ready(trueHeading: 0),
      locale: Locale(identifier: "en"))
    #expect(!antipode.isAtKaaba)
    #expect(antipode.instruction == "No single Qibla direction")
  }

  @Test func speaksArabicWithItsOwnLettersAndDigits() {
    let arabic = qibla(.ready(trueHeading: 93), locale: AppLanguage.arabic.locale)
    #expect(arabic.center == "١١٩°")
    #expect(plain(arabic.instruction) == "استدر ٢٦° يمينًا")
    #expect(arabic.cardinalLetters == ["ش", "ق", "ج", "غ"])
  }

  /// The letters are the initials of north, east, south and west in each language.
  @Test(
    arguments: [
      ("fr", ["N", "E", "S", "O"]), ("ur", ["ش", "م", "ج", "مغ"]), ("id", ["U", "T", "S", "B"]),
      ("tr", ["K", "D", "G", "B"]), ("fa", ["ش", "شر", "ج", "غ"]), ("bn", ["উ", "পূ", "দ", "প"]),
      ("ms", ["U", "T", "S", "B"]),
    ])
  func namesTheCardinalPointsInEachLanguage(language: String, letters: [String]) {
    #expect(qibla(.unavailable, locale: Locale(identifier: language)).cardinalLetters == letters)
  }
}
