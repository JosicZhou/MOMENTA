//
//  FriendsListView.swift
//  MOMENTA
//
//  好友列表页：收到的申请、发出的申请、好友列表、手输 code 搜索。
//  Apple 原生 insetGrouped 风格。
//

import SwiftUI

struct FriendsListView: View {
    @ObservedObject var profileViewModel: ProfileViewModel

    @State private var codeInput = ""
    @State private var isSearching = false
    @State private var foundProfile: FriendProfile?
    @State private var showRequestSheet = false
    @State private var selectedFriend: FriendProfile?
    @State private var showFriendProfile = false
    @State private var showCancelConfirm: SentRequest?

    var body: some View {
        List {
            if !profileViewModel.acceptedNotifications.isEmpty { acceptedSection }
            addByCodeSection
            if !profileViewModel.pendingRequests.isEmpty { receivedSection }
            if !profileViewModel.sentRequests.isEmpty { sentSection }
            friendsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.large)
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await profileViewModel.loadFriendData() }
        // 搜索到用户 → 弹确认 sheet
        .sheet(isPresented: $showRequestSheet) {
            if let profile = foundProfile {
                SendFriendRequestSheet(
                    profile: profile,
                    onSend: { note in
                        Task {
                            await profileViewModel.addFriendByCode(profile.friendCode ?? "", note: note)
                            foundProfile = nil
                            codeInput = ""
                        }
                    },
                    onCancel: { foundProfile = nil }
                )
            }
        }
        // 好友主页
        .navigationDestination(isPresented: $showFriendProfile) {
            if let friend = selectedFriend {
                FriendProfileSheet(
                    friend: friend,
                    onRemove: {
                        Task { await profileViewModel.deleteFriend(friend) }
                    }
                )
            }
        }
        // 搜索报错 alert
        .alert("Oops", isPresented: Binding(
            get: { profileViewModel.friendSearchError != nil },
            set: { if !$0 { profileViewModel.friendSearchError = nil } }
        )) {
            Button("OK", role: .cancel) { profileViewModel.friendSearchError = nil }
        } message: {
            Text(profileViewModel.friendSearchError ?? "")
        }
        // 撤回申请确认
        .confirmationDialog("Cancel Request", isPresented: Binding(
            get: { showCancelConfirm != nil },
            set: { if !$0 { showCancelConfirm = nil } }
        ), titleVisibility: .visible) {
            Button("Cancel Request", role: .destructive) {
                if let req = showCancelConfirm {
                    Task { await profileViewModel.cancelSentRequest(req) }
                }
                showCancelConfirm = nil
            }
            Button("Keep", role: .cancel) { showCancelConfirm = nil }
        } message: {
            if let req = showCancelConfirm {
                Text("Cancel your friend request to \(req.resolvedName)?")
            }
        }
        // Deep link 自动弹 sheet
        .onChange(of: profileViewModel.incomingFriendCode) { _, code in
            guard let code, !code.isEmpty else { return }
            Task {
                if let profile = try? await FriendService.shared.searchByFriendCode(code) {
                    foundProfile = profile
                    showRequestSheet = true
                }
                profileViewModel.incomingFriendCode = nil
            }
        }
    }

    // MARK: - Accepted Notifications Section

    private var acceptedSection: some View {
        Section {
            ForEach(profileViewModel.acceptedNotifications) { notif in
                HStack(spacing: 12) {
                    FriendAvatarView(name: notif.friendName, avatarUrl: notif.friendAvatarUrl, size: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(notif.friendName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Accepted your friend request")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Button {
                        profileViewModel.dismissAcceptedNotification(notif)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                .listRowBackground(
                    Color(uiColor: .systemGreen).opacity(0.08)
                )
            }
        } header: {
            Label("New", systemImage: "checkmark.seal.fill")
                .foregroundStyle(Color(uiColor: .systemGreen))
        }
    }

    // MARK: - Add by Code Section

    private var addByCodeSection: some View {
        Section {
            FriendsAddByCodeRow(
                codeInput: $codeInput,
                isSearching: isSearching,
                onSearch: searchFriend
            )
        } header: {
            Text("Add by Code")
        }
    }

    private func searchFriend() {
        let trimmed = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSearching else { return }
        isSearching = true
        Task {
            defer { isSearching = false }
            if let profile = try? await FriendService.shared.searchByFriendCode(trimmed) {
                foundProfile = profile
                showRequestSheet = true
            } else {
                profileViewModel.friendSearchError = "No user found with that code"
            }
        }
    }

    // MARK: - Received Requests Section

    private var receivedSection: some View {
        Section {
            ForEach(profileViewModel.pendingRequests) { request in
                ReceivedRequestRow(
                    request: request,
                    onAccept: { Task { await profileViewModel.acceptRequest(request) } },
                    onDecline: { Task { await profileViewModel.declineRequest(request) } }
                )
            }
        } header: {
            HStack {
                Text("Requests")
                Spacer()
                Text("\(profileViewModel.pendingRequests.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
            }
        }
    }

    // MARK: - Sent Requests Section

    private var sentSection: some View {
        Section {
            ForEach(profileViewModel.sentRequests) { request in
                SentRequestRow(request: request)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            showCancelConfirm = request
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                    }
            }
        } header: {
            Text("Sent")
        }
    }

    // MARK: - Friends Section

    private var friendsSection: some View {
        Section {
            if profileViewModel.friends.isEmpty {
                emptyFriendsView
            } else {
                ForEach(profileViewModel.friends) { friend in
                    Button {
                        selectedFriend = friend
                        showFriendProfile = true
                    } label: {
                        FriendRow(friend: friend)
                    }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await profileViewModel.deleteFriend(friend) }
                        } label: {
                            Label("Remove", systemImage: "person.badge.minus")
                        }
                    }
                }
            }
        } header: {
            Text("Friends\(profileViewModel.friends.isEmpty ? "" : " · \(profileViewModel.friends.count)")")
        }
    }

    private var emptyFriendsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.quaternary)
            Text("No friends yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Share your code or scan a QR to add friends")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Received Request Row

private struct ReceivedRequestRow: View {
    let request: FriendRequest
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            FriendAvatarView(name: request.senderName, avatarUrl: request.senderAvatarUrl, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(request.senderName ?? "User")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                if let note = request.note, !note.isEmpty {
                    Text("\"\(note)\"")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(2)
                } else {
                    Text("Wants to add you as a friend")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button(action: onDecline) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color(uiColor: .systemRed).opacity(0.75))
                }
                .buttonStyle(.plain)

                Button(action: onAccept) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color(uiColor: .systemGreen))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Sent Request Row

private struct SentRequestRow: View {
    let request: SentRequest

    var body: some View {
        HStack(spacing: 12) {
            FriendAvatarView(name: request.displayName, avatarUrl: request.avatarUrl, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(request.resolvedName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                if let note = request.note, !note.isEmpty {
                    Text("\"\(note)\"")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(1)
                } else {
                    Text("No note added")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            Text("Pending")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Friend Row

private struct FriendRow: View {
    let friend: FriendProfile

    var body: some View {
        HStack(spacing: 12) {
            FriendAvatarView(name: friend.displayName, avatarUrl: friend.avatarUrl, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.resolvedName)
                    .font(.system(size: 16, weight: .semibold))

                if let code = friend.friendCode {
                    Text(code)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
