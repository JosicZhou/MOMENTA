import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins
#if canImport(VisionKit)
import VisionKit
#endif

struct ShareView: View {
    private enum ActivityFilter: String, CaseIterable, Identifiable {
        case drafts
        case completed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .drafts:
                return "Draft"
            case .completed:
                return "Completed"
            }
        }
    }

    @ObservedObject var deepLinkRouter: DeepLinkRouter
    @Environment(PlayerManager.self) private var playerManager
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isCreateInputFocused: Bool

    @StateObject private var viewModel = ShareViewModel()
    @State private var showFriendsSheet = false
    @State private var selectedSongForSend: GeneratedMusic?
    @State private var sendSheetAllowedModes: [ShareSendMode] = ShareSendMode.allCases
    @State private var sendSheetInitialMode: ShareSendMode = .shareOnly
    @State private var sendSheetDraftActivityID: UUID?
    @State private var sendSheetDidSend = false
    @State private var composerContext: ShareComposerSheetContext?
    @State private var navigationPath = NavigationPath()
    @State private var pendingPreparedCoCreate: PreparedCoCreateDraft?
    @State private var preferredCreateLanguage = "en"
    @State private var createPrompt = ""
    @State private var createSelectedImage: UIImage?
    @State private var createInstrument = ""
    @State private var createHasVocals = true
    @State private var showCreateImagePicker = false
    @State private var createImagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedActivityFilter: ActivityFilter = .drafts

    private var theme: ShareTheme { ShareTheme(colorScheme: colorScheme) }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: ShareLayout.rootSectionSpacing) {
                        header
                        createComposerSection
                        destinationCards
                        activitySection
                    }
                    .frame(width: ShareLayout.contentWidth(for: proxy.size.width), alignment: .leading)
                    .padding(.top, ShareLayout.topPadding)
                    .padding(.bottom, ShareLayout.bottomPadding)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .background(theme.pageBackground.ignoresSafeArea())
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ShareDestination.self) { destination in
                switch destination {
                case .inbox:
                    ShareInboxHubView(
                        viewModel: viewModel,
                        onPlay: playSong,
                        onOpenComposerForSession: { item in
                            composerContext = .continueSession(item)
                        }
                    )
                case .outbox:
                    ShareOutboxHubView(
                        activities: outboxItems,
                        theme: theme,
                        onOpen: { activity in
                            navigationPath.append(ShareDestination.activityDetail(activity.id))
                        },
                        onResumeSend: { activity in
                            resumePreparedCoCreate(from: activity)
                        },
                        onPlay: { activity in
                            playCompletedActivity(activity)
                        },
                        onDelete: { activity in
                            deleteActivity(activity)
                        }
                    )
                case .invitationDetail(let sessionId):
                    if let item = viewModel.invitation(sessionId: sessionId) {
                        ShareCoCreateDetailView(
                            item: item,
                            onPlay: playSong,
                            onContinue: {
                                if item.session != nil {
                                    composerContext = .continueSession(item)
                                }
                            },
                            onDecline: {
                                Task { await viewModel.declineInvitation(item) }
                            }
                        )
                    } else {
                        ShareMissingDetailView(
                            title: "Request unavailable",
                            subtitle: "This co-create request is no longer available."
                        )
                    }
                case .sharedSongDetail(let taskId):
                    if let item = viewModel.sharedSong(taskId: taskId) {
                        ShareSharedSongDetailView(
                            item: item,
                            onPlay: playSong,
                            onSave: {
                                Task { await viewModel.save(song: item.song) }
                            }
                        )
                    } else {
                        ShareMissingDetailView(
                            title: "Shared song unavailable",
                            subtitle: "This song is no longer available in your inbox."
                        )
                    }
                case .activityDetail(let activityId):
                    if let activity = viewModel.activity(id: activityId) {
                        ShareActivityDetailView(
                            activity: activity,
                            theme: theme,
                            onResumeSend: activity.isSendResumable ? {
                                resumePreparedCoCreate(from: activity)
                            } : nil,
                            onPlay: activity.status == .completed ? {
                                playCompletedActivity(activity)
                            } : nil,
                            onDelete: {
                                deleteActivity(activity)
                            }
                        )
                    } else {
                        ShareMissingDetailView(
                            title: "Activity unavailable",
                            subtitle: "This session is no longer available."
                        )
                    }
                }
            }
            .sheet(isPresented: $showFriendsSheet, onDismiss: {
                Task { await viewModel.load() }
            }) {
                FriendsSheet(
                    prefilledFriendCode: deepLinkRouter.pendingFriendCode,
                    onConsumePrefilledCode: { deepLinkRouter.clearPendingFriendCode() }
                )
            }
            .sheet(item: $selectedSongForSend, onDismiss: {
                let didSend = sendSheetDidSend
                sendSheetAllowedModes = ShareSendMode.allCases
                sendSheetInitialMode = .shareOnly
                sendSheetDraftActivityID = nil
                sendSheetDidSend = false
                if didSend {
                    pendingPreparedCoCreate = nil
                }
                Task { await viewModel.load() }
            }) { song in
                ShareSendSheet(
                    song: song,
                    friends: viewModel.friends,
                    theme: theme,
                    allowedModes: sendSheetAllowedModes,
                    initialMode: sendSheetInitialMode,
                    onAddFriends: { showFriendsSheet = true },
                    onSend: { friend, mode in
                        Task {
                            do {
                                if mode == .coCreate,
                                   let prepared = pendingPreparedCoCreate,
                                   prepared.song.id == song.id {
                                    try await viewModel.sendPreparedCoCreate(
                                        song: prepared.song,
                                        sessionId: prepared.sessionId,
                                        to: friend
                                    )
                                } else {
                                    try await viewModel.send(
                                        song: song,
                                        to: friend,
                                        mode: mode,
                                        replacingActivityID: sendSheetDraftActivityID
                                    )
                                }
                                sendSheetDidSend = true
                                pendingPreparedCoCreate = nil
                                selectedSongForSend = nil
                            } catch {
                                viewModel.errorMessage = error.localizedDescription
                            }
                        }
                    }
                )
            }
            .sheet(item: $composerContext, onDismiss: {
                Task { await viewModel.load() }
            }) { context in
                ShareComposerSheet(
                    context: context,
                    initialLanguage: preferredCreateLanguage,
                    onStartCreateNew: { request in
                        let localDraftID = viewModel.beginGeneratingCreateHalfActivity()
                        Task {
                            do {
                                let prepared = try await viewModel.generateHalfSongForCreateHub(request: request)
                                viewModel.promoteGeneratingActivity(localDraftID, to: prepared)
                                pendingPreparedCoCreate = prepared
                                openPreparedCoCreate(prepared)
                            } catch {
                                viewModel.removeActivity(id: localDraftID)
                                viewModel.errorMessage = error.localizedDescription
                            }
                        }
                    },
                    onFinished: {
                        Task { await viewModel.load() }
                    }
                )
            }
            .sheet(isPresented: $showCreateImagePicker) {
                ImagePicker(sourceType: createImagePickerSourceType, selectedImage: $createSelectedImage)
            }
            .task {
                await viewModel.load()
                viewModel.startActivityPolling()
                handlePendingShareRouteIfNeeded()
            }
            .onDisappear {
                viewModel.stopActivityPolling()
            }
            .onChange(of: deepLinkRouter.pendingShareRoute) { _, _ in
                handlePendingShareRouteIfNeeded()
            }
            .alert(
                "Share",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { isPresented in
                        if !isPresented { viewModel.errorMessage = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 22) {
            SharePosterTitleBlock(theme: theme)
                .frame(width: ShareLayout.posterTitleWidth, alignment: .leading)

            Spacer(minLength: 0)

            Text("Co-creation of music with your friends")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(theme.secondaryText)
                .frame(width: ShareLayout.posterBodyWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
        }
        .frame(minHeight: ShareLayout.headerMinHeight, alignment: .bottomLeading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var createComposerSection: some View {
        CoCreationInlineComposer(
            prompt: $createPrompt,
            selectedImage: $createSelectedImage,
            preferredLanguage: preferredCreateLanguage,
            isTextFieldFocused: $isCreateInputFocused,
            isGenerating: viewModel.isGeneratingCreateHalf,
            hasVocals: createHasVocals,
            selectedInstrument: createInstrument,
            progressText: viewModel.createHalfProgress,
            onToggleLanguage: togglePreferredCreateLanguage,
            onCameraPress: {
                createImagePickerSourceType = .camera
                showCreateImagePicker = true
            },
            onPhotoPress: {
                createImagePickerSourceType = .photoLibrary
                showCreateImagePicker = true
            },
            onVocalsChange: { createHasVocals = $0 },
            onInstrumentSelect: { createInstrument = $0 },
            onGeneratePress: startInlineCreateGeneration
        )
    }

    private var destinationCards: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: ShareDestination.inbox) {
                ShareHeroCard(
                    title: "Inbox",
                    subtitle: inboxSubtitle,
                    systemImage: "tray.and.arrow.down",
                    iconTint: inboxItems.isEmpty ? theme.secondaryText : theme.accent,
                    showsLoadingAccessory: false,
                    theme: theme
                )
            }
            .buttonStyle(SharePressStyle())

            NavigationLink(value: ShareDestination.outbox) {
                ShareHeroCard(
                    title: "Outbox",
                    subtitle: outboxSubtitle,
                    systemImage: "tray.and.arrow.up",
                    iconTint: outboxItems.isEmpty ? theme.secondaryText : theme.accent,
                    showsLoadingAccessory: false,
                    theme: theme
                )
            }
            .buttonStyle(SharePressStyle())
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent Activities")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.primaryText)

            HStack(spacing: 10) {
                ForEach(ActivityFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedActivityFilter = filter
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(filter.title)
                                .font(.system(size: 14, weight: .semibold))

                            Text("\(activityCount(for: filter))")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(selectedActivityFilter == filter ? .white : theme.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedActivityFilter == filter ? theme.accent : theme.groupSurface)
                        )
                        .overlay {
                            if selectedActivityFilter != filter {
                                Capsule(style: .continuous)
                                    .stroke(theme.groupStroke, lineWidth: 0.8)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if filteredRecentActivities.isEmpty {
                ShareActivityEmptyCard(
                    title: selectedActivityFilter == .drafts ? "No drafts yet" : "No completed collaborations",
                    subtitle: selectedActivityFilter == .drafts
                        ? "Half-finished songs that are still with you appear here."
                        : "Completed co-creations appear here when the collaborator finishes.",
                    theme: theme
                )
            } else {
                VStack(spacing: ShareLayout.listRowSpacing) {
                    ForEach(filteredRecentActivities) { activity in
                        ShareActivityRow(
                            activity: activity,
                            theme: theme,
                            onOpen: {
                                navigationPath.append(ShareDestination.activityDetail(activity.id))
                            },
                            onResumeSend: activity.isSendResumable ? {
                                resumePreparedCoCreate(from: activity)
                            } : nil,
                            onPlay: activity.status == .completed ? {
                                playCompletedActivity(activity)
                            } : nil,
                            onDelete: {
                                deleteActivity(activity)
                            }
                        )
                    }
                }
            }
        }
    }

    private var inboxItems: [ShareInboxItem] {
        viewModel.invitations.filter { $0.kind == .coCreateRequest }
    }

    private var outboxItems: [ShareActivityItem] {
        viewModel.activities.filter {
            $0.mode == .coCreate && ($0.status == .waitingForReply || $0.status == .inProgress)
        }
    }

    private var recentDraftActivities: [ShareActivityItem] {
        viewModel.activities.filter {
            $0.mode == .coCreate && ($0.status == .generatingDraft || $0.status == .readyToSend)
        }
    }

    private var completedActivities: [ShareActivityItem] {
        viewModel.activities.filter {
            $0.mode == .coCreate && $0.status == .completed
        }
    }

    private var filteredRecentActivities: [ShareActivityItem] {
        switch selectedActivityFilter {
        case .drafts:
            return recentDraftActivities
        case .completed:
            return completedActivities
        }
    }

    private func activityCount(for filter: ActivityFilter) -> Int {
        switch filter {
        case .drafts:
            return recentDraftActivities.count
        case .completed:
            return completedActivities.count
        }
    }

    private var inboxSubtitle: String {
        inboxItems.isEmpty ? "Requests sent to you appear here." : "\(inboxItems.count) request\(inboxItems.count == 1 ? "" : "s") waiting"
    }

    private var outboxSubtitle: String {
        outboxItems.isEmpty ? "Half-finished invitations you send stay here." : "\(outboxItems.count) session\(outboxItems.count == 1 ? "" : "s") active"
    }

    private func togglePreferredCreateLanguage() {
        preferredCreateLanguage = preferredCreateLanguage == "zh" ? "en" : "zh"
    }

    private func playSong(_ song: GeneratedMusic) {
        playerManager.currentMusic = song
        playerManager.lyrics = []
        playerManager.currentLineIndex = 0
        playerManager.showLyrics = false
        playerManager.lyricsControlsVisible = true
        playerManager.play()
    }

    private func openPreparedCoCreate(_ prepared: PreparedCoCreateDraft) {
        sendSheetAllowedModes = [.coCreate]
        sendSheetInitialMode = .coCreate
        selectedSongForSend = prepared.song
    }

    private func startInlineCreateGeneration() {
        let trimmedPrompt = createPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasInput = !trimmedPrompt.isEmpty || createSelectedImage != nil
        guard hasInput, !viewModel.isGeneratingCreateHalf else { return }

        isCreateInputFocused = false

        let effectivePrompt = buildCreatePrompt(basePrompt: trimmedPrompt)
        let request = ShareCreateHalfSongRequest(
            prompt: effectivePrompt,
            selectedImage: createSelectedImage,
            language: preferredCreateLanguage,
            instrumentalOnly: !createHasVocals,
            instrument: createInstrument
        )

        let localDraftID = viewModel.beginGeneratingCreateHalfActivity()
        Task {
            do {
                let prepared = try await viewModel.generateHalfSongForCreateHub(request: request)
                await MainActor.run {
                    viewModel.promoteGeneratingActivity(localDraftID, to: prepared)
                    pendingPreparedCoCreate = prepared
                    createPrompt = ""
                    createSelectedImage = nil
                    createInstrument = ""
                    createHasVocals = true
                    openPreparedCoCreate(prepared)
                }
            } catch {
                await MainActor.run {
                    viewModel.removeActivity(id: localDraftID)
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func buildCreatePrompt(basePrompt: String) -> String {
        var parts: [String] = []
        if !basePrompt.isEmpty {
            parts.append(basePrompt)
        }
        if !createInstrument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Primary instrument preference: \(createInstrument).")
        }
        parts.append(createHasVocals ? "Vocal mode: include vocals." : "Vocal mode: instrumental only.")
        return parts.joined(separator: "\n")
    }

    private func resumePreparedCoCreate(from activity: ShareActivityItem) {
        Task {
            do {
                guard let prepared = try await viewModel.preparedDraft(for: activity) else {
                    viewModel.errorMessage = "This draft is no longer available."
                    return
                }
                pendingPreparedCoCreate = prepared
                openPreparedCoCreate(prepared)
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func playCompletedActivity(_ activity: ShareActivityItem) {
        Task {
            do {
                guard let music = try await viewModel.songForActivity(activity) else {
                    viewModel.errorMessage = "This song is no longer available."
                    return
                }
                playSong(music)
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteActivity(_ activity: ShareActivityItem) {
        if pendingPreparedCoCreate?.sessionId == activity.id {
            pendingPreparedCoCreate = nil
        }
        if selectedSongForSend?.id == activity.musicId {
            selectedSongForSend = nil
        }
        viewModel.removeActivity(id: activity.id)
    }

    private func handlePendingShareRouteIfNeeded() {
        guard let route = deepLinkRouter.pendingShareRoute else { return }

        switch route {
        case .invitations:
            navigationPath = NavigationPath([ShareDestination.inbox])
        case .invitationDetail(let id):
            navigationPath = NavigationPath([
                ShareDestination.inbox,
                ShareDestination.invitationDetail(id)
            ])
        case .start:
            navigationPath = NavigationPath([ShareDestination.outbox])
        case .sharedSongDetail(let taskId):
            navigationPath = NavigationPath([
                ShareDestination.inbox,
                ShareDestination.sharedSongDetail(taskId)
            ])
        case .activityDetail(let id):
            navigationPath = NavigationPath([
                ShareDestination.outbox,
                ShareDestination.activityDetail(id)
            ])
        }

        deepLinkRouter.clearPendingShareRoute()
    }
}

// MARK: - Completed Cocreates UI
private extension ShareView {
    var cocreateCompletedSection: some View {
        ForEach(viewModel.completedItems) { item in
            completedCocreateRow(item: item)
        }
    }

    @ViewBuilder
    func completedCocreateRow(item: ShareViewModel.CompletedCocreate) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: item.music.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle()
                        .fill(Color(uiColor: .secondarySystemFill))
                        .overlay(Image(systemName: "music.mic").font(.title3).foregroundStyle(.secondary))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.music.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                if let name = item.inviteeName {
                    Text("Cocreated with \(name)").font(.system(size: 13)).foregroundStyle(.secondary)
                } else {
                    Text("Cocreated").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                playerManager.currentMusic = item.music
                playerManager.lyrics = []
                playerManager.currentLineIndex = 0
                playerManager.showLyrics = false
                playerManager.lyricsControlsVisible = true
                playerManager.effectiveLyricDuration = nil
                playerManager.play()
            } label: {
                Image(systemName: "play.circle.fill").font(.system(size: 30)).foregroundStyle(.purple)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

private enum ShareDestination: Hashable {
    case inbox
    case outbox
    case invitationDetail(UUID)
    case sharedSongDetail(String)
    case activityDetail(UUID)
}

private enum ShareComposerSheetContext: Identifiable {
    case createNew
    case continueSession(ShareInboxItem)

    var id: String {
        switch self {
        case .createNew:
            return "create-new"
        case .continueSession(let item):
            return "continue-\(item.id)"
        }
    }
}

private struct ShareCreateHalfSongRequest {
    let prompt: String
    let selectedImage: UIImage?
    let language: String
    let instrumentalOnly: Bool
    let instrument: String
}

private enum ShareLayout {
    static let topPadding: CGFloat = 10
    static let bottomPadding: CGFloat = 120
    static let contentColumnWidth: CGFloat = 370
    static let pushScrollSpace = "share-push-scroll"

    static let rootSectionSpacing: CGFloat = 24
    static let rootHeaderToCardsSpacing: CGFloat = 30
    static let rootCardsToActivitySpacing: CGFloat = 28
    static let heroCardSpacing: CGFloat = 16
    static let listRowSpacing: CGFloat = 14
    static let pushSectionSpacing: CGFloat = 28
    static let invitationSectionContentSpacing: CGFloat = 18
    static let invitationsHeaderToSectionsSpacing: CGFloat = 22
    static let startHeaderToCreateSpacing: CGFloat = 60
    static let startCreateToSongsSpacing: CGFloat = 28
    static let pushHorizontalPadding: CGFloat = 16
    static let pushTopPadding: CGFloat = -16
    static let pushHeaderMinHeight: CGFloat = 42
    static let startHeaderMinHeight: CGFloat = 50
    static let backButtonSize: CGFloat = 35
    static let pinnedTitleFadeDistance: CGFloat = 360
    static let detailCardCornerRadius: CGFloat = 28

    static let headerMinHeight: CGFloat = 104
    static let posterTitleWidth: CGFloat = 150
    static let posterBodyWidth: CGFloat = 144
    static let invitationTitleWidth: CGFloat = 161
    static let startTitleWidth: CGFloat = 176

    static let heroCardHeight: CGFloat = 119
    static let infoCardHeight: CGFloat = 119
    static let activityRowHeight: CGFloat = 94
    static let songRowHeight: CGFloat = 82
    static let createButtonHeight: CGFloat = 58

    static func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        min(contentColumnWidth, max(availableWidth - 32, 0))
    }
}

private struct PreparedCoCreateDraft {
    let song: GeneratedMusic
    let sessionId: UUID
}

private struct ShareTheme {
    let colorScheme: ColorScheme

    var pageBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.115, green: 0.115, blue: 0.125)
        : Color(uiColor: .systemGray6)
    }
    var groupSurface: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.038)
        : Color(uiColor: .systemBackground)
    }
    var groupStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)
    }
    var primaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.95) : Color.black.opacity(0.96)
    }
    var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.56)
    }
    var tertiaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.42) : Color.black.opacity(0.36)
    }
    var chipFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.82)
    }
    var chipStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
    var glassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.08)
    }
    var accent: Color { Color(uiColor: .systemIndigo) }
}

