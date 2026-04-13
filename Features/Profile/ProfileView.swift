//
//  ProfileView.swift
//  MOMENTA
//
//  深色资料档案页：黑玻璃身份卡、原生筛选，以及按 Today / This Week /
//  This Month / This Year 分组、再按具体日期合并的歌曲归档列表。
//

import SwiftUI
import UIKit

struct ProfileView: View {
    fileprivate enum ShareDirectionFilter: String, CaseIterable, Identifiable {
        case received
        case sent

        var id: String { rawValue }

        var title: String {
            switch self {
            case .received:
                return "Sent to you"
            case .sent:
                return "Sent by you"
            }
        }
    }

    @ObservedObject var deepLinkRouter: DeepLinkRouter
    @ObservedObject var viewModel: LightViewModel
    @ObservedObject var authViewModel: AuthViewModel
    @ObservedObject var profileViewModel: ProfileViewModel

    @Environment(PlayerManager.self) private var playerManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var showSettings = false
    @State private var showFriendsSheet = false
    @State private var showAvatarOptions = false
    @State private var showAvatarPicker = false
    @State private var avatarPickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var pendingAvatarImage: UIImage?
    @State private var presentedFilterSheet: ProfileFilterSheet?
    @State private var archiveLayoutMode: ProfileArchiveLayoutMode = .list
    @State private var selectedPipeline: ProfilePipelineFilter? = .all
    @State private var selectedShareDirection: ShareDirectionFilter = .received
    @State private var selectedGenre: String?
    @State private var pendingDeletionTarget: ProfileDeleteTarget?
    @State private var collapsedTimelineSections: Set<String> = []

    private let calendar = Calendar.current
    private let profilePrototypeSize = CGSize(width: 402, height: 874)
    private let profilePlayerCanvasSize = CGSize(width: 420, height: 912)

