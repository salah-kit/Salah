import SwiftUI

@main
struct SalahWatchApp: App {
  @State private var runtime = WatchAppRuntime()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      WatchRootView()
        .environment(runtime)
        .environment(runtime.store)
        .onOpenURL { runtime.navigation.open($0) }
        .task(id: scenePhase) {
          switch scenePhase {
          case .active:
            runtime.activate()
            await runtime.runClock(every: .seconds(1))
          case .inactive:
            // The wrist is down and Salah stays frontmost: the watch redraws once a minute,
            // and an adhan that's playing plays on.
            await runtime.runClock(every: .seconds(60))
          default:
            runtime.deactivate()
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
          runtime.timeContextChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
          runtime.timeContextChanged()
        }
    }
    // The system wakes Salah in the background to deliver preferences the iPhone sent while
    // it wasn't running.
    .backgroundTask(.watchConnectivity) {
      await runtime.finishPendingTransfers()
    }
  }
}
