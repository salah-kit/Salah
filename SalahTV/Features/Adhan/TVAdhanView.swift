import SalahCore
import SalahUI
import SwiftUI

/// A prayer's adhan, full screen while it plays. Stop has focus; Stop, Play/Pause and Back
/// all stop it. The day's ribbon and the next prayer sit at the bottom.
struct TVAdhanView: View {
  let event: PrayerEvent

  @Environment(IOSAppStore.self) private var store
  @Environment(TVAppRuntime.self) private var runtime
  @Environment(TVAudioService.self) private var audio
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  @FocusState private var stopFocused: Bool

  var body: some View {
    let display = store.display
    let copy = TVCopy(locale: store.locale)
    let time = TVTimeText(locale: store.locale, timeZone: store.timeZone)
    let phase =
      display.map {
        $0.settings.followsTimeOfDay
          ? SalahPhase.at(event.time, events: $0.listedDay?.events ?? [event]) : .neutral
      } ?? .neutral
    ZStack {
      TVSkyBackground(phase: phase)
      VStack(spacing: 0) {
        TVPrayerGlyph(
          name: event.glyphName, size: 132,
          color: SalahColors(phase: phase, scheme: scheme, contrast: contrast).phase.tint.color)
        Label {
          Text(verbatim: playing(copy))
        } icon: {
          Image(systemName: "waveform").accessibilityHidden(true)
        }
        .font(.callout.bold())
        .foregroundStyle(TVTheme.accentText)
        .padding(.top, 28)
        Text(verbatim: store.names.name(of: event))
          .font(.title.bold())
          .foregroundStyle(TVTheme.labelPrimary)
        Text(
          verbatim: [time.time(event.time), store.preferences.location?.name ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        )
        .font(.title3.weight(.medium))
        .foregroundStyle(TVTheme.labelSecondary)
        Button {
          runtime.stopAdhan()
        } label: {
          Label(copy("Stop", "إيقاف"), systemImage: "stop.fill")
        }
        .focused($stopFocused)
        .padding(.top, 44)
        .accessibilityIdentifier("adhan.stop")
        Text(
          verbatim: copy(
            "Play/Pause on the remote also stops it",
            "زر التشغيل/الإيقاف المؤقت في جهاز التحكم يوقفه أيضًا")
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(TVTheme.labelSecondary)
        .padding(.top, 22)
        if audio.hasQueuedDua {
          Text(verbatim: copy("The du’a after the adhan follows", "يلي الأذان الدعاء"))
            .font(.callout.weight(.medium))
            .foregroundStyle(TVTheme.labelSecondary)
            .padding(.top, 14)
        }
        Spacer(minLength: 24)
        if let display, let day = display.listedDay {
          TVDayRibbon(
            day: day, date: display.date, followsTimeOfDay: display.settings.followsTimeOfDay,
            barHeight: 22.5, knobSize: 52.5, knobStroke: 7.5
          )
          .frame(width: 1200)
          if let next = display.prayerState?.nextPrayer {
            let remaining = TVPrayerPresentation(display: display, preferences: store.preferences)
              .detail(for: next)
            Text(
              verbatim: [
                copy.format(
                  "%1$@ at %2$@", "%1$@ %2$@", store.names.name(of: next), time.time(next.time)),
                remaining,
              ].compactMap { $0 }.joined(separator: " · ")
            )
            .font(.callout.weight(.medium))
            .foregroundStyle(TVTheme.labelSecondary)
            .padding(.top, 20)
          }
        }
      }
      .multilineTextAlignment(.center)
      .padding(.top, 150)
      .padding(.bottom, 82)
      .padding(.horizontal, TVMetrics.safeHorizontal)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .ignoresSafeArea()
    .defaultFocus($stopFocused, true)
    .onPlayPauseCommand { runtime.stopAdhan() }
    .onExitCommand { runtime.stopAdhan() }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("adhan")
  }

  /// What's playing: the du'a, the adhan, or the soft tone, which isn't called an adhan.
  private func playing(_ copy: TVCopy) -> String {
    let display = store.display
    if audio.isPlayingDua {
      return display?.labels.playingDua ?? copy("Playing du’a", "يُتلى الدعاء")
    }
    let sound = store.preferences.tvSound(for: event.kind, observance: event.observance)
    if sound == .softTone { return TVSettingsCopy(locale: store.locale).sound(.softTone) }
    return display?.labels.playingAdhan ?? copy("Playing adhan", "يُرفع الأذان")
  }
}