    private var theme: ProfileArchiveTheme { ProfileArchiveTheme(colorScheme: colorScheme) }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("PROFILE")
                                .font(.system(size: 20, weight: .regular, design: .default).width(.expanded))
                                .foregroundStyle(theme.primaryText)
                                .kerning(0)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Spacer()
                            profileTopSettingsButton
                        }
                        .frame(width: geometry.size.width * (375 / profilePlayerCanvasSize.width))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, -8)

                        profileIdentityCard(viewportWidth: geometry.size.width)
                        filterControls
                        archiveSectionsView(viewportWidth: geometry.size.width)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, geometry.safeAreaInsets.top + 10)
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 108)
                    .frame(maxWidth: 430)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(theme.pageBackground)
                .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                SettingsView(authViewModel: authViewModel, profileViewModel: profileViewModel)
            }
            .sheet(isPresented: $showFriendsSheet) {
                FriendsSheet(
                    prefilledFriendCode: deepLinkRouter.pendingFriendCode,
                    onConsumePrefilledCode: { deepLinkRouter.clearPendingFriendCode() }
                )
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
            .sheet(item: $presentedFilterSheet) { sheet in
                switch sheet {
                case .pipeline:
                    MemoryGenreSheet(
                        genres: ProfilePipelineFilter.allCases.map(\.title),
                        selectedGenre: Binding(
                            get: { selectedPipeline?.title },
                            set: { newValue in
                                selectedPipeline = ProfilePipelineFilter.allCases.first(where: { $0.title == newValue })
                            }
                        )
                    )
                case .genre:
                    MemoryGenreSheet(
                        genres: availableGenres,
                        selectedGenre: $selectedGenre
                    )
                }
            }
            .alert(
                "Are you sure you want to delete?",
                isPresented: Binding(
                    get: { pendingDeletionTarget != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingDeletionTarget = nil
                        }
                    }
                ),
                presenting: pendingDeletionTarget
            ) { target in
                Button("Delete", role: .destructive) {
                    Task {
                        await profileViewModel.deleteSong(
                            musicId: target.song.id,
                            playlistType: target.playlistType
                        )
                        pendingDeletionTarget = nil
                    }
                }

                Button("Cancel", role: .cancel) {
                    pendingDeletionTarget = nil
                }
            }
        }
        .task {
            await profileViewModel.load()
            handlePendingFriendCodeIfNeeded()
        }
        .onChange(of: pendingAvatarImage) { _, image in
            guard let image else { return }
            profileViewModel.updateProfilePhoto(with: image)
        }
        .onChange(of: deepLinkRouter.pendingFriendCode) { _, _ in
            handlePendingFriendCodeIfNeeded()
        }
    }

    private func handlePendingFriendCodeIfNeeded() {
        guard deepLinkRouter.pendingFriendCode?.isEmpty == false else { return }
        showFriendsSheet = true
    }

    private func profileIdentityCard(viewportWidth: CGFloat) -> some View {
        let cardWidth = viewportWidth * (375 / profilePlayerCanvasSize.width)
        let cardHeight = cardWidth * (234 / 375)
        let cardCornerRadius: CGFloat = 24

        return Group {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 0) {
                    profileIdentityCardContent(
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        cardCornerRadius: cardCornerRadius
                    )
                    .frame(width: cardWidth, height: cardHeight)
                    .glassEffect(.regular, in: .rect(cornerRadius: cardCornerRadius))
                }
            } else {
                profileIdentityCardContent(
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    cardCornerRadius: cardCornerRadius
                )
                .frame(width: cardWidth, height: cardHeight)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .stroke(
                            colorScheme == .dark
                            ? Color.white.opacity(0.10)
                            : Color.white.opacity(0.65),
                            lineWidth: 0.8
                        )
                }
            }
        }
        .shadow(color: Color.black.opacity(0.035), radius: 22, x: 0, y: 10)
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: cardHeight)
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ProfileArchiveLayoutButton(layoutMode: $archiveLayoutMode)

                ProfileArchiveFilterChip(
                    title: selectedGenre ?? "Style",
                    action: { presentedFilterSheet = .genre }
                )

                ProfileArchiveFilterChip(
                    title: selectedPipeline?.title ?? "All",
                    action: { presentedFilterSheet = .pipeline }
                )
            }

            if selectedPipeline == .share {
                ProfileShareDirectionControl(selection: $selectedShareDirection)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func archiveSectionsView(viewportWidth: CGFloat) -> some View {
        let archiveBlockWidth = viewportWidth * (375 / profilePlayerCanvasSize.width)

        if archiveSections.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No songs yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                Text("Songs you generate will be grouped here by time.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.top, 14)
        } else {
                    VStack(alignment: .leading, spacing: 28) {
                ForEach(archiveSections) { section in
                    let isExpanded = !collapsedTimelineSections.contains(section.id)

                    VStack(alignment: .leading, spacing: 16) {
                        ProfileSectionHeader(
                            title: section.title,
                            isExpanded: isExpanded,
                            action: { toggleTimelineSection(section.id) }
                        )

                        ProfileCollapsibleSectionContent(isExpanded: isExpanded) {
                            Group {
                                if archiveLayoutMode == .list {
                                    ProfileSectionSongBlock(
                                        songs: section.songs,
                                        favoriteIds: profileViewModel.favoriteIds,
                                        onPlay: { handleSongTap($0) },
                                        onFavorite: { toggleFavorite($0) },
                                        onDelete: { promptDelete($0) },
                                        onShare: { shareSong($0) },
                                        locationText: { locationText(for: $0) }
                                    )
                                    .frame(width: archiveBlockWidth)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                } else {
                                    ProfileSectionSongGrid(
                                        songs: section.songs,
                                        blockWidth: archiveBlockWidth,
                                        onPlay: { handleSongTap($0) }
                                    )
                                    .frame(width: archiveBlockWidth)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var mergedSongs: [GeneratedMusic] {
        var seen = Set<String>()
        return (profileViewModel.mineSongs + profileViewModel.cocreateSongs + profileViewModel.sharedSongs)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredSongs: [GeneratedMusic] {
        timelineEligibleSongs
            .filter(matchesPipeline(_:))
            .filter { song in
                guard let selectedGenre else { return true }
                return genreTag(for: song) == selectedGenre
            }
    }

    private var availableGenres: [String] {
        Array(Set(timelineEligibleSongs.filter(matchesPipeline(_:)).map(genreTag(for:))))
            .sorted()
    }

    private var timelineEligibleSongs: [GeneratedMusic] {
        mergedSongs.filter { song in
            guard song.imageURL != nil else { return false }
            return song.createdAt >= timelineCutoffDate
        }
    }

    private var timelineCutoffDate: Date {
        let components = DateComponents(year: 2026, month: 3, day: 28)
        let cutoff = calendar.date(from: components) ?? .distantPast
        return calendar.startOfDay(for: cutoff)
    }

    private var archiveSections: [ProfileArchiveSection] {
        let songs = filteredSongs

        let todaySongs = songs.filter { calendar.isDateInToday($0.createdAt) }
        let thisWeekSongs = songs.filter {
            !calendar.isDateInToday($0.createdAt) &&
            calendar.isDate($0.createdAt, equalTo: Date(), toGranularity: .weekOfYear)
        }
        let thisMonthSongs = songs.filter {
            !calendar.isDateInToday($0.createdAt) &&
            !calendar.isDate($0.createdAt, equalTo: Date(), toGranularity: .weekOfYear) &&
            calendar.isDate($0.createdAt, equalTo: Date(), toGranularity: .month)
        }
        let thisYearSongs = songs.filter {
            !calendar.isDate($0.createdAt, equalTo: Date(), toGranularity: .month) &&
            calendar.isDate($0.createdAt, equalTo: Date(), toGranularity: .year)
        }

        let sections = [
            ProfileArchiveSection(title: "Today", songs: todaySongs),
            ProfileArchiveSection(title: "This week", songs: thisWeekSongs),
            ProfileArchiveSection(title: "This month", songs: thisMonthSongs),
            ProfileArchiveSection(title: "This year", songs: thisYearSongs)
        ]

        return sections.filter { !$0.songs.isEmpty }
    }

    private func matchesPipeline(_ song: GeneratedMusic) -> Bool {
        guard let selectedPipeline else { return true }

        let sharedIds = Set(profileViewModel.sharedSongs.map(\.id))
        let sentSharedIds = profileViewModel.sentSharedMusicIds
        let cocreateIds = Set(profileViewModel.cocreateSongs.map(\.id))
        let favoriteIds = profileViewModel.favoriteIds

        switch selectedPipeline {
        case .all:
            return true
        case .mine:
            return !sharedIds.contains(song.id) && !cocreateIds.contains(song.id)
        case .cocreate:
            return cocreateIds.contains(song.id)
        case .share:
            switch selectedShareDirection {
            case .received:
                return sharedIds.contains(song.id)
            case .sent:
                return sentSharedIds.contains(song.id)
            }
        case .favorites:
            return favoriteIds.contains(song.id)
        }
    }

    private func sourceTag(for song: GeneratedMusic) -> String {
        let sharedIds = Set(profileViewModel.sharedSongs.map(\.id))
        let cocreateIds = Set(profileViewModel.cocreateSongs.map(\.id))

        if sharedIds.contains(song.id) { return "Share" }
        if cocreateIds.contains(song.id) { return "Co-Create" }
        return "Mine"
    }

    private func genreTag(for song: GeneratedMusic) -> String {
        let candidates = song.style
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for candidate in candidates {
            let lowercased = candidate.lowercased()
            if candidate.uppercased().contains("BPM") { continue }
            if lowercased.contains("vocal") { continue }
            if lowercased.contains("instrumental") { continue }
            return candidate
        }

        return "Memory"
    }

    private func locationText(for song: GeneratedMusic) -> String {
        let trimmed = MemorySongMetadataStore.shared.metadata(for: song)
            .locationName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed != MemorySongMetadata.unknownLocationLabel else {
            return ""
        }
        return trimmed
    }

    private func playlistType(for song: GeneratedMusic) -> PlaylistType {
        let sharedIds = Set(profileViewModel.sharedSongs.map(\.id))
        let cocreateIds = Set(profileViewModel.cocreateSongs.map(\.id))

        if sharedIds.contains(song.id) { return .shared }
        if cocreateIds.contains(song.id) { return .cocreate }
        return .mine
    }

    private func toggleFavorite(_ song: GeneratedMusic) {
        Task {
            await profileViewModel.toggleFavorite(musicId: song.id, ownerId: song.ownerId)
        }
    }

    private func promptDelete(_ song: GeneratedMusic) {
        pendingDeletionTarget = ProfileDeleteTarget(song: song, playlistType: playlistType(for: song))
    }

    private func shareSong(_ song: GeneratedMusic) {
        // Placeholder: UI only for now.
    }

    private func toggleTimelineSection(_ sectionID: String) {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            if collapsedTimelineSections.contains(sectionID) {
                collapsedTimelineSections.remove(sectionID)
            } else {
                collapsedTimelineSections.insert(sectionID)
            }
        }
    }

    private func handleSongTap(_ song: GeneratedMusic) {
        playerManager.currentMusic = song
        playerManager.lyrics = []
        playerManager.currentLineIndex = 0
        playerManager.showLyrics = false
        playerManager.lyricsControlsVisible = true
        playerManager.play()
    }

    private func profileIdentityCardContent(
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        cardCornerRadius: CGFloat
    ) -> some View {
        let horizontalInset = cardWidth * (24 / 375)
        let topInset = cardHeight * (24 / 234)
        let bottomInset = cardHeight * (26 / 234)
        let avatarSize = cardWidth * (104 / 375)
        let textWidth = cardWidth * (210 / 375)

        return ZStack {
            avatarView(size: avatarSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, horizontalInset)
                .padding(.top, topInset)

            VStack(alignment: .trailing, spacing: cardHeight * (7 / 234)) {
                Text(identityCardNameText)
                    .font(.system(
                        size: cardWidth * (24 / 375),
                        weight: .regular,
                        design: .default
                    ).width(.expanded))
                    .foregroundStyle(identityNameColor)
                    .kerning(0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(identityCardLocationText)
                    .font(.system(
                        size: cardWidth * (15 / 375),
                        weight: .regular,
                        design: .default
                    ).width(.expanded))
                    .foregroundStyle(identityLocationColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .multilineTextAlignment(.trailing)
            .frame(width: textWidth, alignment: .trailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, horizontalInset)
            .padding(.bottom, bottomInset)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
    }

    private var identityDisplayName: String {
        let saved = UserDefaults.standard.string(forKey: ProfileIdentityStore.displayNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? "Name" : profileViewModel.displayName
    }

    private var identityCardNameText: String {
        identityDisplayName.uppercased()
    }

    private var identityLocation: String {
        profileViewModel.displayLocation
    }

    private var identityCardLocationText: String {
        identityLocation.uppercased()
    }

    private var identityNameColor: Color {
        identityDisplayName == "Name"
        ? theme.primaryText.opacity(0.42)
        : theme.primaryText
    }

    private var identityLocationColor: Color {
        identityLocation == "Address"
        ? theme.primaryText.opacity(0.34)
        : theme.primaryText.opacity(0.72)
    }

    private func scaledX(_ width: CGFloat, _ value: CGFloat) -> CGFloat {
        width * (value / profilePrototypeSize.width)
    }

    private func avatarView(size: CGFloat) -> some View {
        Button {
            showAvatarOptions = true
        } label: {
            Group {
                if let avatarImage = profileViewModel.profileAvatarImage {
                    Image(uiImage: avatarImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Circle()
                            .fill(
                                colorScheme == .dark
                                ? Color.white.opacity(0.14)
                                : Color.white.opacity(0.72)
                            )

                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.32, weight: .medium))
                            .foregroundStyle(theme.secondaryText.opacity(0.82))
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(
                        colorScheme == .dark
                        ? Color.white.opacity(0.18)
                        : Color.white.opacity(0.8),
                        lineWidth: 2
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change profile photo")
    }

    private func settingsButton(size: CGFloat) -> some View {
        Button { showSettings = true } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(theme.secondaryText.opacity(0.88))
                .frame(width: size + 10, height: size + 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile settings")
    }

    private var profileTopSettingsButton: some View {
        HStack(spacing: 0) {
            Button {
                showFriendsSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.secondaryText.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add friend")

            Rectangle()
                .fill(theme.chipStroke.opacity(0.9))
                .frame(width: 0.8)
                .padding(.vertical, 9)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(theme.secondaryText.opacity(0.88))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile settings")
        }
        .frame(width: 92, height: 38)
        .background(theme.chipFill, in: Capsule(style: .continuous))
        .modifier(ProfileGlassChrome(cornerRadius: 19))
    }
}

private struct ProfileArchiveTheme {
    let colorScheme: ColorScheme

    var pageBackground: Color { Color(uiColor: .systemGray6) }
    var groupSurface: Color { Color(uiColor: .systemBackground) }
    var groupBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.05)
    }
    var primaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.95) : Color.black.opacity(0.96)
    }
    var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.56)
    }
    var chipFill: Color {
        colorScheme == .dark ? Color.black.opacity(0.32) : Color.white.opacity(0.82)
    }
    var chipText: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88)
    }
    var chipStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    var glassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.08)
    }
}

private enum ProfileArchiveLayoutMode {
    case list
    case grid
}

private struct ProfileGlassChrome: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ProfileArchiveTheme { ProfileArchiveTheme(colorScheme: colorScheme) }

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(
                    .regular.tint(theme.glassTint).interactive(),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(theme.chipStroke, lineWidth: 0.8)
                }
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(theme.chipStroke, lineWidth: 0.8)
                }
        }
    }
}

private struct ProfileArchiveBlockChrome: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ProfileArchiveTheme { ProfileArchiveTheme(colorScheme: colorScheme) }

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(
                    .regular.tint(theme.glassTint),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(theme.groupBorder, lineWidth: 0.8)
                }
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(theme.groupBorder, lineWidth: 0.8)
                }
        }
    }
}

