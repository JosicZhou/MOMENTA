//
//  ContentView.swift
//  Butterfly
//
//  App 的主入口，负责管理 Tab 导航框架
//

import SwiftUI
import AVKit

// MARK: - Main ContentView

struct ContentView: View {
    private enum AppTab {
        static let light = 0
        static let memories = 1
        static let share = 2
        static let profile = 3
    }

    private enum GenerationSource {
        case light
        case memory
    }

    @ObservedObject var deepLinkRouter: DeepLinkRouter
    @StateObject private var viewModel = LightViewModel()
    @StateObject private var memoryViewModel = MemoryViewModel()
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var profileViewModel = ProfileViewModel()
    @State private var selectedTab = AppTab.light
    @State private var showControls = true
    @State private var playerManager = PlayerManager()

    // 全局设置：外观模式 & 字体大小
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = "system"
    @AppStorage("fontSizeLevel") private var fontSizeLevelRaw: String = "standard"
    
    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                mainAppView
            } else {
                LoginView(viewModel: authViewModel)
            }
        }
        .preferredColorScheme(AppearanceMode(rawValue: appearanceModeRaw)?.colorScheme)
        .dynamicTypeSize(FontSizeLevel(rawValue: fontSizeLevelRaw)?.dynamicTypeSize ?? .medium)
        .onAppear {
            // 监听全局认证状态
            Task {
                for await (_, session) in AuthService.shared.authStateChanges() {
                    authViewModel.isAuthenticated = (session != nil)
                }
            }
            Task {
                handlePendingShareDeepLinkIfNeeded()
                handlePendingFriendCodeIfNeeded()
                await handlePendingSystemSongDeepLinkIfNeeded()
                await handlePendingMemoryDeepLinkIfNeeded()
                await SystemSongLibrarySync.shared.refresh()
            }
        }
        .onChange(of: authViewModel.isAuthenticated) { _, _ in
            handlePendingShareDeepLinkIfNeeded()
            handlePendingFriendCodeIfNeeded()
            Task {
                await handlePendingSystemSongDeepLinkIfNeeded()
                await handlePendingMemoryDeepLinkIfNeeded()
                await SystemSongLibrarySync.shared.refresh()
            }
        }
        .onChange(of: deepLinkRouter.pendingSystemSongRoute) { _, _ in
            Task {
                await handlePendingSystemSongDeepLinkIfNeeded()
            }
        }
        .onChange(of: deepLinkRouter.pendingMemoryTaskId) { _, _ in
            Task {
                await handlePendingMemoryDeepLinkIfNeeded()
            }
        }
        .onChange(of: deepLinkRouter.pendingShareRoute) { _, _ in
            handlePendingShareDeepLinkIfNeeded()
        }
        .onChange(of: deepLinkRouter.pendingFriendCode) { _, _ in
            handlePendingFriendCodeIfNeeded()
        }
    }
    
    // 将原有的 TabView 逻辑提取出来
    private var mainAppView: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                // 主页面 (Light 功能模块)
                ZStack {
                    Color(uiColor: .systemGray6)
                        .ignoresSafeArea()

                    LightView(viewModel: viewModel)
                }
                    .tabItem {
                        Image(systemName: "rays")
                            .accessibilityLabel("Light")
                    }
                    .tag(AppTab.light)
                
                // 回忆页面
                MemoriesView(viewModel: memoryViewModel, profileViewModel: profileViewModel)
                    .tabItem {
                        Image(systemName: "photo.on.rectangle.angled")
                            .accessibilityLabel("Memories")
                    }
                    .tag(AppTab.memories)

                // 分享页面
                ShareView(deepLinkRouter: deepLinkRouter)
                    .tabItem {
                        Image(systemName: "person.2.fill")
                            .accessibilityLabel("Share")
                    }
                    .tag(AppTab.share)
                
                // 个人资料页面
                ProfileView(
                    deepLinkRouter: deepLinkRouter,
                    viewModel: viewModel,
                    authViewModel: authViewModel,
                    profileViewModel: profileViewModel
                )
                    .tabItem {
                        Image(systemName: "person.circle.fill")
                            .accessibilityLabel("Profile")
                    }
                    .tag(AppTab.profile)
            }
            .tabViewStyle(.automatic)
            .onAppear {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.2)) {
                    showControls = true
                }
            }
            
            if viewModel.isGenerating
                || memoryViewModel.isGenerating
                || viewModel.generatedMusic != nil
                || memoryViewModel.generatedMusic != nil
                || playerManager.currentMusic != nil {
                ExpandablePlayerContainer(
                    music: resolvedBarMusic,
                    isGenerating: resolvedIsGenerating,
                    generationProgress: resolvedGenerationProgress
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: resolvedIsGenerating)
            }
        }
        .environment(playerManager)
        .sheet(isPresented: $viewModel.showImagePicker) {
            ImagePicker(
                sourceType: viewModel.imagePickerSourceType,
                selectedImage: $viewModel.selectedImage
            )
        }
        .alert("Error", isPresented: Binding(
            get: { globalErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    dismissGlobalErrors()
                }
            }
        )) {
            Button("OK", role: .cancel) {
                dismissGlobalErrors()
            }
        } message: {
            Text(globalErrorMessage ?? "")
        }
        .onChange(of: viewModel.generatedMusic) { _, newMusic in
            playerManager.currentMusic = newMusic
            // 切换歌曲时清除旧歌词状态
            playerManager.lyrics = []
            playerManager.currentLineIndex = 0
            playerManager.showLyrics = false
            playerManager.lyricsControlsVisible = true
            Task {
                await SystemSongLibrarySync.shared.refresh()
            }
        }
        .onChange(of: memoryViewModel.generatedMusic) { _, newMusic in
            playerManager.currentMusic = newMusic
            playerManager.lyrics = []
            playerManager.currentLineIndex = 0
            playerManager.showLyrics = false
            playerManager.lyricsControlsVisible = true
            Task {
                await SystemSongLibrarySync.shared.refresh()
            }
        }
    }

    private var activeGenerationSource: GenerationSource? {
        if memoryViewModel.isGenerating {
            return .memory
        }

        if viewModel.isGenerating {
            return .light
        }

        return nil
    }

    private var resolvedBarMusic: GeneratedMusic? {
        switch activeGenerationSource {
        case .memory:
            return memoryViewModel.generatedMusic ?? viewModel.generatedMusic ?? playerManager.currentMusic
        case .light:
            return viewModel.generatedMusic ?? memoryViewModel.generatedMusic ?? playerManager.currentMusic
        case nil:
            return playerManager.currentMusic ?? memoryViewModel.generatedMusic ?? viewModel.generatedMusic
        }
    }

    private var resolvedIsGenerating: Bool {
        activeGenerationSource != nil
    }

    private var resolvedGenerationProgress: String {
        switch activeGenerationSource {
        case .memory:
            return memoryViewModel.generationProgress
        case .light:
            return viewModel.generationProgress
        case nil:
            return ""
        }
    }

    private var globalErrorMessage: String? {
        memoryViewModel.errorMessage ?? viewModel.errorMessage
    }

    private func dismissGlobalErrors() {
        if memoryViewModel.errorMessage != nil {
            memoryViewModel.dismissError()
        }

        if viewModel.errorMessage != nil {
            viewModel.dismissError()
        }
    }

    private func handlePendingMemoryDeepLinkIfNeeded() async {
        guard authViewModel.isAuthenticated,
              let taskId = deepLinkRouter.pendingMemoryTaskId else {
            return
        }

        selectedTab = AppTab.memories

        do {
            if let music = try await MusicDatabaseService.shared.fetchMusicRecord(taskId: taskId) {
                memoryViewModel.generatedMusic = music
                playerManager.currentMusic = music
                playerManager.lyrics = []
                playerManager.currentLineIndex = 0
                playerManager.showLyrics = false
                playerManager.lyricsControlsVisible = true
                await memoryViewModel.refreshLibrary()
            }
        } catch {
            print("❌ [ContentView] Failed to open memory song deep link: \(error.localizedDescription)")
        }

        deepLinkRouter.clearPendingMemoryTaskId()
    }

    private func handlePendingSystemSongDeepLinkIfNeeded() async {
        guard authViewModel.isAuthenticated,
              let route = deepLinkRouter.pendingSystemSongRoute else {
            return
        }

        if let snapshot = SystemSongSnapshotStore().snapshot(taskId: route.taskId) {
            let music = snapshot.asGeneratedMusic()
            playerManager.currentMusic = music
            playerManager.lyrics = []
            playerManager.currentLineIndex = 0
            playerManager.showLyrics = false
            playerManager.lyricsControlsVisible = true
            if route.autoplay {
                playerManager.play()
            }
            deepLinkRouter.clearPendingSystemSongRoute()
            return
        }

        do {
            if let music = try await MusicDatabaseService.shared.fetchMusicRecord(taskId: route.taskId) {
                playerManager.currentMusic = music
                playerManager.lyrics = []
                playerManager.currentLineIndex = 0
                playerManager.showLyrics = false
                playerManager.lyricsControlsVisible = true
                if route.autoplay {
                    playerManager.play()
                }
            }
        } catch {
            print("❌ [ContentView] Failed to open song deep link: \(error.localizedDescription)")
        }

        deepLinkRouter.clearPendingSystemSongRoute()
    }

    private func handlePendingShareDeepLinkIfNeeded() {
        guard authViewModel.isAuthenticated,
              deepLinkRouter.pendingShareRoute != nil else {
            return
        }
        selectedTab = AppTab.share
    }

    private func handlePendingFriendCodeIfNeeded() {
        guard authViewModel.isAuthenticated,
              deepLinkRouter.pendingFriendCode?.isEmpty == false else {
            return
        }
        selectedTab = AppTab.profile
    }
}
