//
//  PlaylistCard.swift
//  MOMENTA
//
//  个人主页中的歌单卡片组件。
//  用于在 ProfileView 的歌单合集区展示每个歌单的入口，
//  显示内容包括：歌单图标、歌单名称、歌曲数量。
//  点击后导航至 PlaylistDetailView。
//  使用 Apple 原生 glassEffect 实现 Liquid Glass 风格。
//

import SwiftUI

struct PlaylistCard: View {
    let icon: String
    let title: String
    let songCount: String
    var action: (() -> Void)? = nil

    private var cardContent: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text(songCount)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
    }

    var body: some View {
        if let action = action {
            Button(action: action) { cardContent }
                .buttonStyle(GlassButtonStyle())
        } else {
            cardContent
        }
    }
}

#Preview {
    ZStack {
        IridescentBackground()

        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ],
            spacing: 16
        ) {
            PlaylistCard(icon: "music.note", title: "All", songCount: "12 songs")
            PlaylistCard(icon: "person", title: "Mine", songCount: "5 songs")
            PlaylistCard(icon: "person.2", title: "Cocreate", songCount: "3 songs")
            PlaylistCard(icon: "square.and.arrow.up", title: "Shared", songCount: "2 songs")
            PlaylistCard(icon: "heart", title: "Favorites", songCount: "4 songs")
        }
        .padding(.horizontal, 20)
    }
}
