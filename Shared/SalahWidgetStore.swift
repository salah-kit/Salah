import Foundation

#if canImport(WidgetKit)
  import WidgetKit
#endif

/// App Group transport. Two jobs:
/// 1. The app writes the latest `SalahWidgetSnapshot`; the widget reads it.
/// 2. The widget's Stop button writes a one-shot command flag and posts a Darwin
///    notification; the running app observes it and stops playback.
///
/// `nonisolated` so `requestStopAudio()` is callable from the widget's
/// `nonisolated` `AppIntent.perform()` even when the app target compiles this
/// file under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
nonisolated enum SalahWidgetStore {
  private static var defaults: UserDefaults? {
    UserDefaults(suiteName: SalahWidgetConstants.appGroupID)
  }

  // MARK: - Snapshot

  @discardableResult
  static func saveSnapshot(_ snapshot: SalahWidgetSnapshot) -> Bool {
    do {
      let data = try JSONEncoder.salahWidget.encode(snapshot)
      // No `synchronize()`: Apple documents it as unnecessary, and it can't make a
      // write reach another process any sooner. The extension reading back its own
      // write (the Stop optimistic clear) is immediate in-process; the app->widget
      // hop is mediated by cfprefsd, which a flush would not speed up.
      defaults?.set(data, forKey: SalahWidgetConstants.snapshotDefaultsKey)
      return true
    } catch {
      #if DEBUG
        print("SalahWidgetStore failed to encode snapshot: \(error)")
      #endif
      return false
    }
  }

  /// Saves the snapshot, and asks WidgetKit to refresh only when `reload` is set
  /// AND the rendered content actually changed. Re-publishing identical content
  /// (per-activation recalculations, the post-stop confirmation the extension's
  /// optimistic write already covered) is skipped on purpose: from a menu-bar
  /// agent the app is not "foreground", so reload requests are deferred and
  /// coalesced by macOS, and firing redundant ones risks the rate limiter
  /// dropping a reload that *does* matter. `generatedAt` is ignored in the
  /// comparison - it is build-time metadata nothing renders.
  static func publishSnapshot(_ snapshot: SalahWidgetSnapshot, reload: Bool) {
    let previous = reload ? loadSnapshot() : nil
    guard saveSnapshot(snapshot), reload else { return }
    if let previous, previous.hasSameContent(as: snapshot) { return }
    reloadPrayerTimesWidgetTimelines()
  }

  static func loadSnapshot() -> SalahWidgetSnapshot? {
    guard let data = defaults?.data(forKey: SalahWidgetConstants.snapshotDefaultsKey) else {
      return nil
    }
    return try? JSONDecoder.salahWidget.decode(SalahWidgetSnapshot.self, from: data)
  }

  // MARK: - Stop command

  static func requestStopAudio() {
    clearActiveAlertForStop()
    defaults?.set(UUID().uuidString, forKey: SalahWidgetConstants.stopAudioCommandDefaultsKey)
    postStopAudioDarwinNotification()
    reloadPrayerTimesWidgetTimelines()
  }

  /// Consumes the pending stop command, if any. Returns `true` when one was set.
  @discardableResult
  static func takeStopAudioCommand() -> Bool {
    guard defaults?.string(forKey: SalahWidgetConstants.stopAudioCommandDefaultsKey) != nil else {
      return false
    }
    defaults?.removeObject(forKey: SalahWidgetConstants.stopAudioCommandDefaultsKey)
    return true
  }

  static func reloadPrayerTimesWidgetTimelines() {
    #if canImport(WidgetKit)
      WidgetCenter.shared.reloadTimelines(ofKind: SalahWidgetConstants.prayerTimesWidgetKind)
    #endif
  }

  private static func clearActiveAlertForStop() {
    guard let snapshot = loadSnapshot() else { return }
    saveSnapshot(snapshot.clearingActiveAlert())
  }

  private static func postStopAudioDarwinNotification() {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(SalahWidgetConstants.stopAudioDarwinNotification as CFString),
      nil,
      nil,
      true
    )
  }
}

extension JSONEncoder {
  fileprivate nonisolated static var salahWidget: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}

extension JSONDecoder {
  fileprivate nonisolated static var salahWidget: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
