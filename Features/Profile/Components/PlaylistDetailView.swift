//
//  PlaylistDetailView.swift
//  MOMENTA
//
//  歌单详情页（通用模板组件）。
//  所有歌单（默认歌单 + 用户自建歌单）点击后共用此页面，通过传入不同的歌单数据渲染不同内容。
//  页面结构：固定返回键 → 可滚动的歌单名+歌曲列表（参考播客 App）。
//  使用 Apple 原生 glassEffect 风格，与 ProfileView 保持一致。
//

import SwiftUI
import UIKit

// MARK: - 左滑返回手势支持（隐藏系统返回键后重新启用）

private struct SwipeBackGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        SwipeBackController()
    }
    func updateUIViewController(_ vc: UIViewController, context: Context) {}

    private class SwipeBackController: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}

private extension View {
    func enableSwipeBack() -> some View {
        background { SwipeBackGestureEnabler().frame(width: 0, height: 0) }
    }
}

/// 歌单中单曲的展示模型
struct PlaylistSongItem: Identifiable {
    let id: String
    let title: String
    let duration: String
    var artworkImage: UIImage?
    var isLiked: Bool
    /// 歌曲归属用户，收藏/取消收藏时用
    var ownerId: UUID?
}

struct PlaylistDetailView: View {
    let playlistType: PlaylistType
    @ObservedObject var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    private var playlistName: String { playlistType.displayName }
    private var songs: [PlaylistSongItem] { viewModel.songs(for: playlistType) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 专辑名，在返回键下方，随内容一起滑动
                Text(playlistName)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .tracking(0.25)
                    .lineLimit(1)
                    .padding(.horizontal, 20)

                LazyVStack(spacing: 12) {
                    ForEach(songs) { song in
                        SongRow(
                            title: song.title,
                            duration: song.duration,
                            artworkImage: song.artworkImage,
                            isLiked: song.isLiked,
                            onLike: { Task { await viewModel.toggleFavorite(musicId: song.id, ownerId: song.ownerId) } },
                            onShare: { },
                            onAddToCalendar: { }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
        }
        .scrollIndicators(.hidden)
        .background { IridescentBackground().ignoresSafeArea() }
        .navigationBarBackButtonHidden(true)
        .enableSwipeBack()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial.opacity(0.4), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    NavigationStack {
        PlaylistDetailView(playlistType: .favorites, viewModel: ProfileViewModel())
    }
}