private struct ShareCardSurface: ViewModifier {
    let theme: ShareTheme
    let cornerRadius: CGFloat
    var strokeWidth: CGFloat = 0.7

    func body(content: Content) -> some View {
        content
            .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(theme.groupStroke, lineWidth: strokeWidth)
            }
    }
}

private struct ShareGlassChrome: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ShareTheme { ShareTheme(colorScheme: colorScheme) }

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.tint(theme.glassTint), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(theme.chipStroke, lineWidth: 0.8)
                }
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(theme.chipStroke, lineWidth: 0.8)
                }
        }
    }
}

private extension View {
    func shareCardSurface(theme: ShareTheme, cornerRadius: CGFloat, strokeWidth: CGFloat = 0.7) -> some View {
        modifier(ShareCardSurface(theme: theme, cornerRadius: cornerRadius, strokeWidth: strokeWidth))
    }
}

private struct SharePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct ShareScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ShareScrollOffsetReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ShareScrollOffsetPreferenceKey.self,
                value: proxy.frame(in: .named(ShareLayout.pushScrollSpace)).minY
            )
        }
        .frame(height: 0)
    }
}

private struct SharePushTopBar: View {
    let title: String
    let theme: ShareTheme
    let safeAreaTop: CGFloat
    let collapseProgress: CGFloat

    var body: some View {
        Text(title)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(theme.primaryText)
            .lineLimit(1)
            .opacity(collapseProgress)
            .scaleEffect(0.982 + (collapseProgress * 0.018))
            .offset(y: (1 - collapseProgress) * -10)
            .frame(maxWidth: .infinity)
        .padding(.top, safeAreaTop + 4)
        .padding(.horizontal, ShareLayout.pushHorizontalPadding)
        .padding(.bottom, 10)
        .allowsHitTesting(false)
    }
}

private struct ShareBackButton: View {
    let theme: ShareTheme

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Circle()
                .fill(theme.accent)
                .frame(width: ShareLayout.backButtonSize, height: ShareLayout.backButtonSize)
                .overlay {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.98))
                }
        }
        .buttonStyle(.plain)
    }
}

private struct ShareCenteredPushHeader: View {
    let title: String
    let titleWidth: CGFloat
    let theme: ShareTheme

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ShareBackButton(theme: theme)

            Text(title)
                .font(.systemExpanded(size: 30, weight: .regular))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: ShareLayout.pushHeaderMinHeight, alignment: .top)
    }
}

private struct SharePosterTitleBlock: View {
    let theme: ShareTheme

    var body: some View {
        VStack(alignment: .leading, spacing: -4) {
            Text("CO")
                .font(.systemExpanded(size: 29, weight: .ultraLight))
                .foregroundStyle(theme.primaryText)
                .tracking(0)

            Text("CREATION")
                .font(.systemExpanded(size: 29, weight: .ultraLight))
                .foregroundStyle(theme.primaryText)
                .tracking(0)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

private struct CoCreationInlineComposer: View {
    @Binding var prompt: String
    @Binding var selectedImage: UIImage?
    let preferredLanguage: String
    var isTextFieldFocused: FocusState<Bool>.Binding
    let isGenerating: Bool
    let hasVocals: Bool
    let selectedInstrument: String
    let progressText: String
    let onToggleLanguage: () -> Void
    let onCameraPress: () -> Void
    let onPhotoPress: () -> Void
    let onVocalsChange: (Bool) -> Void
    let onInstrumentSelect: (String) -> Void
    let onGeneratePress: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let instrumentOptions = ["Piano", "Synth", "Guitar", "Strings", "Drums"]

    private var canGenerate: Bool {
        !(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedImage == nil) && !isGenerating
    }

    private var instrumentSelection: Binding<String> {
        Binding(
            get: { selectedInstrument },
            set: { onInstrumentSelect($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("", text: $prompt, axis: .vertical)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.black.opacity(0.92))
                .focused(isTextFieldFocused)
                .submitLabel(.done)
                .lineLimit(1...2)
                .frame(minHeight: 24, alignment: .topLeading)
                .onSubmit {
                    if canGenerate {
                        isTextFieldFocused.wrappedValue = false
                        onGeneratePress()
                    }
                }

            HStack(alignment: .bottom, spacing: 8) {
                CoCreationComposerCameraButton(
                    hasSelectedImage: selectedImage != nil,
                    onTap: onCameraPress,
                    onLongPress: onPhotoPress
                )

                Button {
                    onVocalsChange(!hasVocals)
                } label: {
                    CoCreationOptionButton(
                        systemName: hasVocals ? "mic.fill" : "mic.slash",
                        isHighlighted: hasVocals
                    )
                }
                .buttonStyle(.plain)

                Menu {
                    Picker("Instrument", selection: instrumentSelection) {
                        Text("No Music Preference").tag("")
                        ForEach(instrumentOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                } label: {
                    CoCreationOptionButton(
                        systemName: "music.note.list",
                        isHighlighted: !selectedInstrument.isEmpty
                    )
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)

                Button(action: onToggleLanguage) {
                    CoCreationOptionButton(
                        systemName: "translate",
                        labelText: preferredLanguage == "zh" ? "中" : "EN",
                        isHighlighted: preferredLanguage == "zh"
                    )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                if isGenerating {
                    HStack(spacing: 8) {
                        ShareRotatingAccessory(theme: ShareTheme(colorScheme: colorScheme))
                        Text(progressText.isEmpty ? "Generating" : "Generating")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.62))
                    }
                    .padding(.trailing, 4)
                } else {
                    Button(action: {
                        isTextFieldFocused.wrappedValue = false
                        onGeneratePress()
                    }) {
                        CoCreationSubmitButton()
                    }
                    .disabled(!canGenerate)
                    .opacity(canGenerate ? 1 : 0.42)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.96 : 0.94))
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 18, y: 10)
    }
}

private struct CoCreationSubmitButton: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(
                        Circle()
                            .fill(Color(uiColor: .systemIndigo).opacity(colorScheme == .dark ? 0.42 : 0.34))
                    )
                    .glassEffect(
                        .regular
                            .interactive()
                            .tint(Color(uiColor: .systemIndigo)),
                        in: .circle
                    )
            } else {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(Color(uiColor: .systemIndigo), in: Circle())
            }
        }
    }
}

private struct CoCreationComposerCameraButton: View {
    let hasSelectedImage: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var didTriggerLongPress = false

    var body: some View {
        Button {
            if didTriggerLongPress {
                didTriggerLongPress = false
                return
            }
            onTap()
        } label: {
            CoCreationOptionButton(systemName: "camera.aperture", isHighlighted: hasSelectedImage)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    didTriggerLongPress = true
                    onLongPress()
                }
        )
    }
}

private struct CoCreationOptionButton: View {
    let systemName: String
    var labelText: String? = nil
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: labelText == nil ? 0 : 3) {
            Image(systemName: systemName)
            if let labelText {
                Text(labelText)
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(isHighlighted ? Color(uiColor: .systemIndigo) : Color.black.opacity(0.58))
        .frame(width: labelText == nil ? 30 : 38, height: 22)
        .contentShape(Rectangle())
    }
}

