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
    @StateObject private var shareCoCreateCoordinator = ShareCoCreateCoordinator.shared
    @StateObject private var shareActivityMonitor = ShareActivityMonitor.shared
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
            if authViewModel.isAuthenticated {
                Task {
                    await shareActivityMonitor.bootstrap()
                    shareActivityMonitor.startPolling()
                }
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
            if authViewModel.isAuthenticated {
                Task {
                    await shareActivityMonitor.bootstrap()
                    shareActivityMonitor.startPolling()
                }
            } else {
                shareActivityMonitor.stopPolling()
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
                MemoriesView(
                    viewModel: memoryViewModel,
                    profileViewModel: profileViewModel,
                    onOpenCoCreation: {
                        selectedTab = AppTab.share
                    }
                )
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

            if let session = shareCoCreateCoordinator.activeSession {
                ShareCoCreateFloatingOrb(
                    session: session,
                    bottomInset: showsPrimaryBar ? 132 : 88,
                    onTap: { shareCoCreateCoordinator.presentDetail() },
                    onOffsetChanged: { shareCoCreateCoordinator.updateOrbOffset($0) }
                )
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .animation(.snappy(duration: 0.28, extraBounce: 0.03), value: shareCoCreateCoordinator.activeSession?.id)
            }
        }
        .environment(playerManager)
        .sheet(isPresented: $viewModel.showImagePicker) {
            ImagePicker(
                sourceType: viewModel.imagePickerSourceType,
                selectedImage: $viewModel.selectedImage
            )
        }
        .sheet(
            isPresented: Binding(
                get: { shareCoCreateCoordinator.isPresentingDetail && shareCoCreateCoordinator.activeSession != nil },
                set: { isPresented in
                    if !isPresented {
                        shareCoCreateCoordinator.dismissDetail()
                    }
                }
            )
        ) {
            if let session = shareCoCreateCoordinator.activeSession {
                ShareCoCreateFloatingStatusSheet(
                    session: session,
                    onDismiss: { shareCoCreateCoordinator.dismissDetail() }
                )
            }
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
        .alert(
            "Co-create Ready",
            isPresented: Binding(
                get: { shareCoCreateCoordinator.completionNotice != nil },
                set: { isPresented in
                    if !isPresented {
                        shareCoCreateCoordinator.clearCompletionNotice()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                shareCoCreateCoordinator.clearCompletionNotice()
            }
        } message: {
            Text(shareCoCreateCoordinator.completionNotice?.message ?? "")
        }
        .alert(
            "Co-create Ready",
            isPresented: Binding(
                get: { shareActivityMonitor.completionNotice != nil },
                set: { isPresented in
                    if !isPresented {
                        shareActivityMonitor.clearCompletionNotice()
                    }
                }
            )
        ) {
            Button("Play Now") {
                Task { await playShareCompletionNotice() }
            }
            Button("View in Share") {
                selectedTab = AppTab.share
                shareActivityMonitor.clearCompletionNotice()
            }
            Button("Later", role: .cancel) {
                shareActivityMonitor.clearCompletionNotice()
            }
        } message: {
            Text(shareActivityMonitor.completionNotice?.message ?? "")
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

    private var showsPrimaryBar: Bool {
        viewModel.isGenerating
            || memoryViewModel.isGenerating
            || viewModel.generatedMusic != nil
            || memoryViewModel.generatedMusic != nil
            || playerManager.currentMusic != nil
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
        shareCoCreateCoordinator.errorMessage ?? memoryViewModel.errorMessage ?? viewModel.errorMessage
    }

    private func dismissGlobalErrors() {
        if shareCoCreateCoordinator.errorMessage != nil {
            shareCoCreateCoordinator.dismissError()
        }

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

    private func playShareCompletionNotice() async {
        defer { shareActivityMonitor.clearCompletionNotice() }
        guard let taskId = shareActivityMonitor.completionNotice?.taskId else { return }

        do {
            if let music = try await MusicDatabaseService.shared.fetchMusicRecord(taskId: taskId) {
                playerManager.currentMusic = music
                playerManager.lyrics = []
                playerManager.currentLineIndex = 0
                playerManager.showLyrics = false
                playerManager.lyricsControlsVisible = true
                playerManager.play()
            }
        } catch {
            print("❌ [ContentView] Failed to open share completion song: \(error.localizedDescription)")
        }
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

@MainActor
final class ShareCoCreateCoordinator: ObservableObject {
    struct ActiveSession: Identifiable {
        let id: UUID
        let title: String
        let collaboratorName: String
        let artworkURL: URL?
        var progressText: String
        var orbOffset: CGSize = .zero
    }

    struct CompletionNotice: Identifiable {
        let id = UUID()
        let message: String
    }

    static let shared = ShareCoCreateCoordinator()

    @Published private(set) var activeSession: ActiveSession?
    @Published var isPresentingDetail = false
    @Published var errorMessage: String?
    @Published var completionNotice: CompletionNotice?

    private var continuationTask: Task<Void, Never>?

    private init() {}

    func start(
        sessionId: UUID,
        title: String,
        collaboratorName: String,
        artworkURL: URL?,
        announceCompletion: Bool = true,
        onSuccess: ((GeneratedMusic) -> Void)? = nil,
        operation: @escaping (@escaping (String) -> Void) async throws -> GeneratedMusic
    ) {
        continuationTask?.cancel()
        activeSession = ActiveSession(
            id: sessionId,
            title: title,
            collaboratorName: collaboratorName,
            artworkURL: artworkURL,
            progressText: "Preparing the co-create…"
        )
        isPresentingDetail = false
        errorMessage = nil

        continuationTask = Task { [weak self] in
            do {
                let music = try await operation { progress in
                    Task { @MainActor in
                        guard let self else { return }
                        guard var session = self.activeSession, session.id == sessionId else { return }
                        session.progressText = progress
                        self.activeSession = session
                    }
                }

                await MainActor.run {
                    self?.activeSession = nil
                    self?.isPresentingDetail = false
                    let resolvedTitle = music.title.isEmpty ? title : music.title
                    if announceCompletion {
                        self?.completionNotice = CompletionNotice(message: "\"\(resolvedTitle)\" is ready.")
                    }
                    onSuccess?(music)
                }
                await SystemSongLibrarySync.shared.refresh()
            } catch is CancellationError {
                await MainActor.run {
                    self?.activeSession = nil
                    self?.isPresentingDetail = false
                }
            } catch {
                await MainActor.run {
                    self?.activeSession = nil
                    self?.isPresentingDetail = false
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func updateOrbOffset(_ offset: CGSize) {
        guard var session = activeSession else { return }
        session.orbOffset = offset
        activeSession = session
    }

    func presentDetail() {
        guard activeSession != nil else { return }
        isPresentingDetail = true
    }

    func dismissDetail() {
        isPresentingDetail = false
    }

    func dismissError() {
        errorMessage = nil
    }

    func clearCompletionNotice() {
        completionNotice = nil
    }
}

@MainActor
final class ShareActivityMonitor: ObservableObject {
    struct CompletionNotice: Identifiable {
        let id = UUID()
        let message: String
        let taskId: String?
    }

    static let shared = ShareActivityMonitor()

    @Published var completionNotice: CompletionNotice?

    private let cocreateService = CocreateService.shared
    private var pollingTask: Task<Void, Never>?
    private var knownStatuses: [UUID: CocreateSession.Status] = [:]
    private var hasBootstrapped = false

    private init() {}

    func bootstrap() async {
        guard let userId = await SupabaseService.shared.getCurrentUserId() else {
            knownStatuses = [:]
            hasBootstrapped = false
            return
        }

        do {
            let sessions = try await cocreateService.loadMySessions(userId: userId)
            knownStatuses = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.status) })
            hasBootstrapped = true
        } catch {
            // Keep previous state; failures here should not spam alerts.
        }
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        knownStatuses = [:]
        hasBootstrapped = false
        completionNotice = nil
    }

    func clearCompletionNotice() {
        completionNotice = nil
    }

    private func refresh() async {
        guard hasBootstrapped,
              let userId = await SupabaseService.shared.getCurrentUserId() else {
            return
        }

        do {
            let sessions = try await cocreateService.loadMySessions(userId: userId)
            for session in sessions {
                let previous = knownStatuses[session.id]
                if previous != .completed, session.status == .completed {
                    let title = (session.sourceTitle?.isEmpty == false ? session.sourceTitle! : "Your co-create")
                    completionNotice = CompletionNotice(
                        message: "\"\(title)\" has finished rendering.",
                        taskId: session.extendTaskId ?? session.sourceTaskId
                    )
                    break
                }
            }
            knownStatuses = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.status) })
        } catch {
            // Swallow transient network / realtime failures; polling will retry.
        }
    }
}

private struct ShareCoCreateFloatingOrb: View {
    let session: ShareCoCreateCoordinator.ActiveSession
    let bottomInset: CGFloat
    let onTap: () -> Void
    let onOffsetChanged: (CGSize) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @GestureState private var dragTranslation: CGSize = .zero

    private var theme: OrbTheme { OrbTheme(colorScheme: colorScheme) }
    private var committedOffset: CGSize { session.orbOffset }
    private var effectiveOffset: CGSize {
        CGSize(
            width: committedOffset.width + dragTranslation.width,
            height: committedOffset.height + dragTranslation.height
        )
    }

    var body: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                Button(action: onTap) {
                    orbBody
                }
                .buttonStyle(.plain)
                .simultaneousGesture(dragGesture)
                .offset(effectiveOffset)
                .padding(.trailing, 20)
                .padding(.bottom, bottomInset)
            }
        }
        .ignoresSafeArea(.keyboard)
        .allowsHitTesting(true)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let next = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
                onOffsetChanged(
                    CGSize(
                        width: min(max(next.width, -220), 12),
                        height: min(max(next.height, -420), 120)
                    )
                )
            }
    }

    private var orbBody: some View {
        ZStack {
            orbArtwork
                .frame(width: 62, height: 62)
                .clipShape(Circle())

            Circle()
                .stroke(theme.ringTrack, lineWidth: 2.5)

            Circle()
                .trim(from: 0, to: 0.78)
                .stroke(theme.ringTint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 70, height: 70)
        .background(orbBackground)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.10), radius: 16, y: 10)
        .overlay(alignment: .bottomTrailing) {
            ProgressView()
                .controlSize(.mini)
                .tint(theme.progressTint)
                .frame(width: 22, height: 22)
                .background(theme.badgeBackground, in: Circle())
                .offset(x: 2, y: 2)
        }
        .accessibilityLabel("Co-create in progress")
        .accessibilityHint("Opens the active co-create status.")
    }

    @ViewBuilder
    private var orbArtwork: some View {
        if let artworkURL = session.artworkURL {
            AsyncImage(url: artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    fallbackArtwork
                }
            }
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(uiColor: .systemIndigo), Color(uiColor: .systemPink)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
    }

    @ViewBuilder
    private var orbBackground: some View {
        if #available(iOS 26, *) {
            Circle()
                .fill(.clear)
                .glassEffect(.regular.tint(theme.glassTint).interactive(), in: .circle)
        } else {
            Circle()
                .fill(.ultraThinMaterial)
        }
    }
}

