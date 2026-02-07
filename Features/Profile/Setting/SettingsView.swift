//
//  SettingsView.swift
//  MOMENTA
//
//  设置页面：Apple 原生 insetGrouped List 风格，
//  参考 Apple Podcasts / Music 的 Account 页面设计。
//  以 sheet 形式从 ProfileView 呈现。
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject var authViewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            List {
                accountSection
                settingsSection
                generalSection
                accountActionsSection
                versionFooter
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(7)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
            }
            // Sign Out 确认
            .alert("Sign Out", isPresented: $viewModel.showSignOutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    Task {
                        await viewModel.signOut()
                        dismiss()
                    }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            // Delete Account 确认
            .alert("Delete Account", isPresented: $viewModel.showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteAccount()
                        dismiss()
                    }
                }
            } message: {
                Text("This action cannot be undone. All your data will be permanently deleted.")
            }
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section {
            NavigationLink {
                editProfilePlaceholder
            } label: {
                HStack(spacing: 14) {
                    // 头像
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.secondary)
                        )

                    // 用户名 & 邮箱
                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.displayName)
                            .font(.system(size: 17, weight: .semibold))

                        Text(viewModel.userEmail)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    /// 编辑个人资料页面（占位）
    private var editProfilePlaceholder: some View {
        List {
            Section {
                // 头像更换入口
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary)
                            )
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.circle.fill")
                                    .font(.system(size: 24))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.blue)
                                    .offset(x: 4, y: 4)
                            }

                        Text("Change Avatar")
                            .font(.footnote)
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Profile") {
                HStack {
                    Text("Name")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.displayName)
                }

                HStack {
                    Text("Email")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.userEmail)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Membership")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Founder Member")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Settings Section (Notifications & Privacy)

    private var settingsSection: some View {
        Section("Settings") {
            // 消息通知开关
            Toggle(isOn: $viewModel.notificationsEnabled) {
                Label {
                    Text("Notifications")
                } icon: {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(.red)
                }
            }
            .tint(.purple)

            // 隐私设置
            NavigationLink {
                privacyPlaceholder
            } label: {
                Label {
                    Text("Privacy")
                } icon: {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    /// 隐私设置页面（占位）
    private var privacyPlaceholder: some View {
        List {
            Section("Visibility") {
                Toggle(isOn: .constant(true)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Public Profile")
                        Text("Allow others to see your profile")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.purple)

                Toggle(isOn: .constant(false)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Discoverable")
                        Text("Allow others to find you by email")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.purple)
            }

            Section("Data") {
                Toggle(isOn: .constant(true)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share Analytics")
                        Text("Help improve MOMENTA by sharing usage data")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.purple)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - General Section

    private var generalSection: some View {
        Section("General") {
            // 外观模式
            Picker(selection: $viewModel.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            } label: {
                Label {
                    Text("Appearance")
                } icon: {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.indigo)
                }
            }

            // 语言
            Picker(selection: $viewModel.appLanguage) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            } label: {
                Label {
                    Text("Language")
                } icon: {
                    Image(systemName: "globe")
                        .foregroundStyle(.cyan)
                }
            }

            // 字体大小
            Picker(selection: $viewModel.fontSizeLevel) {
                ForEach(FontSizeLevel.allCases) { size in
                    Text(size.displayName).tag(size)
                }
            } label: {
                Label {
                    Text("Font Size")
                } icon: {
                    Image(systemName: "textformat.size")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Account Actions

    private var accountActionsSection: some View {
        Section {
            // 退出登录
            Button {
                viewModel.showSignOutConfirmation = true
            } label: {
                Label {
                    Text("Sign Out")
                } icon: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .foregroundStyle(.red)
            }

            // 切换账号
            Button {
                Task {
                    await viewModel.switchAccount()
                    dismiss()
                }
            } label: {
                Label {
                    Text("Switch Account")
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .foregroundStyle(.purple)
            }

            // 删除账号
            Button {
                viewModel.showDeleteConfirmation = true
            } label: {
                Label {
                    Text("Delete Account")
                } icon: {
                    Image(systemName: "person.crop.circle.badge.minus")
                }
                .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Version Footer

    private var versionFooter: some View {
        Section {
            EmptyView()
        } footer: {
            Text("MOMENTA \(viewModel.appVersion)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }
}
