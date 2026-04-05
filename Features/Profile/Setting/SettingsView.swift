//
//  SettingsView.swift
//  MOMENTA
//
//  设置页：恢复上一版原生 insetGrouped 结构，
//  保留账户编辑入口并支持修改 Display Name。
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject var authViewModel: AuthViewModel
    @ObservedObject var profileViewModel: ProfileViewModel

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
            .scrollDismissesKeyboard(.immediately)
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

    private var accountSection: some View {
        Section {
            NavigationLink {
                EditAccountView(profileViewModel: profileViewModel, email: viewModel.userEmail)
            } label: {
                HStack(spacing: 14) {
                    Group {
                        if let avatar = profileViewModel.profileAvatarImage {
                            Image(uiImage: avatar)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Circle()
                                .fill(Color(.systemGray5))
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.secondary)
                                )
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(profileViewModel.displayName)
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

    private var settingsSection: some View {
        Section("Settings") {
            Toggle(isOn: $viewModel.notificationsEnabled) {
                Label {
                    Text("Notifications")
                } icon: {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(.red)
                }
            }
            .tint(.purple)

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

    private var generalSection: some View {
        Section("General") {
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

    private var accountActionsSection: some View {
        Section {
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

            Button {
                viewModel.showDeleteConfirmation = true
            } label: {
                Label {
                    Text("Delete Account")
                } icon: {
                    Image(systemName: "trash")
                }
                .foregroundStyle(.red)
            }
        }
    }

    private var versionFooter: some View {
        Section {
            HStack {
                Spacer()
                Text(viewModel.appVersion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .listRowBackground(Color.clear)
    }
}

private struct EditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var profileViewModel: ProfileViewModel

    let email: String

    @State private var displayName = ""
    @State private var showAvatarOptions = false
    @State private var showAvatarPicker = false
    @State private var avatarPickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var pendingAvatarImage: UIImage?

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Button {
                            showAvatarOptions = true
                        } label: {
                            Group {
                                if let avatar = profileViewModel.profileAvatarImage {
                                    Image(uiImage: avatar)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else {
                                    Circle()
                                        .fill(Color(.systemGray5))
                                        .overlay(
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 32))
                                                .foregroundStyle(.secondary)
                                        )
                                }
                            }
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.circle.fill")
                                    .font(.system(size: 24))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.blue)
                                    .offset(x: 4, y: 4)
                            }
                        }
                        .buttonStyle(.plain)

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
                TextField("Name", text: $displayName)

                HStack {
                    Text("Email")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(email)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    profileViewModel.updateDisplayName(displayName)
                    dismiss()
                }
                .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            displayName = profileViewModel.displayName
        }
        .confirmationDialog(
            "Profile Photo",
            isPresented: $showAvatarOptions,
            titleVisibility: .visible
        ) {
            Button("Take Photo") {
                avatarPickerSource = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
                showAvatarPicker = true
            }

            Button("Choose from Library") {
                avatarPickerSource = .photoLibrary
                showAvatarPicker = true
            }

            if profileViewModel.profileAvatarImage != nil {
                Button("Remove Photo", role: .destructive) {
                    profileViewModel.removeProfilePhoto()
                }
            }
        }
        .sheet(isPresented: $showAvatarPicker) {
            ImagePicker(sourceType: avatarPickerSource, selectedImage: $pendingAvatarImage)
        }
        .onChange(of: pendingAvatarImage) { _, image in
            guard let image else { return }
            profileViewModel.updateProfilePhoto(with: image)
        }
    }
}
