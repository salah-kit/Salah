import SalahCore
import SwiftUI

/// Setup: the reason first, then the system's location prompt. Allow Once is enough,
/// because an Apple TV doesn't move; choosing a city needs no permission. Setup completes
/// once there's a location, and the calculation follows the country.
struct TVOnboardingView: View {
  @Environment(IOSAppStore.self) private var store
  @Environment(TVAppRuntime.self) private var runtime
  @Environment(TVLocationService.self) private var location
  @FocusState private var useLocationFocused: Bool

  var body: some View {
    let copy = TVCopy(locale: store.locale)
    ZStack {
      TVSkyBackground(phase: .dhuhr)
      VStack(spacing: 0) {
        Image(systemName: "location.fill")
          .font(.system(size: 64))
          .foregroundStyle(TVTheme.accentText)
          .frame(width: 80, height: 80)
          .padding(40)
          .background(TVTheme.accentSubtle, in: Circle())
          .accessibilityHidden(true)
        Text(verbatim: copy("Times for where you are", "أوقات الصلاة حيث أنت"))
          .font(.title.bold())
          .foregroundStyle(TVTheme.labelPrimary)
          .padding(.top, 40)
          .accessibilityAddTraits(.isHeader)
        Text(
          verbatim: copy(
            "Salah uses this Apple TV’s location once to find your city and its time zone. Or choose a city yourself.",
            "يستخدم تطبيق صلاة موقع جهاز Apple TV هذا مرة واحدة لمعرفة مدينتك ومنطقتها الزمنية. أو اختر مدينة بنفسك."
          )
        )
        .font(.headline.weight(.regular))
        .foregroundStyle(TVTheme.labelSecondary)
        .frame(maxWidth: 1100)
        .padding(.top, 16)
        HStack(spacing: TVMetrics.gutter) {
          Button {
            runtime.useCurrentLocation()
          } label: {
            Label(
              copy("Use This Apple TV’s Location", "استخدام موقع جهاز Apple TV هذا"),
              systemImage: "location.fill")
          }
          .focused($useLocationFocused)
          .disabled(location.isLocating)
          .accessibilityIdentifier("onboarding.useLocation")
          NavigationLink(value: TVSettingsRoute.citySearch) {
            Text(verbatim: copy("Choose a City", "اختيار مدينة"))
          }
          .accessibilityIdentifier("onboarding.chooseCity")
        }
        .padding(.top, 64)
        // A ZStack, unlike a Group, keeps its 120 pt while empty, so nothing above moves.
        ZStack {
          if location.isLocating {
            ProgressView(copy("Finding your city…", "جارٍ العثور على مدينتك…"))
          } else if let error = location.errorMessage {
            Text(verbatim: error.message(copy))
              .foregroundStyle(TVTheme.warning)
              .accessibilityIdentifier("onboarding.error")
          }
        }
        .font(.callout)
        .frame(maxWidth: 1100, minHeight: 120)
        .padding(.top, 24)
      }
      .multilineTextAlignment(.center)
      .padding(.horizontal, TVMetrics.safeHorizontal)
    }
    .ignoresSafeArea()
    .defaultFocus($useLocationFocused, true)
    .navigationDestination(for: TVSettingsRoute.self) { route in
      if route == .citySearch { TVCitySearchView(completesOnboarding: true) }
    }
    .onChange(of: store.preferences.location) { _, place in
      if place != nil { store.completeOnboarding() }
    }
  }
}
