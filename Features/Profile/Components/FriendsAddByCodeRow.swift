//
//  FriendsAddByCodeRow.swift
//  MOMENTA
//
//  好友码搜索行 + 发送申请 Sheet（含可选备注）。
//

import SwiftUI

// MARK: - 搜索输入行

struct FriendsAddByCodeRow: View {
    @Binding var codeInput: String
    var isSearching: Bool
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Enter friend code", text: $codeInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .submitLabel(.search)
                .onSubmit { onSearch() }

            if !codeInput.isEmpty {
                Button {
                    onSearch()
                } label: {
                    if isSearching {
                        ProgressView()
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color(uiColor: .systemIndigo))
                    }
                }
                .disabled(isSearching)
            }
        }
    }
}

// MARK: - List Section

struct FriendsAddByCodeListSection: View {
    @Binding var codeInput: String
    var isSearching: Bool
    let onSearch: () -> Void

    var body: some View {
        Section {
            FriendsAddByCodeRow(
                codeInput: $codeInput,
                isSearching: isSearching,
                onSearch: onSearch
            )
        } header: {
            Text("Add by Code")
        }
    }
}

// MARK: - 发送申请确认 Sheet

struct SendFriendRequestSheet: View {
    let profile: FriendProfile
    let onSend: (String?) -> Void
    let onCancel: () -> Void

    @State private var note: String = ""
    @FocusState private var noteFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 对方信息
            VStack(spacing: 10) {
                FriendAvatarView(name: profile.displayName,
                                 avatarUrl: profile.avatarUrl,
                                 size: 72)
                    .padding(.top, 32)

                Text(profile.resolvedName)
                    .font(.system(size: 20, weight: .semibold))

                if let code = profile.friendCode {
                    Text(code)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 32)

            // 备注输入 + 操作按钮（紧凑分组）
            VStack(spacing: 12) {
                // 备注输入框
                HStack(spacing: 0) {
                    TextField("Say hi! 👋  (optional)", text: $note)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.primary)
                        .focused($noteFocused)
                        .submitLabel(.done)
                        .autocorrectionDisabled()
                        .onSubmit { noteFocused = false }
                        .padding(.horizontal, 16)
                }
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .circular)
                        .fill(Color(uiColor: .secondarySystemFill))
                )
                .padding(.horizontal, 20)

                // 发送按钮
                Button {
                    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSend(trimmed.isEmpty ? nil : trimmed)
                    dismiss()
                } label: {
                    Text("Send Request")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(.white)
                        .background(.black, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                // 取消按钮
                Button {
                    onCancel()
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 36)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onTapGesture { hideKeyboard() }
    }
}

// MARK: - 通用好友头像 View

/// 优先显示 Supabase avatar_url；无头像时显示苹果官方 person.fill 占位符
struct FriendAvatarView: View {
    let name: String?
    let avatarUrl: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let urlString = avatarUrl,
               !urlString.isEmpty,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        placeholderCircle
                    }
                }
            } else {
                placeholderCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholderCircle: some View {
        Circle()
            .fill(Color(uiColor: .systemGray5))
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45, weight: .regular))
                    .foregroundStyle(Color(uiColor: .systemGray2))
            }
    }
}
