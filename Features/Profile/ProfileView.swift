//
//  ProfileView.swift
//  MOMENTA
//
//  按截图重构的个人页：Liquid Glass 主视觉 + 可滚动歌曲记录。
//

import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: LightViewModel
    @ObservedObject var authViewModel: AuthViewModel
    @ObservedObject var profileViewModel: ProfileViewModel

    @State private var showSettings = false
    private let uiScale: CGFloat = 1.08

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let bottomInset = geometry.safeAreaInsets.bottom

                ZStack {
                    profileBackground(geometry: geometry)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            profileIdentityCard
                            actionButtonsRow
                            songsContainer
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, geometry.safeAreaInsets.top + 68)
                        .padding(.bottom, bottomInset + 140)
                        .frame(maxWidth: 430)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .ignoresSafeArea()
            .sheet(isPresented: $showSettings) {
                SettingsView(authViewModel: authViewModel)
            }
        }
        .task { await profileViewModel.load() }
    }

    private var profileIdentityCard: some View {
        LiquidWindow2(cornerRadius: s(28), horizontalPadding: s(16), verticalPadding: s(16)) {
            VStack(spacing: s(12)) {
                HStack(alignment: .top) {
                    avatarView
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: s(14), weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: s(34), height: s(34))
                            .background(Circle().fill(.black.opacity(0.25)))
                    }
                    .buttonStyle(PressableGlassStyle())
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Text("FOUNDER MEMBERS")
                        .font(.systemExpanded(size: s(10), weight: .semibold))
                        .tracking(s(1.6))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(displayName)
                        .font(.systemExpanded(size: s(18), weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("23 | Hong Kong")
                        .font(.system(size: s(13), weight: .regular))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var actionButtonsRow: some View {
        HStack(spacing: s(16)) {
            Button {
                // Share profile action.
            } label: {
                Text("Share")
                    .font(.systemExpanded(size: s(11), weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity)
                    .frame(height: s(48))
                    .glassEffect(.clear, in: .capsule)
            }
            .buttonStyle(PressableGlassStyle())

            Button {
                // Co-create action.
            } label: {
                Text("Co-Create")
                    .font(.systemExpanded(size: s(11), weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity)
                    .frame(height: s(48))
                    .glassEffect(.clear, in: .capsule)
            }
            .buttonStyle(PressableGlassStyle())
        }
    }

    private var songsContainer: some View {
        VStack(spacing: s(12)) {
            if recentSongs.isEmpty {
                emptySongRow
            } else {
                ForEach(Array(recentSongs.enumerated()), id: \.element.id) { index, song in
                    VStack(spacing: s(10)) {
                        Button {
                            // Song row tap action.
                        } label: {
                            songRow(song)
                        }
                        .buttonStyle(PressableGlassStyle())

                        if index < recentSongs.count - 1 {
                            Rectangle()
                                .fill(.white.opacity(0.22))
                                .frame(height: 1)
                                .padding(.leading, s(88))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func songRow(_ song: GeneratedMusic) -> some View {
        HStack(spacing: s(12)) {
            artwork(for: song)
                .frame(width: s(74), height: s(74))
                .clipShape(RoundedRectangle(cornerRadius: s(18), style: .continuous))

            VStack(alignment: .leading, spacing: s(4)) {
                Text(song.title.isEmpty ? "Songs Name" : song.title)
                    .font(.system(size: s(14), weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(authorNameText)
                    .font(.system(size: s(14), weight: .regular))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                Text(songDateText(song.createdAt))
                    .font(.system(size: s(13), weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, s(2))
    }

    private var emptySongRow: some View {
        HStack(spacing: s(12)) {
            RoundedRectangle(cornerRadius: s(18), style: .continuous)
                .fill(.black.opacity(0.45))
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: s(20), weight: .light))
                        .foregroundStyle(.white.opacity(0.72))
                )
                .frame(width: s(74), height: s(74))

            VStack(alignment: .leading, spacing: s(4)) {
                Text("Songs Name")
                    .font(.system(size: s(14), weight: .medium))
                    .foregroundStyle(.white)
                Text(authorNameText)
                    .font(.system(size: s(14), weight: .regular))
                    .foregroundStyle(.white.opacity(0.86))
                Text("Time")
                    .font(.system(size: s(13), weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer()
        }
        .padding(.vertical, s(2))
    }

    @ViewBuilder
    private func artwork(for song: GeneratedMusic) -> some View {
        if let imageURL = song.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.black.opacity(0.45))
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: s(20), weight: .light))
                                .foregroundStyle(.white.opacity(0.72))
                        )
                }
            }
        } else {
            RoundedRectangle(cornerRadius: s(18), style: .continuous)
                .fill(.black.opacity(0.45))
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: s(20), weight: .light))
                        .foregroundStyle(.white.opacity(0.72))
                )
        }
    }

    private var avatarView: some View {
        Group {
            if let imageURL = recentSongs.first?.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Circle().fill(.white.opacity(0.16))
                    }
                }
            } else {
                Circle().fill(.white.opacity(0.16))
            }
        }
        .frame(width: s(88), height: s(88))
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.62), lineWidth: 2))
    }

    private var recentSongs: [GeneratedMusic] {
        let merged = profileViewModel.mineSongs + profileViewModel.cocreateSongs + profileViewModel.sharedSongs
        var seen = Set<String>()
        let unique = merged.filter { seen.insert($0.id).inserted }
            .filter { $0.imageURL != nil }
        return unique.sorted { $0.createdAt > $1.createdAt }
    }

    private var displayName: String {
        if let email = AuthService.shared.currentUser?.email {
            return email.components(separatedBy: "@").first?.uppercased() ?? "EVE ANDERSON"
        }
        return "EVE ANDERSON"
    }

    private var authorNameText: String {
        if let email = AuthService.shared.currentUser?.email {
            return email.components(separatedBy: "@").first ?? "Name"
        }
        return "Name"
    }

    private func songDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func s(_ value: CGFloat) -> CGFloat {
        value * uiScale
    }

    @ViewBuilder
    private func profileBackground(geometry: GeometryProxy) -> some View {
        Image("desert_background")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .overlay(Color.black.opacity(0.2))
            .ignoresSafeArea()
    }
}

private struct PressableGlassStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