private struct ProfileArchiveLayoutButton: View {
    @Binding var layoutMode: ProfileArchiveLayoutMode
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ProfileArchiveTheme { ProfileArchiveTheme(colorScheme: colorScheme) }

    var body: some View {
        Button {
            layoutMode = layoutMode == .list ? .grid : .list
        } label: {
            Image(systemName: "music.note.list")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme.chipText)
                .frame(width: 48, height: 46)
                .background(theme.chipFill, in: Capsule(style: .continuous))
                .modifier(ProfileGlassChrome(cornerRadius: 23))
        }
        .buttonStyle(ProfilePressStyle())
        .accessibilityLabel("Switch song layout")
    }
}

private struct ProfileArchiveFilterChip: View {
    let title: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ProfileArchiveTheme { ProfileArchiveTheme(colorScheme: colorScheme) }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .regular))
                .lineLimit(1)
                .foregroundStyle(theme.chipText)
                .frame(width: 116, height: 46)
                .background(theme.chipFill, in: Capsule(style: .continuous))
                .modifier(ProfileGlassChrome(cornerRadius: 23))
        }
        .buttonStyle(ProfilePressStyle())
    }
}

private struct ProfileShareDirectionControl: View {
    @Binding var selection: ProfileView.ShareDirectionFilter

