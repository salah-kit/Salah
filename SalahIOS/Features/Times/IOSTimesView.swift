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
    IOSDisplayGeometryReader { geometry in
      // Beside iPhone Duo's vertical bar the navigation bar stays, so the calendar moves to the
      // side bar with the title above the content; the tablet shows its own title row instead.
      let barsAtSide = geometry.hasVerticalBar
      let pages = geometry.pages.flatMap { $0.axis == .vertical ? $0 : nil }
      let insets = contentInsets(geometry)
      // At accessibility sizes Times keeps its one column, on the first page.
      let firstPageColumn = typeSize.isAccessibilitySize ? pages?.first.length : nil
      ScrollView {
        content(
          barsAtSide: barsAtSide, pages: firstPageColumn == nil ? pages : nil,
          weekColumns: typeSize.isAccessibilitySize
            ? nil
            : IOSWeekColumns(
              rowStart: insets.leading + 24, rowEnd: geometry.size.width - insets.trailing - 24,
              fold: pages == nil ? nil : geometry.fold)
        )
        .frame(maxWidth: geometry.fold == nil && !barsAtSide ? 1_200 : .infinity)
        .frame(width: firstPageColumn)
        .padding(.leading, insets.leading)
        .padding(.trailing, insets.trailing)
        .padding(.top, max(8, geometry.topMargin))
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: firstPageColumn == nil ? .center : .leading)
      }
      .toolbar(wideLayout && !barsAtSide ? .hidden : .visible, for: .navigationBar)
    }
    .background { IOSSkyBackground(phase: store.display?.phase ?? .neutral) }
    .navigationTitle(copy("Times", "الأوقات"))
    .navigationBarTitleDisplayMode(.large)
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

  /// The tablet's wide layout keeps its 48-point margins; iPhone Duo's displays follow the system.
  private func contentInsets(_ geometry: IOSDisplayGeometry) -> IOSContentInsets {
    if geometry.hasVerticalBar || geometry.fold != nil || !wideLayout { return geometry.insets }
    return IOSContentInsets(leading: 48, trailing: 48)
  }

  @ViewBuilder
  private func content(barsAtSide: Bool, pages: IOSFoldPages?, weekColumns: IOSWeekColumns?)
    -> some View
  {
    VStack(alignment: .leading, spacing: 16) {
      if wideLayout, barsAtSide, let pages {
        // The fold separates the date's buttons from the day and week choice.
        HStack(spacing: 0) {
          dateNavigator.frame(width: pages.first.length)
          Spacer(minLength: pages.second.lowerBound - pages.first.upperBound)
          modePicker.frame(width: min(280, pages.second.length))
        }
      } else if wideLayout {
        HStack {
          if !barsAtSide {
            Text(verbatim: copy("Times", "الأوقات"))
              .font(.largeTitle.bold())
              .accessibilityAddTraits(.isHeader)
          }
          Spacer()
          modePicker.frame(width: 280)
        }
        dateNavigator
          .frame(maxWidth: 560)
          .frame(maxWidth: .infinity)
      } else {
        modePicker
        dateNavigator
      }
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
        .frame(maxWidth: pages?.first.length)
      } else if mode == .day {
        dayList.frame(maxWidth: selectedDisplay == nil ? pages?.first.length : nil)
      } else {
        weekTable(columns: weekColumns)
      }
      if store.preferences.location != nil {
        // Beside a fold, the footer wraps on the first page.
        calculationFooter.frame(maxWidth: pages?.first.length, alignment: .leading)
      }
    }
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

  /// `columns` puts iPhone Duo's fold between Dhuhr and Asr; without them, columns share the width.
  private func weekTable(columns: IOSWeekColumns?) -> some View {
    IOSCard(padding: wideLayout ? 12 : 8) {
      ScrollView(.horizontal, showsIndicators: false) {
        // Rows start at the leading edge, where the week's columns are measured from.
        VStack(alignment: .leading, spacing: 2) {
          HStack(alignment: .bottom, spacing: 0) {
            Color.clear.frame(width: dayColumnWidth(columns), height: 1)
            prayerCells(columns) { kind in
              VStack(spacing: 2) {
                IOSPrayerGlyph(name: "salah." + kind.rawValue, size: wideLayout ? 22 : 18)
                Text(verbatim: store.names.name(of: kind))
                  .font(wideLayout ? .footnote.weight(.semibold) : .caption2)
                  .fixedSize(horizontal: false, vertical: true)
              }
              .foregroundStyle(IOSTheme.labelSecondary)
            }
          }
          .padding(.horizontal, wideLayout ? 12 : 6)
          .padding(.top, 4)
          .padding(.bottom, 4)
          .accessibilityHidden(true)
          ForEach(store.weekDays, id: \.self) { day in
            weekRow(day, columns: columns)
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

  private func dayColumnWidth(_ columns: IOSWeekColumns?) -> CGFloat {
    columns?.day ?? (wideLayout ? 220 : 50)
  }

  /// A header or day row's six prayer cells, leaving the fold's gap after Dhuhr.
  private func prayerCells<Cell: View>(
    _ columns: IOSWeekColumns?, @ViewBuilder cell: @escaping (PrayerKind) -> Cell
  ) -> some View {
    ForEach(PrayerKind.allCases, id: \.self) { kind in
      if let columns {
        cell(kind).frame(width: columns.prayer)
        if kind == .dhuhr { Color.clear.frame(width: columns.gap, height: 1) }
      } else {
        cell(kind).frame(maxWidth: .infinity)
      }
    }
  }

  private func weekRow(_ day: CivilDay, columns: IOSWeekColumns?) -> some View {
    let events = store.schedule?.day(day).day?.events ?? []
    let isToday = day == store.today
    let text = SalahText(locale: store.locale, timeZone: store.timeZone)
    return Button {
      store.selectedDay = day
      mode = .day
    } label: {
      HStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
          // Two pages leave the day column room for its short form.
          if wideLayout && columns == nil {
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
            Text(verbatim: Self.dayNumber(day, text: text))
              .font(.headline)
              .foregroundStyle(IOSTheme.labelPrimary)
          }
        }
        .frame(width: dayColumnWidth(columns), alignment: .leading)
        prayerCells(columns) { kind in
          Text(verbatim: events.first(where: { $0.kind == kind }).map(weekTime(_:)) ?? "—")
            .font(wideLayout ? .body.monospacedDigit() : .footnote.monospacedDigit())
            .foregroundStyle(IOSTheme.labelPrimary)
            .fixedSize(horizontal: true, vertical: false)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
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
    Self.dateTitle(
      day: store.selectedDay, week: mode == .week ? store.weekDays : [],
      text: SalahText(locale: store.locale, timeZone: store.timeZone))
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
    SalahText(locale: store.locale, timeZone: store.timeZone).civilDate(
      day.start(in: store.timeZone), template: template)
  }

  private func weekTime(_ event: PrayerEvent) -> String {
    let formatter = DateFormatter()
    formatter.locale = store.locale
    formatter.timeZone = store.timeZone
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: event.time).bidiIsolated
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

extension IOSTimesView {
  /// The title's civil date: the day in full, or its week's range when `week` has days, in
  /// the calendar of `SalahText.gregorianDate(_:)`, so the Hijri date below never repeats.
  static func dateTitle(day: CivilDay, week: [CivilDay], text: SalahText) -> String {
    guard let first = week.first, let last = week.last else {
      return text.civilDate(day.start(in: text.timeZone), template: "EEEE d MMMM yyyy")
    }
    return text.civilRange(
      from: first.start(in: text.timeZone), to: last.start(in: text.timeZone),
      template: "d MMMM yyyy")
  }

  /// A week row's day of the month, in the title's calendar and the locale's digits, so in
  /// Persian it's the Solar Hijri day, as the title's range is.
  static func dayNumber(_ day: CivilDay, text: SalahText) -> String {
    text.civilDate(day.start(in: text.timeZone), template: "d")
  }
}
