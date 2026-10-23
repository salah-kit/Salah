import Foundation
import SalahCore
import Testing

/// The Notifications pane's prayer picker: what each segment edits, and which show a
/// muted bell.
@Suite("Notification targets")
struct NotificationTargetTests {
  init() { TestEnvironment.configure() }

  /// The six events of the day in order, then Jumu'ah, named in the app's language.
  @Test func thePickerListsTheDayThenJumuah() {
    #expect(
      NotificationTarget.all
        == [
          .prayer(.fajr), .prayer(.sunrise), .prayer(.dhuhr), .prayer(.asr), .prayer(.maghrib),
          .prayer(.isha), .jumuah,
        ])
    let english = PrayerNames(locale: Locale(identifier: "en"))
    #expect(NotificationTarget.jumuah.name(english) == english.string(for: .jumuah))
    #expect(NotificationTarget.prayer(.asr).name(english) == "Asr")
  }

  /// A segment shows the muted bell only when every alert of its prayer is off: the alert,
  /// and the reminders before and after.
  @Test func aPrayerIsMutedOnlyWithEveryAlertOff() {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.setConfig(.off, for: .sunrise)
    preferences.setConfig(.alert(false, before: 10), for: .asr)
    preferences.setConfig(.alert(false, after: 5), for: .isha)
    preferences.setConfig(.alert(), for: .fajr)
    #expect(NotificationTarget.prayer(.sunrise).isMuted(in: preferences))
    #expect(!NotificationTarget.prayer(.asr).isMuted(in: preferences))
    #expect(!NotificationTarget.prayer(.isha).isMuted(in: preferences))
    #expect(!NotificationTarget.prayer(.fajr).isMuted(in: preferences))
  }

  /// Jumu'ah has alerts of its own only while Friday's differ; otherwise Fridays use
  /// Dhuhr's, so it has nothing to edit and is as quiet as Dhuhr.
  @Test func jumuahFollowsDhuhrUntilFridaysDiffer() throws {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.jumuahOverrideEnabled = false
    preferences.setConfig(.off, for: .dhuhr)
    #expect(NotificationTarget.jumuah.config(in: preferences) == nil)
    #expect(NotificationTarget.jumuah.isMuted(in: preferences))

    preferences.setConfig(.alert(), for: .dhuhr)
    #expect(!NotificationTarget.jumuah.isMuted(in: preferences))

    preferences.jumuahOverrideEnabled = true
    preferences.setJumuahConfig(.off)
    #expect(try #require(NotificationTarget.jumuah.config(in: preferences)) == .off)
    #expect(NotificationTarget.jumuah.isMuted(in: preferences))
    #expect(!NotificationTarget.prayer(.dhuhr).isMuted(in: preferences))
  }
}
