//
//  FriendProfileSheet.swift
//  MOMENTA
//
//  好友个人主页：展示基础信息 + 对方分享给我的音乐 + 我们共创的音乐。
//

import SwiftUI
import Supabase

// MARK: - ViewModel

@MainActor
private class FriendProfileViewModel: ObservableObject {
    @Published var sharedByFriend: [GeneratedMusic] = []
    @Published var cocreatedWithFriend: [GeneratedMusic] = []
    @Published var isLoading = false

    private let client = SupabaseConfig.client

    func load(friendId: UUID) async {
        guard let myId = try? await client.auth.session.user.id else { return }
        isLoading = true
        defer { isLoading = false }

        async let shared = fetchSharedByFriend(friendId: friendId, myId: myId)
        async let cocreated = fetchCocreated(friendId: friendId, myId: myId)

        sharedByFriend = (try? await shared) ?? []
        cocreatedWithFriend = (try? await cocreated) ?? []
    }

    // 对方分享给我的歌曲
    private func fetchSharedByFriend(friendId: UUID, myId: UUID) async throws -> [GeneratedMusic] {
        struct SharedRow: Decodable { let music_id: String }
        let response = try await client
            .from("music_shared")
            .select("music_id")
            .eq("from_user_id", value: friendId.uuidString.lowercased())
            .eq("to_user_id", value: myId.uuidString.lowercased())
            .execute()

        let decoder = JSONDecoder()
        let rows = try decoder.decode([SharedRow].self, from: response.data)
        let ids = rows.map { $0.music_id }
        guard !ids.isEmpty else { return [] }

        let musicResponse = try await client
            .from("music_generations")
            .select("*")
            .in("task_id", values: ids)
            .execute()

        decoder.dateDecodingStrategy = .custom { decoder in
            let str = try decoder.singleValueContainer().decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: str) { return d }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: str) ?? Date()
        }
        return (try? decoder.decode([GeneratedMusic].self, from: musicResponse.data)) ?? []
    }

    // 与好友共创的歌曲（completed sessions）
    private func fetchCocreated(friendId: UUID, myId: UUID) async throws -> [GeneratedMusic] {
        let myUid = myId.uuidString.lowercased()
        let fid = friendId.uuidString.lowercased()

        struct SessionRow: Decodable { let extend_task_id: String? }
        let sessionResp = try await client
            .from("cocreate_sessions")
            .select("extend_task_id")
            .eq("status", value: "completed")
            .or("and(creator_id.eq.\(myUid),invitee_id.eq.\(fid)),and(creator_id.eq.\(fid),invitee_id.eq.\(myUid))")
            .execute()

        let decoder = JSONDecoder()
        let sessions = (try? decoder.decode([SessionRow].self, from: sessionResp.data)) ?? []
        let taskIds = sessions.compactMap { $0.extend_task_id }
        guard !taskIds.isEmpty else { return [] }

        let musicResp = try await client
            .from("music_generations")
            .select("*")
            .in("task_id", values: taskIds)
            .execute()

        decoder.dateDecodingStrategy = .custom { decoder in
            let str = try decoder.singleValueContainer().decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: str) { return d }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: str) ?? Date()
        }
        return (try? decoder.decode([GeneratedMusic].self, from: musicResp.data)) ?? []
    }
}

// MARK: - View

struct FriendProfileSheet: View {
    let friend: FriendProfile
    let onRemove: () -> Void

    @StateObject private var viewModel = FriendProfileViewModel()
    @State private var showRemoveConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 顶部身份卡片
                identityHeader
                    .padding(.top, 24)
                    .padding(.bottom, 28)

                Divider()
                    .padding(.horizontal, 20)

                // 分享给我的音乐
                musicSection(
                    title: "Shared with Me",
                    icon: "square.and.arrow.down",
                    songs: viewModel.sharedByFriend,
                    emptyText: "No songs shared yet"
                )

                Divider()
                    .padding(.horizontal, 20)

                // 共创的音乐
                musicSection(
                    title: "Created Together",
                    icon: "person.2.wave.2",
                    songs: viewModel.cocreatedWithFriend,
                    emptyText: "No cocreated songs yet"
                )

                // Remove Friend
                Button(role: .destructive) {
                    showRemoveConfirm = true
                } label: {
                    Label("Remove Friend", systemImage: "person.badge.minus")
                        .font(.system(size: 16, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(uiColor: .secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .padding(.horizontal, 20)
                .padding(.top, 32)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(friend.resolvedName)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .confirmationDialog("Remove Friend", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("Remove \(friend.resolvedName)", role: .destructive) {
                onRemove()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be notified, but will no longer appear in your friends list.")
        }
        .task { await viewModel.load(friendId: friend.id) }
    }

    // MARK: - Identity Header

    private var identityHeader: some View {
        VStack(spacing: 10) {
            FriendAvatarView(name: friend.displayName, avatarUrl: friend.avatarUrl, size: 80)

            Text(friend.resolvedName)
                .font(.system(size: 22, weight: .bold))

            if let code = friend.friendCode {
                HStack(spacing: 5) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 11))
                    Text(code)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Music Section

    @ViewBuilder
    private func musicSection(title: String, icon: String, songs: [GeneratedMusic], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 10)

            if songs.isEmpty {
                Text(emptyText)
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(songs) { song in
                        FriendProfileSongRow(song: song)
                        if song.id != songs.last?.id {
                            Divider().padding(.leading, 72)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Song Row

private struct FriendProfileSongRow: View {
    let song: GeneratedMusic

    var body: some View {
        HStack(spacing: 14) {
            // 封面
            ZStack {
                if let imageURL = song.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                        default: placeholderArtwork
                        }
                    }
                } else {
                    placeholderArtwork
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // 歌曲信息
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title.isEmpty ? "Untitled" : song.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                Text(firstGenre(from: song.style))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                LinearGradient(
                    colors: [Color(uiColor: .systemIndigo).opacity(0.6), Color(uiColor: .systemPink).opacity(0.5)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(.white.opacity(0.8))
            }
    }

    private func firstGenre(from style: String) -> String {
        style.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { s in
                let l = s.lowercased()
                return !s.contains("BPM") && !l.contains("vocal") && !l.contains("instrumental")
            } ?? style
    }
}
