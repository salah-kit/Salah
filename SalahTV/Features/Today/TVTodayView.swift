import SalahCore
import SalahUI
import SwiftUI

/// The next prayer beside the day's prayers, in two columns of 860 pt. The rows take focus;
/// pressing one opens that prayer's adhan setting. At accessibility text sizes it becomes
/// one column that scrolls.
struct TVTodayView: View {
  @Environment(IOSAppStore.self) private var store
  @Environment(TVNavigation.self) private var navigation
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @FocusState private var focusedRow: PrayerKind?

  var body: some View {
    ZStack(alignment: .topLeading) {
      TVSkyBackground(phase: store.display?.phase ?? .neutral)
      if let display = store.display {
        let presentation = TVPrayerPresentation(display: display, preferences: store.preferences)
        if dynamicTypeSize.isAccessibilitySize {
          ScrollView {
            VStack(alignment: .leading, spacing: 48) {
              TVNextPrayerHero(presentation: presentation)
              rows(presentation)
              keepOnScreen(presentation)
              footer(presentation)
            }
            .padding(.horizontal, TVMetrics.safeHorizontal)
            .padding(.top, TVMetrics.contentTop)
            .padding(.bottom, TVMetrics.safeVertical)
          }
          .scrollClipDisabled()
        } else {
          HStack(alignment: .top, spacing: TVMetrics.gutter) {
            VStack(alignment: .leading, spacing: 0) {
              TVDateHeader(display: display)
              TVNextPrayerHero(presentation: presentation)
                .padding(.top, 42)
              keepOnScreen(presentation)
                .padding(.top, 62)
            }
            .frame(width: TVMetrics.column, alignment: .leading)
            // Keep on Screen sits below most rows, so moving across reaches it from any row.
            .focusSection()
            VStack(alignment: .leading, spacing: 22) {
              Text(verbatim: presentation.copy("Today’s prayers", "صلوات اليوم"))
                .font(.headline.bold())
                .foregroundStyle(TVTheme.labelSecondary)
                .padding(.leading, 28)
                .accessibilityAddTraits(.isHeader)
              rows(presentation)
              if footerUnderRows {
                footer(presentation)
                  .fixedSize(horizontal: false, vertical: true)
                  .padding(.top, 2)
              }
            }
            .frame(width: TVMetrics.column, alignment: .leading)
            .focusSection()
          }
          .padding(.top, TVMetrics.contentTop)
          .padding(.horizontal, TVMetrics.safeHorizontal)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .overlay(alignment: .bottomLeading) {
            if !footerUnderRows {
              footer(presentation)
                .padding(.horizontal, TVMetrics.safeHorizontal)
                .padding(.bottom, 82)
            }
          }
        }
      } else {
        TVUnavailableView()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .ignoresSafeArea()
    // Moving down from the tab bar also lands on the next prayer.
    .defaultFocus($focusedRow, store.display.flatMap(defaultRow), priority: .userInitiated)
  }

  /// Urdu's Nastaliq and Bengali set taller lines, which bring Keep on Screen down to where
  /// the line about the method runs across the screen, so there it follows the rows instead.
  private var footerUnderRows: Bool {
    ["ur", "bn"].contains(store.locale.language.languageCode?.identifier)
  }

  private func rows(_ presentation: TVPrayerPresentation) -> some View {
    VStack(spacing: TVMetrics.rowSpacing) {
      ForEach(presentation.display.slots) { slot in
        switch slot {
        case .event(let event):
          TVPrayerRow(event: event, presentation: presentation) {
            navigation.settingsPath = [.prayers, .prayer(event.kind, event.observance)]
            navigation.selectedTab = .settings
          }
          .focused($focusedRow, equals: event.kind)
        case .missing(let kind):
          TVMissingRow(name: presentation.display.name(of: kind), copy: presentation.copy)
        }
      }
    }
  }

  private func keepOnScreen(_ presentation: TVPrayerPresentation) -> some View {
    Button(presentation.copy("Keep on Screen", "إبقاء على الشاشة")) {
      navigation.showRoomDisplay()
    }
    .accessibilityHint(
      presentation.copy(
        "Shows the day’s times and keeps the screen on", "يعرض أوقات اليوم ويُبقي الشاشة قيد التشغيل"
      )
    )
    .accessibilityIdentifier("today.keepOnScreen")
  }

  private func footer(_ presentation: TVPrayerPresentation) -> some View {
    Text(
      verbatim: TVSourceNote(display: presentation.display, preferences: store.preferences).today
    )
    .font(.caption.weight(.medium))
    .foregroundStyle(TVTheme.labelSecondary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier("today.source")
  }

  /// Focus starts on the next prayer, the row people most often want.
  private func defaultRow(_ display: SalahDisplay) -> PrayerKind? {
    display.prayerState?.next.flatMap { display.isListed($0) ? $0.kind : nil }
  }
}

/// A prayer the schedule couldn't give, in place of its row.
struct TVMissingRow: View {
  let name: String
  let copy: TVCopy

  var body: some View {
    HStack {
      Text(verbatim: name)
      Spacer()
      Text(verbatim: copy("Not available", "غير متاح"))
    }
    .font(.headline.weight(.medium))
    .foregroundStyle(TVTheme.labelSecondary)
    .padding(.horizontal, 28)
    .frame(height: TVMetrics.rowHeight)
    .accessibilityElement(children: .combine)
  }
}

/// No times: the location's times can't be calculated for this date.
struct TVUnavailableView: View {
  @Environment(IOSAppStore.self) private var store

  var body: some View {
    let copy = TVCopy(locale: store.locale)
    VStack(spacing: 24) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 80))
        .foregroundStyle(TVTheme.warning)
        .accessibilityHidden(true)
      Text(verbatim: copy("Prayer times aren’t available", "أوقات الصلاة غير متاحة"))
        .font(.title2.bold())
      Text(
        verbatim: copy(
          "Choose another city or calculation method in Settings.",
          "اختر مدينة أو طريقة حساب أخرى من الإعدادات.")
      )
      .font(.callout)
      .foregroundStyle(TVTheme.labelSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// The line under the times that says where they come from.
struct TVSourceNote {
  let display: SalahDisplay
  let preferences: IOSPreferences

  private var copy: TVCopy { TVCopy(locale: display.locale) }
  private var settings: TVSettingsCopy { TVSettingsCopy(locale: display.locale) }

  /// "Umm al-Qura, Makkah · Shafi'i · Calculated on this Apple TV for Makkah, Saudi Arabia."
  var today: String {
    "\(settings.methodName(preferences)) · \(settings.madhab(preferences.madhab)) · "
      + calculatedFor
  }

  var place: String {
    [
      display.settings.location.name,
      display.settings.location.countryCode.flatMap {
        display.locale.localizedString(forRegionCode: $0)
      },
    ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: copy(", ", "، "))
  }

  var calculatedFor: String {
    place.isEmpty
      ? copy("Calculated on this Apple TV.", "حُسبت الأوقات على جهاز Apple TV هذا.")
      : copy.format(
        "Calculated on this Apple TV for %@.", "حُسبت الأوقات على جهاز Apple TV هذا لمدينة %@.",
        place)
  }
}
