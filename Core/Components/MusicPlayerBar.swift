//
//  MusicPlayerBar.swift
//  MOMENTA
//
//  通用迷你音乐播放条组件：Liquid Glass 风格，显示封面、歌名、艺术家，提供播放/歌词按钮。
//

import SwiftUI

/// 通用迷你音乐播放条，可嵌入任意页面。
struct MusicPlayerBar: View {
    // MARK: - 外部参数
    let songTitle: String
    let artistName: String

    /// 播放 / 暂停按钮点击回调
    var onPlayPauseTap: (() -> Void)?
    /// 展开歌词按钮点击回调
    var onLyricsTap: (() -> Void)?

    // MARK: - 内部状态
    @State private var isPlaying = false

    // MARK: - Body
    var body: some View {
        LiquidWindow2(horizontalPadding: 12, verticalPadding: 10) {
            HStack(spacing: 12) {
                // 专辑封面占位
                albumArt

                // 歌名 / 艺术家
                songInfo

                Spacer()

                // 播放 / 暂停
                playPauseButton

                // 展开歌词
                lyricsButton
            }
        }
    }

    // MARK: - Subviews

    /// 专辑封面占位图
    private var albumArt: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.ultraThinMaterial)
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            )
    }

    /// 歌名与艺术家信息
    private var songInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(songTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(artistName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// 播放 / 暂停按钮
    private var playPauseButton: some View {
        Button {
            isPlaying.toggle()
            onPlayPauseTap?()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 20))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
        }
    }

    /// 展开歌词按钮
    private var lyricsButton: some View {
        Button {
            onLyricsTap?()
        } label: {
            Image(systemName: "text.quote")
                .font(.system(size: 18))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
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
