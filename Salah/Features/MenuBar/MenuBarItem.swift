import Foundation
import SalahCore

/// What the status item shows, from the menu-bar settings and the moment: the glyph or the
/// speaker, the text, the attention dot, the approaching capsule, and what VoiceOver says.
///
/// The five displays Settings offers draw as Figma's menu bar gallery does:
/// - Icon: the glyph alone.
/// - Icon + countdown: the glyph and "2:16".
/// - Icon + name + countdown: the glyph and "Asr 2:16".
/// - Name + time: "Asr 3:35", without the glyph.
/// - Abbreviation + countdown: the glyph and "A 2:16".
///
/// For 15 minutes after a prayer begins, it leads: its glyph, and "Dhuhr +4m" or, showing the
/// time, "Dhuhr 12:19". While audio plays, the speaker stands in for the glyph, and the text
/// names the prayer it plays for ("Maghrib"), with its time when the display shows the time
/// ("Maghrib 7:00"). A permission that's off adds a dot to the glyph, never a glyph of its own.
struct MenuBarItem: Equatable {
  enum Icon: Equatable {
    /// The display has no icon.
    case none
    /// A prayer's glyph; `nil` while the next prayer isn't known.
    case glyph(PrayerKind?)
    /// Audio plays.
    case speaker
  }

  var icon: Icon
  var text: String
  /// The warning dot in the icon's top-trailing corner: a permission is off.
  var attention: Bool
  /// The gold capsule of the 15 minutes before a prayer.
  var approaching: Bool
  /// "Salah, Asr in 2 hours, 16 minutes".
  var accessibilityLabel: String

  /// The menu-bar settings: Settings → General → Menu bar.
  struct Display: Equatable {
    var showsIcon: Bool
    var showsNextPrayer: Bool
    var name: NextPrayerDisplayName
    var time: NextPrayerDisplayType

    init(
      showsIcon: Bool = true, showsNextPrayer: Bool = true, name: NextPrayerDisplayName = .full,
      time: NextPrayerDisplayType = .timeUntil
    ) {
      self.showsIcon = showsIcon
      self.showsNextPrayer = showsNextPrayer
      self.name = name
      self.time = time
    }
  }

  /// The moment: what plays, the schedule's state, and whether a permission is off.
  struct Moment {
    var now: Date
    /// The prayer any audio plays for, a reminder before it included.
    var playing: PrayerEvent?
    /// What plays, for VoiceOver: "Playing adhan".
    var playingTitle: String = ""
    /// The prayer that began less than 15 minutes ago (never Sunrise).
    var justStarted: PrayerEvent?
    /// The next event; `nil` while the schedule doesn't know it.
    var next: PrayerEvent?
    /// The 15 minutes before the next prayer.
    var isApproaching: Bool
    var needsAttention: Bool
  }

  init(
    icon: Icon, text: String, attention: Bool, approaching: Bool, accessibilityLabel: String
  ) {
    self.icon = icon
    self.text = text
    self.attention = attention
    self.approaching = approaching
    self.accessibilityLabel = accessibilityLabel
  }

  init(display: Display, moment: Moment, text: SalahText, names: PrayerNames, appName: String) {
    func name(_ event: PrayerEvent, fullWhenHidden: Bool) -> String {
      switch display.name {
      case .full: names.name(of: event)
      case .abbreviation: names.abbreviation(of: event)
      case .none: fullWhenHidden ? names.name(of: event) : ""
      }
    }
    func join(_ parts: String...) -> String {
      parts.filter { !$0.isEmpty }.joined(separator: " ")
    }
    let spoken = { (seconds: TimeInterval) in
      PrayerDurationFormat.string(abs(seconds), width: .spoken, locale: text.locale)
    }

    let shown: String
    let said: String
    if let playing = moment.playing {
      icon = display.showsIcon ? .speaker : .none
      approaching = false
      // The countdown gives way to the prayer's name; a time display keeps its time.
      shown =
        display.showsNextPrayer
        ? join(
          name(playing, fullWhenHidden: true),
          display.time == .timeOfPrayer ? text.compactTime(playing.time) : "")
        : ""
      said = [moment.playingTitle, names.name(of: playing)].filter { !$0.isEmpty }
        .joined(separator: " · ")
    } else {
      // The prayer that just began leads the countdown and the clock time alike.
      // A hidden next prayer's time style doesn't apply: the Icon display leads with it too.
      let lead = display.showsNextPrayer && display.time == .none ? nil : moment.justStarted
      icon = display.showsIcon ? .glyph((lead ?? moment.next)?.kind) : .none
      approaching = lead == nil && moment.isApproaching
      if let lead {
        let elapsed = moment.now.timeIntervalSince(lead.time)
        shown =
          display.showsNextPrayer
          ? join(
            name(lead, fullWhenHidden: false),
            display.time == .timeUntil
              ? text.duration(elapsed, direction: .elapsed, bidiIsolated: true)
              : text.compactTime(lead.time))
          : ""
        said = text.labels.sinceSpoken(prayer: names.name(of: lead), time: spoken(elapsed))
      } else if let next = moment.next {
        let remaining = next.time.timeIntervalSince(moment.now)
        let time: String =
          switch display.time {
          case .timeUntil: text.duration(remaining, direction: .remaining, bidiIsolated: true)
          case .timeOfPrayer: text.compactTime(next.time)
          case .none: ""
          }
        shown = display.showsNextPrayer ? join(name(next, fullWhenHidden: false), time) : ""
        said =
          names.name(of: next) + " "
          + String(
            format: localizedString("today.row.in", locale: text.locale), locale: text.locale,
            spoken(remaining))
      } else {
        // The schedule doesn't know what comes next: say so rather than invent one.
        shown = display.showsNextPrayer ? "–" : ""
        said = text.labels.nextUnknown
      }
    }
    self.text = shown
    attention = moment.needsAttention && icon != .none
    accessibilityLabel = String(
      format: localizedString("menu.status.label", locale: text.locale), locale: text.locale,
      appName, said)
  }
}