    @Environment(\.colorScheme) private var colorScheme
    private var theme: ProfileArchiveTheme { ProfileArchiveTheme(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ProfileView.ShareDirectionFilter.allCases) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selection = option
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selection == option ? theme.primaryText : theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selection == option ? theme.groupSurface : .clear)
                        )
                        .overlay {
                            if selection == option {
                                Capsule(style: .continuous)
                                    .stroke(theme.groupBorder, lineWidth: 0.8)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(theme.chipFill, in: Capsule(style: .continuous))
        .modifier(ProfileGlassChrome(cornerRadius: 22))
    }
}

private struct ProfileSectionHeader: View {
    let title: String
    let isExpanded: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ProfileArchiveTheme { ProfileArchiveTheme(colorScheme: colorScheme) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.primaryText)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.24, extraBounce: 0), value: isExpanded)
        .accessibilityLabel(title)
    }
}

private struct ProfileCollapsibleSectionContent<Content: View>: View {
    let isExpanded: Bool
    @ViewBuilder let content: () -> Content

    @State private var measuredHeight: CGFloat = 0

    private var visibleHeight: CGFloat? {
        if isExpanded {
            return measuredHeight > 0 ? measuredHeight : nil
        }
        return 0
    }

    var body: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: ProfileSectionContentHeightKey.self,
                            value: proxy.size.height
                        )
                }
            }
            .onPreferenceChange(ProfileSectionContentHeightKey.self) { height in
                guard height > 0 else { return }
                measuredHeight = height
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: visibleHeight, alignment: .top)
            .clipped()
            .animation(.snappy(duration: 0.24, extraBounce: 0), value: isExpanded)
    }
}

