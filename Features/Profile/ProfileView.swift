//
//  ProfileView.swift
//  MOMENTA
//
//  个人主页视图：展示用户资料卡片与歌单网格。
//  使用 Apple 原生 glassEffect (Liquid Glass) 风格窗口，
//  与 ContentWindow (LiquidWindow2) 保持一致的设计语言。
//

import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: LightViewModel
    @ObservedObject var authViewModel: AuthViewModel
    @ObservedObject var profileViewModel: ProfileViewModel

    @State private var showSettings = false

    // 2 列歌单网格
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                IridescentBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        Spacer().frame(height: 60)

                        profileCard

                        Text("Playlists")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .tracking(-0.3)
                            .frame(maxWidth: .infinity)

                        playlistGrid

                        signOutButton

                        Spacer().frame(height: 120)
                    }
                    .padding(.horizontal, 4)
                    .frame(maxWidth: 390)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .ignoresSafeArea()
            .navigationDestination(for: PlaylistType.self) { type in
                PlaylistDetailView(playlistType: type, viewModel: profileViewModel)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(authViewModel: authViewModel)
            }
        }
        .task { await profileViewModel.load() }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        VStack(spacing: 4) {
            // Top bar — 右上角设置按钮
            HStack {
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial.opacity(0.4), in: Circle())
                }
                .buttonStyle(.plain)
            }

            // 头像
            Circle()
                .fill(.ultraThinMaterial.opacity(0.3))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.white.opacity(0.8))
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.19), lineWidth: 2.5)
                )

            // 会员标签
            Text("FOUNDER MEMBERS")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(2.5)
                .padding(.top, 2)

            // 用户名
            Text(displayName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .tracking(0.5)

            // 用户信息
            if let email = AuthService.shared.currentUser?.email {
                Text(email)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
    }

    // MARK: - Playlist Grid

    private var playlistGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(PlaylistType.allCases) { type in
                let info = profileViewModel.displayInfo(for: type)
                NavigationLink(value: type) {
                    PlaylistCard(
                        icon: info.type.iconName,
                        title: info.type.displayName,
                        songCount: info.songCountText
                    )
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
    }

    // MARK: - Sign Out Button

    private var signOutButton: some View {
        Button(action: {
            Task { await authViewModel.signOut() }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14))
                Text("退出登录")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.red.opacity(0.8))
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(GlassButtonStyle())
        .padding(.top, 10)
    }

    // MARK: - Helpers

    /// 从邮箱提取用户名作为展示名称
    private var displayName: String {
        if let email = AuthService.shared.currentUser?.email {
            return email.components(separatedBy: "@").first?.uppercased() ?? "USER"
        }
        return "USER"
    }
}
