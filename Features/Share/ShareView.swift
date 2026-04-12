import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins
#if canImport(VisionKit)
import VisionKit
#endif

struct ShareView: View {
    @ObservedObject var deepLinkRouter: DeepLinkRouter
    @Environment(PlayerManager.self) private var playerManager
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var viewModel = ShareViewModel()
    @State private var showFriendsSheet = false
    @State private var selectedSongForSend: GeneratedMusic?
    @State private var composerContext: ShareComposerSheetContext?
    @State private var navigationPath = NavigationPath()

    private var theme: ShareTheme { ShareTheme(colorScheme: colorScheme) }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    destinationCards
                    activitySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 120)
                .frame(maxWidth: 430)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(theme.pageBackground)
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ShareDestination.self) { destination in
                switch destination {
                case .invitations:
                    ShareInvitationsView(
                        viewModel: viewModel,
                        onPlay: playSong,
                        onOpenComposerForSession: { item in
                            composerContext = .continueSession(item)
                        },
                        onSendSong: { selectedSongForSend = $0 }
                    )
                case .start:
                    ShareStartToCoCreateView(
                        viewModel: viewModel,
                        onCreateNew: { composerContext = .createNew },
                        onSelectSong: { selectedSongForSend = $0 },
                        onOpenFriends: { showFriendsSheet = true },
                        onPlay: playSong
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
                            },
                            onStartCoCreate: {
                                selectedSongForSend = item.song
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
                        ShareActivityDetailView(activity: activity, theme: theme)
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
                Task { await viewModel.load() }
            }) { song in
                ShareSendSheet(
                    song: song,
                    friends: viewModel.friends,
                    theme: theme,
                    onAddFriends: { showFriendsSheet = true },
                    onSend: { friend, mode in
                        Task {
                            await viewModel.send(song: song, to: friend, mode: mode)
                            selectedSongForSend = nil
                        }
                    }
                )
            }
            .sheet(item: $composerContext, onDismiss: {
                Task { await viewModel.load() }
            }) { context in
                ShareComposerSheet(
                    context: context,
                    onGenerated: { music in
                        switch context {
                        case .createNew:
                            selectedSongForSend = music
                        case .continueSession:
                            break
                        }
                    },
                    onFinished: {
                        Task { await viewModel.load() }
                    }
                )
            }
            .task {
                await viewModel.load()
                handlePendingShareRouteIfNeeded()
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
        VStack(alignment: .leading, spacing: 8) {
            Text("SHARE")
                .font(.system(size: 20, weight: .regular, design: .default).width(.expanded))
                .foregroundStyle(theme.primaryText)

            Text("Receive songs, send songs, and continue a track with one collaborator at a time.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var destinationCards: some View {
        VStack(spacing: 14) {
            NavigationLink(value: ShareDestination.invitations) {
                ShareHeroCard(
                    title: "Invitations",
                    subtitle: invitationSubtitle,
                    systemImage: "tray.full",
                    artworkName: "share",
                    theme: theme
                )
            }
            .buttonStyle(SharePressStyle())

            NavigationLink(value: ShareDestination.start) {
                ShareHeroCard(
                    title: "Start to Co-create",
                    subtitle: startSubtitle,
                    systemImage: "sparkles.rectangle.stack",
                    artworkName: "compose",
                    theme: theme
                )
            }
            .buttonStyle(SharePressStyle())
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent Activity")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
            }

            if viewModel.activities.isEmpty {
                SharePlaceholderSurface(
                    artworkName: "compose",
                    title: "Nothing in progress yet",
                    subtitle: viewModel.friends.isEmpty
                    ? "Add a friend first, then send a song as Share Only or Invite to Co-create."
                    : "Start from one of your songs and the session will appear here.",
                    actionTitle: viewModel.friends.isEmpty ? "Add Friends" : nil,
                    action: viewModel.friends.isEmpty ? { showFriendsSheet = true } : nil,
                    theme: theme
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.activities) { activity in
                        ShareActivityRow(activity: activity, theme: theme)
                    }
                }
            }
        }
    }

    private var invitationSubtitle: String {
        if viewModel.invitations.isEmpty {
            return "No requests yet."
        }
        return "\(viewModel.invitations.count) waiting for you."
    }

    private var startSubtitle: String {
        if viewModel.mySongs.isEmpty {
            return "Create a new song here, then send it to one friend."
        }
        return "Pick from \(viewModel.mySongs.count) of your songs or create a new one."
    }

    private func playSong(_ song: GeneratedMusic) {
        playerManager.currentMusic = song
        playerManager.lyrics = []
        playerManager.currentLineIndex = 0
        playerManager.showLyrics = false
        playerManager.lyricsControlsVisible = true
        playerManager.play()
    }

    private func handlePendingShareRouteIfNeeded() {
        guard let route = deepLinkRouter.pendingShareRoute else { return }

        switch route {
        case .invitations:
            navigationPath = NavigationPath([ShareDestination.invitations])
        case .invitationDetail(let id):
            navigationPath = NavigationPath([
                ShareDestination.invitations,
                ShareDestination.invitationDetail(id)
            ])
        case .start:
            navigationPath = NavigationPath([ShareDestination.start])
        case .sharedSongDetail(let taskId):
            navigationPath = NavigationPath([
                ShareDestination.invitations,
                ShareDestination.sharedSongDetail(taskId)
            ])
        case .activityDetail(let id):
            navigationPath = NavigationPath([
                ShareDestination.start,
                ShareDestination.activityDetail(id)
            ])
        }

        deepLinkRouter.clearPendingShareRoute()
    }
}

