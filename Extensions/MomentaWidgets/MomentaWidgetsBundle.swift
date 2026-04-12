import WidgetKit
import SwiftUI

@main
struct MomentaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SongWidget()
        PlaybackLiveActivityWidget()
    }
}
