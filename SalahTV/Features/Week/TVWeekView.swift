import SalahCore
import SwiftUI

/// Seven days in columns, Monday to Sunday, with today's column focused. Focus moves by
/// day; moving past either end turns to the next or previous week. Back returns to the tab
/// bar.
struct TVWeekView: View {
  @Environment(IOSAppStore.self) private var store
  @FocusState private var focusedDay: CivilDay?
  @FocusState private var focusedEnd: WeekEnd?

  /// The strips past Monday and past Sunday, which take focus only to turn the week.
  private enum WeekEnd: Hashable {
    case previous, next
  }

  var body: some View {
    let copy = TVCopy(locale: store.locale)
    let time = TVTimeText(locale: store.locale, timeZone: store.timeZone)
    ZStack(alignment: .topLeading) {
      TVSkyBackground(phase: store.display?.phase ?? .neutral)
      if let schedule = store.schedule {
        VStack(alignment: .leading, spacing: 0) {
          header(copy: copy, time: time)
          // The end strips sit outside the columns' spacing, so the week keeps its width.
          HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
              prayerLabels
                .overlay(alignment: .trailing) { weekEnd(.previous) }
              ForEach(store.weekDays, id: \.self) { day in
                TVWeekDayColumn(
                  day: day, availability: schedule.day(day), isToday: day == store.today,
                  time: time, turnWeek: turnWeek
                ) {
                  store.selectedDay = day
                }
                .focused($focusedDay, equals: day)
              }
            }
            weekEnd(.next)
              .frame(height: TVWeekDayColumn.height)
          }
          .padding(.top, 4)
          .focusSection()
        }
        .padding(.top, 150)
        .padding(.horizontal, TVMetrics.safeHorizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomLeading) {
          Text(verbatim: footer(copy: copy))
            .font(.caption.weight(.medium))
            .foregroundStyle(TVTheme.labelSecondary)
            .padding(.horizontal, TVMetrics.safeHorizontal)
            .padding(.bottom, 68)
        }
      } else {
        TVUnavailableView()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .ignoresSafeArea()
    // Moving down from the tab bar lands on the selected day, not the column under the tab.
    .defaultFocus($focusedDay, store.selectedDay, priority: .userInitiated)
    // Browsing moves the selected day, so the tab comes back to the current week.
    .onAppear { store.selectedDay = store.today }
    .onChange(of: focusedDay) { _, day in
      if let day { store.selectedDay = day }
    }
    .onChange(of: focusedEnd) { _, end in
      if let end { turnWeek(forward: end == .next) }
    }
  }

  /// An invisible strip beside the first or last column. Moving focus past that day lands
  /// on it, which turns the week. VoiceOver turns the week with the days' actions instead.
  private func weekEnd(_ end: WeekEnd) -> some View {
    Color.clear
      .frame(width: 1)
      .focusable()
      .focusEffectDisabled()
      .focused($focusedEnd, equals: end)
      .accessibilityHidden(true)
  }