private struct ProfileSectionContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ProfileSectionSongBlock: View {
    let songs: [GeneratedMusic]
    let favoriteIds: Set<String>
    let onPlay: (GeneratedMusic) -> Void
    let onFavorite: (GeneratedMusic) -> Void
    let onDelete: (GeneratedMusic) -> Void
    let onShare: (GeneratedMusic) -> Void
    let locationText: (GeneratedMusic) -> String

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ProfileArchiveTheme { ProfileArchiveTheme(colorScheme: colorScheme) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        VStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                ProfileGroupedSongRow(
                    song: song,
                    isFavorite: favoriteIds.contains(song.id),
                    locationText: locationText(song),
                    onPlay: { onPlay(song) },
                    onFavorite: { onFavorite(song) },
                    onDelete: { onDelete(song) },
                    onShare: { onShare(song) }
                )

                if index != songs.count - 1 {
                    Divider()
                        .overlay(theme.groupBorder.opacity(0.9))
                        .padding(.leading, 86)
                        .padding(.trailing, 16)
                }
            }
        }
            .background(theme.groupSurface.opacity(0.001), in: shape)
            .modifier(ProfileArchiveBlockChrome(cornerRadius: 24))
            .clipShape(shape)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.05), radius: 12, y: 6)
    }
}

