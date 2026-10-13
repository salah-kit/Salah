import Adhan
import AppKit
import Foundation
import SwiftUI
import Testing

// MARK: - Pipeline: catalog entry → snapshot → view

/// Builds the view each baseline renders. The catalog says what to show; this is the
/// part that changes when the app moves onto SalahKit (D1 swaps it and keeps the
/// catalog, the moments and the PNGs).
enum BaselinePipeline {
  /// The preview scenarios' clock: 16:00 on the fixture day. They place prayers at
  /// minute offsets from it, as the Xcode previews do from the real clock.
  static let previewNow = Fixture.date(16, 0)

  static func appLanguage(_ language: Baseline.Language) -> AppLanguage {
    switch language {
    case .en: .english
    case .ar: .arabic
    case .fr: .french
    }
  }

  static func previewLanguage(_ language: Baseline.Language) -> PreviewLang {
    switch language {
    case .en: .en
    case .ar: .ar
    case .fr: .fr
    }
  }

  static func colorScheme(_ appearance: Baseline.Appearance) -> ColorScheme {
    appearance == .dark ? .dark : .light
  }

  static func size(_ family: Baseline.Family) -> GuidanceWidgetSize {
    switch family {
    case .small: .small
    case .medium: .medium
    case .large: .large
    }
  }

  static func theme(_ preset: ThemePreset) -> GuidanceWidgetTheme {
    switch preset {
    case .nocturne: .nocturne
    case .dawn: .dawn
    case .oasis: .oasis
    case .ink: .ink
    case .highContrast: .highContrast
    }
  }

  /// The moment a spec state is shown at, on the fixture day.
  static func moment(for state: SpecState) -> Date {
    let times = Fixture.prayerTimes(ishaAdjustment: state.ishaAdjustment)
    switch state {
    case .idle, .silent, .setupNeeded: return times.dhuhr.adding(minutes: 60)
    case .imminent: return times.asr.adding(minutes: -10)
    case .countUp, .countUpSilent: return times.dhuhr.adding(minutes: 4)
    case .countUpImminent: return times.maghrib.adding(minutes: 4)
    case .endOfDay: return times.isha.adding(minutes: 60)
    case .playingAdhan: return times.maghrib.adding(minutes: 2)
    case .playingPreReminder: return times.maghrib.adding(minutes: -10)
    case .playingPostReminder: return times.maghrib.adding(minutes: 5)
    case .stale: return Fixture.date(0, 10, dayOffset: 1)
    }
  }

  /// When the app built the snapshot; the stale face shows the idle moment's
  /// snapshot after midnight.
  static func buildMoment(for state: SpecState) -> Date {
    state == .stale ? moment(for: .idle) : moment(for: state)
  }

  static func audio(for state: SpecState) -> AudioPlaybackState {
    let maghrib = Fixture.prayerTimes().maghrib
    func playing(_ slot: PrayerNotificationSoundSlot, _ offset: Int?) -> AudioPlaybackState {
      .playing(
        AudioPlaybackContext(
          prayer: .maghrib, source: .prayerAlert, slot: slot, prayerTime: maghrib,
          prayerAlertOffsetMinutes: offset))
    }
    switch state {
    case .playingAdhan: return playing(.alert, nil)
    case .playingPreReminder: return playing(.preReminder, 10)
    case .playingPostReminder: return playing(.postReminder, 5)
    default: return .idle
    }
  }

  /// The fixture's settings: the app's defaults, plus Fajr's 30-minute before-reminder
  /// and Maghrib's 10-minute before and 5-minute after reminders, so reminder text
  /// shows.
  static func configure(
    _ preferences: Preferences, for state: SpecState, language: Baseline.Language
  ) {
    preferences.appLanguage = appLanguage(language)
    var fajr = preferences.config(for: .fajr)
    fajr.preReminderEnabled = true
    fajr.preReminderOffset = 30
    preferences.setConfig(fajr, for: .fajr)
    var maghrib = preferences.config(for: .maghrib)
    maghrib.preReminderEnabled = true
    maghrib.preReminderOffset = 10
    maghrib.postReminderEnabled = true
    maghrib.postReminderOffset = 5
    preferences.setConfig(maghrib, for: .maghrib)
    preferences.ishaAdjustment = state.ishaAdjustment
    preferences.silentMode = state.silentMode
  }

