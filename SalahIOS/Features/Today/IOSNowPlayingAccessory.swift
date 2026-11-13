import SalahCore
import SalahUI
import SwiftUI

/// What's playing, with Stop, above the tab bar on every tab.
///
/// The tab bar's accessory can be switched off from iOS 26.1. On iOS 26.0 it always draws its
/// capsule, even empty, so there each tab shows the same content above the bar instead.
nonisolated enum IOSNowPlayingPlacement: Sendable {
  case tabBarAccessory, aboveTabBar

  /// `-salah.ios.nowPlayingAboveTabBar` runs the iOS 26.0 placement on a later system.
  static let current: IOSNowPlayingPlacement = {
    if ProcessInfo.processInfo.arguments.contains("-salah.ios.nowPlayingAboveTabBar") {
      return .aboveTabBar
    }
    if #available(iOS 26.1, *) { return .tabBarAccessory }
    return .aboveTabBar
  }()
}

extension View {
  /// On the tab view: the accessory, where the system can hide it while nothing plays.
  @ViewBuilder func iosNowPlayingAccessory() -> some View {
    if #available(iOS 26.1, *), IOSNowPlayingPlacement.current == .tabBarAccessory {
      modifier(IOSNowPlayingAccessory())
    } else {
      self
    }
  }

  /// On each tab's content: the same bar above the tab bar where there's no accessory.
  func iosNowPlayingInset() -> some View { modifier(IOSNowPlayingInset()) }
}

@available(iOS 26.1, *)
private struct IOSNowPlayingAccessory: ViewModifier {
  @Environment(IOSAppStore.self) private var store

  func body(content: Content) -> some View {
    content.tabViewBottomAccessory(isEnabled: store.display?.playback != nil) {
      if let display = store.display, display.playback != nil {
        IOSNowPlayingBar(display: display, onStop: store.stopPlayback)
          .padding(.horizontal, 16)
      }
    }
  }
}

private struct IOSNowPlayingInset: ViewModifier {
  @Environment(IOSAppStore.self) private var store

  func body(content: Content) -> some View {
    content.safeAreaInset(edge: .bottom, spacing: 0) {
      if IOSNowPlayingPlacement.current == .aboveTabBar, let display = store.display,
        display.playback != nil
      {
        IOSNowPlayingBar(display: display, onStop: store.stopPlayback)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .glassEffect(.regular, in: .capsule)
          .padding(.horizontal, 16)
          .padding(.bottom, 8)
      }
    }
  }
}

/// One line: what's playing, and Stop.
struct IOSNowPlayingBar: View {
  let display: SalahDisplay
  let onStop: () -> Void
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    let model = IOSPrayerPresentation(display: display)
    let colors = SalahColors(phase: display.phase, scheme: scheme, contrast: contrast)
    HStack(spacing: 10) {
      Image(systemName: "speaker.wave.2.fill")
        .font(.system(size: 17))
        .foregroundStyle(colors.phase.tint.color)
        .accessibilityHidden(true)
      Text(verbatim: model.eyebrow + " · " + model.name)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(IOSTheme.labelPrimary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("nowPlaying.title")
      Button(action: onStop) {
        Label(display.labels.stopAudio, systemImage: "stop.fill")
          .labelStyle(.iconOnly)
          .font(.system(size: 17, weight: .semibold))
          .frame(width: IOSMetrics.hitTarget, height: 32)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .foregroundStyle(IOSTheme.accentText)
      .accessibilityIdentifier("nowPlaying.stop")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("nowPlaying.bar")
  }
}