private enum ShareDestination: Hashable {
    case invitations
    case start
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

private struct ShareTheme {
    let colorScheme: ColorScheme

    var pageBackground: Color { Color(uiColor: .systemGray6) }
    var groupSurface: Color { Color(uiColor: .systemBackground) }
    var groupStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05)
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
        colorScheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.82)
    }
    var chipStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
    var glassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.08)
    }
    var accent: Color { Color(uiColor: .systemIndigo) }
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

private struct SharePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct ShareHeroCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let artworkName: String
    let theme: ShareTheme

    var body: some View {
        HStack(spacing: 16) {
            ShareStaticArtwork(name: artworkName)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                } icon: {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                }

                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
        }
        .padding(18)
        .background(theme.chipFill, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(ShareGlassChrome(cornerRadius: 28))
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

private struct ShareActivityRow: View {
    let activity: ShareActivityItem
    let theme: ShareTheme

    var body: some View {
        HStack(spacing: 14) {
            ShareActivityArtwork(activity: activity)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(activity.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text("\(activity.mode.title) with \(activity.recipientName)")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)

                Text(activity.status.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
            }

            Spacer(minLength: 0)

            Text(activity.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(theme.tertiaryText)
        }
        .padding(14)
        .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.groupStroke, lineWidth: 0.8)
        }
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
    let onSendSong: (GeneratedMusic) -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: ShareTheme { ShareTheme(colorScheme: colorScheme) }

    private var coCreateRequests: [ShareInboxItem] {
        viewModel.invitations.filter { $0.kind == .coCreateRequest }
    }

    private var sharedSongs: [ShareInboxItem] {
        viewModel.invitations.filter { $0.kind == .sharedSong }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                invitationSection(
                    title: "Co-create Requests",
                    items: coCreateRequests,
                    emptyTitle: "No co-create requests",
                    emptySubtitle: "When someone sends you a half-finished track to continue, it will appear here.",
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
                    title: "Shared with You",
                    items: sharedSongs,
                    emptyTitle: "No shared songs yet",
                    emptySubtitle: "Songs sent to you for listening will stay separate from co-create requests.",
                    rowBuilder: { item in
                        NavigationLink {
                            ShareSharedSongDetailView(
                                item: item,
                                onPlay: onPlay,
                                onSave: {
                                    Task { await viewModel.save(song: item.song) }
                                },
                                onStartCoCreate: {
                                    onSendSong(item.song)
                                }
                            )
                        } label: {
                            ShareInboxRow(item: item, theme: theme)
                        }
                        .buttonStyle(.plain)
                    }
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 120)
            .frame(maxWidth: 430)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(theme.pageBackground)
        .navigationTitle("Invitations")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func invitationSection<Row: View>(
        title: String,
        items: [ShareInboxItem],
        emptyTitle: String,
        emptySubtitle: String,
        @ViewBuilder rowBuilder: @escaping (ShareInboxItem) -> Row
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(theme.primaryText)

            if items.isEmpty {
                SharePlaceholderSurface(
                    artworkName: "share",
                    title: emptyTitle,
                    subtitle: emptySubtitle,
                    actionTitle: nil,
                    action: nil,
                    theme: theme
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        rowBuilder(item)
                    }
                }
            }
        }
    }
}

