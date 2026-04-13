//
//  LyricsScrollView.swift
//  MOMENTA
//
//  Apple Music-style lyric stage built on stable phrase cues rather than
//  line-by-line layout mutation.
//

import SwiftUI

struct LyricsScrollView: View {

    @Environment(PlayerManager.self) private var playerManager

    let bottomInset: CGFloat

    @State private var controlsAutoHideTask: Task<Void, Never>?
    @State private var browseResumeTask: Task<Void, Never>?

    private let focusAnchor = UnitPoint(x: 0.5, y: 0.34)
    private let rowAnimation = Animation.spring(response: 0.3, dampingFraction: 0.88)

    private var phrases: [PhraseCue] {
        playerManager.lyricsPresentation.phrases
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        Spacer()
                            .frame(height: 34)

                        ForEach(Array(phrases.enumerated()), id: \.element.id) { index, phrase in
                            phraseRow(phrase: phrase, index: index)
                                .id(phrase.id)
                        }

                        Spacer()
                            .frame(height: bottomInset)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .contentShape(Rectangle())
                .mask(lyricMask)
                .simultaneousGesture(userBrowseGesture)
                .onTapGesture {
                    guard playerManager.showLyrics else { return }
                    withAnimation(.easeInOut(duration: 0.22)) {
                        playerManager.lyricsControlsVisible.toggle()
                    }
                    if playerManager.lyricsControlsVisible {
                        scheduleControlsAutoHide()
                    } else {
                        controlsAutoHideTask?.cancel()
                    }
                }
                .onAppear {
                    focusCurrentPhrase(with: proxy, animated: false)
                    scheduleControlsAutoHide()
                }
                .onDisappear {
                    controlsAutoHideTask?.cancel()
                    browseResumeTask?.cancel()
                }
                .onChange(of: playerManager.currentLineIndex) { _, _ in
                    guard playerManager.lyricsFollowMode == .follow else { return }
                    focusCurrentPhrase(with: proxy, animated: true)
                    scheduleControlsAutoHide()
                }
                .onChange(of: phrases.count) { _, _ in
                    focusCurrentPhrase(with: proxy, animated: false)
                }
                .onChange(of: playerManager.lyricsFollowMode) { _, mode in
                    if mode == .follow {
                        browseResumeTask?.cancel()
                        focusCurrentPhrase(with: proxy, animated: true)
                        scheduleControlsAutoHide()
                    } else {
                        controlsAutoHideTask?.cancel()
                    }
                }
            }
        }
    }

    private func phraseRow(phrase: PhraseCue, index: Int) -> some View {
        let isCurrent = playerManager.lyricsAreTimeSynced && index == playerManager.currentLineIndex
        let distance = abs(index - playerManager.currentLineIndex)

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(phrase.lines) { line in
                Text(line.text)
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .lineSpacing(0)
        .scaleEffect(phraseScale(isCurrent: isCurrent, distance: distance), anchor: .leading)
        .foregroundStyle(.white.opacity(phraseOpacity(isCurrent: isCurrent, distance: distance)))
        .blur(radius: phraseBlur(isCurrent: isCurrent, distance: distance))
        .contentShape(Rectangle())
        .onTapGesture {
            seekToPhrase(phrase)
        }
        .animation(rowAnimation, value: playerManager.currentLineIndex)
    }

    private var userBrowseGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { _ in
                controlsAutoHideTask?.cancel()
                browseResumeTask?.cancel()
                playerManager.revealLyricsControls()
                if playerManager.lyricsFollowMode == .follow {
                    playerManager.beginLyricsBrowseMode()
                }
            }
            .onEnded { _ in
                scheduleBrowseResume()
            }
    }

    private func focusCurrentPhrase(with proxy: ScrollViewProxy, animated: Bool) {
        guard !phrases.isEmpty,
              playerManager.currentLineIndex >= 0,
              playerManager.currentLineIndex < phrases.count else { return }

        let targetID = phrases[playerManager.currentLineIndex].id
        let performScroll = {
            proxy.scrollTo(targetID, anchor: focusAnchor)
        }

        if animated {
            withAnimation(.snappy(duration: 0.22, extraBounce: 0.01)) {
                performScroll()
            }
        } else {
            performScroll()
        }
    }

    private func scheduleControlsAutoHide() {
        guard playerManager.showLyrics,
              playerManager.lyricsAreTimeSynced,
              playerManager.isPlaying,
              playerManager.lyricsFollowMode == .follow else { return }

        controlsAutoHideTask?.cancel()
        controlsAutoHideTask = Task {
            try? await Task.sleep(for: .seconds(4.5))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        playerManager.lyricsControlsVisible = false
                    }
                }
            }
        }
    }

    private func scheduleBrowseResume() {
        guard playerManager.showLyrics,
              playerManager.lyricsAreTimeSynced,
              playerManager.lyricsFollowMode == .browse else { return }

        browseResumeTask?.cancel()
        browseResumeTask = Task {
            try? await Task.sleep(for: .seconds(5.0))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.snappy(duration: 0.24, extraBounce: 0.01)) {
                    playerManager.resumeLyricsFollowMode()
                }
            }
        }
    }

    private func phraseOpacity(isCurrent: Bool, distance: Int) -> Double {
        guard playerManager.lyricsAreTimeSynced else { return 0.92 }
        if isCurrent { return 0.98 }
        switch distance {
        case 1: return 0.52
        case 2: return 0.3
        default: return 0.14
        }
    }

    private func phraseBlur(isCurrent: Bool, distance: Int) -> CGFloat {
        guard playerManager.lyricsAreTimeSynced else { return 0 }
        if isCurrent { return 0 }
        switch distance {
        case 1: return 0.4
        case 2: return 0.95
        default: return 1.45
        }
    }

    private func phraseScale(isCurrent: Bool, distance: Int) -> CGFloat {
        guard playerManager.lyricsAreTimeSynced else { return 0.94 }
        if isCurrent { return 1.0 }
        switch distance {
        case 1: return 0.9
        case 2: return 0.84
        default: return 0.78
        }
    }

    private var lyricMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.55), location: 0.07),
                .init(color: .black, location: 0.16),
                .init(color: .black, location: 0.78),
                .init(color: .black.opacity(0.58), location: 0.88),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func seekToPhrase(_ phrase: PhraseCue) {
        guard playerManager.lyricsAreTimeSynced,
              playerManager.totalDuration > 0 else { return }

        let progress = min(max(phrase.startTime / playerManager.totalDuration, 0), 1)
        playerManager.seek(to: progress)
        playerManager.revealLyricsControls()
        browseResumeTask?.cancel()
        playerManager.resumeLyricsFollowMode()
        scheduleControlsAutoHide()
    }
}
