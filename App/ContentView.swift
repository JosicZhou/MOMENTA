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
    @StateObject private var viewModel = LightViewModel()
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
        }
    }
    
    // 将原有的 TabView 逻辑提取出来
    private var mainAppView: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                // 主页面 (Light 功能模块)
                LightView(viewModel: viewModel)
                    .tabItem {
                        Image(systemName: "lightbulb.fill")
                        Text("Light")
                    }
                    .tag(0)
                
                // 分享页面
                ShareView()
                    .tabItem {
                        Image(systemName: "person.2.fill")
                        Text("Share")
                    }
                    .tag(1)
                
                // 回忆页面
                MemoriesView()
                    .tabItem {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("Memories")
                    }
                    .tag(2)
                
                // 个人资料页面
                ProfileView(viewModel: viewModel, authViewModel: authViewModel, profileViewModel: profileViewModel)
                    .tabItem {
                        Image(systemName: "person.circle.fill")
                        Text("Profile")
                    }
                    .tag(3)
            }
            .tabViewStyle(.automatic)
            .onAppear {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.2)) {
                    showControls = true
                }
            }
            
            if viewModel.isGenerating || viewModel.generatedMusic != nil {
                ExpandablePlayerContainer(
                    music: viewModel.generatedMusic,
                    isGenerating: viewModel.isGenerating,
                    generationProgress: viewModel.generationProgress
                )
                .environment(playerManager)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.isGenerating)
            }
        }
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
    }
}
