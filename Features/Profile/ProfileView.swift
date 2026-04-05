//
//  ProfileView.swift
//  MOMENTA
//
//  白底 Profile 首页：个人卡片、原生筛选、按日期分组的歌曲记录。
//

import SwiftUI
import UIKit

struct ProfileView: View {
    @ObservedObject var viewModel: LightViewModel
    @ObservedObject var authViewModel: AuthViewModel
    @ObservedObject var profileViewModel: ProfileViewModel

    @State private var showSettings = false
    @State private var showAvatarOptions = false
    @State private var showAvatarPicker = false
    @State private var avatarPickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var pendingAvatarImage: UIImage?
    @State private var presentedFilterSheet: ProfileFilterSheet?
    @State private var selectedPipeline: ProfilePipelineFilter?
    @State private var selectedGenre: String?
    @State private var shareMode: ProfileShareMode = .share
    @State private var collapsedSongSections: Set<String> = []
    @State private var showQRSheet = false
    @State private var showScanSheet = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        profileIdentityCard
                        filterRow
                        songsSection
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, geometry.safeAreaInsets.top + 20)
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 120)
                    .frame(maxWidth: 430)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(profileBackground)
                .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                SettingsView(authViewModel: authViewModel, profileViewModel: profileViewModel)
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
            .sheet(isPresented: $showQRSheet) {
                FriendQRCodeView(
                    friendCode: profileViewModel.myFriendCode,
                    displayName: profileViewModel.displayName,
                    avatarImage: profileViewModel.profileAvatarImage
                )
            }
            .fullScreenCover(isPresented: $showScanSheet) {
                ScanQRView { code, note in
                    showScanSheet = false
                    Task { await profileViewModel.addFriendByCode(code, note: note) }
                }
            }
            .alert("Friend Request Sent", isPresented: $profileViewModel.showFriendAddedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Request sent to \(profileViewModel.friendAddedName ?? "user")!")
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
        }
        .task { await profileViewModel.load() }
        .onChange(of: pendingAvatarImage) { _, image in
            guard let image else { return }
            profileViewModel.updateProfilePhoto(with: image)
        }
        // Deep link 进来时自动打开好友列表（让 FriendsListView 接管 sheet）
        .onChange(of: profileViewModel.incomingFriendCode) { _, code in
            guard code != nil else { return }
            // 自动导航到好友列表，由 FriendsListView.onChange 弹出 sheet
        }
    }

    private var profileBackground: some View {
        ProfileHeroBackdrop()
    }

    private var profileIdentityCard: some View {
        ProfileSurfaceCard(cornerRadius: 30) {
            VStack(spacing: 18) {
                HStack(alignment: .top) {
                    avatarView
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        friendsListIconButton
                        scanButton
                        settingsButton
                    }
                }

                Spacer(minLength: 0)

                identityInfo
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 252, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: 252, alignment: .topLeading)
    }

    private var filterRow: some View {
        HStack(spacing: 14) {
            Menu {
                ForEach(ProfileShareMode.allCases) { mode in
                    Button {
                        shareMode = mode
                    } label: {
                        if shareMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            } label: {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 46)
                    .background(Color(uiColor: .systemIndigo), in: Capsule(style: .continuous))
            }
            .buttonStyle(ProfilePressStyle())

            ProfileFilterChip(
                title: selectedPipeline?.title ?? "Sources",
                action: { presentedFilterSheet = .pipeline }
            )

            ProfileFilterChip(
                title: selectedGenre ?? "Genres",
                action: { presentedFilterSheet = .genre }
            )
        }
        .padding(.vertical, 2)
    }

    private var songsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(profileSections) { section in
                VStack(alignment: .leading, spacing: 14) {
                    ProfileSectionHeader(
                        title: section.title,
                        isExpanded: !collapsedSongSections.contains(section.title),
                        action: { toggleSongSection(section.title) }
                    )

                    if !collapsedSongSections.contains(section.title) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, song in
                                ProfileSongRow(
                                    song: song,
                                    sourceTag: sourceTag(for: song),
                                    genreTag: genreTag(for: song),
                                    voiceTag: voiceTag(for: song)
                                )

                                if index != section.items.count - 1 {
                                    Divider()
                                        .overlay(Color.black.opacity(0.08))
                                        .padding(.leading, 92)
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
        mergedSongs
            .filter(matchesPipeline(_:))
            .filter { song in
                guard let selectedGenre else { return true }
                return genreTag(for: song) == selectedGenre
            }
    }

    private var availableGenres: [String] {
        Array(Set(mergedSongs.map(genreTag(for:))))
            .sorted()
    }

    private var profileSections: [ProfileSongSection] {
        let songs = filteredSongs
        let today = songs.filter { calendar.isDateInToday($0.createdAt) }
        let thisWeek = songs.filter {
            !calendar.isDateInToday($0.createdAt) &&
            calendar.isDate($0.createdAt, equalTo: Date(), toGranularity: .weekOfYear)
        }
        let thisMonth = songs.filter {
            !calendar.isDateInToday($0.createdAt) &&
            !calendar.isDate($0.createdAt, equalTo: Date(), toGranularity: .weekOfYear) &&
            calendar.isDate($0.createdAt, equalTo: Date(), toGranularity: .month)
        }
        let thisYear = songs.filter {
            !calendar.isDate($0.createdAt, equalTo: Date(), toGranularity: .month) &&
            calendar.isDate($0.createdAt, equalTo: Date(), toGranularity: .year)
        }
        let earlier = songs.filter {
            !calendar.isDate($0.createdAt, equalTo: Date(), toGranularity: .year)
        }

        let sections = [
            ProfileSongSection(title: "Today", items: today),
            ProfileSongSection(title: "This Week", items: thisWeek),
            ProfileSongSection(title: "This Month", items: thisMonth),
            ProfileSongSection(title: "This Year", items: thisYear),
            ProfileSongSection(title: "Earlier", items: earlier)
        ]

        return sections.filter { !$0.items.isEmpty }
    }

    private func matchesPipeline(_ song: GeneratedMusic) -> Bool {
        guard let selectedPipeline else { return true }

        switch selectedPipeline {
        case .memory:
            return song.source == "memory"
        case .light:
            return song.source == nil || song.source == "mine"
        }
    }

    private func isInWeekend(_ date: Date, weekOffset: Int) -> Bool {
        guard let referenceWeek = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: Date()),
              let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceWeek) else {
            return false
        }

        return calendar.isDateInWeekend(date) && weekInterval.contains(date)
    }

    private func sourceTag(for song: GeneratedMusic) -> String {
        let sharedIds = Set(profileViewModel.sharedSongs.map(\.id))
        let cocreateIds = Set(profileViewModel.cocreateSongs.map(\.id))

        if sharedIds.contains(song.id) { return "Shared" }
        if cocreateIds.contains(song.id) { return "Co-Create" }
        if song.source == "memory" { return "Memory" }
        return "Light"
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

    private func voiceTag(for song: GeneratedMusic) -> String {
        let searchable = "\(song.style) \(song.prompt)".lowercased()
        if searchable.contains("instrumental") || searchable.contains("pure music") || searchable.contains("no vocals") {
            return "Instrumental"
        }
        return "Vocal"
    }

    private func toggleSongSection(_ title: String) {
        if collapsedSongSections.contains(title) {
            collapsedSongSections.remove(title)
        } else {
            collapsedSongSections.insert(title)
        }
    }

    private var avatarView: some View {
        Button {
            showAvatarOptions = true
        } label: {
            Group {
                if let avatarImage = profileViewModel.profileAvatarImage {
                    Image(uiImage: avatarImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Circle()
                        .fill(Color.black.opacity(0.06))
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 34, weight: .regular))
                                .foregroundStyle(.black.opacity(0.72))
                        }
                }
            }
            .frame(width: 122, height: 122)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.92), lineWidth: 3))
            .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var settingsButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black.opacity(0.58))
                .frame(width: 48, height: 48)
                .background(Color.black.opacity(0.05), in: Circle())
        }
        .buttonStyle(ProfilePressStyle())
    }

    private var identityInfo: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(profileViewModel.displayBadgeName)
                .font(.systemExpanded(size: 19, weight: .semibold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            Button { showQRSheet = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 11, weight: .medium))
                    Text(profileViewModel.myFriendCode.isEmpty ? "Loading..." : profileViewModel.myFriendCode)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.black.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
    }

    private var scanButton: some View {
        Button { showScanSheet = true } label: {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black.opacity(0.58))
                .frame(width: 48, height: 48)
                .background(Color.black.opacity(0.05), in: Circle())
        }
        .buttonStyle(ProfilePressStyle())
    }

    private var friendsListIconButton: some View {
        NavigationLink {
            FriendsListView(profileViewModel: profileViewModel)
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.58))
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.05), in: Circle())

                if profileViewModel.friendNotificationCount > 0 {
                    Text("\(profileViewModel.friendNotificationCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .padding(.horizontal, 4)
                        .background(Color.red, in: Capsule())
                        .offset(x: 6, y: -4)
                }
            }
        }
        .buttonStyle(ProfilePressStyle())
    }
}

