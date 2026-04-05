//
//  ShareView.swift
//  MOMENTA
//
//  Cocreate 测试界面。三段式布局：
//  1. Friends —— 好友码 / 添加 / 列表 / 待处理请求
//  2. Start Cocreate (A) —— 输入 + 生成半首 + 选好友发送
//  3. Continue a Song (B) —— 待续写列表 + 续写输入 + extend
//

import SwiftUI

struct ShareView: View {

    @StateObject private var vm = ShareViewModel()
    @Environment(PlayerManager.self) private var playerManager
    @State private var showImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var imagePickerTarget: ImagePickerTarget = .aSide
    @State private var expandedSessionId: UUID?

    enum ImagePickerTarget { case aSide, bSide }

    var body: some View {
        NavigationStack {
            List {
                cocreateASection
                if !vm.completedItems.isEmpty {
                    cocreateCompletedSection
                }
                cocreateBSection
            }
            .navigationTitle("Cocreate")
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
            .refreshable {
                await vm.refreshFriends()
                await vm.loadPendingSessions()
                await vm.loadCompletedItems()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let notice = vm.completionNotice {
                    completionBanner(message: notice)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .alert("Error", isPresented: $vm.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(
                sourceType: imagePickerSource,
                selectedImage: imagePickerTarget == .aSide ? $vm.selectedImage : $vm.bSelectedImage
            )
        }
        .task {
            await vm.requestHealthAccess()
            await vm.fetchEnvironment()
            await vm.onAppear()
        }
        .onChange(of: vm.halfSongResult) { _, music in
            guard let music else { return }
            playerManager.currentMusic = music
            playerManager.lyrics = []
            playerManager.currentLineIndex = 0
            playerManager.showLyrics = false
            playerManager.lyricsControlsVisible = true
            playerManager.effectiveLyricDuration = music.continueAtSec  // cocreate: 只显示到裁剪点
            playerManager.play()
        }
        .onChange(of: vm.extendedMusic) { _, music in
            guard let music else { return }
            playerManager.currentMusic = music
            playerManager.lyrics = []
            playerManager.currentLineIndex = 0
            playerManager.showLyrics = false
            playerManager.lyricsControlsVisible = true
            playerManager.effectiveLyricDuration = nil  // 完整歌曲，不裁剪
            playerManager.play()
        }
    }

    // MARK: - Completion Banner

    private func completionBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 20))
            Text(message)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.3)) {
                    vm.completionNotice = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Section: A Side Completed Cocreates

    private var cocreateCompletedSection: some View {
        Section {
            ForEach(vm.completedItems) { item in
                completedCocreateRow(item: item)
            }
        } header: {
            Label("Your Cocreates", systemImage: "checkmark.seal.fill")
        }
    }

    @ViewBuilder
    private func completedCocreateRow(item: ShareViewModel.CompletedCocreate) -> some View {
        HStack(spacing: 14) {
            // Album art
            AsyncImage(url: item.music.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle()
                        .fill(Color(uiColor: .secondarySystemFill))
                        .overlay(
                            Image(systemName: "music.mic")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(item.music.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                if let name = item.inviteeName {
                    Text("Cocreated with \(name)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Cocreated")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                if !item.music.style.isEmpty {
                    Text(item.music.style)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Play button
            Button {
                playerManager.currentMusic = item.music
                playerManager.lyrics = []
                playerManager.currentLineIndex = 0
                playerManager.showLyrics = false
                playerManager.lyricsControlsVisible = true
                playerManager.effectiveLyricDuration = nil
                playerManager.play()
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Section 1: A Side (Generate Half)

    private var cocreateASection: some View {
        Section {
            if let image = vm.selectedImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Button { vm.selectedImage = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .padding(6)
                }
            } else {
                HStack(spacing: 8) {
                    Button { openPicker(.camera, target: .aSide) } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    .buttonStyle(.bordered)
                    Button { openPicker(.photoLibrary, target: .aSide) } label: {
                        Label("Photo", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                }
            }

            TextField("Describe a memory...", text: $vm.prompt, axis: .vertical)
                .lineLimit(2...4)

            HStack(spacing: 12) {
                Picker("", selection: $vm.language) {
                    Text("EN").tag("en")
                    Text("中文").tag("zh")
                }
                .pickerStyle(.segmented)
                .frame(width: 110)

                Toggle(isOn: $vm.instrumentalOnly) {
                    Label("Instrumental", systemImage: "music.note")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .tint(vm.instrumentalOnly ? .orange : .gray)

                Toggle(isOn: $vm.usePsychologicalProfile) {
                    Label("Health", systemImage: "heart.fill")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .tint(vm.usePsychologicalProfile ? .pink : .gray)
            }

            Button {
                Task { await vm.generateHalfSong() }
            } label: {
                Group {
                    if vm.isGeneratingHalf {
                        HStack(spacing: 6) {
                            ProgressView().tint(.white)
                            Text(vm.generationProgress)
                        }
                    } else {
                        Label("Generate Half Song", systemImage: "wand.and.stars")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isGeneratingHalf)

            if let half = vm.halfSongResult {
                VStack(alignment: .leading, spacing: 4) {
                    Text(half.title).font(.headline)
                    Text(half.style).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let cap = half.continueAtSec {
                        Text("Cut at \(String(format: "%.1f", cap))s")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }

                if !vm.friends.isEmpty {
                    ForEach(vm.friends) { friend in
                        Button {
                            Task { await vm.sendToFriend(friend) }
                        } label: {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                Text("Send to \(friend.resolvedName)")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }
                } else {
                    Text("Add friends from Profile to send.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if vm.selectedFriend != nil {
                    Label("Sent!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
        } header: {
            Label("Start Cocreate", systemImage: "music.note.list")
        }
    }

    // MARK: - Section 2: B Side (Continue / Extend)

    private var cocreateBSection: some View {
        Section {
            if vm.pendingSessions.isEmpty {
                Text("No pending invitations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.pendingSessions) { session in
                    VStack(alignment: .leading, spacing: 0) {
                        sessionHeader(session: session)

                        if expandedSessionId == session.id {
                            Divider().padding(.vertical, 8)
                            extendComposer(session: session)
                        }
                    }
                }
            }
        } header: {
            Label("Continue a Song", systemImage: "arrow.right.circle")
        }
    }

    @ViewBuilder
    private func sessionHeader(session: CocreateSession) -> some View {
        HStack(spacing: 14) {
            // Album art
            AsyncImage(url: session.sourceImageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle()
                        .fill(Color(uiColor: .secondarySystemFill))
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(session.sourceTitle ?? session.profileA.title ?? "Untitled Song")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                Text("From \(session.creatorDisplayName ?? "a friend")")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                if let style = session.profileA.style, !style.isEmpty {
                    Text(style)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Text("Continue at \(String(format: "%.0f", session.continueAtSec))s")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation {
                    expandedSessionId = expandedSessionId == session.id ? nil : session.id
                }
            } label: {
                Image(systemName: expandedSessionId == session.id ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    // MARK: - B Side Composer (inline)

    @ViewBuilder
    private func extendComposer(session: CocreateSession) -> some View {
        if let image = vm.bSelectedImage {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button { vm.bSelectedImage = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .padding(4)
            }
        } else {
            HStack(spacing: 6) {
                Button { openPicker(.camera, target: .bSide) } label: {
                    Label("Camera", systemImage: "camera").font(.caption)
                }
                .buttonStyle(.bordered)
                Button { openPicker(.photoLibrary, target: .bSide) } label: {
                    Label("Photo", systemImage: "photo").font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }

        TextField("Your continuation idea...", text: $vm.bPrompt, axis: .vertical)
            .lineLimit(2...3)
            .font(.subheadline)

        HStack(spacing: 10) {
            Picker("", selection: $vm.bLanguage) {
                Text("EN").tag("en")
                Text("中文").tag("zh")
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
        }

        Button {
            Task { await vm.extendSong(session: session) }
        } label: {
            Group {
                if vm.isExtending {
                    HStack(spacing: 6) {
                        ProgressView().tint(.white)
                        Text(vm.extendProgress)
                    }
                } else {
                    Label("Continue & Extend", systemImage: "arrow.right.circle.fill")
                }
            }
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple)
        .disabled(vm.isExtending)

        if let extended = vm.extendedMusic {
            VStack(alignment: .leading, spacing: 2) {
                Text(extended.title).font(.subheadline.bold())
                Text("Full cocreated song ready!")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Helpers

    private func openPicker(_ source: UIImagePickerController.SourceType, target: ImagePickerTarget) {
        imagePickerSource = source
        imagePickerTarget = target
        showImagePicker = true
    }
}
