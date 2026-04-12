#if canImport(ActivityKit)
import ActivityKit
import Foundation

@MainActor
final class PlaybackLiveActivityManager {
    private var activity: Activity<PlaybackLiveActivityAttributes>?

    func startOrUpdate(
        song: GeneratedMusic,
        isPlaying: Bool,
        progress: Double,
        elapsedTime: Double,
        remainingTime: Double
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let title = song.title.isEmpty ? "Untitled Song" : song.title
        let subtitle = song.style.isEmpty ? "MOMENTA" : song.style
        let state = PlaybackLiveActivityAttributes.ContentState(
            taskId: song.id,
            title: title,
            subtitle: subtitle,
            isPlaying: isPlaying,
            progress: progress,
            elapsedTime: elapsedTime,
            remainingTime: remainingTime,
            imageURLString: song.imageURL?.absoluteString
        )

        if let activity, activity.attributes.sessionTitle == song.id {
            await activity.update(ActivityContent(state: state, staleDate: nil))
            return
        }

        if let activity {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let attributes = PlaybackLiveActivityAttributes(sessionTitle: song.id)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil)
            )
        } catch {
            print("⚠️ [PlaybackLiveActivity] Failed to start activity: \(error.localizedDescription)")
        }
    }

    func end() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
    }
}
#endif