private struct ProfileSurfaceCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            shape
                .fill(Color.white.opacity(0.78))
                .modifier(ProfileGlassBackground(cornerRadius: cornerRadius))

            content
                .clipShape(shape)
        }
        .overlay {
            shape
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(0.08), radius: 22, y: 12)
    }
}

private struct ProfileGlassBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(
                    .regular.tint(Color.white.opacity(0.22)).interactive(),
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

private struct ProfileHeroBackdrop: View {
    private let baseColor = Color(red: 0.99, green: 0.99, blue: 0.995)

    var body: some View {
        GeometryReader { geometry in
            let heroHeight = min(max(geometry.size.height * 0.66, 500), 660)

            ZStack(alignment: .top) {
                baseColor

                Image("desert_background")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width + 140, height: heroHeight + 170)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.08),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.72),
                                .init(color: .white.opacity(0.9), location: 0.84),
                                .init(color: .white.opacity(0.42), location: 0.95),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }

                Image("desert_background")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width + 164, height: heroHeight + 320)
                    .clipped()
                    .blur(radius: 52)
                    .opacity(0.46)
                    .offset(y: heroHeight * 0.38)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(0.28), location: 0.42),
                                .init(color: .white, location: 0.82),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }

                LinearGradient(
                    stops: [
                        .init(color: Color.clear, location: 0),
                        .init(color: baseColor.opacity(0.03), location: 0.64),
                        .init(color: baseColor.opacity(0.34), location: 0.84),
                        .init(color: baseColor, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: heroHeight + 360)
                .frame(maxWidth: .infinity, alignment: .top)

                Circle()
                    .fill(Color.white.opacity(0.62))
                    .frame(width: 260, height: 260)
                    .blur(radius: 80)
                    .offset(x: geometry.size.width * 0.36, y: heroHeight + 54)
            }
            .ignoresSafeArea()
        }
    }
}