private struct ShareHeroCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let iconTint: Color
    let showsLoadingAccessory: Bool
    let theme: ShareTheme

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(iconTint)
                .frame(width: 30, height: 24, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                Spacer(minLength: 18)

                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: 172, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)

            Spacer(minLength: 0)

            Group {
                if showsLoadingAccessory {
                    ShareRotatingAccessory(theme: theme)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(theme.tertiaryText)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(minHeight: ShareLayout.heroCardHeight - 32, alignment: .top)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .shareCardSurface(theme: theme, cornerRadius: 26)
    }
}

private struct ShareRotatingAccessory: View {
    let theme: ShareTheme
    @State private var isAnimating = false

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(theme.accent)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

private struct SharePlaceholderSurface: View {
    let artworkName: String
    let title: String
    let subtitle: String
    let actionTitle: String?
    let action: (() -> Void)?
    let theme: ShareTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ShareStaticArtwork(name: artworkName)
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.primaryText)

                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(theme.accent, in: Capsule(style: .continuous))
                    .buttonStyle(SharePressStyle())
            }
        }
        .padding(18)
        .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(theme.groupStroke, lineWidth: 0.8)
        }
    }
}

private struct ShareActivityEmptyCard: View {
    let title: String
    let subtitle: String
    let theme: ShareTheme

    var body: some View {
        HStack(spacing: 14) {
            ShareStaticArtwork(name: "compose")
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: ShareLayout.activityRowHeight - 24, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .shareCardSurface(theme: theme, cornerRadius: 24)
    }
}

private struct ShareActivityRow: View {
    let activity: ShareActivityItem
    let theme: ShareTheme
    let onOpen: () -> Void
    let onResumeSend: (() -> Void)?
    let onPlay: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    ShareActivityArtwork(activity: activity)
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(activity.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: 14)

                        HStack(alignment: .lastTextBaseline) {
                            Text(relationText)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            Text(activity.createdAt.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(theme.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ShareActivityMenuButton(
                theme: theme,
                onOpen: onOpen,
                onResumeSend: onResumeSend,
                onPlay: onPlay,
                onDelete: onDelete
            )
        }
        .frame(minHeight: ShareLayout.activityRowHeight - 18)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .shareCardSurface(theme: theme, cornerRadius: 26)
    }

    private var relationText: String {
        if activity.mode == .coCreate {
            switch activity.status {
            case .generatingDraft:
                return "Generating draft"
            case .readyToSend:
                return "Ready to send"
            default:
                break
            }
        }
        if activity.mode == .coCreate && activity.recipientName.isEmpty {
            return "Co-create draft"
        }
        switch activity.mode {
        case .shareOnly:
            return "Shared with \(activity.recipientName)"
        case .coCreate:
            return "Co-create with \(activity.recipientName)"
        }
    }
}

private struct ShareActivityMenuButton: View {
    let theme: ShareTheme
    let onOpen: () -> Void
    let onResumeSend: (() -> Void)?
    let onPlay: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        Menu {
            Button(action: onOpen) {
                Label("View", systemImage: "eye")
            }

            if let onResumeSend {
                Button(action: onResumeSend) {
                    Label("Send Sound", systemImage: "paperplane")
                }
            }

            if let onPlay {
                Button(action: onPlay) {
                    Label("Play", systemImage: "play.fill")
                }
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete Activity", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
    }
}

private struct ShareActivitySummaryCard: View {
    let title: String
    let count: Int
    let subtitle: String
    let theme: ShareTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                Spacer(minLength: 0)

                Text("\(count)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }

            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .shareCardSurface(theme: theme, cornerRadius: 24)
    }
}

private struct ShareActivityArtwork: View {
    let activity: ShareActivityItem

    var body: some View {
        if let artworkURL = activity.artworkURL {
            AsyncImage(url: artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .empty:
                    ShareStaticArtwork(name: activity.mode == .coCreate ? "compose" : "share")
                case .failure:
                    ShareStaticArtwork(name: activity.mode == .coCreate ? "compose" : "share")
                @unknown default:
                    ShareStaticArtwork(name: activity.mode == .coCreate ? "compose" : "share")
                }
            }
        } else {
            ShareStaticArtwork(name: activity.mode == .coCreate ? "compose" : "share")
        }
    }
}

private struct ShareStaticArtwork: View {
    let name: String

    var body: some View {
        if let image = UIImage(named: name) ?? UIImage(named: "\(name).png") ?? Bundle.main.url(forResource: name, withExtension: "png").flatMap({ UIImage(contentsOfFile: $0.path) }) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: [Color(uiColor: .systemIndigo), Color(uiColor: .systemPink)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
    }
}

private struct ShareRemoteArtwork: View {
    let imageURL: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    let noteSize: CGFloat
    var strokeColor: Color? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        artwork
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if let strokeColor {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(strokeColor, lineWidth: 0.8)
                }
            }
    }

    @ViewBuilder
    private var artwork: some View {
        if let imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .empty:
                    loading
                case .failure:
                    fallback
                @unknown default:
                    fallback
                }
            }
        } else {
            fallback
        }
    }

    private var loading: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(colorScheme == .dark ? Color(uiColor: .systemGray5) : Color(uiColor: .systemGray4))
            .overlay {
                ProgressView()
                    .tint(colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.45))
            }
    }

    private var fallback: some View {
        ShareStaticArtwork(name: "compose")
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: noteSize, weight: .light))
                    .foregroundStyle(.white.opacity(0.82))
            }
    }
}

private struct ShareInvitationsView: View {
    @ObservedObject var viewModel: ShareViewModel
    let onPlay: (GeneratedMusic) -> Void
    let onOpenComposerForSession: (ShareInboxItem) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var scrollOffset: CGFloat = 0
    private var theme: ShareTheme { ShareTheme(colorScheme: colorScheme) }

    private var coCreateRequests: [ShareInboxItem] {
        viewModel.invitations.filter { $0.kind == .coCreateRequest }
    }

    private var sharedSongs: [ShareInboxItem] {
        viewModel.invitations.filter { $0.kind == .sharedSong }
    }

    private var collapseProgress: CGFloat {
        let raw = min(max(-scrollOffset / ShareLayout.pinnedTitleFadeDistance, 0), 1)
        return raw * raw * raw * raw * raw
    }

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = ShareLayout.contentWidth(for: proxy.size.width)
            ZStack(alignment: .top) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ShareScrollOffsetReader()

                        ShareCenteredPushHeader(
                            title: "Invitations",
                            titleWidth: ShareLayout.invitationTitleWidth,
                            theme: theme
                        )

                        VStack(alignment: .leading, spacing: ShareLayout.pushSectionSpacing) {
                            friendInvitationSection

                            invitationSection(
                                title: "Co-Create Request",
                                items: coCreateRequests,
                                emptyTitle: "No invitations",
                                emptySubtitle: "Tracks sent to you to continue will appear here.",
                                emptyIcon: "person.2",
                                rowBuilder: { item in
                                    NavigationLink {
                                        ShareCoCreateDetailView(
                                            item: item,
                                            onPlay: onPlay,
                                            onContinue: {
                                                if item.session != nil {
                                                    onOpenComposerForSession(item)
                                                }
                                            },
                                            onDecline: {
                                                Task { await viewModel.declineInvitation(item) }
                                            }
                                        )
                                    } label: {
                                        ShareInboxRow(item: item, theme: theme)
                                    }
                                    .buttonStyle(.plain)
                                }
                            )

                            invitationSection(
                                title: "Shared with U",
                                items: sharedSongs,
                                emptyTitle: "No invitations",
                                emptySubtitle: "Songs shared with you appear here, separate from co-create requests.",
                                emptyIcon: "square.and.arrow.down.on.square",
                                rowBuilder: { item in
                                    NavigationLink {
                                        ShareSharedSongDetailView(
                                            item: item,
                                            onPlay: onPlay,
                                            onSave: {
                                                Task { await viewModel.save(song: item.song) }
                                            }
                                        )
                                    } label: {
                                        ShareInboxRow(item: item, theme: theme)
                                    }
                                    .buttonStyle(.plain)
                                }
                            )
                        }
                        .padding(.top, ShareLayout.invitationsHeaderToSectionsSpacing)
                    }
                    .padding(.top, proxy.safeAreaInsets.top + ShareLayout.pushTopPadding)
                    .padding(.bottom, ShareLayout.bottomPadding)
                    .frame(width: columnWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .coordinateSpace(name: ShareLayout.pushScrollSpace)
                .onPreferenceChange(ShareScrollOffsetPreferenceKey.self) { scrollOffset = $0 }

                SharePushTopBar(
                    title: "Invitations",
                    theme: theme,
                    safeAreaTop: proxy.safeAreaInsets.top,
                    collapseProgress: collapseProgress
                )
            }
            .background(theme.pageBackground.ignoresSafeArea())
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var friendInvitationSection: some View {
        VStack(alignment: .leading, spacing: ShareLayout.invitationSectionContentSpacing) {
            Text("Friend Invitations")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(theme.primaryText)

            if viewModel.friendInvitations.isEmpty {
                ShareInvitationInfoCard(
                    iconName: "person.badge.plus",
                    title: "No invitations",
                    subtitle: "Friend requests appear here, so you can respond right from Share.",
                    theme: theme
                )
            } else {
                VStack(spacing: ShareLayout.listRowSpacing) {
                    ForEach(viewModel.friendInvitations) { request in
                        ShareFriendInvitationRow(
                            request: request,
                            theme: theme,
                            onAccept: {
                                Task { await viewModel.acceptFriendInvitation(request) }
                            },
                            onDecline: {
                                Task { await viewModel.declineFriendInvitation(request) }
                            }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func invitationSection<Row: View>(
        title: String,
        items: [ShareInboxItem],
        emptyTitle: String,
        emptySubtitle: String,
        emptyIcon: String,
        @ViewBuilder rowBuilder: @escaping (ShareInboxItem) -> Row
    ) -> some View {
        VStack(alignment: .leading, spacing: ShareLayout.invitationSectionContentSpacing) {
            Text(title)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(theme.primaryText)

            if items.isEmpty {
                ShareInvitationInfoCard(
                    iconName: emptyIcon,
                    title: emptyTitle,
                    subtitle: emptySubtitle,
                    theme: theme
                )
            } else {
                VStack(spacing: ShareLayout.listRowSpacing) {
                    ForEach(items) { item in
                        rowBuilder(item)
                    }
                }
            }
        }
    }
}

private struct ShareFriendInvitationRow: View {
    let request: FriendRequest
    let theme: ShareTheme
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            FriendAvatarPlaceholder(name: request.senderName ?? "User")
                .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 7) {
                Text(request.senderName ?? "User")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text(request.senderFriendCode ?? "Friend request")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)

                Text(request.createdAtDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
            }
            .padding(.leading, 6)

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button("Accept", action: onAccept)
                    .friendMiniCapsule(theme: theme, filled: true)
                Button("Decline", action: onDecline)
                    .friendMiniCapsule(theme: theme)
            }
        }
        .frame(minHeight: ShareLayout.infoCardHeight - 32, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .shareCardSurface(theme: theme, cornerRadius: ShareLayout.detailCardCornerRadius, strokeWidth: 0.8)
    }
}

private struct ShareInvitationInfoCard: View {
    let iconName: String
    let title: String
    let subtitle: String
    let theme: ShareTheme

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            Image(systemName: iconName)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 30, height: 24, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                Spacer(minLength: 14)

                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: 198, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 8)

            Spacer(minLength: 0)

            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(theme.tertiaryText)
                .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(minHeight: ShareLayout.infoCardHeight - 32, alignment: .top)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .shareCardSurface(theme: theme, cornerRadius: ShareLayout.detailCardCornerRadius)
    }
}

private struct ShareInboxRow: View {
    let item: ShareInboxItem
    let theme: ShareTheme

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            ShareRemoteArtwork(
                imageURL: item.song.imageURL,
                size: 62,
                cornerRadius: 16,
                noteSize: 20,
                strokeColor: theme.groupStroke
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(item.song.title.isEmpty ? "Untitled Song" : item.song.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.senderName)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)

                    Text(item.receivedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 6)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                Text(item.kind.badgeTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.chipFill, in: Capsule(style: .continuous))

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .frame(minHeight: ShareLayout.infoCardHeight - 32, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .shareCardSurface(theme: theme, cornerRadius: ShareLayout.detailCardCornerRadius, strokeWidth: 0.8)
    }
}

private struct ShareCoCreateDetailView: View {
    let item: ShareInboxItem
    let onPlay: (GeneratedMusic) -> Void
    let onContinue: () -> Void
    let onDecline: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: ShareTheme { ShareTheme(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ShareRemoteArtwork(
                    imageURL: item.song.imageURL,
                    size: 220,
                    cornerRadius: 26,
                    noteSize: 28,
                    strokeColor: theme.groupStroke
                )
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.song.title.isEmpty ? "Untitled Song" : item.song.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(theme.primaryText)

                    Text("Sent by \(item.senderName)")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(theme.secondaryText)

                    if let session = item.session {
                        Text("Continue from \(formatContinueAt(session.continueAtSec))")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(theme.tertiaryText)
                    }
                }

                Text("This request asks you to continue the existing track, not just listen to it.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 12) {
                    Button("Continue", action: onContinue)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(theme.accent, in: Capsule(style: .continuous))

                    HStack(spacing: 12) {
                        Button("Play") { onPlay(item.song) }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(theme.groupSurface, in: Capsule(style: .continuous))
                            .overlay {
                                Capsule(style: .continuous).stroke(theme.groupStroke, lineWidth: 0.8)
                            }

                        Button("Decline", role: .destructive, action: onDecline)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 120)
        }
        .background(theme.pageBackground)
        .navigationTitle("Co-create Request")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatContinueAt(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remaining = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remaining)
    }
}