private struct ShareInboxRow: View {
    let item: ShareInboxItem
    let theme: ShareTheme

    var body: some View {
        HStack(spacing: 14) {
            ShareRemoteArtwork(
                imageURL: item.song.imageURL,
                size: 60,
                cornerRadius: 16,
                noteSize: 20,
                strokeColor: theme.groupStroke
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(item.song.title.isEmpty ? "Untitled Song" : item.song.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text(item.senderName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)

                Text(item.receivedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
            }

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
        .padding(14)
        .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.groupStroke, lineWidth: 0.8)
        }
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
    let onStartCoCreate: () -> Void

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

                    HStack(spacing: 12) {
                        Button("Save", action: onSave)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(theme.groupSurface, in: Capsule(style: .continuous))
                            .overlay {
                                Capsule(style: .continuous).stroke(theme.groupStroke, lineWidth: 0.8)
                            }

                        Button("Start to Co-create", action: onStartCoCreate)
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

                    Text("\(activity.mode.title) with \(activity.recipientName)")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(theme.secondaryText)

                    Text(activity.status.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                }

                Text("This detail view is ready for notifications and future widget entry points. It tracks the collaboration state without changing the current Share structure.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 120)
        }
        .background(theme.pageBackground)
        .navigationTitle("Session Activity")
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
    let onSelectSong: (GeneratedMusic) -> Void
    let onOpenFriends: () -> Void
    let onPlay: (GeneratedMusic) -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: ShareTheme { ShareTheme(colorScheme: colorScheme) }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    Button(action: onCreateNew) {
                        HStack(spacing: 14) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24, weight: .regular))
                                .foregroundStyle(theme.accent)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Create New Song")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(theme.primaryText)
                                Text("Generate in Share, then drop directly into the send flow.")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(theme.secondaryText)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(18)
                        .background(theme.chipFill, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .modifier(ShareGlassChrome(cornerRadius: 28))
                    }
                    .buttonStyle(SharePressStyle())
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Your Songs")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                        Spacer()
                        if viewModel.mySongs.isEmpty {
                            Button("Add Friends", action: onOpenFriends)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }

                    if viewModel.mySongs.isEmpty {
                        SharePlaceholderSurface(
                            artworkName: "compose",
                            title: "No songs yet",
                            subtitle: "Create a song here or generate one in Light or Memories first.",
                            actionTitle: "Create New Song",
                            action: onCreateNew,
                            theme: theme
                        )
                    } else {
                        VStack(spacing: 12) {
                            ForEach(viewModel.mySongs) { song in
                                ShareTimelineSongRow(song: song, theme: theme, onPlay: {
                                    onPlay(song)
                                }, onSelect: {
                                    onSelectSong(song)
                                })
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Sent / Active")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.primaryText)

                    if viewModel.activities.isEmpty {
                        SharePlaceholderSurface(
                            artworkName: "share",
                            title: "No sessions in flight",
                            subtitle: "After you share a song or invite someone to continue it, the state will appear here.",
                            actionTitle: nil,
                            action: nil,
                            theme: theme
                        )
                    } else {
                        VStack(spacing: 12) {
                            ForEach(viewModel.activities) { activity in
                                ShareActivityRow(activity: activity, theme: theme)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 120)
            .frame(maxWidth: 430)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(theme.pageBackground)
        .navigationTitle("Start to Co-create")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct ShareTimelineSongRow: View {
    let song: GeneratedMusic
    let theme: ShareTheme
    let onPlay: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onPlay) {
                ShareRemoteArtwork(
                    imageURL: song.imageURL,
                    size: 58,
                    cornerRadius: 14,
                    noteSize: 20,
                    strokeColor: theme.groupStroke
                )
            }
            .buttonStyle(SharePressStyle())

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title.isEmpty ? "Untitled Song" : song.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text(song.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: 0)

            Button("Send", action: onSelect)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(theme.chipFill, in: Capsule(style: .continuous))
                .modifier(ShareGlassChrome(cornerRadius: 18))
        }
        .padding(14)
        .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.groupStroke, lineWidth: 0.8)
        }
    }
}

private struct ShareSendSheet: View {
    let song: GeneratedMusic
    let friends: [FriendProfile]
    let theme: ShareTheme
    let onAddFriends: () -> Void
    let onSend: (FriendProfile, ShareSendMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFriendId: UUID?
    @State private var selectedMode: ShareSendMode = .shareOnly

    var body: some View {
        NavigationStack {
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
                    }
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

                        Picker("", selection: $selectedMode) {
                            ForEach(ShareSendMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

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
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 120)
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
                    viewModel.addFriendCode = code
                    Task { await viewModel.searchByCode() }
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
            Text("My Code")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.secondaryText)

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
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 16, weight: .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(theme.groupSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(theme.groupStroke, lineWidth: 0.8)
                }

            HStack(spacing: 12) {
                Button("Send Request") {
                    Task { await viewModel.sendRequest() }
                }
                .friendActionCapsule(theme: theme, filled: true)

                Button("Scan QR") { showScanner = true }
                    .friendActionCapsule(theme: theme)
            }

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

private struct FriendAvatarView: View {
    let friend: FriendProfile

    var body: some View {
        if let avatarUrl = friend.avatarUrl.flatMap(URL.init(string:)) {
            AsyncImage(url: avatarUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    FriendAvatarPlaceholder(name: friend.resolvedName)
                }
            }
            .clipShape(Circle())
        } else {
            FriendAvatarPlaceholder(name: friend.resolvedName)
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
        if let userId = await SupabaseService.shared.getCurrentUserId() {
            try? await friendService.ensureProfile(userId: userId, displayName: displayName)
        }
        myFriendCode = (try? await friendService.getMyFriendCode(displayName: displayName)) ?? "MOM-00000"
        friends = (try? await friendService.loadFriends()) ?? []
        incomingRequests = (try? await friendService.loadPendingRequests()) ?? []
        sentRequests = (try? await friendService.loadSentRequests()) ?? []
    }

    func searchByCode() async {
        do {
            searchResult = try await friendService.searchByFriendCode(addFriendCode, displayName: ProfileIdentityStore.resolvedDisplayName(email: AuthService.shared.currentUser?.email))
            if searchResult == nil {
                errorMessage = "No user found for that code."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyIncomingFriendCode(_ code: String) async {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
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
    @Published var invitations: [ShareInboxItem] = []
    @Published var activities: [ShareActivityItem] = []
    @Published var mySongs: [GeneratedMusic] = []
    @Published var errorMessage: String?

    private let friendService = FriendService.shared
    private let profileService = ProfileService.shared
    private let musicDb = MusicDatabaseService.shared
    private let cocreateService = CocreateService.shared
    private let localStore = ShareLocalStore()

    func load() async {
        let localActivities = localStore.loadActivities()
        activities = localActivities

        guard let userId = await SupabaseService.shared.getCurrentUserId() else { return }

        let displayName = ProfileIdentityStore.resolvedDisplayName(email: AuthService.shared.currentUser?.email)
        try? await friendService.ensureProfile(userId: userId, displayName: displayName)

        friends = (try? await friendService.loadFriends()) ?? []

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
                recipientName: session.inviteeDisplayName ?? "Collaborator",
                mode: .coCreate,
                status: activityStatus(for: session.status),
                createdAt: session.createdAt
            )
        }

        activities = mergeActivities(local: localActivities, remote: remoteActivities)
        await SystemSongLibrarySync.shared.refresh()
    }

    func send(song: GeneratedMusic, to friend: FriendProfile, mode: ShareSendMode) async {
        guard let userId = await SupabaseService.shared.getCurrentUserId() else { return }

        switch mode {
        case .shareOnly:
            do {
                try await profileService.shareMusic(fromUserId: userId, toUserId: friend.id, musicId: song.id)
            } catch {
                print("⚠️ [Share] Share-only backend insert failed, keeping local activity: \(error.localizedDescription)")
            }

        case .coCreate:
            let continueAt = song.continueAtSec ?? suggestedContinueAt(for: song)
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
            do {
                let sessionId = try await cocreateService.createSession(
                    sourceTaskId: song.id,
                    sunoAudioId: song.sunoAudioId,
                    continueAtSec: continueAt,
                    model: MusicGenerationRequest.SunoModel.v5.rawValue,
                    profileA: snapshot,
                    sourceTitle: song.title.isEmpty ? "Untitled Song" : song.title,
                    sourceImageURL: song.imageURL
                )
                try await cocreateService.inviteFriend(sessionId: sessionId, friendId: friend.id)
            } catch {
                print("⚠️ [Share] Cocreate backend insert failed, keeping local activity: \(error.localizedDescription)")
            }
        }

        localStore.append(
            ShareActivityItem(
                id: UUID(),
                musicId: song.id,
                title: song.title.isEmpty ? "Untitled Song" : song.title,
                artworkURLString: song.imageURL?.absoluteString,
                recipientName: friend.resolvedName,
                mode: mode,
                status: mode == .shareOnly ? .shared : .waitingForReply,
                createdAt: Date()
            )
        )

        await load()
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

    private func activityStatus(for status: CocreateSession.Status) -> ShareActivityItem.Status {
        switch status {
        case .halfReady, .invited:
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
        var merged = remote
        var seen = Set(remote.map { "\($0.musicId)|\($0.recipientName)|\($0.mode.rawValue)" })

        for item in local {
            let key = "\(item.musicId)|\(item.recipientName)|\(item.mode.rawValue)"
            if seen.insert(key).inserted {
                merged.append(item)
            }
        }

        return merged.sorted { $0.createdAt > $1.createdAt }
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
        case shared
        case waitingForReply
        case inProgress
        case completed

        var title: String {
            switch self {
            case .shared:
                return "Shared"
            case .waitingForReply:
                return "Waiting for reply"
            case .inProgress:
                return "In progress"
            case .completed:
                return "Completed"
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
}

private final class ShareLocalStore {
    private let defaults = UserDefaults.standard
    private let activitiesKey = "momenta.share.local-activities"

    func loadActivities() -> [ShareActivityItem] {
        guard let data = defaults.data(forKey: activitiesKey),
              let items = try? JSONDecoder().decode([ShareActivityItem].self, from: data) else {
            return []
        }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    func append(_ item: ShareActivityItem) {
        var items = loadActivities()
        items.removeAll { $0.musicId == item.musicId && $0.mode == item.mode && $0.recipientName == item.recipientName }
        items.insert(item, at: 0)
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: activitiesKey)
        }
    }
}

@MainActor
private final class ShareComposerViewModel: ObservableObject {
    let context: ShareComposerSheetContext

    @Published var prompt: String = ""
    @Published var selectedImage: UIImage?
    @Published var language: String = "en"
    @Published var instrumentalOnly: Bool = false
    @Published var pipeline: ShareComposerPipeline = .light
    @Published var isGenerating = false
    @Published var generationProgress = "Preparing..."
    @Published var errorMessage: String?
    @Published var showImagePicker = false
    @Published var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary

    private let photoManager = Photo2MusicManager.createDefault()
    private let memoryManager = Memory2MusicManager.createDefault()
    private let extendManager = CocreateExtendManager()

    init(context: ShareComposerSheetContext) {
        self.context = context

        if case .continueSession(let item) = context {
            prompt = item.session?.profileA.prompt ?? ""
            language = item.session?.profileA.language ?? "en"
            instrumentalOnly = item.session?.profileA.instrumental ?? false

            if item.song.source == "memory" || item.session?.profileA.locationName != nil || item.session?.profileA.weather != nil {
                pipeline = .memories
            }
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
            return "Generate Song"
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

    func generate() async -> GeneratedMusic? {
        isGenerating = true
        generationProgress = "Preparing..."
        defer { isGenerating = false }

        do {
            switch context {
            case .createNew:
                return try await generateNewSong()
            case .continueSession(let item):
                return try await extendManager.continueSession(
                    item: item,
                    userPrompt: prompt,
                    selectedImage: selectedImage,
                    language: language,
                    instrumentalOnly: instrumentalOnly,
                    pipeline: pipeline,
                    onProgress: { [weak self] progress in
                        Task { @MainActor in self?.generationProgress = progress }
                    }
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func generateNewSong() async throws -> GeneratedMusic {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty || selectedImage != nil else {
            throw ShareComposerError.missingInput
        }

        switch pipeline {
        case .light:
            let parameters = MusicParameters(
                style: nil,
                instrument: nil,
                hasVocals: !instrumentalOnly,
                language: language,
                useAIRecommendation: true
            )
            return try await photoManager.generate(
                userInput: trimmedPrompt,
                selectedImage: selectedImage,
                parameters: parameters,
                onProgress: { [weak self] progress in
                    Task { @MainActor in self?.generationProgress = progress }
                }
            )

        case .memories:
            let context = MemoryMusicContext(
                photo: selectedImage.flatMap { ImageUtility.toBase64(image: $0) },
                story: trimmedPrompt.isEmpty ? nil : trimmedPrompt,
                language: language,
                instrumentalOnly: instrumentalOnly,
                heartRate: nil,
                hrv: nil,
                healthHints: nil,
                suggestedBPM: nil,
                localTime: nil,
                locationName: nil,
                weather: nil,
                temperature: nil
            )
            return try await memoryManager.generate(
                context: context,
                onProgress: { [weak self] progress in
                    Task { @MainActor in self?.generationProgress = progress }
                }
            )
        }
    }

    private func formatContinueAt(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remaining = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remaining)
    }
}

private enum ShareComposerPipeline: String, CaseIterable {
    case light
    case memories

    var title: String {
        switch self {
        case .light:
            return "Light"
        case .memories:
            return "Memories"
        }
    }
}

private struct ShareComposerSheet: View {
    let context: ShareComposerSheetContext
    let onGenerated: (GeneratedMusic) -> Void
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ShareComposerViewModel

    init(
        context: ShareComposerSheetContext,
        onGenerated: @escaping (GeneratedMusic) -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.context = context
        self.onGenerated = onGenerated
        self.onFinished = onFinished
        _viewModel = StateObject(wrappedValue: ShareComposerViewModel(context: context))
    }

    var body: some View {
        NavigationStack {
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
                        Text("Pipeline")
                            .font(.system(size: 15, weight: .semibold))
                        if case .createNew = context {
                            Picker("", selection: $viewModel.pipeline) {
                                ForEach(ShareComposerPipeline.allCases, id: \.self) { pipeline in
                                    Text(pipeline.title).tag(pipeline)
                                }
                            }
                            .pickerStyle(.segmented)
                        } else {
                            Text(viewModel.pipeline.title)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
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
                        Task {
                            if let music = await viewModel.generate() {
                                onGenerated(music)
                                onFinished()
                                dismiss()
                            }
                        }
                    } label: {
                        Group {
                            if viewModel.isGenerating {
                                HStack(spacing: 10) {
                                    ProgressView()
                                        .tint(.white)
                                    Text(viewModel.generationProgress)
                                }
                            } else {
                                Text(viewModel.buttonTitle)
                            }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color(uiColor: .systemIndigo), in: Capsule(style: .continuous))
                    }
                    .buttonStyle(SharePressStyle())
                    .disabled(viewModel.isGenerating)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
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
}

private final class CocreateExtendManager {
    private let llmService = OpenAILyricsService(
        apiKey: APIConfiguration.openAIAPIKey,
        baseURL: APIConfiguration.openAIBaseURL
    )
    private let sunoService = SunoDirectService()
    private let musicDb = MusicDatabaseService.shared
    private let cocreateService = CocreateService.shared

    @MainActor
    func continueSession(
        item: ShareInboxItem,
        userPrompt: String,
        selectedImage: UIImage?,
        language: String,
        instrumentalOnly: Bool,
        pipeline: ShareComposerPipeline,
        onProgress: (String) -> Void
    ) async throws -> GeneratedMusic {
        guard let session = item.session else {
            throw ShareComposerError.invalidContinuation
        }

        let audioId = session.sunoAudioId ?? item.song.sunoAudioId
        guard let audioId, !audioId.isEmpty else {
            throw ShareComposerError.missingSourceAudio
        }

        onProgress("Understanding the handoff...")
        let continuation = try await generateContinuationPackage(
            item: item,
            userPrompt: userPrompt,
            selectedImage: selectedImage,
            language: language,
            instrumentalOnly: instrumentalOnly,
            pipeline: pipeline
        )

        onProgress("Starting the co-create extension...")
        let request = MusicExtendRequest(
            defaultParamFlag: false,
            audioId: audioId,
            model: MusicGenerationRequest.SunoModel(rawValue: session.model) ?? .v5,
            callBackUrl: APIConfiguration.sunoCallbackURL,
            prompt: instrumentalOnly ? nil : continuation.prompt,
            style: continuation.style,
            title: continuation.title,
            continueAt: session.continueAtSec,
            negativeTags: nil,
            vocalGender: continuation.vocalGender,
            styleWeight: nil,
            weirdnessConstraint: nil,
            audioWeight: nil
        )

        let taskId = try await sunoService.extendMusic(request: request)

        guard let userId = await SupabaseService.shared.getCurrentUserId() else {
            throw ShareComposerError.missingUser
        }

        try await musicDb.createInitialRecord(
            taskId: taskId,
            prompt: request.prompt ?? userPrompt.nilIfBlank ?? item.song.prompt,
            style: request.style ?? item.song.style,
            userId: userId,
            source: "cocreate",
            continueAtSec: session.continueAtSec,
            parentAudioId: audioId,
            cocreateSessionId: session.id
        )

        let profileB = CocreateProfileSnapshot(
            language: language,
            instrumental: instrumentalOnly,
            style: request.style,
            title: request.title,
            prompt: request.prompt ?? userPrompt.nilIfBlank,
            bpm: nil,
            vocalGender: request.vocalGender?.rawValue,
            locationName: nil,
            weather: nil,
            healthQuadrant: pipeline == .memories ? "memory" : "light"
        )

        try await cocreateService.updateSessionForExtend(
            sessionId: session.id,
            extendTaskId: taskId,
            profileB: profileB
        )

        onProgress("Finishing the song...")
        let completed = try await sunoService.waitForCompletion(taskId: taskId)
        await musicDb.syncCompletedMusic(completed)
        try await cocreateService.markCompleted(sessionId: session.id)

        if let synced = try await musicDb.fetchMusicRecord(taskId: taskId) {
            return synced
        }

        return GeneratedMusic(
            id: completed.id,
            title: completed.title,
            style: completed.style,
            prompt: completed.prompt,
            audioURL: completed.audioURL,
            imageURL: completed.imageURL,
            sunoAudioId: completed.sunoAudioId,
            status: completed.status,
            createdAt: completed.createdAt,
            source: "cocreate",
            ownerId: userId,
            duration: completed.duration,
            continueAtSec: session.continueAtSec
        )
    }

    private func generateContinuationPackage(
        item: ShareInboxItem,
        userPrompt: String,
        selectedImage: UIImage?,
        language: String,
        instrumentalOnly: Bool,
        pipeline: ShareComposerPipeline
    ) async throws -> (title: String?, style: String?, prompt: String?, vocalGender: MusicGenerationRequest.VocalGender?) {
        let session = item.session
        let continuationPrompt = buildContinuationPrompt(
            item: item,
            userPrompt: userPrompt,
            language: language,
            instrumentalOnly: instrumentalOnly,
            pipeline: pipeline
        )

        let response = try await llmService.generateLyrics(
            request: LyricsGenerationRequest(
                photo: selectedImage.flatMap { ImageUtility.toBase64(image: $0) },
                photoPresent: selectedImage != nil,
                storyShare: userPrompt,
                instrumentalOnly: instrumentalOnly,
                language: language,
                rawPrompt: continuationPrompt
            )
        )

        let baseStyle = session?.profileA.style ?? item.song.style
        let mergedStyle = [baseStyle.nilIfBlank, response.style.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: ", ")
            .nilIfBlank

        let title = item.song.title.isEmpty ? response.title : item.song.title
        let prompt = instrumentalOnly ? nil : (response.prompt?.nilIfBlank ?? userPrompt.nilIfBlank)
        let vocalGender = extractVocalGender(from: mergedStyle ?? "")

        return (title: title, style: mergedStyle, prompt: prompt, vocalGender: vocalGender)
    }

    private func buildContinuationPrompt(
        item: ShareInboxItem,
        userPrompt: String,
        language: String,
        instrumentalOnly: Bool,
        pipeline: ShareComposerPipeline
    ) -> String {
        let pipelineHint = pipeline == .memories
            ? "Lean into memory, intimacy, and lived emotional detail."
            : "Keep the continuation immediate, luminous, and forward-moving."
        let continuationHint = item.session.map {
            "Continue after \($0.continueAtSec) seconds."
        } ?? "Continue the song naturally from its current handoff."
        let userNote = userPrompt.nilIfBlank ?? "No extra collaborator note was provided."

        return """
        You are continuing a collaborative song for a music app.

        Original title: \(item.song.title.isEmpty ? "Untitled Song" : item.song.title)
        Original style: \(item.song.style)
        Original prompt or lyrics context:
        \(item.song.prompt.nilIfBlank ?? "No original prompt stored.")

        Handoff guidance:
        - \(continuationHint)
        - Collaborator note: \(userNote)
        - Language: \(language)
        - Instrumental only: \(instrumentalOnly ? "yes" : "no")
        - Direction: \(pipelineHint)

        Output requirements:
        - Return ONLY valid JSON in this exact format:
          {
            "title": "string",
            "style": "string",
            "prompt": "string"
          }
        - Preserve continuity with the original track.
        - Do not rewrite the opening; generate only the continuation direction.
        - If instrumental only, set prompt to an empty string.
        - Keep the existing title unless a small refinement is clearly better.
        """
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
    case invalidContinuation
    case missingSourceAudio
    case missingUser

    var errorDescription: String? {
        switch self {
        case .missingInput:
            return "Add a prompt or an image before generating."
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
