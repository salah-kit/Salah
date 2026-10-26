import SalahCore
import SalahTimes
import SalahUI
import SwiftUI
import UIKit

struct IOSTodayView: View {
  @Environment(IOSAppStore.self) private var store
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.openURL) private var openURL

  private var copy: IOSPrayerScreenCopy { IOSPrayerScreenCopy(locale: store.locale) }

  var body: some View {
    IOSDisplayGeometryReader { geometry in
      Group {
        if let display = store.display {
          switch layout(in: geometry) {
          case .pages(let pages): foldPages(display, pages: pages, geometry: geometry)
          case .wide: scrolling { wideColumns(display, width: geometry.size.width) }
          case .sideBySide: scrolling { sideBySide(display, geometry: geometry) }
          case .stacked: scrolling { stacked(display, geometry: geometry) }
          }
        } else if let pages = geometry.pages {
          // Beside a fold, the recovery keeps to the first page.
          scrolling { locationRecovery.padding(16) }
            .frame(
              width: pages.axis == .vertical ? pages.first.length : nil,
              height: pages.axis == .horizontal ? pages.first.length : nil
            )
            .padding(pages.axis == .vertical ? .leading : .top, pages.first.lowerBound)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
          scrolling {
            locationRecovery
              .padding(16)
              .frame(minHeight: max(0, geometry.size.height - 32), alignment: .top)
          }
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
      .background { IOSSkyBackground(phase: store.display?.phase ?? .neutral) }
    }
    .toolbar(.hidden, for: .navigationBar)
    .accessibilityIdentifier("today.screen")
  }

  private func layout(in geometry: IOSDisplayGeometry) -> IOSTodayLayout {
    IOSTodayLayout.resolve(
      size: geometry.size, pages: geometry.pages,
      isCompactHeight: verticalSizeClass == .compact, hasVerticalBar: geometry.hasVerticalBar,
      isAccessibilitySize: typeSize.isAccessibilitySize)
  }

  private func scrolling<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    ScrollView { content() }.scrollIndicators(.hidden)
  }

  private func stacked(_ display: SalahDisplay, geometry: IOSDisplayGeometry) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      dateHeader(display)
      hero(display)
      calculationGapBanner(display)
      prayerList(display)
      sun(display)
      calculationSummary
    }
    .frame(width: geometry.contentWidth)
    .padding(.leading, geometry.insets.leading)
    .padding(.trailing, geometry.insets.trailing)
    .padding(.top, geometry.topMargin)
    .padding(.bottom, 24)
  }

  private func wideColumns(_ display: SalahDisplay, width: CGFloat) -> some View {
    let columnsWidth = max(0, width - 120)
    return HStack(alignment: .top, spacing: 24) {
      VStack(spacing: 16) {
        dateHeader(display)
        hero(display)
        sun(display)
      }
      .frame(width: columnsWidth * 520 / 1_090)
      VStack(alignment: .leading, spacing: 16) {
        calculationGapBanner(display)
        prayerList(display)
        calculationSummary
      }
      .frame(maxWidth: .infinity)
    }
    .frame(width: max(0, width - 96))
    .padding(.horizontal, 48)
    .padding(.top, 8)
    .padding(.bottom, 32)
  }

  /// iPhone Duo standing closed on its side keeps the next prayer large enough to read from a
  /// distance, beside the day's prayers.
  private func sideBySide(_ display: SalahDisplay, geometry: IOSDisplayGeometry) -> some View {
    let column = max(0, (geometry.contentWidth - 16) / 2)
    return VStack(alignment: .leading, spacing: 16) {
      dateHeader(display)
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 16) {
          hero(display)
          sun(display)
          calculationSummary
        }
        .frame(width: column)
        VStack(alignment: .leading, spacing: 16) {
          calculationGapBanner(display)
          prayerList(display)
        }
        .frame(width: column)
      }
    }
    .frame(width: geometry.contentWidth)
    .padding(.leading, geometry.insets.leading)
    .padding(.trailing, geometry.insets.trailing)
    .padding(.top, max(8, geometry.topMargin))
    .padding(.bottom, 24)
  }

  /// iPhone Duo's inner display, flat or folded, opens Today like a book: the next prayer on the
  /// first page and the day on the second, beside each other or above and below. Each page
  /// scrolls on its own and nothing sits in the fold. Propped like a laptop, the controls lie on
  /// the lower half, so Stop moves there while audio plays.
  @ViewBuilder
  private func foldPages(
    _ display: SalahDisplay, pages: IOSFoldPages, geometry: IOSDisplayGeometry
  ) -> some View {
    switch pages.axis {
    case .vertical:
      HStack(spacing: 0) {
        scrolling {
          VStack(alignment: .leading, spacing: 16) {
            dateHeader(display)
            hero(display)
            sun(display)
          }
          .padding(.top, max(8, geometry.topMargin))
          .padding(.bottom, 24)
        }
        .frame(width: pages.first.length)
        Spacer(minLength: 0)
          .frame(width: pages.second.lowerBound - pages.first.upperBound)
        scrolling {
          VStack(alignment: .leading, spacing: 16) {
            calculationGapBanner(display)
            prayerList(display)
            calculationSummary
          }
          .padding(.top, max(8, geometry.topMargin))
          .padding(.bottom, 24)
        }
        .frame(width: pages.second.length)
      }
      .padding(.leading, pages.first.lowerBound)
      .frame(width: geometry.size.width, alignment: .leading)
    case .horizontal:
      VStack(spacing: 0) {
        scrolling {
          VStack(alignment: .leading, spacing: 16) {
            dateHeader(display)
            hero(display, showsStop: false)
          }
          .frame(width: geometry.contentWidth)
          .padding(.leading, geometry.insets.leading)
          .padding(.trailing, geometry.insets.trailing)
          .padding(.top, max(8, geometry.topMargin))
          .padding(.bottom, 16)
        }
        .frame(height: pages.first.length)
        Spacer(minLength: 0)
          .frame(height: pages.second.lowerBound - pages.first.upperBound)
        ScrollViewReader { proxy in
          scrolling {
            VStack(alignment: .leading, spacing: 16) {
              if display.playback != nil {
                IOSNowPlayingCard(display: display, onStop: store.stopPlayback)
                  .id(IOSNowPlayingCard.id)
              }
              calculationGapBanner(display)
              prayerList(display)
              calculationSummary
              sun(display)
            }
            .frame(width: geometry.contentWidth)
            .padding(.leading, geometry.insets.leading)
            .padding(.trailing, geometry.insets.trailing)
            .padding(.top, 8)
            .padding(.bottom, 24)
          }
          .onAppear { reveal(lowerPageAnchor(display), with: proxy, animated: false) }
          .onChange(of: lowerPageAnchor(display)) { _, anchor in
            reveal(anchor, with: proxy, animated: true)
          }
        }
        .frame(height: pages.second.length)
      }
      .padding(.top, pages.first.lowerBound)
      .frame(height: geometry.size.height, alignment: .top)
    }
  }

  /// What's playing, or else the prayer that has just started, or else the next one: the place
  /// the lower page keeps in view.
  private func lowerPageAnchor(_ display: SalahDisplay) -> String? {
    if display.playback != nil { return IOSNowPlayingCard.id }
    let model = IOSPrayerPresentation(display: display)
    let events: [PrayerEvent] = display.slots.compactMap {
      if case .event(let event) = $0 { event } else { nil }
    }
    let current = events.first {
      if case .justStarted = model.rowStatus(for: $0) { true } else { false }
    }
    let next = events.first {
      if case .next = model.rowStatus(for: $0) { true } else { false }
    }
    return (current ?? next).map { IOSPrayerDayCard.rowID($0.kind) }
  }

  private func reveal(_ anchor: String?, with proxy: ScrollViewProxy, animated: Bool) {
    guard let anchor else { return }
    Task { @MainActor in
      // Without an anchor point, scrolling stops as soon as the anchor is in view.
      withAnimation(animated && !reduceMotion ? .spring(response: 0.35, dampingFraction: 0.9) : nil)
      {
        proxy.scrollTo(anchor)
      }
    }
  }

  @ViewBuilder
  private func dateHeader(_ display: SalahDisplay) -> some View {
    let hijri = HijriDateFormat(
      locale: display.locale, timeZone: display.settings.location.timeZone,
      dayOffset: display.settings.hijriOffset
    ).components(of: display.date)
    let layout =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    layout {
      VStack(alignment: .leading, spacing: 2) {
        Text(
          verbatim:
            "\(display.header.hijriDay) \(display.header.hijriMonth) \(display.text.digits(hijri.year))"
        )
        .font(.title3.weight(.semibold))
        .accessibilityIdentifier("today.hijriDate")
        Text(verbatim: display.header.gregorianDate)
          .font(.subheadline)
          .foregroundStyle(IOSTheme.labelSecondary)
          .accessibilityIdentifier("today.gregorianDate")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      Button {
        showLocation()
      } label: {
        Label(display.header.location, systemImage: "location.fill")
          .font(.subheadline.weight(.semibold))
          .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.capsule)
      .controlSize(.small)
      .tint(.primary)
      .accessibilityLabel(copy("Location", "الموقع") + ", " + display.header.location)
      .accessibilityIdentifier("today.location")
    }
  }

  /// `showsStop` is false where Stop has moved to the lower half of a folded display.
  @ViewBuilder
  private func hero(_ display: SalahDisplay, showsStop: Bool = true) -> some View {
    let model = IOSPrayerPresentation(display: display)
    let state: IOSPrayerHeroState =
      display.playback != nil
      ? .playing
      : model.event == nil
        ? .unavailable
        : model.isCountingUp ? .current : model.isApproaching ? .approaching : .normal
    let stops = showsStop && display.playback != nil
    IOSPrayerHero(
      eyebrow: model.eyebrow, name: model.name, subtitle: model.subtitle,
      countdown: model.countdown, glyph: model.event.map(model.glyph(for:)) ?? "salah.isha",
      phase: display.phase, state: state, footer: heroFooter(model, display: display),
      stopTitle: stops ? display.labels.stopAudio : nil,
      onStop: stops ? { store.stopPlayback() } : nil
    )
    .accessibilityIdentifier("today.nextPrayer")
  }

  private func heroFooter(_ model: IOSPrayerPresentation, display: SalahDisplay) -> String? {
    if display.playback != nil {
      return model.playbackFooter(hasQueuedDua: store.playbackHasQueuedDua)
    }
    return model.footer
  }

  @ViewBuilder
  private func calculationGapBanner(_ display: SalahDisplay) -> some View {
    let model = IOSPrayerPresentation(display: display)
    if display.listedDay != nil, model.hasCalculationGaps {
      Button {
        store.handle(url: URL(string: "salah://calculation")!)
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "clock.badge.questionmark")
            .font(.system(size: 22))
            .frame(width: 22, height: 22)
            .foregroundStyle(IOSTheme.labelSecondary)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: model.calculationGapMessage)
              .font(.headline)
              .foregroundStyle(IOSTheme.labelPrimary)
              .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: copy("Calculation Settings", "إعدادات الحساب"))
              .font(.footnote.weight(.semibold))
              .foregroundStyle(IOSTheme.accentText)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: "chevron.forward")
            .font(.system(size: 14))
            .foregroundStyle(IOSTheme.labelSecondary)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          IOSTheme.groupedSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("today.calculationGap")
    }
  }

  private func prayerList(_ display: SalahDisplay) -> some View {
    IOSPrayerDayCard(
      display: display, title: copy("Today", "اليوم"), live: true,
      onAlert: store.toggleAlert(for:), onPlay: store.playPrayer(_:)
    )
    .accessibilityIdentifier("today.dayList")
  }

  @ViewBuilder
  private func sun(_ display: SalahDisplay) -> some View {
    if display.listedDay != nil {
      IOSCard {
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: copy("The sun today", "الشمس اليوم"))
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
          IOSSunArc(display: display)
        }
      }
      .accessibilityIdentifier("today.sunArc")
    }
  }

  private var calculationSummary: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button {
        store.handle(url: URL(string: "salah://calculation")!)
      } label: {
        Label(methodSummary, systemImage: "function")
          .font(.caption.weight(.semibold))
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.capsule)
      .controlSize(.small)
      .tint(.primary)
      .accessibilityIdentifier("today.calculation")
      Text(
        verbatim: copy("Calculated on this device for", "محسوبة على هذا الجهاز لموقع") + " "
          + (store.preferences.location?.name ?? copy("your location", "موقعك")) + "."
      )
      .font(.footnote)
      .foregroundStyle(IOSTheme.labelSecondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var methodSummary: String {
    let method: String
    if store.preferences.method == .custom {
      method = copy("Custom", "مخصص")
    } else {
      method = IOSCalculationMethod.preset(store.preferences.resolvedMethod).title(
        locale: store.locale)
    }
    let madhab =
      store.preferences.madhab == .hanafi ? copy("Hanafi", "حنفي") : copy("Shafi’i", "شافعي")
    return method + " · " + madhab
  }

  private var locationRecovery: some View {
    VStack(spacing: 20) {
      ContentUnavailableView {
        Label(
          copy("Location is off for Salah", "الموقع غير مفعّل لصلاة"),
          systemImage: "location.slash.fill")
      } description: {
        Text(
          verbatim: copy(
            "Allow location access, or choose a city to calculate your prayer times.",
            "اسمح بالوصول إلى الموقع، أو اختر مدينة لحساب أوقات الصلاة."))
      } actions: {
        Button(copy("Open Settings", "فتح الإعدادات")) {
          openURL(URL(string: UIApplication.openSettingsURLString)!)
        }
        .buttonStyle(.glassProminent)
        .tint(IOSTheme.accentFill)
        .accessibilityIdentifier("today.openSettings")
        Button(copy("Choose a City", "اختيار مدينة")) { showLocation() }
          .accessibilityIdentifier("today.chooseCity")
      }
    }
  }

  private func showLocation() { store.handle(url: URL(string: "salah://location")!) }
}