private struct ShareSharedSongDetailView: View {
    let item: ShareInboxItem
    let onPlay: (GeneratedMusic) -> Void
    let onSave: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: ShareTheme { ShareTheme(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ShareRemoteArtwork(
                    imageURL: item.song.imageURL,
                    size: 220,
                    cornerRadius: 26,
                    noteSize: 28,
                    strokeColor: theme.groupStroke
                )
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.song.title.isEmpty ? "Untitled Song" : item.song.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(theme.primaryText)

                    Text("Shared by \(item.senderName)")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(theme.secondaryText)
                }

                VStack(spacing: 12) {
                    Button("Play") { onPlay(item.song) }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(theme.accent, in: Capsule(style: .continuous))

                    Button("Save", action: onSave)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(theme.groupSurface, in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous).stroke(theme.groupStroke, lineWidth: 0.8)
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 120)
        }
        .background(theme.pageBackground)
        .navigationTitle("Shared Song")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ShareActivityDetailView: View {
    let activity: ShareActivityItem
    let theme: ShareTheme
    let onResumeSend: (() -> Void)?
    let onPlay: (() -> Void)?
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ShareActivityArtwork(activity: activity)
                    .frame(width: 220, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 8) {
                    Text(activity.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(theme.primaryText)

                    Text(activityRecipientSummary)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(theme.secondaryText)

                    Text(activity.status.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                }

                statusHero
                statusTimeline
                statusDetailCard
                actionSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 120)
        }
        .background(theme.pageBackground)
        .navigationTitle("Session Activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var actionSection: some View {
        VStack(spacing: 12) {
            if let onResumeSend {
                Button("Send Sound", action: onResumeSend)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.accent, in: Capsule(style: .continuous))
            } else if let onPlay {
                Button("Play", action: onPlay)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.accent, in: Capsule(style: .continuous))
            }

            Button(role: .destructive) {
                onDelete()
                dismiss()
            } label: {
                Text("Delete Activity")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .foregroundStyle(Color(uiColor: .systemRed))
            .background(theme.groupSurface, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(theme.groupStroke, lineWidth: 0.8)
            }
        }
    }

