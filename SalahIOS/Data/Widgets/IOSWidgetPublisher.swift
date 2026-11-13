import Foundation
import SalahCore
import SalahWidgets
import WidgetKit

/// Saves Salah's settings where its extension reads them, and asks the system to draw the
/// widgets and controls again.
@MainActor struct IOSWidgetPublisher {
  /// The system's side of publishing, replaceable in tests.
  struct System {
    /// The settings the extension reads now.
    var load: () -> SalahSettings?
    /// Saves the settings and reloads the given widget kinds; `false` when nothing changed.
    var save: (_ settings: SalahSettings, _ reloading: [String]) throws -> Bool
    var reloadAllTimelines: () -> Void
    var reloadControls: (_ kind: String) -> Void
    var reloadAllControls: () -> Void

    static var live: System {
      System(
        load: { SharedValue.settings.load() },
        save: { settings, kinds in try SharedValue.settings.save(settings, reloading: kinds) },
        reloadAllTimelines: { WidgetCenter.shared.reloadAllTimelines() },
        reloadControls: { ControlCenter.shared.reloadControls(ofKind: $0) },
        reloadAllControls: { ControlCenter.shared.reloadAllControls() })
    }
  }

  var system: System = .live

  /// Publishes `settings`; `true` when they differ from the saved ones.
  ///
  /// A new language changes the words on every widget and control Salah has, on the Home
  /// Screen, the Lock Screen and in Control Center, so all of them reload at once rather
  /// than at their next scheduled refresh. Any other change reloads the prayer times widget
  /// and the mute control, the surfaces that show a setting.
  @discardableResult
  func publish(_ settings: SalahSettings) throws -> Bool {
    let languageChanged = system.load().map { $0.language != settings.language } ?? false
    let changed = try system.save(
      settings, languageChanged ? [] : [SalahWidgetConstants.prayerTimesWidgetKind])
    guard changed else { return false }
    if languageChanged {
      system.reloadAllTimelines()
      system.reloadAllControls()
    } else {
      system.reloadControls(IOSControlKind.muteSounds)
    }
    return true
  }
}