private struct ProfileGroupedSongRow: View {
    let song: GeneratedMusic
    let isFavorite: Bool
    let locationText: String
    let onPlay: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ProfileArchiveTheme { ProfileArchiveTheme(colorScheme: colorScheme) }

    var body: some View {
        let artworkSize: CGFloat = 58

        HStack(alignment: .top, spacing: 14) {
            Button(action: onPlay) {
                HStack(alignment: .top, spacing: 14) {
                    ProfileGroupedSongArtwork(song: song)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(song.title.isEmpty ? "Untitled Memory" : song.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        VStack(alignment: .leading, spacing: 1) {
                            if !locationText.isEmpty {
                                Text(locationText)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(theme.secondaryText)
                                    .lineLimit(1)
                            }

                            Text(profileSongTimeLine(song.createdAt))
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: artworkSize, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ProfilePressStyle())

            VStack(alignment: .trailing, spacing: 0) {
                ProfileGroupedSongMenu(
                    song: song,
                    isFavorite: isFavorite,
                    onFavorite: onFavorite,
                    onDelete: onDelete,
                    onShare: onShare
                )

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                            .frame(width: 16, height: 16)
                    }

                    Image(systemName: pipelineSymbolName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.secondaryText.opacity(0.92))
                        .frame(width: 18, height: 18)
                }
            }
            .frame(height: artworkSize)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private func profileSongTimeLine(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d · h:mm a"
        return formatter.string(from: date)
    }

    private var pipelineSymbolName: String {
        if song.isCocreate {
            return "person.2.fill"
        }
        if song.source == "memory" {
            return "photo.on.rectangle.angled"
        }
        return "rays"
    }
}

private struct ProfileSectionSongGrid: View {
    let songs: [GeneratedMusic]
    let blockWidth: CGFloat
    let onPlay: (GeneratedMusic) -> Void

    private let cardSpacing: CGFloat = 14

    private var cardWidth: CGFloat {
        ((blockWidth - cardSpacing) / 2).rounded(.down)
    }

    private var columns: [GridItem] {
        [
            GridItem(.fixed(cardWidth), spacing: cardSpacing, alignment: .top),
            GridItem(.fixed(cardWidth), spacing: 0, alignment: .top)
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: cardSpacing) {
            ForEach(songs, id: \.id) { song in
                ProfileSongGridCard(
                    song: song,
                    cardWidth: cardWidth,
                    onPlay: { onPlay(song) }
                )
            }
        }
        .frame(width: blockWidth, alignment: .leading)
    }
}

private struct ProfileSongGridCard: View {
    let song: GeneratedMusic
    let cardWidth: CGFloat
    let onPlay: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ProfileArchiveTheme { ProfileArchiveTheme(colorScheme: colorScheme) }
    private let cornerRadius: CGFloat = 22

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 8) {
                ProfileTimelineArtwork(
                    imageURL: song.imageURL,
                    size: cardWidth,
                    cornerRadius: cornerRadius,
                    noteSize: 22
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title.isEmpty ? "Untitled Memory" : song.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(gridSubtitle(song.createdAt))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
                .padding(.leading, 4)
                .frame(width: cardWidth, alignment: .leading)
            }
            .frame(width: cardWidth, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProfilePressStyle())
    }

    private func gridSubtitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d · h:mm a"
        return formatter.string(from: date)
    }
}

private struct ProfileGroupedSongArtwork: View {
    let song: GeneratedMusic

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ProfileArchiveTheme { ProfileArchiveTheme(colorScheme: colorScheme) }