    private var statusHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                statusIndicator

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusHeadline)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.primaryText)

                    Text(statusHeroSubtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if let progressValue {
                ProgressView(value: progressValue)
                    .progressViewStyle(.linear)
                    .tint(activity.status == .completed ? theme.accent : theme.primaryText.opacity(0.78))
            }

            Text(statusHeroFootnote)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(theme.chipFill, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(ShareGlassChrome(cornerRadius: 28))
    }

    private var statusTimeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(milestones.enumerated()), id: \.offset) { _, milestone in
                HStack(alignment: .top, spacing: 12) {
                    milestoneIcon(for: milestone.state)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(milestone.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(milestoneTextColor(for: milestone.state))

                        Text(milestone.subtitle)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.groupStroke, lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private var statusDetailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if activity.status == .inProgress {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(theme.primaryText)
                    Text("The continuation is being generated.")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                }
            } else {
                Text(statusHeadline)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
            }

            Text(statusBody)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.groupStroke, lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(theme.groupSurface)
                .frame(width: 58, height: 58)

            switch activity.status {
            case .generatingDraft:
                ProgressView()
                    .controlSize(.regular)
                    .tint(theme.primaryText)

            case .readyToSend:
                Image(systemName: "paperplane.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(theme.accent)

            case .shared:
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

            case .waitingForReply:
                Image(systemName: "person.badge.clock.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

            case .inProgress:
                ProgressView()
                    .controlSize(.regular)
                    .tint(theme.primaryText)

            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
        }
        .overlay {
            Circle()
                .stroke(theme.groupStroke, lineWidth: 0.8)
        }
    }

    private var statusHeadline: String {
        switch activity.status {
        case .generatingDraft:
            return "Generating half song"
        case .readyToSend:
            return "Ready to send"
        case .shared:
            return "Shared successfully"
        case .waitingForReply:
            return "Waiting for \(collaboratorDisplayName)"
        case .inProgress:
            return "Generating"
        case .completed:
            return "Co-create ready"
        }
    }

    private var statusBody: String {
        if activity.mode == .coCreate && activity.recipientName.isEmpty {
            switch activity.status {
            case .generatingDraft:
                return "The half song is still being prepared. Once it is ready, you can choose a collaborator and send the invitation manually."
            case .readyToSend:
                return "The half song is ready. Open Send Sound whenever you want and choose one collaborator to invite."
            default:
                break
            }
        }
        switch activity.status {
        case .generatingDraft:
            return "The half song is still rendering. This activity stays here while the draft is being prepared."
        case .readyToSend:
            return "The starter song is ready. You can come back at any time, pick one collaborator, and send the co-create handoff."
        case .shared:
            return "The song has been sent. It will stay here even before the recipient responds."
        case .waitingForReply:
            return "The invitation is out. \(collaboratorDisplayName) has not started the co-create flow yet."
        case .inProgress:
            return "\(collaboratorDisplayName) has started processing the continuation. This state updates automatically while the session is active."
        case .completed:
            return "The collaboration finished successfully. You can keep this activity as a record of the completed session."
        }
    }

    private var statusHeroSubtitle: String {
        if activity.mode == .coCreate && activity.recipientName.isEmpty {
            switch activity.status {
            case .generatingDraft:
                return "The co-create draft is still generating."
            case .readyToSend:
                return "Choose one collaborator whenever you are ready."
            default:
                break
            }
        }
        switch activity.status {
        case .generatingDraft:
            return "The draft is being generated right now."
        case .readyToSend:
            return "The draft is finished and waiting for your send decision."
        case .shared:
            return "The song is safely in your outgoing activity list."
        case .waitingForReply:
            return "\(collaboratorDisplayName) has not started the co-create flow yet."
        case .inProgress:
            return "\(collaboratorDisplayName) is generating the continuation right now."
        case .completed:
            return "Both sides can now treat this session as finished."
        }
    }

    private var statusHeroFootnote: String {
        if activity.mode == .coCreate && activity.recipientName.isEmpty {
            switch activity.status {
            case .generatingDraft:
                return "This draft stays here until generation finishes."
            case .readyToSend:
                return "You can leave this screen and come back later. The send step stays available until you send or delete it."
            default:
                break
            }
        }
        switch activity.status {
        case .generatingDraft:
            return "Status updates automatically while the starter song is rendering."
        case .readyToSend:
            return "This session has not been sent yet. It becomes active only after you choose a collaborator."
        case .shared:
            return "Share-only sessions stay visible here even before the recipient reacts."
        case .waitingForReply:
            return "This screen updates automatically while you wait for \(collaboratorDisplayName)."
        case .inProgress:
            return "Status comes from the co-create session and refreshes in the background."
        case .completed:
            return "A completion notice appears once the session reaches the finished state."
        }
    }

    private var progressValue: Double? {
        guard activity.mode == .coCreate else { return nil }
        switch activity.status {
        case .generatingDraft:
            return 0.16
        case .readyToSend:
            return 0.5
        case .shared:
            return nil
        case .waitingForReply:
            return 0.34
        case .inProgress:
            return 0.68
        case .completed:
            return 1.0
        }
    }

    private var milestones: [ActivityMilestone] {
        if activity.mode == .coCreate && activity.recipientName.isEmpty {
            if activity.status == .readyToSend {
                return [
                    ActivityMilestone(
                        title: "Half song ready",
                        subtitle: "The starter song is finished and stored locally.",
                        state: .completed
                    ),
                    ActivityMilestone(
                        title: "Ready to send",
                        subtitle: "Open Send Sound and choose who should continue the track.",
                        state: .current
                    ),
                    ActivityMilestone(
                        title: "Song ready",
                        subtitle: "The completed co-create appears here after the collaborator finishes the extension.",
                        state: .pending
                    )
                ]
            }
            return [
                ActivityMilestone(
                    title: "Generating half song",
                    subtitle: "MOMENTA is preparing the track that will be handed off for co-creation.",
                    state: .current
                ),
                ActivityMilestone(
                    title: "Ready to send",
                    subtitle: "Once generation finishes, you can choose who to invite.",
                    state: .pending
                )
            ]
        }
        switch activity.mode {
        case .shareOnly:
            return [
                ActivityMilestone(
                    title: "Shared",
                    subtitle: "The song was sent successfully and remains listed here.",
                    state: .completed
                )
            ]

        case .coCreate:
            let generatingState: ActivityMilestone.State
            let readyState: ActivityMilestone.State

            switch activity.status {
            case .generatingDraft:
                generatingState = .current
                readyState = .pending
            case .readyToSend:
                generatingState = .completed
                readyState = .pending
            case .waitingForReply:
                generatingState = .pending
                readyState = .pending
            case .inProgress:
                generatingState = .current
                readyState = .pending
            case .completed:
                generatingState = .completed
                readyState = .completed
            case .shared:
                generatingState = .pending
                readyState = .pending
            }

            return [
                ActivityMilestone(
                    title: activity.status == .readyToSend ? "Half song ready" : "Invitation sent",
                    subtitle: activity.status == .readyToSend
                        ? "The starter song is prepared and waiting for you to choose one collaborator."
                        : "\(collaboratorDisplayName) received the co-create handoff.",
                    state: .completed
                ),
                ActivityMilestone(
                    title: activity.status == .readyToSend
                        ? "Ready to send"
                        : (activity.status == .waitingForReply ? "Waiting for \(collaboratorDisplayName)" : "Generating continuation"),
                    subtitle: activity.status == .readyToSend
                        ? "Open Send Sound whenever you are ready."
                        : (activity.status == .waitingForReply
                            ? "\(collaboratorDisplayName) has not started the extension yet."
                            : "This becomes active once \(collaboratorDisplayName) starts the extension."),
                    state: generatingState
                ),
                ActivityMilestone(
                    title: "Song ready",
                    subtitle: "The completed co-create appears here when \(collaboratorDisplayName) finishes the extension.",
                    state: readyState
                )
            ]
        }
    }

    private var collaboratorDisplayName: String {
        let trimmed = activity.recipientName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "your collaborator" : trimmed
    }

    @ViewBuilder
    private func milestoneIcon(for state: ActivityMilestone.State) -> some View {
        switch state {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.accent)
        case .current:
            ProgressView()
                .controlSize(.small)
                .tint(theme.primaryText)
                .frame(width: 16, height: 16)
        case .pending:
            Circle()
                .stroke(theme.groupStroke, lineWidth: 1.4)
                .frame(width: 16, height: 16)
        }
    }

    private func milestoneTextColor(for state: ActivityMilestone.State) -> Color {
        switch state {
        case .completed, .current:
            return theme.primaryText
        case .pending:
            return theme.secondaryText
        }
    }

    private var activityRecipientSummary: String {
        if activity.mode == .coCreate && activity.recipientName.isEmpty {
            switch activity.status {
            case .generatingDraft:
                return "Generating co-create draft"
            case .readyToSend:
                return "Starter song ready to send"
            default:
                return "Co-create draft"
            }
        }
        return "\(activity.mode.title) with \(activity.recipientName)"
    }
}

private struct ActivityMilestone {
    enum State {
        case pending
        case current
        case completed
    }

    let title: String
    let subtitle: String
    let state: State
}

private struct ShareInboxHubView: View {
    @ObservedObject var viewModel: ShareViewModel
    let onPlay: (GeneratedMusic) -> Void
    let onOpenComposerForSession: (ShareInboxItem) -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: ShareTheme { ShareTheme(colorScheme: colorScheme) }

    private var items: [ShareInboxItem] {
        viewModel.invitations.filter { $0.kind == .coCreateRequest }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Inbox")
                    .font(.systemExpanded(size: 30, weight: .regular))
                    .foregroundStyle(theme.primaryText)

                if items.isEmpty {
                    ShareInvitationInfoCard(
                        iconName: "tray.and.arrow.down",
                        title: "No invitations",
                        subtitle: "Co-creation requests sent to you will appear here.",
                        theme: theme
                    )
                } else {
                    VStack(spacing: ShareLayout.listRowSpacing) {
                        ForEach(items) { item in
                            NavigationLink {
                                ShareCoCreateDetailView(
                                    item: item,
                                    onPlay: onPlay,
                                    onContinue: {
                                        if item.session != nil {
                                            onOpenComposerForSession(item)
                                        }
                                    },
                                    onDecline: {
                                        Task { await viewModel.declineInvitation(item) }
                                    }
                                )
                            } label: {
                                ShareInboxRow(item: item, theme: theme)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 120)
        }
        .background(theme.pageBackground)
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ShareOutboxHubView: View {
    let activities: [ShareActivityItem]
    let theme: ShareTheme
    let onOpen: (ShareActivityItem) -> Void
    let onResumeSend: (ShareActivityItem) -> Void
    let onPlay: (ShareActivityItem) -> Void
    let onDelete: (ShareActivityItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Outbox")
                    .font(.systemExpanded(size: 30, weight: .regular))
                    .foregroundStyle(theme.primaryText)

                if activities.isEmpty {
                    ShareActivityEmptyCard(
                        title: "No sessions yet",
                        subtitle: "Half-finished invitations you send stay here until collaboration is done.",
                        theme: theme
                    )
                } else {
                    VStack(spacing: ShareLayout.listRowSpacing) {
                        ForEach(activities) { activity in
                            ShareActivityRow(
                                activity: activity,
                                theme: theme,
                                onOpen: { onOpen(activity) },
                                onResumeSend: activity.isSendResumable ? { onResumeSend(activity) } : nil,
                                onPlay: activity.status == .completed ? { onPlay(activity) } : nil,
                                onDelete: { onDelete(activity) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 120)
        }
        .background(theme.pageBackground)
        .navigationTitle("Outbox")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ShareMissingDetailView: View {
    let title: String
    let subtitle: String

    @Environment(\.colorScheme) private var colorScheme
    private var theme: ShareTheme { ShareTheme(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 16) {
            ShareStaticArtwork(name: "share")
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.primaryText)

            Text(subtitle)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(theme.pageBackground)
    }
}

private struct ShareStartToCoCreateView: View {
    @ObservedObject var viewModel: ShareViewModel
    let onCreateNew: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var scrollOffset: CGFloat = 0
    private var theme: ShareTheme { ShareTheme(colorScheme: colorScheme) }

    private var collapseProgress: CGFloat {
        let raw = min(max(-scrollOffset / ShareLayout.pinnedTitleFadeDistance, 0), 1)
        return raw * raw * raw * raw * raw
    }

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = ShareLayout.contentWidth(for: proxy.size.width)
            ZStack(alignment: .top) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ShareScrollOffsetReader()

                        VStack(alignment: .leading, spacing: ShareLayout.startHeaderToCreateSpacing) {
                            HStack(alignment: .top) {
                                ShareBackButton(theme: theme)
                                    .padding(.top, 0)

                                Spacer(minLength: 18)

                                Text("Start to\nco-create")
                                    .font(.systemExpanded(size: 31, weight: .regular))
                                    .foregroundStyle(theme.primaryText)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: ShareLayout.startHeaderMinHeight, alignment: .top)

                            VStack(spacing: 16) {
                                Text("Create a new song to co-create")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(theme.primaryText)
                                    .frame(maxWidth: .infinity, alignment: .center)

                                Button(action: onCreateNew) {
                                    ZStack {
                                        Capsule(style: .continuous)
                                            .fill(viewModel.isGeneratingCreateHalf ? theme.groupSurface : theme.accent)
                                            .frame(height: ShareLayout.createButtonHeight)

                                        if viewModel.isGeneratingCreateHalf {
                                            HStack(spacing: 10) {
                                                ShareRotatingAccessory(theme: theme)
                                                Text("Generating")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundStyle(theme.primaryText)
                                            }
                                        } else {
                                            Image(systemName: "plus")
                                                .font(.system(size: 22, weight: .regular))
                                                .foregroundStyle(.white.opacity(0.98))
                                        }
                                    }
                                }
                                .buttonStyle(SharePressStyle())
                                .disabled(viewModel.isGeneratingCreateHalf)
                            }
                        }

                        VStack(alignment: .leading, spacing: 18) {
                            Text("How it works")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(theme.primaryText)

                            ShareInvitationInfoCard(
                                iconName: "waveform.path.badge.plus",
                                title: viewModel.isGeneratingCreateHalf ? "Generating in the hub" : "Create a half song first",
                                subtitle: viewModel.isGeneratingCreateHalf
                                    ? (viewModel.createHalfProgress.isEmpty
                                        ? "The starter track is being prepared in the background."
                                        : viewModel.createHalfProgress)
                                    : "Generate the starter track here, then choose one friend to invite manually.",
                                theme: theme
                            )
                        }
                        .padding(.top, ShareLayout.startCreateToSongsSpacing)
                    }
                    .padding(.top, proxy.safeAreaInsets.top + ShareLayout.pushTopPadding)
                    .padding(.bottom, ShareLayout.bottomPadding)
                    .frame(width: columnWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .coordinateSpace(name: ShareLayout.pushScrollSpace)
                .onPreferenceChange(ShareScrollOffsetPreferenceKey.self) { scrollOffset = $0 }

                SharePushTopBar(
                    title: "Start to co-create",
                    theme: theme,
                    safeAreaTop: proxy.safeAreaInsets.top,
                    collapseProgress: collapseProgress
                )
            }
            .background(theme.pageBackground.ignoresSafeArea())
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct ShareTimelineSongRow: View {
    let song: GeneratedMusic
    let theme: ShareTheme
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                ShareRemoteArtwork(
                    imageURL: song.imageURL,
                    size: 54,
                    cornerRadius: 15,
                    noteSize: 20,
                    strokeColor: theme.groupStroke
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(song.title.isEmpty ? "Untitled Song" : song.title)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    Text(song.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(theme.tertiaryText)
                }
                .padding(.leading, 4)

                Spacer(minLength: 0)

                Circle()
                    .fill(theme.accent)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.white)
                    }
            }
            .frame(minHeight: ShareLayout.songRowHeight - 26)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .shareCardSurface(theme: theme, cornerRadius: 25)
        }
        .buttonStyle(SharePressStyle())
    }
}

private struct ShareSendSheet: View {
    let song: GeneratedMusic
    let friends: [FriendProfile]
    let theme: ShareTheme
    let allowedModes: [ShareSendMode]
    let initialMode: ShareSendMode
    let onAddFriends: () -> Void
    let onSend: (FriendProfile, ShareSendMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFriendId: UUID?
    @State private var selectedMode: ShareSendMode

    init(
        song: GeneratedMusic,
        friends: [FriendProfile],
        theme: ShareTheme,
        allowedModes: [ShareSendMode] = ShareSendMode.allCases,
        initialMode: ShareSendMode = .shareOnly,
        onAddFriends: @escaping () -> Void,
        onSend: @escaping (FriendProfile, ShareSendMode) -> Void
    ) {
        self.song = song
        self.friends = friends
        self.theme = theme
        self.allowedModes = allowedModes
        self.initialMode = initialMode
        self.onAddFriends = onAddFriends
        self.onSend = onSend
        _selectedMode = State(initialValue: initialMode)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let contentWidth = max(proxy.size.width - 40, 0)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 14) {
                            ShareRemoteArtwork(
                                imageURL: song.imageURL,
                                size: 72,
                                cornerRadius: 18,
                                noteSize: 22,
                                strokeColor: theme.groupStroke
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.title.isEmpty ? "Untitled Song" : song.title)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(theme.primaryText)
                                    .lineLimit(2)

                                Text(song.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(theme.secondaryText)
                            }

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(theme.groupStroke, lineWidth: 0.8)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Send Mode")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.primaryText)

                            if allowedModes.count > 1 {
                                Picker("", selection: $selectedMode) {
                                    ForEach(allowedModes, id: \.self) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                            } else if let mode = allowedModes.first {
                                Text(mode.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(theme.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(theme.groupStroke, lineWidth: 0.8)
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Choose Friend")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.primaryText)

                            if friends.isEmpty {
                                SharePlaceholderSurface(
                                    artworkName: "share",
                                    title: "No friends yet",
                                    subtitle: "Add one friend first, then come back to send this song.",
                                    actionTitle: "Add Friends",
                                    action: onAddFriends,
                                    theme: theme
                                )
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(friends) { friend in
                                        Button {
                                            selectedFriendId = friend.id
                                        } label: {
                                            HStack(spacing: 12) {
                                                FriendAvatarView(friend: friend)
                                                    .frame(width: 44, height: 44)

                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(friend.resolvedName)
                                                        .font(.system(size: 16, weight: .semibold))
                                                        .foregroundStyle(theme.primaryText)
                                                    Text(friend.friendCode ?? "No code")
                                                        .font(.system(size: 13, weight: .regular))
                                                        .foregroundStyle(theme.secondaryText)
                                                }

                                                Spacer(minLength: 0)

                                                Image(systemName: selectedFriendId == friend.id ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 18, weight: .medium))
                                                    .foregroundStyle(selectedFriendId == friend.id ? theme.accent : theme.tertiaryText)
                                            }
                                            .padding(14)
                                            .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                    .stroke(selectedFriendId == friend.id ? theme.accent.opacity(0.4) : theme.groupStroke, lineWidth: 0.8)
                                            }
                                        }
                                        .buttonStyle(SharePressStyle())
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .background(theme.pageBackground)
                .navigationTitle("Send Song")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Send") {
                            if let friend = friends.first(where: { $0.id == selectedFriendId }) {
                                onSend(friend, selectedMode)
                                dismiss()
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(selectedFriendId == nil)
                    }
                }
            }
        }
    }
}

struct FriendsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = FriendsSheetViewModel()
    @State private var showQRCode = false
    @State private var showScanner = false

    let prefilledFriendCode: String?
    let onConsumePrefilledCode: (() -> Void)?

    private var theme: ShareTheme { ShareTheme(colorScheme: colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    myCodeCard
                    addFriendSection
                    requestsSection
                    friendsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 80)
                .frame(maxWidth: 430)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(theme.pageBackground)
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await viewModel.load() }
            .task(id: prefilledFriendCode) {
                guard let prefilledFriendCode,
                      !prefilledFriendCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return
                }
                await viewModel.applyIncomingFriendCode(prefilledFriendCode)
                onConsumePrefilledCode?()
            }
            .sheet(isPresented: $showQRCode) {
                FriendCodePreviewSheet(code: viewModel.myFriendCode)
            }
            .sheet(isPresented: $showScanner) {
                FriendCodeScannerSheet { code in
                    Task { await viewModel.applyIncomingFriendCode(code) }
                }
            }
            .alert(
                "Friends",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { isPresented in
                        if !isPresented { viewModel.errorMessage = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var myCodeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text("My Code")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)

                Spacer(minLength: 0)

                Button {
                    showScanner = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .frame(width: 38, height: 38)
                        .background(theme.groupSurface, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(theme.groupStroke, lineWidth: 0.8)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan QR")
            }

            Text(viewModel.myFriendCode)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(theme.primaryText)

            HStack(spacing: 12) {
                Button("Show QR") { showQRCode = true }
                    .friendActionCapsule(theme: theme)

                Button("Copy Code") {
                    UIPasteboard.general.string = viewModel.myFriendCode
                }
                .friendActionCapsule(theme: theme)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chipFill, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .modifier(ShareGlassChrome(cornerRadius: 30))
    }

    private var addFriendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Friend")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(theme.primaryText)

            TextField("Enter friend code", text: $viewModel.addFriendCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 16, weight: .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(theme.groupStroke, lineWidth: 0.8)
                }
                .onChange(of: viewModel.addFriendCode) { _, newValue in
                    let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if normalized != newValue {
                        viewModel.addFriendCode = normalized
                    }
                }

            Button("Send Request") {
                Task { await viewModel.sendRequest() }
            }
            .friendActionCapsule(theme: theme, filled: true)

            if let profile = viewModel.searchResult {
                HStack(spacing: 12) {
                    FriendAvatarView(friend: profile)
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.resolvedName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                        Text(profile.friendCode ?? "Preview")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                .padding(14)
                .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(theme.groupStroke, lineWidth: 0.8)
                }
            }
        }
    }

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            friendsListSection(
                title: "Incoming Requests",
                emptyTitle: "No incoming requests",
                emptySubtitle: "Requests sent to you will appear here.",
                emptyArtwork: "share"
            ) {
                ForEach(viewModel.incomingRequests) { request in
                    HStack(spacing: 12) {
                        FriendAvatarPlaceholder(name: request.senderName ?? "User")
                            .frame(width: 46, height: 46)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(request.senderName ?? "User")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                            Text(request.senderFriendCode ?? "Pending request")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(theme.secondaryText)
                        }

                        Spacer(minLength: 0)

                        Button("Accept") {
                            Task { await viewModel.accept(request) }
                        }
                        .friendMiniCapsule(theme: theme, filled: true)

                        Button("Decline") {
                            Task { await viewModel.decline(request) }
                        }
                        .friendMiniCapsule(theme: theme)
                    }
                    .padding(14)
                    .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(theme.groupStroke, lineWidth: 0.8)
                    }
                }
            }

            friendsListSection(
                title: "Sent Requests",
                emptyTitle: "Nothing pending",
                emptySubtitle: "Requests you send will stay here until they are accepted.",
                emptyArtwork: "compose"
            ) {
                ForEach(viewModel.sentRequests) { request in
                    HStack(spacing: 12) {
                        FriendAvatarPlaceholder(name: request.displayName ?? "User")
                            .frame(width: 46, height: 46)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(request.resolvedName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                            Text(request.friendCode ?? "Pending")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(theme.secondaryText)
                        }

                        Spacer(minLength: 0)

                        Button("Cancel") {
                            Task { await viewModel.cancel(request) }
                        }
                        .friendMiniCapsule(theme: theme)
                    }
                    .padding(14)
                    .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(theme.groupStroke, lineWidth: 0.8)
                    }
                }
            }
        }
    }

    private var friendsSection: some View {
        friendsListSection(
            title: "Friends",
            emptyTitle: "No friends yet",
            emptySubtitle: "Once someone accepts your request, they will appear here.",
            emptyArtwork: "share"
        ) {
            ForEach(viewModel.friends) { friend in
                HStack(spacing: 12) {
                    FriendAvatarView(friend: friend)
                        .frame(width: 50, height: 50)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(friend.resolvedName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                        Text(friend.friendCode ?? "Friend")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(theme.secondaryText)
                    }

                    Spacer(minLength: 0)

                    Button("Remove") {
                        Task { await viewModel.remove(friend) }
                    }
                    .friendMiniCapsule(theme: theme)
                }
                .padding(14)
                .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(theme.groupStroke, lineWidth: 0.8)
                }
            }
        }
    }

    @ViewBuilder
    private func friendsListSection<Rows: View>(
        title: String,
        emptyTitle: String,
        emptySubtitle: String,
        emptyArtwork: String,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(theme.primaryText)

            if isSectionEmpty(title) {
                SharePlaceholderSurface(
                    artworkName: emptyArtwork,
                    title: emptyTitle,
                    subtitle: emptySubtitle,
                    actionTitle: nil,
                    action: nil,
                    theme: theme
                )
            } else {
                VStack(spacing: 12) {
                    rows()
                }
            }
        }
    }

    private func isSectionEmpty(_ title: String) -> Bool {
        switch title {
        case "Incoming Requests":
            return viewModel.incomingRequests.isEmpty
        case "Sent Requests":
            return viewModel.sentRequests.isEmpty
        default:
            return viewModel.friends.isEmpty
        }
    }
}

private struct FriendAvatarPlaceholder: View {
    let name: String

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(uiColor: .systemIndigo), Color(uiColor: .systemPink)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Text(initials)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

private extension View {
    func friendActionCapsule(theme: ShareTheme, filled: Bool = false) -> some View {
        self
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(filled ? Color.white : theme.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(filled ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.chipFill))
            )
            .overlay {
                if !filled {
                    Capsule(style: .continuous)
                        .stroke(theme.chipStroke, lineWidth: 0.8)
                }
            }
    }

    func friendMiniCapsule(theme: ShareTheme, filled: Bool = false) -> some View {
        self
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(filled ? Color.white : theme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(filled ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.chipFill))
            )
            .overlay {
                if !filled {
                    Capsule(style: .continuous)
                        .stroke(theme.chipStroke, lineWidth: 0.8)
                }
            }
    }
}