/// A day's rows are shared by Today and the selected day in Times.
struct IOSPrayerDayCard: View {
  let display: SalahDisplay
  let title: String
  var live = true
  var onAlert: (PrayerEvent) -> Void
  var onPlay: ((PrayerEvent) -> Void)? = nil

  private var model: IOSPrayerPresentation { IOSPrayerPresentation(display: display) }

  /// Both the scroll position and the journeys find a prayer's row by this identifier.
  static func rowID(_ kind: PrayerKind) -> String { "prayer.row." + kind.rawValue }

  var body: some View {
    IOSCard(padding: 6) {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: title)
          .font(.title3.weight(.semibold))
          .padding(.horizontal, 12)
          .padding(.top, 8)
          .padding(.bottom, 6)
          .accessibilityAddTraits(.isHeader)
        if display.slots.isEmpty {
          Label(display.labels.timesUnavailable, systemImage: "clock.badge.questionmark")
            .font(.body)
            .foregroundStyle(IOSTheme.labelSecondary)
            .padding(16)
        }
        ForEach(display.slots) { slot in
          switch slot {
          case .event(let event):
            IOSPrayerRow(
              name: display.name(of: event), time: display.timeText(of: event),
              detail: model.detail(for: event, live: live), state: rowState(event),
              glyph: model.glyph(for: event), alertEnabled: display.alerts(for: event).alert,
              currentLabel: rowState(event) == .current ? display.labels.now : nil,
              dayOffset: model.dayOffset(for: event), phase: display.phase,
              alertAccessibilityLabel: model.copy("Alert for", "تنبيه") + " "
                + display.name(of: event),
              onAlert: { onAlert(event) }
            )
            .id(Self.rowID(event.kind))
            .accessibilityIdentifier(Self.rowID(event.kind))
            .contextMenu {
              if let onPlay {
                Button(
                  model.copy("Play prayer sound", "تشغيل صوت الصلاة"), systemImage: "play.fill"
                ) {
                  onPlay(event)
                }
              }
            }
            .accessibilityAction(
              named: Text(verbatim: model.copy("Play prayer sound", "تشغيل صوت الصلاة"))
            ) {
              onPlay?(event)
            }
          case .missing(let kind):
            IOSPrayerRow(
              name: display.name(of: kind), time: "—",
              detail: model.missing[kind].map(model.missingDetail(_:)), state: .missing,
              glyph: "salah." + kind.rawValue, alertEnabled: false, onAlert: {}
            )
            .accessibilityIdentifier("prayer.missing." + kind.rawValue)
          }
        }
      }
      .padding(.bottom, 4)
    }
    .accessibilityElement(children: .contain)
  }

  private func rowState(_ event: PrayerEvent) -> IOSPrayerRowState {
    guard live else { return .upcoming }
    switch model.rowStatus(for: event) {
    case .passed: return .past
    case .justStarted: return .current
    case .next(let approaching): return approaching ? .approaching : .next
    case .upcoming: return .upcoming
    }
  }
}