  /// The snapshot the app publishes for a spec state: its real builder over the
  /// fixture's preferences and Adhan's times, as `PrayerManager` wires it.
  static func snapshot(for state: SpecState, language: Baseline.Language) -> GuidanceWidgetSnapshot
  {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    configure(preferences, for: state, language: language)
    let now = buildMoment(for: state)
    let today = Fixture.prayerTimes(ishaAdjustment: state.ishaAdjustment)
    let tomorrow = Fixture.prayerTimes(dayOffset: 1, ishaAdjustment: state.ishaAdjustment)
    return AppLanguageScope.with(preferences.appLanguage) {
      GuidanceWidgetSnapshotBuilder(
        preferences: preferences, prayerTimes: today, tomorrowPrayerTimes: tomorrow,
        currentPrayer: today.currentPrayer(at: now), nextPrayer: today.nextPrayer(at: now),
        audioState: audio(for: state), now: now
      ).build()!
    }
  }

  static func previewSnapshot(_ scenario: PreviewScenario, _ language: Baseline.Language)
    -> GuidanceWidgetSnapshot
  {
    let lang = previewLanguage(language)
    switch scenario {
    case .idle: return WidgetPreviewData.idle(lang, now: previewNow)
    case .imminent: return WidgetPreviewData.imminent(lang, now: previewNow)
    case .countUp: return WidgetPreviewData.countUp(lang, now: previewNow)
    case .countUpEnded: return WidgetPreviewData.countUpEnded(lang, now: previewNow)
    case .since: return WidgetPreviewData.since(lang, now: previewNow)
    case .tomorrow: return WidgetPreviewData.tomorrow(lang, now: previewNow)
    case .silent: return WidgetPreviewData.silent(lang, now: previewNow)
    case .playing: return WidgetPreviewData.playing(lang, now: previewNow)
    }
  }

  static func view(for baseline: Baseline) throws -> AnyView {
    let content: AnyView
    switch baseline.surface {
    case .widget:
      let state = SpecState(rawValue: baseline.state)!
      let size = size(baseline.family!)
      let now = moment(for: state)
      switch state {
      case .setupNeeded:
        // No snapshot was ever published: the provider's setup entry. The extension
        // resolves the message under the sample snapshot's locale, English, so the
        // face doesn't follow the app's language.
        let sample = GuidanceWidgetSnapshot.sample(now: now)
        let message = try ExtensionCatalog.string(
          "widget.openToSetUp", localeIdentifier: sample.localeIdentifier)
        content = AnyView(
          WidgetShellMessage(
            snapshot: sample, size: size, date: now, systemImage: "moon.stars", message: message))
      case .stale:
        let snapshot = snapshot(for: state, language: baseline.language)
        content = AnyView(
          WidgetShellMessage(
            snapshot: snapshot, size: size, date: now, systemImage: "arrow.clockwise",
            message: snapshot.labels.openToUpdate))
      default:
        content = AnyView(
          WidgetPreviewContainer(
            snapshot: snapshot(for: state, language: baseline.language), size: size, date: now))
      }
    case .menu:
      let state = SpecState(rawValue: baseline.state)!
      content = AnyView(
        MenuDropdownContent(
          snapshot: snapshot(for: state, language: baseline.language), now: moment(for: state)))
    case .preview:
      let scenario = PreviewScenario(rawValue: baseline.state)!
      content = AnyView(
        WidgetPreviewContainer(
          snapshot: previewSnapshot(scenario, baseline.language), size: size(baseline.family!),
          date: previewNow))
    case .theme:
      var snapshot = WidgetPreviewData.idle(previewLanguage(baseline.language), now: previewNow)
      snapshot.theme = theme(ThemePreset(rawValue: baseline.state)!)
      content = AnyView(WidgetPreviewContainer(snapshot: snapshot, size: .medium, date: previewNow))
    }
    return AnyView(content.environment(\.colorScheme, colorScheme(baseline.appearance)))
  }
}

/// The extension shell's setup and stale faces (`GuidancePrayerWidgetEntryView`'s
/// first two branches) in the frame, backdrop and clip `WidgetPreviewContainer`
/// gives the data faces. WidgetKit's own container only renders in a widget host.
struct WidgetShellMessage: View {
  let snapshot: GuidanceWidgetSnapshot
  let size: GuidanceWidgetSize
  let date: Date
  let systemImage: String
  let message: String

  @Environment(\.colorScheme) private var scheme