private struct FriendCodePreviewSheet: View {
    let code: String

    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: UIImage?
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                Text(code)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))

                Text("Scan this code in MOMENTA to send a friend request.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .navigationTitle("My QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                qrImage = generateQRCode(from: "momenta://add-friend?code=\(code)")
            }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.correctionLevel = "Q"
        guard let outputImage = filter.outputImage?
            .transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

private struct FriendCodeScannerSheet: View {
    let onScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                #if canImport(VisionKit)
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    FriendCodeScannerRepresentable { code in
                        onScanned(code)
                        dismiss()
                    }
                } else {
                    unavailableView
                }
                #else
                unavailableView
                #endif
            }
            .navigationTitle("Scan QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
            Text("QR scanning is not available on this device right now.")
                .font(.system(size: 16, weight: .semibold))
            Text("You can still paste a friend code manually.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

#if canImport(VisionKit)
private struct FriendCodeScannerRepresentable: UIViewControllerRepresentable {
    let onScanned: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScanned: (String) -> Void

        init(onScanned: @escaping (String) -> Void) {
            self.onScanned = onScanned
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle(item)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            if let first = addedItems.first {
                handle(first)
            }
        }

        private func handle(_ item: RecognizedItem) {
            guard case .barcode(let barcode) = item,
                  let payload = barcode.payloadStringValue else { return }
            if let components = URLComponents(string: payload),
               components.scheme?.lowercased() == "momenta",
               let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                onScanned(code)
            } else {
                onScanned(payload)
            }
        }
    }
}
#endif

@MainActor
private final class FriendsSheetViewModel: ObservableObject {
    @Published var myFriendCode: String = ""
    @Published var addFriendCode: String = ""
    @Published var searchResult: FriendProfile?
    @Published var incomingRequests: [FriendRequest] = []
    @Published var sentRequests: [SentRequest] = []
    @Published var friends: [FriendProfile] = []
    @Published var errorMessage: String?

    private let friendService = FriendService.shared

    func load() async {
        let displayName = ProfileIdentityStore.resolvedDisplayName(email: AuthService.shared.currentUser?.email)
        errorMessage = nil

        do {
            guard let userId = await SupabaseService.shared.getCurrentUserId() else {
                throw FriendServiceError.notAuthenticated
            }
            try await friendService.ensureProfile(userId: userId, displayName: displayName)
            async let friendCode = friendService.getMyFriendCode(displayName: displayName)
            async let loadedFriends = friendService.loadFriends()
            async let loadedIncoming = friendService.loadPendingRequests()
            async let loadedSent = friendService.loadSentRequests()

            myFriendCode = try await friendCode
            friends = try await loadedFriends
            incomingRequests = try await loadedIncoming
            sentRequests = try await loadedSent
        } catch {
            myFriendCode = ""
            friends = []
            incomingRequests = []
            sentRequests = []
            errorMessage = error.localizedDescription
        }
    }

