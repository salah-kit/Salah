import SalahCore
import SalahTimes
import SalahUI
import SwiftUI
import UIKit

struct IOSTodayView: View {
  @Environment(IOSAppStore.self) private var store
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.openURL) private var openURL

  private var copy: IOSPrayerScreenCopy { IOSPrayerScreenCopy(locale: store.locale) }

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        if let display = store.display {
          let wide = geometry.size.width >= 740 && !typeSize.isAccessibilitySize
          if wide {
            let columnsWidth = max(0, geometry.size.width - 120)
            HStack(alignment: .top, spacing: 24) {
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
            .frame(width: max(0, geometry.size.width - 96))
            .padding(.horizontal, 48)
            .padding(.top, 24)
            .padding(.bottom, 32)
          } else {
            VStack(alignment: .leading, spacing: 16) {
              dateHeader(display)
              hero(display)
              calculationGapBanner(display)
              prayerList(display)
              sun(display)
              calculationSummary
            }
            .frame(width: max(0, geometry.size.width - 32))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
          }
        } else {
          locationRecovery
            .padding(16)
            .frame(minHeight: max(0, geometry.size.height - 32), alignment: .top)
        }
      }
      .frame(width: geometry.size.width)
      .background { IOSSkyBackground(phase: store.display?.phase ?? .neutral) }
      .scrollIndicators(.hidden)
    }
    .toolbar(.hidden, for: .navigationBar)
    .accessibilityIdentifier("today.screen")
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

  @ViewBuilder
  private func hero(_ display: SalahDisplay) -> some View {
    let model = IOSPrayerPresentation(display: display)
    let state: IOSPrayerHeroState =
      display.playback != nil
      ? .playing
      : model.event == nil
        ? .unavailable
        : model.isCountingUp ? .current : model.isApproaching ? .approaching : .normal
    IOSPrayerHero(
      eyebrow: model.eyebrow, name: model.name, subtitle: model.subtitle,
      countdown: model.countdown, glyph: model.event.map(model.glyph(for:)) ?? "salah.isha",
      phase: display.phase, state: state, footer: heroFooter(model, display: display),
      stopTitle: display.playback == nil ? nil : display.labels.stopAudio,
      onStop: display.playback == nil
        ? nil
        : {
          store.stopPlayback()
        }
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
            .accessibilityIdentifier("prayer.row." + event.kind.rawValue)
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
