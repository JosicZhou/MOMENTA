#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct PlaybackLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var taskId: String
        var title: String
        var subtitle: String
        var isPlaying: Bool
        var progress: Double
        var elapsedTime: Double
        var remainingTime: Double
        var imageURLString: String?
    }

    var sessionTitle: String
}
#endif