  /// `WidgetPreviewContainer`'s macOS desktop widget point sizes.
  static func pointSize(_ size: GuidanceWidgetSize) -> CGSize {
    switch size {
    case .small: CGSize(width: 158, height: 158)
    case .medium: CGSize(width: 338, height: 158)
    case .large: CGSize(width: 338, height: 354)
    }
  }

  var body: some View {
    let colors = snapshot.resolvedTheme.colors(for: scheme)
    let point = Self.pointSize(size)
    WidgetMessageContent(
      systemImage: systemImage, message: Text(verbatim: message), accent: colors.accent
    )
    .frame(width: point.width, height: point.height)
    .background {
      GuidanceWidgetBackground(tone: snapshot.backgroundTone(at: date), colors: colors)
    }
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .environment(\.locale, snapshot.resolvedLocale)
    .environment(\.layoutDirection, snapshot.layoutDirectionIsRTL ? .rightToLeft : .leftToRight)
    .guidanceColorScheme(snapshot.resolvedTheme.forcedColorScheme)
  }
}

/// Reads the widget extension's String Catalog from the source tree. The extension
/// resolves `widget.openToSetUp` from its own bundle, which the test bundle doesn't
/// contain, in the language of the locale its view has in the environment.
enum ExtensionCatalog {
  struct MissingString: Error, CustomStringConvertible {
    var key: String
    var description: String { "widget catalog has no value for \(key)" }
  }

  static func string(_ key: String, localeIdentifier: String) throws -> String {
    let url = BaselineStore.repositoryRoot.appending(
      path: "GuidanceWidgetsExtension/Localizable.xcstrings")
    let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let strings = catalog?["strings"] as? [String: Any]
    let localizations = (strings?[key] as? [String: Any])?["localizations"] as? [String: Any]
    let language = Locale(identifier: localeIdentifier).language.languageCode?.identifier ?? "en"
    let localization = (localizations?[language] ?? localizations?["en"]) as? [String: Any]
    guard let value = (localization?["stringUnit"] as? [String: Any])?["value"] as? String else {
      throw MissingString(key: key)
    }
    return value
  }
}

// MARK: - Rendering and comparison

enum BaselineRenderer {
  /// One pixel per point keeps the 450 images near 30 MB; scale 2 quadruples that,
  /// and every re-render adds the changed images to the history again.
  nonisolated static let scale = 1

  struct RenderFailed: Error {}
  struct Unstable: Error, CustomStringConvertible {
    var description: String { "four renders in a row never matched" }
  }

  /// ImageRenderer at a fixed scale, encoded as PNG.
  static func png(_ view: some View) throws -> Data {
    let renderer = ImageRenderer(content: view)
    renderer.scale = CGFloat(scale)
    guard let image = renderer.cgImage else { throw RenderFailed() }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw RenderFailed() }
    return data
  }

  /// Renders until two renders in a row are identical and returns that image. The
  /// first render of a face in a process can differ slightly while glyphs and
  /// symbols are first rasterized; every later render matches.
  static func stablePNG(_ view: () throws -> some View) throws -> Data {
    var previous = try png(view())
    for _ in 1..<4 {
      let next = try png(view())
      if next == previous { return next }
      previous = next
    }
    throw Unstable()
  }
}

enum PixelComparison {
  struct Result: CustomStringConvertible {
    var size: (width: Int, height: Int)
    var recordedSize: (width: Int, height: Int)
    var differingPixels: Int
    var maxChannelDelta: Int

    var matches: Bool {
      size == recordedSize && differingPixels <= allowedOutliers && maxChannelDelta <= jitterCeiling
    }

    var description: String {
      if size != recordedSize {
        return
          "size \(size.width)×\(size.height) px, recorded \(recordedSize.width)×\(recordedSize.height) px"
      }
      return
        "\(differingPixels) pixels differ by more than \(noiseFloor)/255 (\(allowedOutliers) allowed), the largest by \(maxChannelDelta)/255 (\(jitterCeiling) allowed)"
    }
  }

  /// A channel difference this small is treated as equal: rounding noise, not a change.
  static let noiseFloor = 2
  /// Pixels that may differ by more than the noise floor. A face rendered in another
  /// process can move a pixel or two of antialiasing by a few levels; a changed digit,
  /// glyph, icon or color moves dozens to hundreds.
  static let allowedOutliers = 16
  /// The most any pixel may differ by. Antialiasing jitter stays far below it, while
  /// a mark that appears or disappears, even a diacritic covering only a few pixels,
  /// moves its pixels by far more.
  static let jitterCeiling = 32

