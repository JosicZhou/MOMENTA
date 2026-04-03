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
    @ObservedObject var deepLinkRouter: DeepLinkRouter
    @StateObject private var viewModel = LightViewModel()
    @StateObject private var memoryViewModel = MemoryViewModel()
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var profileViewModel = ProfileViewModel()
    @State private var selectedTab = 0
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
                for await (event, session) in AuthService.shared.authStateChanges() {
                    authViewModel.isAuthenticated = (session != nil)
                }
            }
            Task {
                await handlePendingMemoryDeepLinkIfNeeded()
            }
        }
        .onChange(of: authViewModel.isAuthenticated) { _, _ in
            Task {
                await handlePendingMemoryDeepLinkIfNeeded()
            }
        }
        .onChange(of: deepLinkRouter.pendingMemoryTaskId) { _, _ in
            Task {
                await handlePendingMemoryDeepLinkIfNeeded()
            }
        }
    }
    
    // 将原有的 TabView 逻辑提取出来
    private var mainAppView: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                // 主页面 (Light 功能模块)
                LightView(viewModel: viewModel)
                    .tabItem {
                        Image(systemName: "rays")
                            .accessibilityLabel("Light")
                    }
                    .tag(0)
                
                // 分享页面
                ShareView()
                    .tabItem {
                        Image(systemName: "person.2.fill")
                            .accessibilityLabel("Share")
                    }
                    .tag(1)
                
                // 回忆页面
                MemoriesView(viewModel: memoryViewModel, profileViewModel: profileViewModel)
                    .tabItem {
                        Image(systemName: "photo.on.rectangle.angled")
                            .accessibilityLabel("Memories")
                    }
                    .tag(2)
                
                // 个人资料页面
                ProfileView(viewModel: viewModel, authViewModel: authViewModel, profileViewModel: profileViewModel)
                    .tabItem {
                        Image(systemName: "person.circle.fill")
                            .accessibilityLabel("Profile")
                    }
                    .tag(3)
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
                    music: playerManager.currentMusic ?? activeGeneratedMusic,
                    isGenerating: activeIsGenerating,
                    generationProgress: activeGenerationProgress
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: activeIsGenerating)
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
            get: { viewModel.errorMessage != nil },
            set: { newValue in if !newValue { viewModel.dismissError() } }
        )) {
            Button("OK", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: viewModel.generatedMusic) { _, newMusic in
            playerManager.currentMusic = newMusic
            // 切换歌曲时清除旧歌词状态
            playerManager.lyrics = []
            playerManager.currentLineIndex = 0
            playerManager.showLyrics = false
            playerManager.lyricsControlsVisible = true
        }
        .onChange(of: memoryViewModel.generatedMusic) { _, newMusic in
            playerManager.currentMusic = newMusic
            playerManager.lyrics = []
            playerManager.currentLineIndex = 0
            playerManager.showLyrics = false
            playerManager.lyricsControlsVisible = true
        }
    }

    private var activeGeneratedMusic: GeneratedMusic? {
        if selectedTab == 2 {
            return memoryViewModel.generatedMusic ?? viewModel.generatedMusic
        }
        return viewModel.generatedMusic ?? memoryViewModel.generatedMusic
    }

    private var activeIsGenerating: Bool {
        selectedTab == 2 ? memoryViewModel.isGenerating : viewModel.isGenerating
    }

    private var activeGenerationProgress: String {
        selectedTab == 2 ? memoryViewModel.generationProgress : viewModel.generationProgress
    }

    private func handlePendingMemoryDeepLinkIfNeeded() async {
        guard authViewModel.isAuthenticated,
              let taskId = deepLinkRouter.pendingMemoryTaskId else {
            return
        }

        selectedTab = 2

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
}
