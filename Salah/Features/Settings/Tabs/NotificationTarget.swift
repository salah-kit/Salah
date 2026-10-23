import SalahCore

/// What the Notifications pane edits: one of the day's six events, or Friday's Jumu'ah.
enum NotificationTarget: Hashable, Identifiable {
  case prayer(PrayerKind)
  case jumuah

  /// The picker's segments: Fajr through Isha, then Jumu'ah.
  static let all: [NotificationTarget] = PrayerKind.allCases.map(Self.prayer) + [.jumuah]

  var id: Self { self }

  /// The segment's name, in the app's language.
  func name(_ names: PrayerNames) -> String {
    switch self {
    case .prayer(let kind): names.name(of: kind)
    case .jumuah: names.string(for: .jumuah)
    }
  }

  /// The alerts the pane edits for this target. Jumu'ah has its own only while Friday's
  /// alerts differ; otherwise Fridays use Dhuhr's, and there's nothing of its own to edit.
  func config(in preferences: Preferences) -> PrayerNotificationConfig? {
    switch self {
    case .prayer(let kind): preferences.config(for: kind)
    case .jumuah:
      preferences.jumuahOverrideEnabled ? preferences.jumuahConfig : nil
    }
  }

  /// Saves the alerts the pane edits: a prayer's own, or Jumu'ah's while Friday's alerts
  /// differ. With them off Jumu'ah has nothing of its own, so nothing is saved.
  func setConfig(_ config: PrayerNotificationConfig, in preferences: Preferences) {
    switch self {
    case .prayer(let kind): preferences.setConfig(config, for: kind)
    case .jumuah:
      guard preferences.jumuahOverrideEnabled else { return }
      preferences.setJumuahConfig(config)
    }
  }

  /// The segment after `target` in `order`, or before it; `nil` at either end.
  static func neighbor(
    of target: NotificationTarget, in order: [NotificationTarget], forward: Bool
  ) -> NotificationTarget? {
    guard let index = order.firstIndex(of: target) else { return nil }
    let next = index + (forward ? 1 : -1)
    return order.indices.contains(next) ? order[next] : nil
  }

  /// Whether nothing alerts for this target, which its segment shows with a muted bell.
  /// Jumu'ah without alerts of its own is as quiet as Dhuhr.
  func isMuted(in preferences: Preferences) -> Bool {
    let config = config(in: preferences) ?? preferences.config(for: .dhuhr)
    return !config.alertEnabled && !config.preReminderEnabled && !config.postReminderEnabled
  }
}