/// What's playing, and Stop, on the half of a folded display that lies on the table.
private struct IOSNowPlayingCard: View {
  static let id = "today.nowPlaying"
  let display: SalahDisplay
  let onStop: () -> Void
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    let model = IOSPrayerPresentation(display: display)
    let colors = SalahColors(phase: display.phase, scheme: scheme, contrast: contrast)
    HStack(spacing: 12) {
      Image(systemName: "speaker.wave.2.fill")
        .font(.system(size: 20))
        .foregroundStyle(colors.phase.tint.color)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: model.eyebrow + " · " + model.name)
          .font(.headline)
          .foregroundStyle(IOSTheme.labelPrimary)
          .fixedSize(horizontal: false, vertical: true)
        Text(verbatim: model.subtitle)
          .font(.footnote)
          .foregroundStyle(IOSTheme.labelSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      Button(action: onStop) {
        Text(verbatim: display.labels.stopAudio)
          .foregroundStyle(IOSTheme.labelOnAccent)
      }
      .buttonStyle(.glassProminent)
      .controlSize(.large)
      .tint(IOSTheme.accentFill)
      .accessibilityIdentifier("today.stopAudio")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(
      IOSTheme.groupedSecondary,
      in: RoundedRectangle(cornerRadius: IOSMetrics.cardRadius, style: .continuous)
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(Self.id)
  }
}