private struct ProfileFilterChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.black)
                .frame(width: 116, height: 46)
                .background(Color.white.opacity(0.86), in: Capsule(style: .continuous))
                .modifier(ProfileGlassBackground(cornerRadius: 23))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
        }
        .buttonStyle(ProfilePressStyle())
    }
}

private struct ProfileSongRow: View {
    let song: GeneratedMusic
    let sourceTag: String
    let genreTag: String
    let voiceTag: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ProfileSongArtwork(song: song)

            VStack(alignment: .leading, spacing: 6) {
                Text(song.title.isEmpty ? "Untitled Memory" : song.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ProfileTag(text: sourceTag)
                        ProfileTag(text: genreTag)
                        ProfileTag(text: voiceTag)
                    }
                }
                .scrollDisabled(true)

                Text(profileSongTimeLine(song.createdAt))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(red: 0.47, green: 0.47, blue: 0.49))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 3)
        }
        .padding(.vertical, 12)
    }

    private func profileSongTimeLine(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d · h:mm a"
        return formatter.string(from: date)
    }
}

private struct ProfileSongArtwork: View {
    let song: GeneratedMusic

    var body: some View {
        artwork
            .frame(width: 72, height: 72)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    @ViewBuilder
    private var artwork: some View {
        if let imageURL = song.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
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
                Image(systemName: "music.note")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white.opacity(0.76))
            }
    }
}

private struct ProfileTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.78))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.black.opacity(0.04), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            }
    }
}

private struct ProfileSectionHeader: View {
    let title: String
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.42))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
        }
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

private struct ProfileSongSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [GeneratedMusic]
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
    case memory
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .memory: return "Memory"
        case .light: return "Light"
        }
    }
}

private enum ProfileShareMode: String, CaseIterable, Identifiable {
    case share = "Share"
    case cocreate = "Co-Create"

    var id: String { rawValue }
    var title: String { rawValue }
}