    var body: some View {
        ProfileTimelineArtwork(
            imageURL: song.imageURL,
            size: 58,
            cornerRadius: 14,
            noteSize: 19,
            strokeColor: theme.groupBorder
        )
    }
}

private struct ProfileTimelineArtwork: View {
    let imageURL: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    let noteSize: CGFloat
    var strokeColor: Color? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        artworkContent
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
    private var artworkContent: some View {
        if let imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    loadingArtwork
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    fallbackArtwork
                @unknown default:
                    fallbackArtwork
                }
            }
        } else {
            fallbackArtwork
        }
    }

    private var loadingArtwork: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                colorScheme == .dark
                ? Color(uiColor: .systemGray5)
                : Color(uiColor: .systemGray4)
            )
            .overlay {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(
                        colorScheme == .dark
                        ? .white.opacity(0.72)
                        : .black.opacity(0.45)
                    )
            }
    }

    private var fallbackArtwork: some View {
        Group {
            if let composeUIImage = fallbackComposeUIImage {
                Image(uiImage: composeUIImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .saturation(1.06)
                    .contrast(1.08)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(uiColor: .systemIndigo), Color(uiColor: .systemPink)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: noteSize, weight: .light))
                            .foregroundStyle(.white.opacity(0.8))
                    }
            }
        }
    }

    private var fallbackComposeUIImage: UIImage? {
        UIImage(named: "compose")
            ?? UIImage(named: "compose.png")
            ?? Bundle.main.url(forResource: "compose", withExtension: "png")
                .flatMap { UIImage(contentsOfFile: $0.path) }
    }
}

private struct ProfileGroupedSongMenu: View {
    let song: GeneratedMusic
    let isFavorite: Bool
    let onFavorite: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ProfileArchiveTheme { ProfileArchiveTheme(colorScheme: colorScheme) }

    var body: some View {
        Menu {
            Button("Share", systemImage: "square.and.arrow.up", action: onShare)
            if song.isWidgetEligible {
                Button("Set for Widget", systemImage: "apps.iphone") {
                    SystemSongSnapshotStore().pin(
                        SystemSongSnapshot.from(song, kind: song.source == "memory" ? .memory : .mine)
                    )
                }
            }
            Button(
                isFavorite ? "Remove Favorite" : "Favorite",
                systemImage: isFavorite ? "heart.slash" : "heart",
                action: onFavorite
            )
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 28, height: 28)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }
}

private struct ProfilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct ProfileArchiveSection: Identifiable {
    var id: String { title }
    let title: String
    let songs: [GeneratedMusic]
}

private struct ProfileDeleteTarget: Identifiable {
    let song: GeneratedMusic
    let playlistType: PlaylistType

    var id: String { song.id }
}

private enum ProfileFilterSheet: Identifiable {
    case pipeline
    case genre

    var id: String {
        switch self {
        case .pipeline: return "pipeline"
        case .genre: return "genre"
        }
    }
}

private enum ProfilePipelineFilter: String, CaseIterable, Identifiable {
    case all
    case mine
    case cocreate
    case share
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .mine: return "Mine"
        case .cocreate: return "Co-create"
        case .share: return "Share"
        case .favorites: return "Favorites"
        }
    }
}