  private func header(copy: TVCopy, time: TVTimeText) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: range)
        .font(.title3.bold())
        .foregroundStyle(TVTheme.labelPrimary)
      Text(
        verbatim: [hijriRange, store.preferences.location?.name ?? ""].filter { !$0.isEmpty }
          .joined(separator: " · ")
      )
      .font(.callout.weight(.medium))
      .foregroundStyle(TVTheme.labelSecondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
    .accessibilityIdentifier("week.header")
  }

  private var prayerLabels: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(PrayerKind.allCases, id: \.self) { kind in
        HStack(spacing: 16) {
          TVPrayerGlyph(name: "salah." + kind.rawValue, size: 36, color: TVTheme.labelSecondary)
          Text(verbatim: store.names.name(of: kind))
            .font(.callout.weight(.medium))
            .foregroundStyle(TVTheme.labelPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(width: 236, height: 76, alignment: .leading)
      }
    }
    .padding(.top, 148)
    .accessibilityHidden(true)
  }

  /// "12 – 18 October 2026".
  private var range: String {
    guard let first = store.weekDays.first, let last = store.weekDays.last else { return "" }
    return TVTimeText(locale: store.locale, timeZone: store.timeZone).range(
      from: first.start(in: store.timeZone), to: last.start(in: store.timeZone),
      template: "d MMMM yyyy")
  }

  /// "1 – 7 Jumada I 1448".
  private var hijriRange: String {
    guard let first = store.weekDays.first, let last = store.weekDays.last else { return "" }
    let text = SalahText(locale: store.locale, timeZone: store.timeZone)
    let offset = store.preferences.hijriOffset
    let start = text.hijri(first.start(in: store.timeZone), dayOffset: offset)
    let end = text.hijri(last.start(in: store.timeZone), dayOffset: offset)
    if start.month == end.month, start.year == end.year {
      return "\(start.day) – \(end.day) \(start.month) \(start.year)"
    }
    return "\(start.day) \(start.month) – \(end.day) \(end.month) \(end.year)"
  }

  /// "Moonsighting Committee · Shafi'i. Times for London, United Kingdom, in British Summer
  /// Time."
  private func footer(copy: TVCopy) -> String {
    let settings = TVSettingsCopy(locale: store.locale)
    let method =
      "\(settings.methodName(store.preferences)) · \(settings.madhab(store.preferences.madhab))."
    guard let display = store.display else { return method }
    let note = TVSourceNote(display: display, preferences: store.preferences)
    let zone = store.timeZone
    let day = store.selectedDay.start(in: zone)
    let zoneName =
      zone.localizedName(
        for: zone.isDaylightSavingTime(for: day) ? .daylightSaving : .standard,
        locale: store.locale) ?? zone.identifier
    return method + " "
      + copy.format(
        "Times for %1$@, in %2$@.", "الأوقات لمدينة %1$@، بتوقيت %2$@.", note.place, zoneName)
  }

  /// Shows the next week from its Monday, or the previous one from its Sunday, and gives
  /// that day focus.
  private func turnWeek(forward: Bool) {
    guard let first = store.weekDays.first, let last = store.weekDays.last else { return }
    let day = forward ? last.adding(days: 1) : first.adding(days: -1)
    store.selectedDay = day
    focusedDay = day
  }
}

/// One day's column: its weekday and dates, then a time per prayer.
struct TVWeekDayColumn: View {
  let day: CivilDay
  let availability: PrayerDayAvailability
  let isToday: Bool
  let time: TVTimeText
  let turnWeek: (_ forward: Bool) -> Void
  let action: () -> Void

  @Environment(IOSAppStore.self) private var store

  /// The weekday and dates, a time per prayer, and the platter's padding.
  static let height: CGFloat = 132 + 76 * 6 + 16 * 2

  var body: some View {
    let zone = store.timeZone
    let start = day.start(in: zone)
    let events = availability.day?.events ?? []
    Button(action: action) {
      VStack(spacing: 0) {
        VStack(spacing: 2) {
          Text(verbatim: time.date(start, template: "EEE"))
            .font(.callout.bold())
            .foregroundStyle(isToday ? TVTheme.accentText : TVTheme.labelPrimary)
          Text(verbatim: time.date(start, template: "d MMM"))
            .font(.caption.weight(.medium))
            .foregroundStyle(TVTheme.labelSecondary)
          Text(verbatim: hijri(start))
            .font(.caption.weight(.medium))
            .foregroundStyle(TVTheme.labelSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(width: 172, height: 132)
        ForEach(PrayerKind.allCases, id: \.self) { kind in
          let event = events.first { $0.kind == kind }
          Text(verbatim: event.map { time.time24($0.time) } ?? "—")
            .font(.headline.weight(isToday ? .bold : .medium))
            .monospacedDigit()
            .foregroundStyle(event == nil ? TVTheme.labelSecondary : TVTheme.labelPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 172, height: 76)
        }
      }
      .padding(16)
    }
    .buttonStyle(TVPlatterButtonStyle())
    .accessibilityLabel(accessibility(start: start, events: events))
    .accessibilityAction(named: copy("Previous week", "الأسبوع السابق")) { turnWeek(false) }
    .accessibilityAction(named: copy("Next week", "الأسبوع التالي")) { turnWeek(true) }
    .accessibilityIdentifier("week.day.\(day)")
  }

  private func hijri(_ date: Date) -> String {
    let value = SalahText(locale: store.locale, timeZone: store.timeZone)
      .hijri(date, dayOffset: store.preferences.hijriOffset)
    return "\(value.day) \(value.month)"
  }

  private var copy: TVCopy { TVCopy(locale: store.locale) }

  private func accessibility(start: Date, events: [PrayerEvent]) -> String {
    return
      ([time.date(start, template: "EEEEdMMMM")] + (isToday ? [copy("Today", "اليوم")] : [])
      + [hijri(start)]
      + PrayerKind.allCases.map { kind in
        let event = events.first { $0.kind == kind }
        let name = event.map(store.names.name(of:)) ?? store.names.name(of: kind)
        return name + " " + (event.map { time.time($0.time) } ?? copy("Not available", "غير متاح"))
      }).joined(separator: ", ")
  }
}
