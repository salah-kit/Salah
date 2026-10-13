import Foundation
import SwiftUI
import Testing

/// Renders every widget state, `WidgetPreviewContainer` scenario, widget family and
/// the menu-bar dropdown, in English, Arabic and French, light and dark, and checks
/// them against `Baselines/` (see its README for the inputs and the record command).
@Suite("Visual baselines")
struct VisualBaselineTests {
  init() { TestEnvironment.configure() }

  static let mode = BaselineMode.current

  @Test(
    .enabled(if: BaselineMode.current.renders, BaselineMode.current.skipReason),
    arguments: BaselineCatalog.all)
  func baseline(_ baseline: Baseline) throws {
    // Rendering settles on one image: no live clock, animation or timer leaks into
    // it (`stablePNG` throws if four renders in a row never agree).
    let png = try AppLanguageScope.with(BaselinePipeline.appLanguage(baseline.language)) {
      try BaselineRenderer.stablePNG { try BaselinePipeline.view(for: baseline) }
    }

    let url = BaselineStore.directory.appending(path: baseline.path)
    switch Self.mode {
    case .record:
      // Keep a PNG the render still matches, so noise never churns the history.
      if let recorded = try? Data(contentsOf: url),
        PixelComparison.compare(png, to: recorded)?.matches == true
      {
        return
      }
      try BaselineStore.write(png, to: url)
    case .compare:
      let recorded = try Data(contentsOf: url)
      let failure = BaselineStore.failuresDirectory.appending(path: baseline.path)
      let checked = try PixelComparison.check(png, against: recorded, failure: failure)
      let result = try #require(checked)
      #expect(result.matches, "\(baseline.path): \(result)")
    case .skip:
      break
    }
  }

  /// `README.md` and `index.json` match the catalog; record mode rewrites them and
  /// `environment.json`.
  @Test func indexMatchesTheCatalog() throws {
    let readme = BaselineStore.directory.appending(path: "README.md")
    let index = BaselineStore.directory.appending(path: "index.json")
    if Self.mode == .record {
      try BaselineStore.write(Data(BaselineIndex.readme().utf8), to: readme)
      try BaselineStore.write(BaselineIndex.json(), to: index)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try BaselineStore.write(
        encoder.encode(BaselineEnvironment.current) + Data("\n".utf8), to: BaselineEnvironment.url)
      return
    }
    try #require(FileManager.default.fileExists(atPath: readme.path), "no baselines recorded yet")
    #expect(try String(contentsOf: readme, encoding: .utf8) == BaselineIndex.readme())
    #expect(try Data(contentsOf: index) == BaselineIndex.json())
  }

  /// Every PNG under `Baselines/` is in the catalog, so stale images can't linger.
  @Test(.enabled(if: BaselineMode.current == .compare, BaselineMode.current.skipReason))
  func noOrphanedImages() throws {
    let expected = Set(BaselineCatalog.all.map(\.path))
    let enumerator = FileManager.default.enumerator(
      at: BaselineStore.directory, includingPropertiesForKeys: nil)
    var found: Set<String> = []
    while let url = enumerator?.nextObject() as? URL {
      guard url.pathExtension == "png" else { continue }
      found.insert(url.path.replacingOccurrences(of: BaselineStore.directory.path + "/", with: ""))
    }
    #expect(found == expected)
  }

  /// The setup face has no snapshot to take a language from: the extension shows it
  /// under the sample snapshot's locale, so it's English whatever the app's language,
  /// although the extension's catalog has the message in Arabic and French.
  @Test func setupFaceIsEnglishInEveryLanguage() throws {
    let messages = try ["en", "ar", "fr"].map {
      try ExtensionCatalog.string("widget.openToSetUp", localeIdentifier: $0)
    }
    #expect(Set(messages).count == 3)

    func png(_ language: Baseline.Language) throws -> Data {
      let baseline = Baseline(
        surface: .widget, state: SpecState.setupNeeded.rawValue, family: .medium,
        language: language, appearance: .light)
      return try AppLanguageScope.with(BaselinePipeline.appLanguage(language)) {
        try BaselineRenderer.stablePNG { try BaselinePipeline.view(for: baseline) }
      }
    }
    // Compared like the baselines: a face's first render in a process can settle a
    // few pixels apart from later ones.
    let english = try png(.en)
    for language in [Baseline.Language.ar, .fr] {
      let result = try #require(PixelComparison.compare(png(language), to: english))
      #expect(result.matches, "\(language): \(result)")
    }
  }