    func searchByCode() async {
        errorMessage = nil
        searchResult = nil
        do {
            let normalizedCode = addFriendCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedCode.isEmpty else { return }
            addFriendCode = normalizedCode
            searchResult = try await friendService.searchByFriendCode(
                normalizedCode,
                displayName: ProfileIdentityStore.resolvedDisplayName(email: AuthService.shared.currentUser?.email)
            )
            if searchResult == nil {
                errorMessage = "No user found for that code."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyIncomingFriendCode(_ code: String) async {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        addFriendCode = normalized
        await searchByCode()
    }

    func sendRequest() async {
        if searchResult == nil {
            await searchByCode()
        }
        guard let searchResult else { return }
        do {
            let result = try await friendService.sendFriendRequest(to: searchResult, note: nil)
            switch result {
            case .sent:
                addFriendCode = ""
                self.searchResult = nil
                await load()
            case .alreadyFriends:
                errorMessage = "You are already friends."
            case .alreadyPending:
                errorMessage = "A request is already pending."
            case .cannotAddSelf:
                errorMessage = "You cannot add yourself."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func accept(_ request: FriendRequest) async {
        do {
            try await friendService.acceptRequest(request.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func decline(_ request: FriendRequest) async {
        do {
            try await friendService.declineRequest(request.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel(_ request: SentRequest) async {
        do {
            try await friendService.cancelSentRequest(request.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ friend: FriendProfile) async {
        do {
            try await friendService.deleteFriend(friend.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
private final class ShareViewModel: ObservableObject {
    @Published var friends: [FriendProfile] = []
    @Published var friendInvitations: [FriendRequest] = []
    @Published var invitations: [ShareInboxItem] = []
    @Published var activities: [ShareActivityItem] = []
    @Published var mySongs: [GeneratedMusic] = []
    @Published var errorMessage: String?
    @Published var completionNotice: String?
    @Published var isGeneratingCreateHalf = false
    @Published var createHalfProgress = ""

    private let friendService = FriendService.shared
    private let profileService = ProfileService.shared
    private let musicDb = MusicDatabaseService.shared
    private let cocreateService = CocreateService.shared
    private let locationWeather = LocationWeatherService.shared
    private let memoryManager = Memory2MusicManager.createDefault()
    private let localStore = ShareLocalStore()
    private var activityPollingTask: Task<Void, Never>?

    // MARK: - Completed Cocreates
    struct CompletedCocreate: Identifiable {
        let id: UUID
        let music: GeneratedMusic
        let inviteeName: String?
    }
    @Published var completedItems: [CompletedCocreate] = []
    private var noticeTask: Task<Void, Never>?

    func load() async {
        errorMessage = nil
        let hiddenActivityIDs = localStore.hiddenActivityIDs()
        let localActivities = localStore.loadActivities()
        let previousActivities = activities
        activities = localActivities

        guard let userId = await SupabaseService.shared.getCurrentUserId() else { return }

        let displayName = ProfileIdentityStore.resolvedDisplayName(email: AuthService.shared.currentUser?.email)
        do {
            try await friendService.ensureProfile(userId: userId, displayName: displayName)
            async let loadedFriends = friendService.loadFriends()
            async let loadedFriendInvitations = friendService.loadPendingRequests()
            friends = try await loadedFriends
            friendInvitations = try await loadedFriendInvitations
        } catch {
            friends = []
            friendInvitations = []
            errorMessage = error.localizedDescription
        }

        let mine = (try? await musicDb.fetchMineSongs(userId: userId)) ?? []
        let memory = (try? await musicDb.fetchMemorySongs(userId: userId)) ?? []
        let cocreate = (try? await musicDb.fetchCocreateSongs(userId: userId)) ?? []
        let sharedSongs = (try? await musicDb.fetchSharedSongs(userId: userId)) ?? []
        let invitedSessions = (try? await cocreateService.loadInvitedSessions(userId: userId)) ?? []
        let mySessions = (try? await cocreateService.loadMySessions(userId: userId)) ?? []

        var seen = Set<String>()
        mySongs = (mine + memory + cocreate)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.createdAt > $1.createdAt }

        let sourceTaskIds = Array(Set((invitedSessions + mySessions).map(\.sourceTaskId)))
        let sourceSongs = (try? await musicDb.fetchMusicRecords(taskIds: sourceTaskIds)) ?? []
        let sourceMap = Dictionary(uniqueKeysWithValues: sourceSongs.map { ($0.id, $0) })

        let requestItems = invitedSessions.map { session in
            let sourceSong = sourceMap[session.sourceTaskId] ?? GeneratedMusic(
                id: session.sourceTaskId,
                title: session.sourceTitle ?? "Co-create Request",
                style: "",
                prompt: "",
                audioURL: nil,
                imageURL: session.sourceImageURL,
                sunoAudioId: session.sunoAudioId,
                status: .completed,
                createdAt: session.createdAt
            )
            return ShareInboxItem(
                id: "session-\(session.id.uuidString)",
                kind: .coCreateRequest,
                song: sourceSong,
                senderName: session.creatorDisplayName ?? "Collaborator",
                receivedAt: session.createdAt,
                session: session
            )
        }

        let sharedItems = sharedSongs.map { song in
            ShareInboxItem(
                id: "shared-\(song.id)",
                kind: .sharedSong,
                song: song,
                senderName: "Friend",
                receivedAt: song.createdAt,
                session: nil
            )
        }

        invitations = (requestItems + sharedItems).sorted { $0.receivedAt > $1.receivedAt }

        let remoteActivities = mySessions.map { session in
            let sourceSong = sourceMap[session.sourceTaskId]
            return ShareActivityItem(
                id: session.id,
                musicId: session.extendTaskId ?? session.sourceTaskId,
                title: (sourceSong?.title.isEmpty == false ? sourceSong?.title : nil) ?? session.sourceTitle ?? "Untitled Song",
                artworkURLString: sourceSong?.imageURL?.absoluteString ?? session.sourceImageURL?.absoluteString,
                recipientName: (session.status == .halfReady && session.inviteeId == nil)
                    ? ""
                    : (session.inviteeDisplayName ?? "Collaborator"),
                mode: .coCreate,
                status: activityStatus(for: session),
                createdAt: session.createdAt
            )
        }
        .filter { !hiddenActivityIDs.contains($0.id) }

        let mergedActivities = mergeActivities(local: localActivities, remote: remoteActivities)
        if let completedActivity = newlyCompletedActivity(in: mergedActivities, previous: previousActivities) {
            completionNotice = "\"\(completedActivity.title)\" is ready."
        }
        activities = mergedActivities
        localStore.replace(with: mergedActivities)
        await loadCompletedItems()
        await SystemSongLibrarySync.shared.refresh()
    }

    func startActivityPolling() {
        guard activityPollingTask == nil else { return }
        activityPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { break }
                await self?.load()
            }
        }
    }

    func stopActivityPolling() {
        activityPollingTask?.cancel()
        activityPollingTask = nil
    }

    func acceptFriendInvitation(_ request: FriendRequest) async {
        do {
            try await friendService.acceptRequest(request.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func declineFriendInvitation(_ request: FriendRequest) async {
        do {
            try await friendService.declineRequest(request.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeActivity(id: UUID) {
        localStore.hide(id: id)
        activities.removeAll { $0.id == id }
    }

    func beginGeneratingCreateHalfActivity() -> UUID {
        let id = UUID()
        let activity = ShareActivityItem(
            id: id,
            musicId: "draft-\(id.uuidString.lowercased())",
            title: "New co-create draft",
            artworkURLString: nil,
            recipientName: "",
            mode: .coCreate,
            status: .generatingDraft,
            createdAt: Date()
        )
        localStore.append(activity)
        activities = mergeActivities(local: [activity] + activities, remote: [])
        return id
    }

    func promoteGeneratingActivity(_ id: UUID, to prepared: PreparedCoCreateDraft) {
        localStore.remove(id: id)
        activities.removeAll { $0.id == id }

        let readyActivity = ShareActivityItem(
            id: prepared.sessionId,
            musicId: prepared.song.id,
            title: prepared.song.title.isEmpty ? "Untitled Song" : prepared.song.title,
            artworkURLString: prepared.song.imageURL?.absoluteString,
            recipientName: "",
            mode: .coCreate,
            status: .readyToSend,
            createdAt: Date()
        )
        localStore.append(readyActivity)
        activities = mergeActivities(local: [readyActivity] + activities, remote: [])
    }

    func sendPreparedCoCreate(
        song: GeneratedMusic,
        sessionId: UUID,
        to friend: FriendProfile
    ) async throws {
        try await cocreateService.inviteFriend(sessionId: sessionId, friendId: friend.id)

        let activity = ShareActivityItem(
            id: sessionId,
            musicId: song.id,
            title: song.title.isEmpty ? "Untitled Song" : song.title,
            artworkURLString: song.imageURL?.absoluteString,
            recipientName: friend.resolvedName,
            mode: .coCreate,
            status: .waitingForReply,
            createdAt: Date()
        )

        localStore.append(activity)
        activities = mergeActivities(local: [activity] + activities, remote: [])
        await load()
    }

    func preparedDraft(for activity: ShareActivityItem) async throws -> PreparedCoCreateDraft? {
        guard activity.isSendResumable else { return nil }
        guard let song = try await songForActivity(activity) else { return nil }
        return PreparedCoCreateDraft(song: song, sessionId: activity.id)
    }

    func songForActivity(_ activity: ShareActivityItem) async throws -> GeneratedMusic? {
        if let song = mySongs.first(where: { $0.id == activity.musicId }) {
            return song
        }
        return try await musicDb.fetchMusicRecord(taskId: activity.musicId)
    }

    func generateHalfSongForCreateHub(request: ShareCreateHalfSongRequest) async throws -> PreparedCoCreateDraft {
        if locationWeather.locationName == nil {
            await locationWeather.requestOnce()
        }

        let trimmedPrompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasInput = !trimmedPrompt.isEmpty || request.selectedImage != nil
        guard hasInput else {
            throw ShareComposerError.missingInput
        }

        isGeneratingCreateHalf = true
        createHalfProgress = "Preparing..."
        defer {
            isGeneratingCreateHalf = false
            createHalfProgress = ""
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "EEEE HH:mm"
        timeFormatter.locale = Locale(identifier: request.language == "zh" ? "zh_CN" : "en_US")
        let localTime = timeFormatter.string(from: Date())

        let generationContext = MemoryMusicContext(
            photo: request.selectedImage.flatMap { ImageUtility.toBase64(image: $0) },
            story: trimmedPrompt.isEmpty ? nil : trimmedPrompt,
            language: request.language,
            instrumentalOnly: request.instrumentalOnly,
            heartRate: nil,
            hrv: nil,
            healthHints: nil,
            suggestedBPM: nil,
            localTime: localTime,
            locationName: locationWeather.locationName,
            weather: locationWeather.weather,
            temperature: locationWeather.temperature
        )

        let music = try await memoryManager.generate(context: generationContext) { [weak self] progress in
            Task { @MainActor in
                self?.createHalfProgress = progress
            }
        }

        let totalDuration = music.duration ?? 180.0
        let cutPoint = CocreateExtendManager.computeContinueAt(
            totalDuration: totalDuration,
            bpm: 120
        )
        try await musicDb.updateContinueAt(taskId: music.id, continueAtSec: cutPoint)

        let preparedMusic = GeneratedMusic(
            id: music.id,
            title: music.title,
            style: music.style,
            prompt: music.prompt,
            audioURL: music.audioURL,
            imageURL: music.imageURL,
            sunoAudioId: music.sunoAudioId,
            status: music.status,
            createdAt: music.createdAt,
            source: music.source,
            ownerId: music.ownerId,
            duration: music.duration,
            continueAtSec: cutPoint
        )

        let snapshot = CocreateProfileSnapshot(
            language: request.language,
            instrumental: request.instrumentalOnly,
            style: preparedMusic.style,
            title: preparedMusic.title,
            prompt: preparedMusic.prompt,
            bpm: nil,
            vocalGender: nil,
            locationName: locationWeather.locationName,
            weather: locationWeather.weather,
            healthQuadrant: nil
        )

        let sessionId = try await cocreateService.createSession(
            sourceTaskId: preparedMusic.id,
            sunoAudioId: preparedMusic.sunoAudioId,
            continueAtSec: cutPoint,
            model: MusicGenerationRequest.SunoModel.v5.rawValue,
            profileA: snapshot
        )

        return PreparedCoCreateDraft(song: preparedMusic, sessionId: sessionId)
    }

    @discardableResult
    func send(
        song: GeneratedMusic,
        to friend: FriendProfile,
        mode: ShareSendMode,
        replacingActivityID: UUID? = nil
    ) async throws -> UUID? {
        guard let userId = await SupabaseService.shared.getCurrentUserId() else { return nil }
        var sessionId: UUID?

        switch mode {
        case .shareOnly:
            try await profileService.shareMusic(fromUserId: userId, toUserId: friend.id, musicId: song.id)

        case .coCreate:
            let continueAt = song.continueAtSec ?? suggestedContinueAt(for: song)
            try await musicDb.updateContinueAt(taskId: song.id, continueAtSec: continueAt)
            let snapshot = CocreateProfileSnapshot(
                language: nil,
                instrumental: song.style.lowercased().contains("instrumental"),
                style: song.style,
                title: song.title,
                prompt: song.prompt,
                bpm: nil,
                vocalGender: nil,
                locationName: nil,
                weather: nil,
                healthQuadrant: nil
            )
            sessionId = try await cocreateService.createSession(
                sourceTaskId: song.id,
                sunoAudioId: song.sunoAudioId,
                continueAtSec: continueAt,
                model: MusicGenerationRequest.SunoModel.v5.rawValue,
                profileA: snapshot
            )
            if let sessionId {
                try await cocreateService.inviteFriend(sessionId: sessionId, friendId: friend.id)
            }
        }

        let newActivity = ShareActivityItem(
            id: sessionId ?? UUID(),
            musicId: song.id,
            title: song.title.isEmpty ? "Untitled Song" : song.title,
            artworkURLString: song.imageURL?.absoluteString,
            recipientName: friend.resolvedName,
            mode: mode,
            status: mode == .shareOnly ? .shared : .waitingForReply,
            createdAt: Date()
        )
        if let replacingActivityID {
            localStore.remove(id: replacingActivityID)
            activities.removeAll { $0.id == replacingActivityID }
        }
        localStore.append(newActivity)
        activities = mergeActivities(local: [newActivity] + activities, remote: [])

        await load()
        return sessionId
    }

    func save(song: GeneratedMusic) async {
        guard let userId = await SupabaseService.shared.getCurrentUserId() else { return }
        let ownerId = song.ownerId ?? userId
        do {
            try await profileService.addFavorite(userId: userId, musicId: song.id, ownerId: ownerId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func declineInvitation(_ item: ShareInboxItem) async {
        guard let session = item.session else { return }
        do {
            try await cocreateService.declineSession(sessionId: session.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func invitation(sessionId: UUID) -> ShareInboxItem? {
        invitations.first { $0.session?.id == sessionId }
    }

    func sharedSong(taskId: String) -> ShareInboxItem? {
        invitations.first { $0.kind == .sharedSong && $0.song.id == taskId }
    }

    func activity(id: UUID) -> ShareActivityItem? {
        activities.first { $0.id == id }
    }

    private func suggestedContinueAt(for song: GeneratedMusic) -> Double {
        if let continueAt = song.continueAtSec, continueAt > 0 {
            return continueAt
        }
        if let duration = song.duration, duration > 32 {
            return max(24, duration * 0.5)
        }
        return 60
    }

    private func activityStatus(for session: CocreateSession) -> ShareActivityItem.Status {
        switch session.status {
        case .halfReady:
            return session.inviteeId == nil ? .readyToSend : .waitingForReply
        case .invited:
            return .waitingForReply
        case .extending:
            return .inProgress
        case .completed:
            return .completed
        case .expired:
            return .shared
        }
    }

    private func mergeActivities(local: [ShareActivityItem], remote: [ShareActivityItem]) -> [ShareActivityItem] {
        var mergedByID: [UUID: ShareActivityItem] = [:]

        for item in local {
            mergedByID[item.id] = preferredActivity(current: mergedByID[item.id], incoming: item)
        }

        // Remote sessions are authoritative for any ID that already exists locally.
        for item in remote {
            mergedByID[item.id] = item
        }

        return mergedByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.status.mergePriority > rhs.status.mergePriority
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func preferredActivity(
        current: ShareActivityItem?,
        incoming: ShareActivityItem
    ) -> ShareActivityItem {
        guard let current else { return incoming }
        if incoming.createdAt != current.createdAt {
            return incoming.createdAt > current.createdAt ? incoming : current
        }
        return incoming.status.mergePriority >= current.status.mergePriority ? incoming : current
    }

    private func newlyCompletedActivity(
        in merged: [ShareActivityItem],
        previous: [ShareActivityItem]
    ) -> ShareActivityItem? {
        let previousStatuses = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0.status) })

        return merged.first { item in
            item.mode == .coCreate &&
            item.status == .completed &&
            previousStatuses[item.id] != nil &&
            previousStatuses[item.id] != .completed
        }
    }

    func loadCompletedItems() async {
        guard let userId = await SupabaseService.shared.getCurrentUserId() else { return }
        do {
            var sessions = try await cocreateService.loadMyCompletedSessions(userId: userId)
            let taskIds = sessions.compactMap { $0.extendTaskId }
            let musicList = taskIds.isEmpty ? [] : (try? await musicDb.fetchMusicRecords(taskIds: taskIds)) ?? []
            let musicByTask = Dictionary(uniqueKeysWithValues: musicList.map { ($0.id, $0) })
            completedItems = sessions.compactMap { session in
                guard let taskId = session.extendTaskId,
                      let music = musicByTask[taskId] else { return nil }
                return CompletedCocreate(id: session.id, music: music, inviteeName: session.inviteeDisplayName)
            }
        } catch {
            print("⚠️ [ShareVM] loadCompletedItems: \(error)")
        }
    }

    func showCompletionNotice(_ message: String) {
        noticeTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            completionNotice = message
        }
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                self?.completionNotice = nil
            }
        }
    }
}

private struct ShareInboxItem: Identifiable {
    enum Kind: String, Hashable {
        case coCreateRequest
        case sharedSong

        var badgeTitle: String {
            switch self {
            case .coCreateRequest:
                return "CO-CREATE"
            case .sharedSong:
                return "SHARED"
            }
        }
    }

    let id: String
    let kind: Kind
    let song: GeneratedMusic
    let senderName: String
    let receivedAt: Date
    let session: CocreateSession?
}

private enum ShareSendMode: String, CaseIterable, Codable {
    case shareOnly
    case coCreate

    var title: String {
        switch self {
        case .shareOnly:
            return "Share Only"
        case .coCreate:
            return "Invite to Co-create"
        }
    }
}

private struct ShareActivityItem: Identifiable, Codable, Hashable {
    enum Status: String, Codable {
        case generatingDraft
        case readyToSend
        case shared
        case waitingForReply
        case inProgress
        case completed

        var title: String {
            switch self {
            case .generatingDraft:
                return "Generating draft"
            case .readyToSend:
                return "Ready to send"
            case .shared:
                return "Shared"
            case .waitingForReply:
                return "Waiting for collaborator"
            case .inProgress:
                return "Generating"
            case .completed:
                return "Ready"
            }
        }

        var mergePriority: Int {
            switch self {
            case .generatingDraft:
                return 0
            case .readyToSend:
                return 1
            case .shared:
                return 2
            case .waitingForReply:
                return 3
            case .inProgress:
                return 4
            case .completed:
                return 5
            }
        }
    }

    let id: UUID
    let musicId: String
    let title: String
    let artworkURLString: String?
    let recipientName: String
    let mode: ShareSendMode
    let status: Status
    let createdAt: Date

    var artworkURL: URL? { artworkURLString.flatMap(URL.init(string:)) }
    var isSendResumable: Bool { mode == .coCreate && status == .readyToSend }
}

private final class ShareLocalStore {
    private let defaults = UserDefaults.standard
    private let activitiesKey = "momenta.share.local-activities"
    private let hiddenActivitiesKey = "momenta.share.hidden-activities"

    func loadActivities() -> [ShareActivityItem] {
        guard let data = defaults.data(forKey: activitiesKey),
              let items = try? JSONDecoder().decode([ShareActivityItem].self, from: data) else {
            return []
        }
        let hidden = hiddenActivityIDs()
        return deduplicated(items)
            .filter { !hidden.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.status.mergePriority > rhs.status.mergePriority
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    func append(_ item: ShareActivityItem) {
        unhide(id: item.id)
        var items = loadActivities()
        items.removeAll { $0.id == item.id || ($0.musicId == item.musicId && $0.mode == item.mode && $0.recipientName == item.recipientName) }
        items.insert(item, at: 0)
        replace(with: items)
    }

    func remove(id: UUID) {
        var items = loadActivities()
        items.removeAll { $0.id == id }
        replace(with: items)
    }

    func hide(id: UUID) {
        var hidden = hiddenActivityIDs()
        hidden.insert(id)
        saveHiddenIDs(hidden)
        remove(id: id)
    }

    func hiddenActivityIDs() -> Set<UUID> {
        guard let data = defaults.data(forKey: hiddenActivitiesKey),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    private func unhide(id: UUID) {
        var hidden = hiddenActivityIDs()
        guard hidden.remove(id) != nil else { return }
        saveHiddenIDs(hidden)
    }

    private func saveHiddenIDs(_ ids: Set<UUID>) {
        if let data = try? JSONEncoder().encode(Array(ids)) {
            defaults.set(data, forKey: hiddenActivitiesKey)
        }
    }

    func replace(with items: [ShareActivityItem]) {
        let sanitizedItems = deduplicated(items).sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.status.mergePriority > rhs.status.mergePriority
            }
            return lhs.createdAt > rhs.createdAt
        }
        if let data = try? JSONEncoder().encode(sanitizedItems) {
            defaults.set(data, forKey: activitiesKey)
        }
    }

    private func deduplicated(_ items: [ShareActivityItem]) -> [ShareActivityItem] {
        var uniqueByID: [UUID: ShareActivityItem] = [:]
        for item in items {
            guard let existing = uniqueByID[item.id] else {
                uniqueByID[item.id] = item
                continue
            }

            if item.createdAt != existing.createdAt {
                uniqueByID[item.id] = item.createdAt > existing.createdAt ? item : existing
            } else if item.status.mergePriority >= existing.status.mergePriority {
                uniqueByID[item.id] = item
            }
        }
        return Array(uniqueByID.values)
    }
}

@MainActor
private final class ShareComposerViewModel: ObservableObject {
    let context: ShareComposerSheetContext

    @Published var prompt: String = ""
    @Published var selectedImage: UIImage?
    @Published var language: String = "en"
    @Published var instrumentalOnly: Bool = false
    @Published var isGenerating = false
    @Published var generationProgress = "Preparing..."
    @Published var errorMessage: String?
    @Published var showImagePicker = false
    @Published var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary

    private let locationWeather = LocationWeatherService.shared
    private let extendManager = CocreateExtendManager.createDefault()

    init(context: ShareComposerSheetContext, initialLanguage: String? = nil) {
        self.context = context

        if case .continueSession(let item) = context {
            prompt = item.session?.profileA.prompt ?? ""
            language = item.session?.profileA.language ?? "en"
            instrumentalOnly = item.session?.profileA.instrumental ?? false
        } else if let initialLanguage {
            language = initialLanguage
        }
    }

    var title: String {
        switch context {
        case .createNew:
            return "Create New Song"
        case .continueSession:
            return "Continue Song"
        }
    }

    var buttonTitle: String {
        switch context {
        case .createNew:
            return "Generate Half Song"
        case .continueSession:
            return "Continue Song"
        }
    }

    var helperTitle: String? {
        switch context {
        case .createNew:
            return nil
        case .continueSession(let item):
            return item.song.title.isEmpty ? "Untitled Song" : item.song.title
        }
    }

    var helperSubtitle: String? {
        switch context {
        case .createNew:
            return nil
        case .continueSession(let item):
            guard let session = item.session else { return nil }
            return "From \(item.senderName) · Continue at \(formatContinueAt(session.continueAtSec))"
        }
    }

    func makeCreateHalfSongRequest() throws -> ShareCreateHalfSongRequest {
        guard case .createNew = context else {
            throw ShareComposerError.invalidCreation
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasInput = !trimmedPrompt.isEmpty || selectedImage != nil
        guard hasInput else {
            throw ShareComposerError.missingInput
        }

        return ShareCreateHalfSongRequest(
            prompt: trimmedPrompt,
            selectedImage: selectedImage,
            language: language,
            instrumentalOnly: instrumentalOnly,
            instrument: ""
        )
    }

    func continueSessionDetached(onProgress: @escaping (String) -> Void) async throws -> GeneratedMusic {
        guard case .continueSession(let item) = context else {
            throw ShareComposerError.invalidContinuation
        }
        guard let session = item.session else {
            throw ShareComposerError.invalidContinuation
        }

        if locationWeather.locationName == nil {
            await fetchEnvironment()
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "EEEE HH:mm"
        let localTime = timeFormatter.string(from: Date())

        let resolvedLanguage = language.isEmpty
            ? (session.profileA.language ?? "en")
            : language

        let context = MemoryMusicContext(
            photo: selectedImage.flatMap { ImageUtility.toBase64(image: $0) },
            story: prompt.nilIfBlank,
            language: resolvedLanguage,
            instrumentalOnly: session.profileA.instrumental ?? instrumentalOnly,
            heartRate: nil,
            hrv: nil,
            healthHints: nil,
            suggestedBPM: nil,
            localTime: localTime,
            locationName: locationWeather.locationName,
            weather: locationWeather.weather,
            temperature: locationWeather.temperature
        )

        return try await extendManager.extend(
            session: session,
            context: context,
            onProgress: onProgress
        )
    }

    private func formatContinueAt(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remaining = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remaining)
    }

    private func fetchEnvironment() async {
        await locationWeather.requestOnce()
    }
}

private struct ShareComposerSheet: View {
    let context: ShareComposerSheetContext
    let initialLanguage: String?
    let onStartCreateNew: (ShareCreateHalfSongRequest) -> Void
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ShareComposerViewModel

    init(
        context: ShareComposerSheetContext,
        initialLanguage: String? = nil,
        onStartCreateNew: @escaping (ShareCreateHalfSongRequest) -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.context = context
        self.initialLanguage = initialLanguage
        self.onStartCreateNew = onStartCreateNew
        self.onFinished = onFinished
        _viewModel = StateObject(wrappedValue: ShareComposerViewModel(context: context, initialLanguage: initialLanguage))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isGenerating {
                    ShareComposerLoadingState(
                        context: context,
                        selectedImage: viewModel.selectedImage,
                        helperTitle: viewModel.helperTitle,
                        helperSubtitle: viewModel.helperSubtitle,
                        progressText: viewModel.generationProgress
                    )
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            if let helperTitle = viewModel.helperTitle,
                               let helperSubtitle = viewModel.helperSubtitle {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(helperTitle)
                                        .font(.system(size: 17, weight: .semibold))
                                    Text(helperSubtitle)
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }

                            if let image = viewModel.selectedImage {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 220)
                                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                                    Button {
                                        viewModel.selectedImage = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 22, weight: .medium))
                                            .foregroundStyle(.white, .black.opacity(0.45))
                                    }
                                    .padding(12)
                                }
                            } else {
                                HStack(spacing: 12) {
                                    Button {
                                        viewModel.imagePickerSourceType = .camera
                                        viewModel.showImagePicker = true
                                    } label: {
                                        Label("Camera", systemImage: "camera")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        viewModel.imagePickerSourceType = .photoLibrary
                                        viewModel.showImagePicker = true
                                    } label: {
                                        Label("Photo", systemImage: "photo")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Prompt")
                                    .font(.system(size: 15, weight: .semibold))
                                TextField("Describe the song you want to start here…", text: $viewModel.prompt, axis: .vertical)
                                    .lineLimit(3...6)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Language")
                                    .font(.system(size: 15, weight: .semibold))
                                Picker("", selection: $viewModel.language) {
                                    Text("EN").tag("en")
                                    Text("中文").tag("zh")
                                }
                                .pickerStyle(.segmented)
                            }

                            Toggle(isOn: $viewModel.instrumentalOnly) {
                                Label("Instrumental", systemImage: "music.note")
                            }
                            .toggleStyle(.switch)

                            Button {
                                switch context {
                                case .continueSession(let item):
                                    guard let session = item.session else { return }
                                    ShareCoCreateCoordinator.shared.start(
                                        sessionId: session.id,
                                        title: item.song.title.isEmpty ? "Untitled Song" : item.song.title,
                                        collaboratorName: item.senderName,
                                        artworkURL: item.song.imageURL
                                    ) { progress in
                                        try await viewModel.continueSessionDetached(onProgress: progress)
                                    }
                                    onFinished()
                                    dismiss()

                                case .createNew:
                                    do {
                                        let request = try viewModel.makeCreateHalfSongRequest()
                                        onStartCreateNew(request)
                                        onFinished()
                                        dismiss()
                                    } catch {
                                        viewModel.errorMessage = error.localizedDescription
                                    }
                                }
                            } label: {
                                Text(viewModel.buttonTitle)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .background(Color(uiColor: .systemIndigo), in: Capsule(style: .continuous))
                            }
                            .buttonStyle(SharePressStyle())
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 120)
                    }
                }
            }
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.isGenerating {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showImagePicker) {
                ImagePicker(sourceType: viewModel.imagePickerSourceType, selectedImage: $viewModel.selectedImage)
            }
            .alert(
                "Composer",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { isPresented in
                        if !isPresented { viewModel.errorMessage = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private func formatContinueAt(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remaining = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remaining)
    }
}

private struct ShareComposerLoadingState: View {
    let context: ShareComposerSheetContext
    let selectedImage: UIImage?
    let helperTitle: String?
    let helperSubtitle: String?
    let progressText: String

    @Environment(\.colorScheme) private var colorScheme
    private var theme: ShareTheme { ShareTheme(colorScheme: colorScheme) }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                loadingArtwork
                    .frame(width: 220, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 8) {
                    Text(loadingTitle)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(theme.primaryText)

                    Text(loadingSubtitle)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(theme.primaryText)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(progressText)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.primaryText)

                            Text("This status updates automatically while the co-create task is active.")
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
                .background(theme.chipFill, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .modifier(ShareGlassChrome(cornerRadius: 28))

                VStack(alignment: .leading, spacing: 12) {
                    Text("What happens next")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.primaryText)

                    loadingStep(title: "Prepare the handoff", subtitle: "MOMENTA reads the existing song and your continuation note.")
                    loadingStep(title: "Generate the extension", subtitle: "The collaborator stage moves to live generation once the request reaches Suno.")
                    loadingStep(title: "Return the finished track", subtitle: "The session flips to ready and the sender sees the same update.")
                }
                .padding(18)
                .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(theme.groupStroke, lineWidth: 0.8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 120)
        }
        .background(theme.pageBackground)
    }

    @ViewBuilder
    private var loadingArtwork: some View {
        switch context {
        case .continueSession(let item):
            ShareRemoteArtwork(
                imageURL: item.song.imageURL,
                size: 220,
                cornerRadius: 28,
                noteSize: 28,
                strokeColor: theme.groupStroke
            )
        case .createNew:
            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ShareStaticArtwork(name: "compose")
            }
        }
    }

    private var loadingTitle: String {
        switch context {
        case .continueSession:
            return "Generating continuation"
        case .createNew:
            return "Generating song"
        }
    }

    private var loadingSubtitle: String {
        switch context {
        case .continueSession:
            if let helperTitle, let helperSubtitle {
                return "\(helperTitle)\n\(helperSubtitle)"
            }
            return "The collaborator state will stay visible in Share while this runs."
        case .createNew:
            return "The new track will be ready to send as soon as it finishes."
        }
    }

    private func loadingStep(title: String, subtitle: String) -> some View {
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

@MainActor
private final class CocreateExtendManager: ObservableObject {
    private let llmService: LLMServiceProtocol
    private let sunoService: SunoDirectService
    private let emotionML: EmotionMLService

    init(
        llmService: LLMServiceProtocol? = nil,
        sunoService: SunoDirectService = SunoDirectService(),
        emotionML: EmotionMLService = EmotionMLService()
    ) {
        self.llmService = llmService ?? OpenAILyricsService(
            apiKey: APIConfiguration.openAIAPIKey,
            baseURL: APIConfiguration.openAIBaseURL
        )
        self.sunoService = sunoService
        self.emotionML = emotionML
    }

    static func createDefault() -> CocreateExtendManager {
        CocreateExtendManager()
    }

    static func computeContinueAt(
        totalDuration: Double,
        bpm: Int = 120,
        targetRatio: Double = 0.5
    ) -> Double {
        let barDuration = 4.0 * 60.0 / Double(bpm)
        let rawCut = totalDuration * targetRatio
        let bars = (rawCut / barDuration).rounded()
        let snapped = bars * barDuration
        return min(max(snapped, barDuration), totalDuration - barDuration)
    }

    func extend(
        session: CocreateSession,
        context: MemoryMusicContext,
        onProgress: (String) -> Void
    ) async throws -> GeneratedMusic {
        var ctx = context

        if ctx.healthHints == nil, let hr = ctx.heartRate {
            onProgress("Analyzing your emotional state...")
            let hrvForModel = ctx.hrv ?? 50.0
            ctx.healthHints = try? emotionML.predict(heartRate: hr, hrv: hrvForModel)
        }

        onProgress("AI is composing the continuation...")
        let promptText: String
        let isInstrumental = session.profileA.instrumental ?? ctx.instrumentalOnly
        if isInstrumental {
            promptText = MemoryInstrumentalPromptBuilder.build(from: ctx)
        } else {
            promptText = MemoryLyricsPromptBuilder.build(from: ctx)
        }

        let llmResponse = try await llmService.generateLyrics(
            request: LyricsGenerationRequest(
                photo: ctx.photo,
                photoPresent: ctx.hasPhoto,
                storyShare: ctx.story ?? "",
                instrumentalOnly: isInstrumental,
                language: ctx.language,
                rawPrompt: promptText
            )
        )

        let profileB = CocreateProfileSnapshot(
            language: ctx.language,
            instrumental: isInstrumental,
            style: llmResponse.style,
            title: llmResponse.title,
            prompt: llmResponse.prompt,
            bpm: ctx.suggestedBPM,
            vocalGender: nil,
            locationName: ctx.locationName,
            weather: ctx.weather,
            healthQuadrant: ctx.healthHints?.quadrant.rawValue
        )

        let merged = session.profileA.merging(with: profileB)
        let finalStyle = buildExtendStyle(merged: merged, profileA: session.profileA, profileB: profileB)

        onProgress("Preparing to extend the song...")
        guard let audioId = session.sunoAudioId, !audioId.isEmpty else {
            throw CocreateServiceError.invalidState("Missing source audio ID")
        }

        let request = MusicExtendRequest(
            defaultParamFlag: true,
            audioId: audioId,
            model: MusicGenerationRequest.SunoModel(rawValue: session.model) ?? .v5,
            callBackUrl: APIConfiguration.sunoCallbackURL,
            prompt: llmResponse.prompt ?? "",
            style: finalStyle,
            title: merged.title ?? llmResponse.title,
            continueAt: session.continueAtSec,
            negativeTags: nil,
            vocalGender: extractVocalGender(from: finalStyle),
            styleWeight: nil,
            weirdnessConstraint: nil,
            audioWeight: nil
        )

        onProgress("Submitting extend task...")
        let taskId = try await sunoService.extendMusic(request: request)

        guard let userId = await SupabaseService.shared.getCurrentUserId() else {
            throw MusicServiceError.apiError(code: 401, message: "User not authenticated")
        }

        try await MusicDatabaseService.shared.createInitialRecord(
            taskId: taskId,
            prompt: request.prompt ?? "",
            style: request.style ?? "",
            userId: userId,
            source: "cocreate",
            parentAudioId: audioId,
            cocreateSessionId: session.id
        )

        try await CocreateService.shared.updateSessionForExtend(
            sessionId: session.id,
            extendTaskId: taskId,
            profileB: profileB
        )

        onProgress("AI is creating music, please wait...")
        return try await withThrowingTaskGroup(of: GeneratedMusic?.self) { group in
            group.addTask {
                do {
                    let stream = MusicDatabaseService.shared.subscribeToTaskUpdate(taskId: taskId)
                    for try await music in stream { return music }
                } catch {
                    print("⚠️ [CocreateExtend·Realtime] 连接中断: \(error.localizedDescription)")
                }
                return nil
            }

            group.addTask {
                let music = try await self.sunoService.waitForCompletion(taskId: taskId)
                await MusicDatabaseService.shared.syncCompletedMusic(music)
                return music
            }

            group.addTask {
                var attempts = 0
                while attempts < 20 {
                    try await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                    if let music = try await MusicDatabaseService.shared.fetchMusicRecord(taskId: taskId),
                       music.status == .completed {
                        return music
                    }
                    attempts += 1
                }
                return nil
            }

            while let result = try await group.next() {
                if let music = result {
                    group.cancelAll()
                    try? await CocreateService.shared.markCompleted(sessionId: session.id)
                    onProgress("Song complete!")
                    return music
                }
            }

            throw MusicServiceError.timeout
        }
    }

    private func buildExtendStyle(
        merged: CocreateProfileSnapshot,
        profileA: CocreateProfileSnapshot,
        profileB: CocreateProfileSnapshot
    ) -> String {
        var style = merged.style ?? ""

        if let bpmA = profileA.bpm, let bpmB = profileB.bpm, abs(bpmA - bpmB) > 30 {
            if !style.uppercased().contains("BPM") {
                style = "\(bpmA) BPM transitioning to \(bpmB) BPM, \(style)"
            }
        } else if let bpm = merged.bpm {
            if !style.uppercased().contains("BPM") {
                style = "\(bpm) BPM, \(style)"
            }
        }

        return style
    }

    private func extractVocalGender(from style: String) -> MusicGenerationRequest.VocalGender? {
        let lowercased = style.lowercased()
        if lowercased.contains("male vocal") && !lowercased.contains("female") {
            return .male
        }
        if lowercased.contains("female vocal") {
            return .female
        }
        return nil
    }
}

private enum ShareComposerError: LocalizedError {
    case missingInput
    case invalidCreation
    case invalidContinuation
    case missingSourceAudio
    case missingUser

    var errorDescription: String? {
        switch self {
        case .missingInput:
            return "Add a prompt or an image before generating."
        case .invalidCreation:
            return "This composer is no longer in create mode."
        case .invalidContinuation:
            return "This co-create request is missing the session context."
        case .missingSourceAudio:
            return "The source song is missing its audio reference, so continuation cannot start yet."
        case .missingUser:
            return "You need to be signed in to continue a song."
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