private struct ShareCoCreateFloatingStatusSheet: View {
    let session: ShareCoCreateCoordinator.ActiveSession
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var theme: OrbTheme { OrbTheme(colorScheme: colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    artwork
                        .frame(width: 220, height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.title)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(theme.primaryText)

                        Text("Co-create with \(session.collaboratorName)")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(theme.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.regular)
                                .tint(theme.primaryText)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.progressText)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(theme.primaryText)

                                Text("You can leave this sheet. The floating orb will stay visible across tabs until the continuation finishes.")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(theme.primaryText.opacity(0.82))
                    }
                    .padding(20)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(theme.stroke, lineWidth: 0.8)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        statusRow(
                            title: "Working in the background",
                            subtitle: "The continuation keeps running even if you move to Light, Memories, Share, or Profile."
                        )
                        statusRow(
                            title: "Recent Activity updates automatically",
                            subtitle: "The sender-side session can flip from waiting to generating to ready as the session progresses."
                        )
                        statusRow(
                            title: "Completion appears automatically",
                            subtitle: "When the song finishes, the orb disappears and MOMENTA shows a completion notice."
                        )
                    }
                    .padding(18)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(theme.stroke, lineWidth: 0.8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }
            .background(theme.pageBackground)
            .navigationTitle("Co-create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL = session.artworkURL {
            AsyncImage(url: artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    fallbackArtwork
                }
            }
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(uiColor: .systemIndigo), Color(uiColor: .systemPink)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
    }

    private func statusRow(title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
                .controlSize(.mini)
                .tint(theme.primaryText.opacity(0.78))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OrbTheme {
    let colorScheme: ColorScheme

    var pageBackground: Color { Color(uiColor: .systemGray6) }
    var surface: Color { Color(uiColor: .systemBackground) }
    var stroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05)
    }
    var primaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.95) : Color.black.opacity(0.96)
    }
    var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.56)
    }
    var ringTint: Color { Color(uiColor: .systemIndigo).opacity(0.95) }
    var ringTrack: Color { Color.white.opacity(colorScheme == .dark ? 0.16 : 0.55) }
    var progressTint: Color { primaryText }
    var badgeBackground: Color { surface }
    var glassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.08)
    }
}
