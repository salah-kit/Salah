import SwiftUI
import UIKit

@main
struct SalahIOSApp: App {
  @State private var runtime: IOSAppRuntime
  @Environment(\.scenePhase) private var scenePhase

  init() {
    let runtime = IOSAppRuntime()
    _runtime = State(initialValue: runtime)
    runtime.registerBackgroundRefresh()
  }

  var body: some Scene {
    WindowGroup {
      IOSRootView()
        .environment(runtime.store)
        .environment(runtime.location)
        .environment(runtime.citySearch)
        .environment(runtime.notifications)
        .environment(runtime.audio)
        .environment(runtime)
        .onOpenURL { runtime.store.handle(url: $0) }
        .task(id: scenePhase) {
          if scenePhase == .active {
            await runtime.activate()
            await runtime.runClock()
          } else {
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
