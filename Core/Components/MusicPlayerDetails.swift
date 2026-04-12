//
//  MusicPlayerDetails.swift
//  MOMENTA
//
//  Apple Music-style full-screen player with a calmer lyric stage,
//  native-feeling transport controls, and a unified darkened artwork surface.
//

import SwiftUI

struct MusicPlayerDetails: View {

    let animation: Namespace.ID

    @Environment(PlayerManager.self) private var playerManager

    @State private var playerContentOffsetY: CGFloat = 420
    @State private var isCurrentSongFavorite = false
    @State private var isFavoriteMutationInFlight = false

    private let hPadding: CGFloat = 24
    private let uiSpring = Animation.spring(response: 0.42, dampingFraction: 0.9)
    private let profileService = ProfileService.shared

    var body: some View {
        GeometryReader { geo in
            let safeArea = geo.safeAreaInsets
            let screenW = geo.size.width
            let screenH = geo.size.height
            let bottomInset = max(safeArea.bottom, 16)
            let artSize = min(screenW - 84, max(screenH * 0.37, 220))

            ZStack {
                playerBackground(screenW: screenW, screenH: screenH)

                VStack(spacing: 0) {
                    dragIndicator
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .padding(.top, safeArea.top + 16)
                        .padding(.bottom, 6)
                        .contentShape(Rectangle())
                        .highPriorityGesture(playerDismissGesture(screenHeight: screenH))

                    if playerManager.showLyrics {
                        lyricsExperience(bottomInset: bottomInset, screenHeight: screenH)
                    } else {
                        artworkExperience(
                            artSize: artSize,
                            bottomInset: bottomInset,
                            screenHeight: screenH
                        )
                    }
                }
                .offset(y: playerContentOffsetY)
            }
            .offset(y: playerManager.dragOffset)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .task(id: playerManager.currentMusic?.id) {
            await refreshFavoriteState()
        }
        .onAppear {
            withAnimation(.snappy(duration: 0.3, extraBounce: 0.04)) {
                playerContentOffsetY = .zero
            }
        }
    }

    private var dragIndicator: some View {
        Capsule()
            .fill(.white.opacity(0.28))
            .frame(width: 64, height: 5)
    }

    @ViewBuilder
    private func playerBackground(screenW: CGFloat, screenH: CGFloat) -> some View {
        if let url = playerManager.currentMusic?.imageURL {
            ZStack {
                Color.black

                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: screenW, height: screenH)
                            .clipped()
                    default:
                        Color.clear
                    }
                }
                .blur(radius: playerManager.showLyrics ? 74 : 58)
                .saturation(playerManager.showLyrics ? 0.82 : 0.94)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.22),
                            Color.black.opacity(playerManager.showLyrics ? 0.38 : 0.28),
                            Color(red: 0.36, green: 0.18, blue: 0.08).opacity(playerManager.showLyrics ? 0.34 : 0.2),
                            Color.black.opacity(playerManager.showLyrics ? 0.58 : 0.36)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Rectangle()
                        .fill(.ultraThinMaterial.opacity(playerManager.showLyrics ? 0.12 : 0.06))
                )
            }
            .frame(width: screenW, height: screenH)
            .clipped()
            .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.22, green: 0.14, blue: 0.1),
                    Color(red: 0.16, green: 0.08, blue: 0.06),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private func playerDismissGesture(screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard playerManager.isExpanded else { return }
                playerManager.dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                guard playerManager.isExpanded else { return }
                let shouldCollapse = value.translation.height > screenHeight / 7
                withAnimation(.snappy(duration: 0.35, extraBounce: 0.04)) {
                    if shouldCollapse {
                        playerManager.isExpanded = false
                        playerContentOffsetY = 420
                    }
                    playerManager.dragOffset = .zero
                }
            }
    }

    private func lyricsExperience(bottomInset: CGFloat, screenHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            playerHeader
                    .padding(.horizontal, hPadding)
                    .padding(.top, 8)
                .contentShape(Rectangle())
                .highPriorityGesture(playerDismissGesture(screenHeight: screenHeight))

            ZStack(alignment: .bottom) {
                lyricStage
                    .padding(.top, 14)

                playerControlStack(
                    bottomInset: bottomInset,
                    includeGradient: true,
                    includePlaybackBadge: true,
                    isVisible: playerManager.lyricsControlsVisible,
                    horizontalPadding: hPadding
                )
            }
        }
    }

    private func artworkExperience(artSize: CGFloat, bottomInset: CGFloat, screenHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            largeAlbumArt(size: artSize)
                .padding(.horizontal, hPadding)
                .contentShape(Rectangle())
                .highPriorityGesture(playerDismissGesture(screenHeight: screenHeight))

            Spacer(minLength: 28)

            VStack(spacing: 18) {
                artworkSongInfo
                playerControlStack(
                    bottomInset: bottomInset,
                    includeGradient: false,
                    includePlaybackBadge: false,
                    isVisible: true,
                    horizontalPadding: 0
                )
            }
            .padding(.horizontal, hPadding)
        }
    }

    private func largeAlbumArt(size: CGFloat) -> some View {
        ZStack {
            if playerManager.isExpanded {
                Group {
                    if let url = playerManager.currentMusic?.imageURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: size, height: size)
                                    .clipped()
                            default:
                                albumPlaceholder
                            }
                        }
                    } else {
                        albumPlaceholder
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.34), radius: 28, y: 16)
                .matchedGeometryEffect(id: "albumArt", in: animation)
                .transition(.offset(y: 1))
            }
        }
        .frame(width: size, height: size)
    }

    private var albumPlaceholder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.white.opacity(0.32))
            }
    }

    private var playerHeader: some View {
        HStack(spacing: 16) {
            headerArtwork(size: 58, cornerRadius: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(playerManager.currentMusic?.title ?? "Unknown Song")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(playerManager.currentMusic?.style ?? "MOMENTA")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                favoriteButton
                moreActionsMenu
            }
        }
    }

    private var artworkSongInfo: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(playerManager.currentMusic?.title ?? "Unknown Song")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(playerManager.currentMusic?.style ?? "MOMENTA")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                favoriteButton
                moreActionsMenu
            }
        }
    }

    @ViewBuilder
    private func headerArtwork(size: CGFloat, cornerRadius: CGFloat) -> some View {
        if let url = playerManager.currentMusic?.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.white.opacity(0.64))
                        }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.64))
                }
        }
    }

    @ViewBuilder
    private var lyricStage: some View {
        if playerManager.isLoadingLyrics {
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                    .tint(.white.opacity(0.72))
                Text("Loading Lyrics")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.58))
                Spacer()
            }
        } else if playerManager.lyrics.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "quote.bubble")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.36))
                Text("No lyrics available")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.56))
                Spacer()
            }
        } else {
            LyricsScrollView()
        }
    }

    private func playerControlStack(
        bottomInset: CGFloat,
        includeGradient: Bool,
        includePlaybackBadge: Bool,
        isVisible: Bool,
        horizontalPadding: CGFloat
    ) -> some View {
        VStack(spacing: 18) {
            progressBarSection(includePlaybackBadge: includePlaybackBadge)
            transportControls
            volumeSlider
            bottomToolbar
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 30)
        .padding(.bottom, bottomInset + 4)
        .background(alignment: .bottom) {
            if includeGradient {
                LinearGradient(
                    colors: [
                        .clear,
                        Color.black.opacity(0.24),
                        Color.black.opacity(0.46),
                        Color.black.opacity(0.62)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .animation(uiSpring, value: isVisible)
        .allowsHitTesting(isVisible)
    }

    private func progressBarSection(includePlaybackBadge: Bool) -> some View {
        VStack(spacing: 8) {
            CustomProgressBar(
                progress: playerManager.playbackProgress,
                onSeek: { progress in
                    playerManager.seek(to: progress)
                }
            )
            .frame(height: 12)

            HStack(alignment: .center) {
                Text(formatTime(playerManager.currentTime))
                    .monospacedDigit()
                    .frame(width: 46, alignment: .leading)

                Spacer(minLength: 0)

                if includePlaybackBadge {
                    playbackBadge
                }

                Spacer(minLength: 0)

                Text("-\(formatTime(max(0, playerManager.totalDuration - playerManager.currentTime)))")
                    .monospacedDigit()
                    .frame(width: 54, alignment: .trailing)
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var playbackBadge: some View {
        Text(currentPlaybackBadgeLabel)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(0.3)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.12))
            )
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(1)
    }

    private var currentPlaybackBadgeLabel: String {
        switch playerManager.currentMusic?.source {
        case "memory":
            "MEMORY MIX"
        case "cocreate":
            "CO-CREATE"
        default:
            "MOMENTA"
        }
    }

    private var transportControls: some View {
        HStack(spacing: 48) {
            Button(action: skipBackward) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 34, weight: .semibold))
            }

            Button(action: playerManager.togglePlayback) {
                Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .frame(width: 76, height: 64)
            }
            .contentTransition(.symbolEffect(.replace))
            .animation(.smooth(duration: 0.28), value: playerManager.isPlaying)

            Button(action: skipForward) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 34, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }

    private var volumeSlider: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.22))
                        .frame(height: 4)

                    Capsule()
                        .fill(.white.opacity(0.84))
                        .frame(width: geo.size.width * 0.35, height: 4)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(height: 20)
    }

    private var bottomToolbar: some View {
        HStack {
            toolbarSelectionButton(
                symbol: playerManager.showLyrics ? "quote.bubble.fill" : "quote.bubble",
                isSelected: playerManager.showLyrics
            ) {
                withAnimation(uiSpring) {
                    if playerManager.showLyrics {
                        playerManager.showLyrics = false
                    } else {
                        playerManager.showLyrics = true
                        playerManager.lyricsControlsVisible = true
                        Task { await playerManager.fetchLyrics() }
                    }
                }
            }

            Spacer()

            toolbarIconButton(symbol: "airplayaudio", action: {})

            Spacer()

            toolbarIconButton(symbol: "list.bullet", action: {})
        }
        .padding(.top, 2)
    }

    private func toolbarSelectionButton(
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 46, height: 46)
                .background {
                    Circle()
                        .fill(isSelected ? .white.opacity(0.22) : .clear)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(isSelected ? 1 : 0.74))
    }

    private func toolbarIconButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.78))
    }

    private var favoriteButton: some View {
        Button(action: toggleFavorite) {
            Image(systemName: isCurrentSongFavorite ? "star.fill" : "star")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 46, height: 46)
                .background {
                    Circle()
                        .fill(.white.opacity(0.1))
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(supportsFavorite ? 0.94 : 0.4))
        .disabled(!supportsFavorite || isFavoriteMutationInFlight)
        .accessibilityLabel(isCurrentSongFavorite ? "Remove Favorite" : "Add Favorite")
    }

    private var moreActionsMenu: some View {
        Menu {
            if let currentMusic = playerManager.currentMusic, currentMusic.isWidgetEligible {
                Button("Set for Widget", systemImage: "apps.iphone") {
                    let kind: SystemSongKind = currentMusic.source == "memory" ? .memory : .mine
                    SystemSongSnapshotStore().pin(SystemSongSnapshot.from(currentMusic, kind: kind))
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 46, height: 46)
                .background {
                    Circle()
                        .fill(.white.opacity(0.1))
                }
                .foregroundStyle(.white.opacity(0.94))
        }
        .menuIndicator(.hidden)
    }

    private var supportsFavorite: Bool {
        playerManager.currentMusic?.ownerId != nil && AuthService.shared.currentUser?.id != nil
    }

    private func refreshFavoriteState() async {
        guard let currentMusic = playerManager.currentMusic,
              let userId = AuthService.shared.currentUser?.id else {
            await MainActor.run {
                isCurrentSongFavorite = false
            }
            return
        }

        do {
            let favoriteIds = try await profileService.fetchFavoriteMusicIds(userId: userId)
            guard !Task.isCancelled, playerManager.currentMusic?.id == currentMusic.id else { return }
            await MainActor.run {
                isCurrentSongFavorite = favoriteIds.contains(currentMusic.id)
            }
        } catch {
            await MainActor.run {
                isCurrentSongFavorite = false
            }
        }
    }

    private func toggleFavorite() {
        guard let currentMusic = playerManager.currentMusic,
              let userId = AuthService.shared.currentUser?.id,
              let ownerId = currentMusic.ownerId,
              !isFavoriteMutationInFlight else {
            return
        }

        let shouldRemove = isCurrentSongFavorite
        isFavoriteMutationInFlight = true

        Task {
            do {
                if shouldRemove {
                    try await profileService.removeFavorite(userId: userId, musicId: currentMusic.id)
                } else {
                    try await profileService.addFavorite(userId: userId, musicId: currentMusic.id, ownerId: ownerId)
                }

                await MainActor.run {
                    isCurrentSongFavorite.toggle()
                    isFavoriteMutationInFlight = false
                }
            } catch {
                await MainActor.run {
                    isFavoriteMutationInFlight = false
                }
            }
        }
    }

    private func skipBackward() {
        guard playerManager.totalDuration > 0 else { return }
        let target = max(0, playerManager.currentTime - 15)
        playerManager.seek(to: target / playerManager.totalDuration)
    }

    private func skipForward() {
        guard playerManager.totalDuration > 0 else { return }
        let target = min(playerManager.totalDuration, playerManager.currentTime + 15)
        playerManager.seek(to: target / playerManager.totalDuration)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}
