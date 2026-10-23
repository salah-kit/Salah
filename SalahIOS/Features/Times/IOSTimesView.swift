import SalahCore
import SalahTimes
import SalahUI
import SwiftUI

struct IOSTimesView: View {
  private enum Mode: String, CaseIterable { case day, week }

  @Environment(IOSAppStore.self) private var store
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  @State private var mode: Mode = .day
  @State private var showsDatePicker = false
  @State private var tableWidth: CGFloat = 370

  private var copy: IOSPrayerScreenCopy { IOSPrayerScreenCopy(locale: store.locale) }
  private var wideLayout: Bool { sizeClass == .regular && !typeSize.isAccessibilitySize }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if wideLayout {
          HStack {
            Text(verbatim: copy("Times", "الأوقات"))
              .font(.largeTitle.bold())
              .accessibilityAddTraits(.isHeader)
            Spacer()
            modePicker.frame(width: 280)
          }
        } else {
          modePicker
        }
        dateNavigator
          .frame(maxWidth: wideLayout ? 560 : .infinity)
          .frame(maxWidth: .infinity)
        if store.preferences.location == nil {
          ContentUnavailableView {
            Label(copy("Choose your location", "اختر موقعك"), systemImage: "location.slash.fill")
          } description: {
            Text(
              verbatim: copy(
                "Choose a city to see its prayer times.", "اختر مدينة لعرض أوقات الصلاة فيها."))
          } actions: {
            Button(copy("Choose a City", "اختيار مدينة")) { showLocation() }
              .buttonStyle(.glassProminent)
              .accessibilityIdentifier("times.chooseCity")
          }
        } else if mode == .day {
          dayList
        } else {
          weekTable
        }
        if store.preferences.location != nil { calculationFooter }
      }
      .frame(maxWidth: 1_200)
      .padding(.horizontal, wideLayout ? 48 : 16)
      .padding(.top, wideLayout ? 24 : 8)
      .padding(.bottom, 24)
      .frame(maxWidth: .infinity)
    }
    .background { IOSSkyBackground(phase: store.display?.phase ?? .neutral) }
    .navigationTitle(copy("Times", "الأوقات"))
    .navigationBarTitleDisplayMode(.large)
    .toolbar(wideLayout ? .hidden : .visible, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(copy("Choose date", "اختيار تاريخ"), systemImage: "calendar") {
          showsDatePicker = true
        }
        .labelStyle(.iconOnly)
        .accessibilityIdentifier("times.calendar")
      }
    }
    .sheet(isPresented: $showsDatePicker) { datePicker }
    .accessibilityIdentifier("times.screen")
  }

  private var modePicker: some View {
    Picker(copy("View", "العرض"), selection: $mode) {
      Text(verbatim: copy("Day", "يوم")).tag(Mode.day).accessibilityIdentifier("times.day")
      Text(verbatim: copy("Week", "أسبوع")).tag(Mode.week).accessibilityIdentifier("times.week")
    }
    .pickerStyle(.segmented)
    .accessibilityIdentifier("times.mode")
  }

  private var dateNavigator: some View {
    HStack(spacing: 8) {
      Button(copy("Previous", "السابق"), systemImage: "chevron.backward") { moveDate(-1) }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .controlSize(.large)
        .accessibilityIdentifier("times.previous")
      Button {
        showsDatePicker = true
      } label: {
        VStack(spacing: 2) {
          Text(verbatim: dateTitle)
            .font(.headline)
            .foregroundStyle(IOSTheme.labelPrimary)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("times.date")
          Text(verbatim: hijriTitle)
            .font(.subheadline)
            .foregroundStyle(IOSTheme.labelSecondary)
            .multilineTextAlignment(.center)
        }
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .combine)
      Button(copy("Next", "التالي"), systemImage: "chevron.forward") { moveDate(1) }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .controlSize(.large)
        .accessibilityIdentifier("times.next")
    }
  }

  @ViewBuilder
  private var dayList: some View {
    if let display = selectedDisplay {
      IOSPrayerDayCard(
        display: display,
        title: store.preferences.location?.name ?? copy("Prayer times", "أوقات الصلاة"),
        live: store.selectedDay == store.today, onAlert: store.toggleAlert(for:),
        onPlay: store.playPrayer(_:)
      )
      .accessibilityIdentifier("times.dayList")
    } else {
      unavailable
    }
  }

  private var weekTable: some View {
    IOSCard(padding: wideLayout ? 12 : 8) {
      ScrollView(.horizontal, showsIndicators: false) {
        VStack(spacing: 2) {
          HStack(alignment: .bottom, spacing: 0) {
            Color.clear.frame(width: wideLayout ? 220 : 50, height: 1)
            ForEach(PrayerKind.allCases, id: \.self) { kind in
              VStack(spacing: 2) {
                IOSPrayerGlyph(name: "salah." + kind.rawValue, size: wideLayout ? 22 : 18)
                Text(verbatim: store.names.name(of: kind))
                  .font(wideLayout ? .footnote.weight(.semibold) : .caption2)
                  .fixedSize(horizontal: false, vertical: true)
              }
              .foregroundStyle(IOSTheme.labelSecondary)
              .frame(maxWidth: .infinity)
            }
          }
          .padding(.horizontal, wideLayout ? 12 : 6)
          .padding(.top, 4)
          .padding(.bottom, 4)
          .accessibilityHidden(true)
          ForEach(store.weekDays, id: \.self) { day in
            weekRow(day)
          }
        }
        .frame(
          width: max(tableWidth - (wideLayout ? 24 : 16), typeSize.isAccessibilitySize ? 780 : 330)
        )
        .padding(.bottom, 8)
      }
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      tableWidth = $0
    }
    .accessibilityIdentifier("times.weekTable")
  }

  private func weekRow(_ day: CivilDay) -> some View {
    let events = store.schedule?.day(day).day?.events ?? []
    let isToday = day == store.today
    return Button {
      store.selectedDay = day
      mode = .day
    } label: {
      HStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
          if wideLayout {
            HStack(spacing: 6) {
              Text(verbatim: formatted(day, template: "EEEE"))
                .font(.headline)
                .foregroundStyle(IOSTheme.labelPrimary)
              Text(verbatim: formatted(day, template: "d MMMM"))
                .font(.body)
                .foregroundStyle(IOSTheme.labelSecondary)
            }
            Text(verbatim: hijriDate(day))
              .font(.footnote)
              .foregroundStyle(IOSTheme.labelSecondary)
          } else {
            Text(verbatim: formatted(day, template: "EEE"))
              .font(.caption.weight(.semibold))
              .foregroundStyle(IOSTheme.labelSecondary)
            Text(verbatim: digits(day.day))
              .font(.headline)
              .foregroundStyle(IOSTheme.labelPrimary)
          }
        }
        .frame(width: wideLayout ? 220 : 50, alignment: .leading)
        ForEach(PrayerKind.allCases, id: \.self) { kind in
          Text(verbatim: events.first(where: { $0.kind == kind }).map(weekTime(_:)) ?? "—")
            .font(wideLayout ? .body.monospacedDigit() : .footnote.monospacedDigit())
            .foregroundStyle(IOSTheme.labelPrimary)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity)
        }
      }
      .padding(.horizontal, wideLayout ? 12 : 6)
      .padding(.vertical, wideLayout ? 9 : 7)
      .background(
        isToday ? todayTint : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(weekAccessibility(day, events: events))
    .accessibilityHint(copy("Show this day", "عرض هذا اليوم"))
    .accessibilityIdentifier("times.day." + day.description)
  }

  private var unavailable: some View {
    IOSCard {
      ContentUnavailableView {
        Label(
          copy("Times unavailable", "الأوقات غير متاحة"), systemImage: "clock.badge.questionmark")
      } description: {
        Text(
          verbatim: copy(
            "No prayer times are available for this date. Review calculation settings.",
            "لا تتوفر أوقات الصلاة لهذا التاريخ. راجع إعدادات الحساب."))
      } actions: {
        Button(copy("Calculation", "الحساب")) {
          store.handle(url: URL(string: "salah://calculation")!)
        }
      }
    }
  }

  private var calculationFooter: some View {
    let method =
      store.preferences.method == .custom
      ? copy("Custom", "مخصص")
      : IOSCalculationMethod.preset(store.preferences.resolvedMethod).title(
        locale: store.locale)
    let madhab =
      store.preferences.madhab == .hanafi ? copy("Hanafi", "حنفي") : copy("Shafi’i", "شافعي")
    let location = store.preferences.location?.name ?? copy("your location", "موقعك")
    return Text(
      verbatim: method + " · " + madhab + ". "
        + copy("Times for", "الأوقات لموقع") + " " + location + ", "
        + (store.timeZone.localizedName(for: .generic, locale: store.locale)
          ?? store.timeZone.identifier)
    )
    .font(.footnote)
    .foregroundStyle(IOSTheme.labelSecondary)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 16)
  }

  private var datePicker: some View {
    NavigationStack {
      DatePicker(
        copy("Date", "التاريخ"),
        selection: Binding(
          get: { store.selectedDay.start(in: store.timeZone) },
          set: { store.selectedDay = CivilDay(containing: $0, in: store.timeZone) }),
        displayedComponents: .date
      )
      .datePickerStyle(.graphical)
      .padding()
      .environment(\.timeZone, store.timeZone)
      .navigationTitle(copy("Choose date", "اختيار تاريخ"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(copy("Today", "اليوم")) { store.selectedDay = store.today }
            .accessibilityIdentifier("times.calendar.today")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(copy("Done", "تم"), systemImage: "checkmark") { showsDatePicker = false }
            .labelStyle(.iconOnly)
            .accessibilityIdentifier("times.calendar.done")
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private var selectedDisplay: SalahDisplay? {
    guard let settings = store.settings, let schedule = store.schedule else { return nil }
    return SalahDisplay(
      date: store.now, settings: settings,
      day: store.selectedDayAvailability ?? .unavailable(.noPublishedData),
      state: schedule.state(
        at: store.now, through: store.now.addingTimeInterval(SalahDisplay.lookahead),
        policy: SalahDisplay.policy),
      playback: store.playback)
  }

  private var dateTitle: String {
    guard mode == .week, let first = store.weekDays.first, let last = store.weekDays.last else {
      return formatted(store.selectedDay, template: "EEEE d MMMM yyyy")
    }
    let formatter = DateIntervalFormatter()
    formatter.locale = store.locale
    formatter.timeZone = store.timeZone
    formatter.dateTemplate = "d MMMM yyyy"
    return formatter.string(
      from: first.start(in: store.timeZone), to: last.start(in: store.timeZone))
  }

  private var hijriTitle: String {
    let day = mode == .week ? (store.weekDays.first ?? store.selectedDay) : store.selectedDay
    let text = SalahText(locale: store.locale, timeZone: store.timeZone)
    let value = text.hijri(day.start(in: store.timeZone), dayOffset: store.preferences.hijriOffset)
    guard mode == .week, let last = store.weekDays.last else {
      return "\(value.day) \(value.month) \(value.year)"
    }
    let end = text.hijri(last.start(in: store.timeZone), dayOffset: store.preferences.hijriOffset)
    if value.month == end.month, value.year == end.year {
      return "\(value.day) – \(end.day) \(value.month) \(value.year)"
    }
    return "\(value.day) \(value.month) – \(end.day) \(end.month) \(end.year)"
  }

  private var todayTint: Color {
    SalahColors(phase: .dhuhr, scheme: scheme, contrast: contrast).phase.tintSubtle.color
  }

  private func formatted(_ day: CivilDay, template: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = store.locale
    formatter.timeZone = store.timeZone
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: day.start(in: store.timeZone))
  }

  private func weekTime(_ event: PrayerEvent) -> String {
    let formatter = DateFormatter()
    formatter.locale = store.locale
    formatter.timeZone = store.timeZone
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: event.time).bidiIsolated
  }

  private func digits(_ value: Int) -> String {
    SalahText(locale: store.locale, timeZone: store.timeZone).digits(value)
  }

  private func hijriDate(_ day: CivilDay) -> String {
    let value = SalahText(locale: store.locale, timeZone: store.timeZone).hijri(
      day.start(in: store.timeZone), dayOffset: store.preferences.hijriOffset)
    return "\(value.day) \(value.month) \(value.year)"
  }

  private func weekAccessibility(_ day: CivilDay, events: [PrayerEvent]) -> String {
    let text = SalahText(locale: store.locale, timeZone: store.timeZone)
    return
      ([formatted(day, template: "EEEE d MMMM yyyy")]
      + PrayerKind.allCases.map { kind in
        let event = events.first { $0.kind == kind }
        let name = event.map(store.names.name(of:)) ?? store.names.name(of: kind)
        return name + " "
          + (event.map { text.timeFormatter().string(from: $0.time) }
            ?? copy("not available", "غير متاح"))
      }).joined(separator: ", ")
  }

  private func moveDate(_ direction: Int) {
    store.selectedDay = store.selectedDay.adding(days: direction * (mode == .week ? 7 : 1))
  }

  private func showLocation() { store.handle(url: URL(string: "salah://location")!) }
}
