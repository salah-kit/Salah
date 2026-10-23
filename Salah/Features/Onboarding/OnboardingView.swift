import AppKit
import SalahUI
import SwiftUI

/// The first launch's welcome: a page at a time, each with its art, a title, why it
/// matters, the page dots and its buttons. Allow asks macOS, then moves on whatever the
/// answer.
struct OnboardingView: View {
  @State var flow: OnboardingFlow
  /// Asks macOS for the location, and returns once it has answered.
  let allowLocation: () async -> Void
  /// Asks macOS to alert, and returns once it has answered.
  let allowNotifications: () async -> Void
  /// Not Now on the notifications page.
  let deferNotifications: () -> Void
  /// The welcome is over; Salah's window opens on the destination.
  let finish: (OnboardingFlow.Destination) -> Void

  @State private var isAsking = false
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast

  private var palette: SalahPalette {
    SalahPalette(isDark: scheme == .dark, increasedContrast: contrast == .increased)
  }

  var body: some View {
    VStack(spacing: 14) {
      art
      Text(title)
        .font(.system(size: 22))
        .foregroundStyle(palette.labelPrimary.color)
        .multilineTextAlignment(.center)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
      Text(message)
        .font(.body)
        .foregroundStyle(palette.labelSecondary.color)
        .multilineTextAlignment(.center)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
      pageDots
      buttons
        .padding(.top, 10)
    }
    .padding(.horizontal, 40)
    // The design's 16 and 24, plus the 1 pt its window border takes at each edge.
    .padding(.top, 17)
    .padding(.bottom, 25)
    .frame(width: 480)
    .disabled(isAsking)
  }

  // MARK: Pieces

  @ViewBuilder
  private var art: some View {
    switch flow.page {
    case .welcome:
      // The icon's art fills 96 pt: macOS draws it on 824 of the image's 1,024 points.
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 96 * 1024 / 824, height: 96 * 1024 / 824)
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
    case .location:
      symbol("location.fill")
    case .notifications:
      symbol("bell.fill")
    }
  }

  private func symbol(_ name: String) -> some View {
    Image(systemName: name)
      .font(.system(size: 30))
      .foregroundStyle(palette.accent.color)
      .frame(width: 88, height: 88)
      .background(Circle().fill(palette.accentSubtle.color))
      .accessibilityHidden(true)
  }

  private var pageDots: some View {
    HStack(spacing: 6) {
      ForEach(Array(flow.pages.enumerated()), id: \.offset) { index, _ in
        Circle()
          .fill(
            (index == flow.index ? palette.labelPrimary : palette.fillSecondary).color
          )
          .frame(width: 6, height: 6)
      }
    }
    .frame(height: 12, alignment: .bottom)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private var buttons: some View {
    HStack(spacing: 10) {
      Spacer(minLength: 0)
      switch flow.page {
      case .welcome:
        prominent("onboarding.continue") { advance() }
      case .location:
        Button("onboarding.location.chooseCity") {
          if let destination = flow.chooseCity() { finish(destination) }
        }
        .buttonStyle(.bordered)
        prominent("onboarding.location.allow") {
          ask(allowLocation)
        }
      case .notifications:
        Button("onboarding.notifications.notNow") {
          deferNotifications()
          advance()
        }
        .buttonStyle(.bordered)
        prominent("onboarding.notifications.allow") {
          ask(allowNotifications)
        }
      }
    }
    .controlSize(.large)
    .buttonBorderShape(.capsule)
  }

  /// The page's main action, the default button: the gold fill with dark text.
  private func prominent(_ title: LocalizedStringKey, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Text(title).foregroundStyle(palette.labelOnAccent.color)
    }
    .buttonStyle(.borderedProminent)
    .tint(palette.accentFill.color)
    .keyboardShortcut(.defaultAction)
  }

  private func ask(_ request: @escaping () async -> Void) {
    isAsking = true
    Task {
      await request()
      isAsking = false
      advance()
    }
  }

  private func advance() {
    if let destination = flow.advance() { finish(destination) }
  }

  // MARK: Text

  private var title: LocalizedStringKey {
    switch flow.page {
    case .welcome: "onboarding.welcome.title"
    case .location: "onboarding.location.title"
    case .notifications: "onboarding.notifications.title"
    }
  }

  private var message: LocalizedStringKey {
    switch flow.page {
    case .welcome: "onboarding.welcome.message"
    case .location: "onboarding.location.message"
    case .notifications: "onboarding.notifications.message"
    }
  }
}
