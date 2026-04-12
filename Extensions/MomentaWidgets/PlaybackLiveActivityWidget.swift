#if canImport(ActivityKit)
import ActivityKit
import SwiftUI
import WidgetKit

struct PlaybackLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlaybackLiveActivityAttributes.self) { context in
            PlaybackLiveLockScreenView(state: context.state)
                .widgetURL(deepLinkURL(for: context.state.taskId))
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PlaybackArtworkView(
                        urlString: context.state.imageURLString,
                        size: 64,
                        cornerRadius: 18
                    )
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(context.state.subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    PlaybackWaveformView(isPlaying: context.state.isPlaying, compact: false)
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 18) {
                        PlaybackProgressRow(state: context.state)

                        HStack(spacing: 28) {
                            Image(systemName: "star")
                            Image(systemName: "backward.fill")
                            Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 28, weight: .semibold))
                            Image(systemName: "forward.fill")
                            Image(systemName: "airplayaudio")
                        }
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 8)
                }
            } compactLeading: {
                PlaybackArtworkView(
                    urlString: context.state.imageURLString,
                    size: 24,
                    cornerRadius: 7
                )
            } compactTrailing: {
                PlaybackWaveformView(isPlaying: context.state.isPlaying, compact: true)
            } minimal: {
                PlaybackWaveformView(isPlaying: context.state.isPlaying, compact: true)
            }
            .widgetURL(deepLinkURL(for: context.state.taskId))
            .keylineTint(.clear)
        }
    }

    private func deepLinkURL(for taskId: String) -> URL? {
        URL(string: "momenta://song/\(taskId)?autoplay=1")
    }
}

private struct PlaybackLiveLockScreenView: View {
    let state: PlaybackLiveActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                PlaybackArtworkView(urlString: state.imageURLString, size: 92, cornerRadius: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(state.subtitle)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                PlaybackWaveformView(isPlaying: state.isPlaying, compact: false)
                    .padding(.top, 6)
            }

            PlaybackProgressRow(state: state)

            HStack(spacing: 32) {
                Image(systemName: "star")
                Image(systemName: "backward.fill")
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34, weight: .semibold))
                Image(systemName: "forward.fill")
                Image(systemName: "airplayaudio")
            }
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.black)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct PlaybackProgressRow: View {
    let state: PlaybackLiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Text(formatTime(state.elapsedTime))
                .frame(width: 46, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.2))

                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.82))
                        .frame(width: max(8, proxy.size.width * boundedProgress))
                }
            }
            .frame(height: 10)

            Text("-\(formatTime(state.remainingTime))")
                .frame(width: 54, alignment: .trailing)
        }
        .font(.system(size: 15, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.78))
    }

    private var boundedProgress: CGFloat {
        CGFloat(min(max(state.progress, 0), 1))
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}

private struct PlaybackArtworkView: View {
    let urlString: String?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        fallbackArtwork
                    }
                }
            } else {
                fallbackArtwork
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(uiColor: .secondarySystemBackground))
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
            }
    }
}

private struct PlaybackWaveformView: View {
    let isPlaying: Bool
    let compact: Bool

    private let tint = Color(red: 0.95, green: 0.62, blue: 0.43)

    var body: some View {
        TimelineView(.periodic(from: .now, by: compact ? 0.38 : 0.42)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: compact ? 3 : 4) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(
                            width: compact ? 4 : 5,
                            height: barHeight(for: index, time: time)
                        )
                }
            }
            .frame(height: compact ? 22 : 28, alignment: .center)
        }
        .opacity(isPlaying ? 1 : 0.55)
    }

    private func barHeight(for index: Int, time: TimeInterval) -> CGFloat {
        guard isPlaying else {
            return compact ? [10, 16, 13, 18, 11][index] : [12, 19, 14, 21, 13][index]
        }

        let base = compact ? 9.0 : 11.0
        let amplitude = compact ? 10.0 : 14.0
        let phase = sin(time * 6 + Double(index) * 0.9)
        return CGFloat(base + ((phase + 1) / 2) * amplitude)
    }
}
#else
import WidgetKit
import SwiftUI

struct PlaybackLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PlaybackLiveActivityFallback", provider: EmptyProvider()) { _ in
            EmptyView()
        }
        .supportedFamilies([])
    }
}

private struct EmptyEntry: TimelineEntry { let date = Date() }

private struct EmptyProvider: TimelineProvider {
    func placeholder(in context: Context) -> EmptyEntry { EmptyEntry() }
    func getSnapshot(in context: Context, completion: @escaping (EmptyEntry) -> Void) { completion(EmptyEntry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EmptyEntry>) -> Void) {
        completion(Timeline(entries: [EmptyEntry()], policy: .never))
    }
}
#endif