  /// Caption-size text, light on dark, as the faces show it.
  static func textPNG(_ text: String) throws -> Data {
    try BaselineRenderer.stablePNG {
      Text(verbatim: text).font(.caption2).foregroundStyle(.white).padding(4)
        .background(.black)
    }
  }

  /// The tolerance absorbs antialiasing jitter, not a changed mark: a diacritic alone
  /// changes about ten pixels at caption size, each by far more than jitter does.
  @Test func aDiacriticAloneIsADifference() throws {
    for (marked, plain) in [("تنبيه مُفعّل", "تنبيه مفعّل"), ("Ishā", "Isha")] {
      let markedPNG = try Self.textPNG(marked)
      let markedAgain = try Self.textPNG(marked)
      let plainPNG = try Self.textPNG(plain)
      let result = try #require(PixelComparison.compare(markedPNG, to: plainPNG))
      #expect(!result.matches, "\(marked) vs \(plain): \(result)")
      #expect(PixelComparison.compare(markedPNG, to: markedAgain)?.matches == true)
    }
  }

  /// A failed comparison leaves the render in the failures folder; once the face
  /// matches again, a render left by an earlier run is removed.
  @Test func failedRendersStayOnlyWhileTheyDiffer() throws {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "GuidanceTests-failures-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let failure = folder.appending(path: "widget/face.png")
    let marked = try Self.textPNG("Ishā")
    let plain = try Self.textPNG("Isha")

    let differing = try PixelComparison.check(marked, against: plain, failure: failure)
    #expect(differing?.matches == false)
    #expect(FileManager.default.fileExists(atPath: failure.path))
    let matching = try PixelComparison.check(plain, against: plain, failure: failure)
    #expect(matching?.matches == true)
    #expect(!FileManager.default.fileExists(atPath: failure.path))
  }

  @Test func catalogCoversEveryStateFamilyLanguageAndAppearance() {
    let all = BaselineCatalog.all
    #expect(Set(all.map(\.path)).count == all.count)
    #expect(all.filter { $0.surface == .widget }.count == SpecState.allCases.count * 3 * 3 * 2)
    #expect(
      all.filter { $0.surface == .menu }.count == SpecState.allCases.filter(\.onMenu).count * 3 * 2)
    #expect(
      all.filter { $0.surface == .preview }.count == PreviewScenario.allCases.count * 3 * 3 * 2)
    #expect(all.filter { $0.surface == .theme }.count == ThemePreset.allCases.count * 3 * 2)
  }

  /// The fixture moments land in the states they name.
  @Test func specStateMomentsShowTheirStates() throws {
    func snapshot(_ state: SpecState) -> GuidanceWidgetSnapshot {
      BaselinePipeline.snapshot(for: state, language: .en)
    }
    func focus(_ state: SpecState) -> GuidanceWidgetSnapshot.Focus? {
      snapshot(state).focus(at: BaselinePipeline.moment(for: state))
    }
    #expect(focus(.idle).map { if case .countdown(let p) = $0 { p.id } else { "" } } == "asr")
    #expect(snapshot(.imminent).tone(at: BaselinePipeline.moment(for: .imminent)) == .imminent)
    #expect(focus(.countUp).map { if case .countUp(let p) = $0 { p.id } else { "" } } == "dhuhr")
    #expect(
      snapshot(.countUpSilent).backgroundTone(at: BaselinePipeline.moment(for: .countUpSilent))
        == .silent)
    let overlap = snapshot(.countUpImminent)
    #expect(
      focus(.countUpImminent).map { if case .countUp(let p) = $0 { p.id } else { "" } } == "maghrib"
    )
    #expect(overlap.tone(at: BaselinePipeline.moment(for: .countUpImminent)) == .imminent)
    #expect(focus(.endOfDay).map { if case .tomorrow(let p) = $0 { p.id } else { "" } } == "fajr")
    #expect(snapshot(.playingAdhan).activeAlert?.slot == .alert)
    #expect(snapshot(.playingPreReminder).activeAlert?.slot == .preReminder)
    #expect(snapshot(.playingPostReminder).activeAlert?.slot == .postReminder)
    #expect(snapshot(.silent).silentMode)
    #expect(snapshot(.stale).isStale(at: BaselinePipeline.moment(for: .stale)))
    // No state sits within a minute of a prayer, where the views switch to the
    // system's live timer text, which reads the real clock.
    for state in SpecState.allCases where state != .stale && state != .setupNeeded {
      let moment = BaselinePipeline.moment(for: state)
      let times = snapshot(state).prayers.map(\.time) + [snapshot(state).tomorrowFajr!.time]
      #expect(times.allSatisfy { abs($0.timeIntervalSince(moment)) > 60 }, "\(state)")
    }
  }
}
