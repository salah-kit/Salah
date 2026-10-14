import Foundation
import OSLog
import SalahWidgets

#if canImport(WidgetKit)
  import WidgetKit
#endif

/// Publishes to the App Group what the widget extension builds its timelines from: the
/// settings mirror and what's playing.
///
/// `start(preferences:)` publishes the settings at once and again whenever a
/// preference with the `display`, `prayerTimes` or `localization` effect changes (a
/// language-only change included), so the widget always has the inputs the menu bar
/// draws from. `SharedValue` writes and reloads the widget only when a value changed,
/// so a republish of the same settings costs no reload.
@MainActor
final class WidgetMirror {
  /// The effects whose preferences the mirror holds.
  static let mirroredEffects: PreferenceRefresh = [.display, .prayerTimes, .localization]

  let settings: SharedValue<SalahSettings>
  let playback: SharedValue<SalahPlayback>
  private let reloadWidgetTimelines: () -> Void
  private var preferences: Preferences?
  /// Written once, on the main actor, in `start`; `deinit` reads it after the last
  /// reference is gone, so nothing can touch it concurrently.
  nonisolated(unsafe) private var observer: NSObjectProtocol?

  /// The defaults are the App Group and WidgetKit; tests pass their own values, whose
  /// reloads they record.
  init(
    settings: SharedValue<SalahSettings> = .settings,
    playback: SharedValue<SalahPlayback> = .playback,
    reloadWidgetTimelines: @escaping () -> Void = WidgetMirror.reloadPrayerTimesWidget
  ) {
    self.settings = settings
    self.playback = playback
    self.reloadWidgetTimelines = reloadWidgetTimelines
  }

  deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }

  /// Publishes `preferences`' settings now, and again after every change with a
  /// mirrored effect.
  func start(preferences: Preferences) {
    self.preferences = preferences
    publish(preferences.mirroredSettings)
    guard observer == nil else { return }
    // Preferences post on the main thread, synchronously from their didSets.
    observer = NotificationCenter.default.addObserver(
      forName: .salahPreferencesDidChange, object: nil, queue: nil
    ) { [weak self] note in
      let raw = note.userInfo?[PreferenceRefresh.userInfoKey] as? Int ?? 0
      MainActor.assumeIsolated {
        self?.preferencesChanged(PreferenceRefresh(rawValue: raw))
      }
    }
  }

  /// Publishes the settings again when the change has a mirrored effect.
  func preferencesChanged(_ effects: PreferenceRefresh) {
    guard let preferences, !effects.isDisjoint(with: Self.mirroredEffects) else { return }
    publish(preferences.mirroredSettings)
  }

  /// Saves the settings mirror; the widget reloads only when it changed.
  @discardableResult
  func publish(_ value: SalahSettings) -> Bool {
    save(value, in: settings)
  }

  /// Saves what's playing, or clears it; the widget reloads only when it changed.
  @discardableResult
  func publish(playback value: SalahPlayback?) -> Bool {
    save(value, in: playback)
  }

  /// Asks WidgetKit for new timelines, whatever changed: at launch, so a widget whose
  /// timeline ran out ("Open Salah to update") gets a new one.
  func reloadWidgets() {
    reloadWidgetTimelines()
  }

  private func save<Value>(_ value: Value?, in store: SharedValue<Value>) -> Bool {
    do {
      return try store.save(value, reloading: [SalahWidgetConstants.prayerTimesWidgetKind])
    } catch {
      AppLog.widgets.error(
        "Couldn't save \(store.key, privacy: .public): \(String(describing: error), privacy: .public)"
      )
      return false
    }
  }

  nonisolated static func reloadPrayerTimesWidget() {
    #if canImport(WidgetKit)
      WidgetCenter.shared.reloadTimelines(ofKind: SalahWidgetConstants.prayerTimesWidgetKind)
    #endif
  }
}
