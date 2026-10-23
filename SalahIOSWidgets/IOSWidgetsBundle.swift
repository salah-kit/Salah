import SwiftUI
import WidgetKit

@main
struct IOSWidgetsBundle: WidgetBundle {
  var body: some Widget {
    IOSPrayerWidget()
    IOSPrayerLiveActivity()
    IOSMuteSoundsControl()
    IOSStopAudioControl()
  }
}
