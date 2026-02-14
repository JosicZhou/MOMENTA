//
//  MusicPlayerBar.swift
//  MOMENTA
//
//  通用迷你音乐播放条组件：Liquid Glass 风格，显示封面、歌名、艺术家，提供播放/歌词按钮。
//  生成中时显示 Loading 内容并应用 IntelligenceGlowEffect 光圈。
//

import SwiftUI

/// 通用迷你音乐播放条，可嵌入任意页面。
/// 播放与生成中复用同一布局，仅光圈、左侧内容、按钮状态不同。
struct MusicPlayerBar: View {
    // MARK: - 外部参数
    let songTitle: String
    let artistName: String

    /// 专辑封面图片 URL（Suno 回传）
    var imageURL: URL? = nil
    /// 生成中时显示的进度文案（严格按 AILoadingView）
    var progress: String = ""
    /// 是否处于生成中（左侧显示三段轮循文案 + 光圈）
    var isGenerating: Bool = false
    /// 是否正在播放（按钮图标）
    var isPlaying: Bool = false

    /// 播放 / 暂停按钮点击回调
    var onPlayPauseTap: (() -> Void)?
    /// 展开歌词按钮点击回调
    var onLyricsTap: (() -> Void)?
    /// 点击整个 bar 展开全屏播放器
    var onTap: (() -> Void)?
    /// matchedGeometryEffect 动画命名空间（由 ExpandablePlayerContainer 传入）
    var animation: Namespace.ID?

    // MARK: - 内部状态
    @State private var textIndex = 0

    private let loadingPhrases = [
        "Compiling your memory now",
        "This isn't just storage; it's structure.",
        "Give it a moment and it'll settle into place"
    ]

    // MARK: - Body（统一布局：以播放态大小为准）
    var body: some View {
        LiquidWindow2(horizontalPadding: 12, verticalPadding: 8) {
            barContent
        }
        .overlay {
            if isGenerating {
                Capsule()
                    .intelligenceStroke(
                        lineWidths: [0.5, 1, 1.5],
                        blurs: [0, 0.3, 1],
                        updateInterval: 0.2,
                        animationDurations: [0.3, 0.4, 0.5]
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .contentShape(Capsule())
        .onTapGesture {
            onTap?()
        }
    }

    // MARK: - 统一 barContent（播放与生成中同一结构）
    private var barContent: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                if isGenerating {
                    loadingText
                } else {
                    albumArt
                    songInfo
                }
                Spacer()
            }
            playPauseButton
                .opacity(isGenerating ? 0.3 : 1.0)
                .disabled(isGenerating)
            lyricsButton
                .opacity(isGenerating ? 0.3 : 1.0)
                .disabled(isGenerating)
        }
    }

    /// 三段轮循文案
    private var loadingText: some View {
        Text(loadingPhrases[textIndex])
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .animation(.easeInOut(duration: 0.4), value: textIndex)
            .task(id: isGenerating) {
                guard isGenerating else { return }
                textIndex = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    textIndex = (textIndex + 1) % 3
                }
            }
    }

    /// 专辑封面（有 imageURL 时加载，否则占位）
    @ViewBuilder
    private var albumArt: some View {
        let artView = Group {
            if let url = imageURL, !isGenerating {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .clipped()
                    case .failure(_):
                        placeholderIcon
                    case .empty:
                        placeholderIcon
                    @unknown default:
                        placeholderIcon
                    }
                }
            } else {
                placeholderIcon
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        
        if let animation = animation {
            artView
                .matchedGeometryEffect(id: "albumArt", in: animation, isSource: true)
        } else {
            artView
        }
    }

    private var placeholderIcon: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.ultraThinMaterial)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            )
    }

    /// 歌名与艺术家信息
    private var songInfo: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(songTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(artistName)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    /// 播放 / 暂停按钮
    private var playPauseButton: some View {
        Button {
            onPlayPauseTap?()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
        }
    }

    /// 展开歌词按钮
    private var lyricsButton: some View {
        Button {
            onLyricsTap?()
        } label: {
            Image(systemName: "text.quote")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient(
            colors: [.purple.opacity(0.6), .orange.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack {
            Spacer()
            MusicPlayerBar(
                songTitle: "测试歌曲名称",
                artistName: "Artist Name",
                onPlayPauseTap: { print("play/pause") },
                onLyricsTap: { print("lyrics") }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}