  static func rgba(_ png: Data) -> (width: Int, height: Int, bytes: [UInt8])? {
    guard let image = NSBitmapImageRep(data: png)?.cgImage,
      let space = CGColorSpace(name: CGColorSpace.sRGB)
    else { return nil }
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: space,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    return drawn ? (width, height, bytes) : nil
  }

  /// Compares a render with its recorded PNG and keeps `failure` in step: the render
  /// is left there when it differs or there's no readable PNG to compare with (nil),
  /// and one left by an earlier run is removed once the render matches again.
  static func check(_ rendered: Data, against recorded: Data?, failure: URL) throws -> Result? {
    guard let recorded, let result = compare(rendered, to: recorded) else {
      try BaselineStore.write(rendered, to: failure)
      return nil
    }
    if !result.matches {
      try BaselineStore.write(rendered, to: failure)
    } else if FileManager.default.fileExists(atPath: failure.path) {
      try FileManager.default.removeItem(at: failure)
    }
    return result
  }

  static func compare(_ rendered: Data, to recorded: Data) -> Result? {
    guard let a = rgba(rendered), let b = rgba(recorded) else { return nil }
    var result = Result(
      size: (a.width, a.height), recordedSize: (b.width, b.height), differingPixels: 0,
      maxChannelDelta: 0)
    guard a.width == b.width, a.height == b.height else { return result }
    for pixel in stride(from: 0, to: a.bytes.count, by: 4) {
      var largest = 0
      for channel in 0..<4 {
        largest = max(largest, abs(Int(a.bytes[pixel + channel]) - Int(b.bytes[pixel + channel])))
      }
      result.maxChannelDelta = max(result.maxChannelDelta, largest)
      if largest > noiseFloor { result.differingPixels += 1 }
    }
    return result
  }
}

// MARK: - Files

nonisolated enum BaselineStore {
  /// `GuidanceTests/`, from this file's place in the source tree.
  static let testsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
  static let directory = testsDirectory.appending(path: "Baselines")
  static let repositoryRoot = testsDirectory.deletingLastPathComponent()
  /// Where a failed comparison leaves the rendered image (gitignored; CI uploads it).
  static let failuresDirectory = repositoryRoot.appending(path: ".baseline-failures")

  static func write(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }
}

/// Where the baselines were recorded. Fonts and text rendering change between macOS
/// releases, so pixels are only compared on the major version recorded.
nonisolated struct BaselineEnvironment: Codable, Equatable {
  var macOS: String
  var macOSMajor: Int
  var xcodeBuild: String
  var scale: Double
  var timeZone: String
  /// The test process's preferred languages, which the scheme's test arguments pin:
  /// they change system-font line heights (see `processLanguagesArePinned`).
  var languages: [String]

  static var url: URL { BaselineStore.directory.appending(path: "environment.json") }

  static var current: BaselineEnvironment {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    let info = Bundle(for: GuidanceTestEnvironment.self).infoDictionary
    return BaselineEnvironment(
      macOS: ProcessInfo.processInfo.operatingSystemVersionString,
      macOSMajor: os.majorVersion,
      xcodeBuild: info?["DTXcodeBuild"] as? String ?? "unknown",
      scale: Double(BaselineRenderer.scale),
      timeZone: "Asia/Riyadh",
      languages: Locale.preferredLanguages)
  }

  static var recorded: BaselineEnvironment? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(BaselineEnvironment.self, from: data)
  }
}

nonisolated enum BaselineMode: Equatable {
  /// `GUIDANCE_RECORD_BASELINES=1`: write the PNGs and the index.
  case record
  /// Compare each render with its committed PNG.
  case compare
  /// Nothing to compare against on this machine.
  case skip(String)

  static var current: BaselineMode {
    if ProcessInfo.processInfo.environment["GUIDANCE_RECORD_BASELINES"] == "1" { return .record }
    guard let recorded = BaselineEnvironment.recorded else { return .skip("no baselines recorded") }
    let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    guard recorded.macOSMajor == major else {
      return .skip("baselines were recorded on macOS \(recorded.macOSMajor), this is \(major)")
    }
    return .compare
  }

  var renders: Bool {
    if case .skip = self { return false }
    return true
  }

  /// Why nothing is rendered, shown on the skipped tests.
  var skipReason: Comment? {
    if case .skip(let reason) = self { return Comment(rawValue: reason) }
    return nil
  }
}
