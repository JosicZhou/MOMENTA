//
//  MusicPlayerDetails.swift
//  MOMENTA
//
//  Apple Music 风格全屏展开播放器页面。
//  使用 GeometryReader 自适应布局，确保所有机型上元素不溢出。
//  专辑封面模式：底部控制区固定高度 ~280pt，封面在剩余空间居中。
//  歌词模式：底部控件为浮动 overlay，支持滚动方向显隐。
//

import SwiftUI

struct MusicPlayerDetails: View {
    
    let animation: Namespace.ID
    
    @Environment(PlayerManager.self) private var playerManager
    
    @State private var playerContentOffsetY: CGFloat = 400
    
    /// 统一水平边距
    private let hPadding: CGFloat = 24
    /// 统一交互动效
    private let uiSpring = Animation.spring(response: 0.42, dampingFraction: 0.9)
    
    var body: some View {
        GeometryReader { geo in
            let safeArea = geo.safeAreaInsets
            let screenW = geo.size.width
            let screenH = geo.size.height
            
            // 专辑封面模式：底部控制区 280pt
            let fullControlsHeight: CGFloat = 280
            let topSectionHeight = safeArea.top + 28
            let bottomInset = safeArea.bottom > 0 ? safeArea.bottom : CGFloat(16)
            let artAreaHeight = screenH - topSectionHeight - fullControlsHeight - bottomInset
            let artSize = min(screenW - hPadding * 2, max(artAreaHeight - 20, 200))
            
            ZStack {
                // 背景：歌词模式用封面模糊+暗色叠加，专辑模式用 material
                Group {
                    if playerManager.showLyrics,
                       let url = playerManager.currentMusic?.imageURL {
                        // 封面图模糊 + 深色叠加（Apple Music 风格沉浸式背景）
                        // 使用 screenW/screenH 硬约束，防止 .fill 图片撑大父 ZStack
                        ZStack {
                            Color.black
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    img.resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: screenW, height: screenH)
                                        .clipped()
                                } else {
                                    Color.clear
                                }
                            }
                            .blur(radius: 80)
                            .saturation(0.78)
                            .overlay(Color.black.opacity(0.56))
                        }
                        .frame(width: screenW, height: screenH)
                        .clipped()
                        .ignoresSafeArea()
                    } else if playerManager.showLyrics {
                        Color.black.ignoresSafeArea()
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThickMaterial)
                            .ignoresSafeArea()
                    }
                }
                
                VStack(spacing: 0) {
                    // 拖拽指示器
                    dragIndicator
                        .frame(height: 20)
                        .padding(.top, safeArea.top + 16)
                    
                    if playerManager.showLyrics {
                        // ===== 歌词模式 =====
                        
                        // 紧凑顶部：小封面 + 歌曲信息（强制暗色适配深色背景）
                        compactSongHeader
                            .environment(\.colorScheme, .dark)
                            .frame(height: 64)
                            .padding(.horizontal, hPadding)
                            .padding(.top, 8)
                        
                        // 歌词滚动区域 + 浮动底部控件
                        ZStack(alignment: .bottom) {
                            // 层 1：歌词内容（填满剩余空间）
                            if playerManager.isLoadingLyrics {
                                VStack(spacing: 12) {
                                    Spacer()
                                    ProgressView()
                                        .tint(.white.opacity(0.65))
                                    Text("Loading Lyrics")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white.opacity(0.56))
                                    Spacer()
                                }
                            } else if playerManager.lyrics.isEmpty {
                                VStack(spacing: 10) {
                                    Spacer()
                                    Image(systemName: "quote.bubble")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.38))
                                    Text("No lyrics available")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white.opacity(0.56))
                                    Spacer()
                                }
                            } else {
                                LyricsScrollView()
                            }
                            
                            // 层 2：浮动底部控件 overlay
                            lyricsBottomOverlay(bottomInset: bottomInset)
                        }
                        
                    } else {
                        // ===== 专辑封面模式（原有布局） =====
                        
                        Spacer()
                        
                        largeAlbumArt(size: artSize)
                        
                        Spacer()
                        
                        // 完整底部控制区
                        VStack(spacing: 0) {
                            songInfoSection
                                .frame(height: 56)
                            
                            progressBarSection
                                .frame(height: 36)
                            
                            playbackControls
                                .frame(height: 64)
                                .padding(.top, 8)
                            
                            volumeSlider
                                .frame(height: 40)
                                .padding(.top, 16)
                            
                            bottomToolbar
                                .frame(height: 48)
                                .padding(.top, 12)
                        }
                        .padding(.horizontal, hPadding)
                        .padding(.bottom, bottomInset)
                        .offset(y: playerContentOffsetY)
                    }
                }
            }
            .offset(y: playerManager.dragOffset)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard playerManager.isExpanded else { return }
                        playerManager.dragOffset = max(0, value.translation.height)
                    }
                    .onEnded { value in
                        guard playerManager.isExpanded else { return }
                        let shouldCollapse = value.translation.height > screenH / 6
                        withAnimation(.snappy(duration: 0.35, extraBounce: 0.04)) {
                            if shouldCollapse {
                                playerManager.isExpanded = false
                                playerContentOffsetY = 400
                            }
                            playerManager.dragOffset = .zero
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.snappy(duration: 0.3, extraBounce: 0.04)) {
                playerContentOffsetY = .zero
            }
        }
    }
    
    // MARK: - 拖拽指示器
    
    private var dragIndicator: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 36, height: 5)
    }
    
    // MARK: - 大封面
    
    private func largeAlbumArt(size: CGFloat) -> some View {
        ZStack {
            if playerManager.isExpanded {
                Group {
                    if let url = playerManager.currentMusic?.imageURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
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
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
                .scaleEffect(playerManager.isPlaying ? 1.0 : 0.9)
                .matchedGeometryEffect(id: "albumArt", in: animation)
                .transition(.offset(y: 1))
                .animation(.smooth(duration: 0.4), value: playerManager.isPlaying)
            }
        }
        .frame(width: size, height: size)
    }
    
    private var albumPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.white.opacity(0.3))
            )
    }
    
    // MARK: - 紧凑歌曲头部（歌词模式）
    
    /// 歌词模式顶部：小封面 48x48 + 歌名/艺术家 + 省略号按钮
    private var compactSongHeader: some View {
        HStack(spacing: 12) {
            // 小封面
            Group {
                if let url = playerManager.currentMusic?.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 48, height: 48)
                                .clipped()
                        default:
                            RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // 歌名 + 艺术家
            VStack(alignment: .leading, spacing: 2) {
                Text(playerManager.currentMusic?.title ?? "Unknown")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                Text(playerManager.currentMusic?.style ?? "")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 省略号按钮
            Button {} label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.15), in: .circle)
            }
            .tint(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
    
    // MARK: - 歌词模式浮动底部控件
    
    /// 歌词模式下的底部浮动 overlay：进度条 + 播放控制 + 音量 + 工具栏
    /// 通过 lyricsControlsVisible 控制显隐（向下滚动隐藏，向上/停止显示）
    private func lyricsBottomOverlay(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            progressBarSection
                .frame(height: 36)
            
            playbackControls
                .frame(height: 64)
                .padding(.top, 8)
            
            volumeSlider
                .frame(height: 40)
                .padding(.top, 16)
            
            bottomToolbar
                .frame(height: 48)
                .padding(.top, 12)
        }
        .padding(.horizontal, hPadding)
        .padding(.bottom, bottomInset)
        .background(
            // 渐变遮罩：顶部透明 → 底部深色，与封面模糊背景融合
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.black.opacity(0.5), location: 0.25),
                    .init(color: Color.black.opacity(0.75), location: 0.5),
                    .init(color: Color.black.opacity(0.85), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
        .environment(\.colorScheme, .dark)
        .opacity(playerManager.lyricsControlsVisible ? 1 : 0)
        .animation(uiSpring, value: playerManager.lyricsControlsVisible)
        .allowsHitTesting(playerManager.lyricsControlsVisible)
    }
    
    // MARK: - 歌曲信息
    
    private var songInfoSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(playerManager.currentMusic?.title ?? "Unknown")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(playerManager.currentMusic?.style ?? "")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {} label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
                    .background(.ultraThickMaterial, in: .circle)
            }
            .tint(.primary)
        }
    }
    
    // MARK: - 进度条
    
    private var progressBarSection: some View {
        VStack(spacing: 6) {
            CustomProgressBar(
                progress: playerManager.playbackProgress,
                onSeek: { progress in
                    playerManager.seek(to: progress)
                }
            )
            .frame(height: 12)
            
            HStack {
                Text(formatTime(playerManager.currentTime))
                    .monospacedDigit()
                Spacer()
                Text("-\(formatTime(max(0, playerManager.totalDuration - playerManager.currentTime)))")
                    .monospacedDigit()
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(playerManager.showLyrics ? .white.opacity(0.65) : .secondary)
        }
    }
    
    // MARK: - 播放控制
    
    private var playbackControls: some View {
        GlassEffectContainer(spacing: 18) {
            HStack(spacing: 26) {
                controlButton(symbol: "backward.fill", iconSize: 19, frame: 44, action: {})

                controlButton(
                    symbol: playerManager.isPlaying ? "pause.fill" : "play.fill",
                    iconSize: 24,
                    frame: 62,
                    action: { playerManager.togglePlayback() }
                )
                .contentTransition(.symbolEffect(.replace))
                .animation(.smooth(duration: 0.35), value: playerManager.isPlaying)

                controlButton(symbol: "forward.fill", iconSize: 19, frame: 44, action: {})
            }
        }
    }
    
    // MARK: - 音量滑块
    
    private var volumeSlider: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(playerManager.showLyrics ? .white.opacity(0.62) : .secondary)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(playerManager.showLyrics ? .white.opacity(0.2) : Color.primary.opacity(0.15))
                        .frame(height: 4)
                    Capsule()
                        .fill(playerManager.showLyrics ? .white.opacity(0.72) : Color.primary.opacity(0.55))
                        .frame(width: geo.size.width * 0.35, height: 4)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(playerManager.showLyrics ? .white.opacity(0.62) : .secondary)
        }
    }
    
    // MARK: - 底部工具栏
    
    private var bottomToolbar: some View {
        HStack {
            Spacer()
            controlButton(symbol: "quote.bubble", iconSize: 17, frame: 40) {
                withAnimation(uiSpring) {
                    if !playerManager.showLyrics {
                        playerManager.showLyrics = true
                        playerManager.lyricsControlsVisible = true
                        Task { await playerManager.fetchLyrics() }
                    } else {
                        playerManager.showLyrics = false
                    }
                }
            }
            .symbolVariant(playerManager.showLyrics ? .fill : .none)
            Spacer()
            controlButton(symbol: "airplayaudio", iconSize: 17, frame: 40, action: {})
            Spacer()
            controlButton(symbol: "list.bullet", iconSize: 17, frame: 40, action: {})
            Spacer()
        }
        .foregroundStyle(playerManager.showLyrics ? .white.opacity(0.84) : .secondary)
    }

    @ViewBuilder
    private func controlButton(
        symbol: String,
        iconSize: CGFloat,
        frame: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: frame, height: frame)
                .glassEffect(.clear.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 工具方法
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}
