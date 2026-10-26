import SwiftUI
import UIKit

@main
struct SalahTVApp: App {
  @State private var runtime = TVAppRuntime()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      TVRootView()
        .environment(runtime.store)
        .environment(runtime.navigation)
        .environment(runtime.location)
        .environment(runtime.citySearch)
        .environment(runtime.audio)
        .environment(runtime)
        .onOpenURL { runtime.navigation.handle(url: $0) }
        .task(id: scenePhase) {
          if scenePhase == .active {
            runtime.activate()
            await runtime.runClock()
          } else if scenePhase == .background {
            runtime.deactivate()
          }
        }
        .onReceive(
          NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
        ) { _ in
          runtime.timeContextChanged()
        }
        .onReceive(
          NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)
        ) { _ in
          runtime.timeContextChanged()
        }
    }
  }
}
