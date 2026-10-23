import Foundation
import SalahCore
import SwiftUI

/// Illustration geometry is the exported design asset. System and prayer symbols stay native.
struct IOSOnboardingArtwork: View {
  let step: IOSOnboardingStep
  var readyKind: PrayerKind?
  var resourceBundle: Bundle? = nil

  var body: some View {
    ZStack {
      Image("OnboardingGeometry", bundle: resourceBundle)
        .resizable()
        .frame(width: 220, height: 220)
      switch step {
      case .welcome:
        Image("OnboardingIcon", bundle: resourceBundle)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 112, height: 112)
          .clipShape(.rect(cornerRadius: 26))
      case .location:
        symbol("location.fill")
      case .notifications:
        symbol("bell.fill")
      case .calculation:
        symbol("function")
      case .ready:
        Circle().fill(
          LinearGradient(
            colors: [
              Color("IOSPhaseDhuhrSkyTop", bundle: resourceBundle),
              Color("IOSPhaseDhuhrSkyBottom", bundle: resourceBundle),
            ],
            startPoint: .top, endPoint: .bottom)
        )
        .frame(width: 120, height: 120)
        IOSPrayerGlyph(
          name: "salah.\((readyKind ?? .asr).rawValue)", size: 84, resourceBundle: resourceBundle
        )
        .foregroundStyle(Color("IOSPhaseDhuhrTint", bundle: resourceBundle))
      }
    }
    .frame(width: 220, height: 220)
  }

  private func symbol(_ name: String) -> some View {
    ZStack {
      Circle()
        .fill(IOSTheme.accentSubtle)
        .frame(width: 104, height: 104)
      Image(systemName: name)
        .font(.system(size: 48))
        .foregroundStyle(IOSTheme.accent)
    }
  }
}
