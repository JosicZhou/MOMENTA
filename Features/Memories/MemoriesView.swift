//
//  MemoriesView.swift
//  MOMENTA
//
//  Memories 主界面：参考演出发现页的轻量白底排版，展示 Collection 与时间分组歌曲列表。
//

import SwiftUI
import UIKit

struct MemoriesView: View {
    @ObservedObject var viewModel: MemoryViewModel
    @ObservedObject var profileViewModel: ProfileViewModel
    let onOpenCoCreation: () -> Void
    @Environment(PlayerManager.self) private var playerManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var presentedFilterSheet: MemoryFilterSheet?
    @State private var isComposerPresented = false
    @State private var selectedLocation: String?
    @State private var selectedGenre: String?
    @State private var selectedDate: Date?
    @State private var selectedDatePreset: MemoryDatePreset?
    @State private var isPaletteExpanded = true
    @State private var collapsedTimelineSections: Set<String> = []
    @State private var pendingDeletionItem: MemoryLibraryItem?

    private let calendar = Calendar.current
    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    theme.backgroundTop,
                    theme.backgroundBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack {
                    LazyVStack(alignment: .leading, spacing: 34) {
                        MemoriesHeader()

                        MemoryTopCreateButtonRow(
                            action: presentComposer
                        )

                        MemoryPaletteSection(
                            items: filteredCollectionItems,
                            favoriteIds: viewModel.favoriteIds,
                            isExpanded: isPaletteExpanded,
                            onToggleExpanded: togglePaletteExpanded,
                            onPlay: handleSongTap(_:),
                            onFavorite: toggleFavorite(_:),
                            onAdd: presentComposer,
                            onOpenCoCreation: onOpenCoCreation
                        )

                        MemoryFilterChipRow(
                            dateLabel: dateChipLabel,
                            genreLabel: genreChipLabel,
                            hasSelectedLocation: selectedLocation != nil,
                            hasSelectedDate: selectedDate != nil || selectedDatePreset != nil,
                            hasSelectedGenre: selectedGenre != nil,
                            onLocationTap: { presentFilterSheet(.location) },
                            onDateTap: { presentFilterSheet(.date) },
                            onGenreTap: { presentFilterSheet(.genre) }
                        )

                        if viewModel.isLoadingLibrary && viewModel.libraryItems.isEmpty {
                            MemoryLoadingSection()
                        } else if timelineSections.isEmpty {
                            MemoryEmptySection(
                                state: emptyState,
                                onCreate: presentComposer
                            )
                        } else {
                            ForEach(timelineSections) { section in
                                MemoryTimelineSectionView(
                                    title: section.title,
                                    items: section.items,
                                    favoriteIds: viewModel.favoriteIds,
                                    isExpanded: !collapsedTimelineSections.contains(section.id),
                                    onToggleExpanded: { toggleTimelineSection(section.id) },
                                    onPlay: handleSongTap(_:),
                                    onFavorite: toggleFavorite(_:),
                                    onDelete: promptDelete(_:)
                                )
                            }
                        }
                    }
                    .frame(maxWidth: 520, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 132)
                .animation(.snappy(duration: 0.28, extraBounce: 0), value: filterAnimationKey)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await viewModel.refreshLibrary()
            }
        }
        .task {
            await initialLoad()
        }
        .animation(.snappy(duration: 0.26, extraBounce: 0), value: presentedFilterSheet?.id ?? "none")
        .sheet(item: $presentedFilterSheet) { sheet in
            switch sheet {
            case .location:
                MemoryLocationSheet(
                    locations: viewModel.availableLocations,
                    currentLocation: viewModel.locationWeather.locationName,
                    selectedLocation: $selectedLocation
                )
            case .date:
                MemoryDateSheet(
                    selectedDate: $selectedDate,
                    selectedPreset: $selectedDatePreset
                )
            case .genre:
                MemoryGenreSheet(
                    genres: viewModel.availableTypes,
                    selectedGenre: $selectedGenre
                )
            }
        }
        .sheet(isPresented: $isComposerPresented) {
            MemoryComposerSheet(viewModel: viewModel, profileViewModel: profileViewModel)
        }
        .alert(
            "Are you sure you want to delete?",
            isPresented: Binding(
                get: { pendingDeletionItem != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletionItem = nil
                    }
                }
            ),
            presenting: pendingDeletionItem
        ) { item in
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteMemory(musicId: item.id)
                    pendingDeletionItem = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeletionItem = nil
            }
        }
    }

    private var filteredItems: [MemoryLibraryItem] {
        viewModel.libraryItems
            .filter(matchesLocation(_:))
            .filter(matchesGenre(_:))
            .filter(matchesDate(_:))
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredCollectionItems: [MemoryLibraryItem] {
        viewModel.collectionItems
            .filter(matchesLocation(_:))
            .filter(matchesGenre(_:))
            .filter(matchesDate(_:))
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var timelineSections: [MemoryTimelineSectionData] {
        if let selectedDate {
            return timelineSections(
                titled: timelineTitle(forSelectedDate: selectedDate),
                items: filteredItems
            )
        }

        if let selectedDatePreset {
            return timelineSections(
                titled: selectedDatePreset.title,
                items: filteredItems
            )
        }

        return defaultTimelineSections
    }

    private var emptyState: MemoryEmptyState {
        guard let selectedDate else { return .yet }

        let today = calendar.startOfDay(for: Date())
        let selectedDay = calendar.startOfDay(for: selectedDate)

        if selectedDay == today {
            return .yet
        }

        return selectedDay < today ? .here : .future
    }

    // Default browsing keeps a stable recency ladder and omits empty buckets.
    private var defaultTimelineSections: [MemoryTimelineSectionData] {
        let todayItems = filteredItems.filter { calendar.isDateInToday($0.createdAt) }
        let thisWeekItems = filteredItems.filter(isInCurrentWeekExcludingToday(_:))
        let thisMonthItems = filteredItems.filter(isInCurrentMonthExcludingCurrentWeek(_:))
        let thisYearItems = filteredItems.filter(isOutsideCurrentMonth(_:))

        return [
            MemoryTimelineSectionData(title: "Today", items: todayItems),
            MemoryTimelineSectionData(title: "This Week", items: thisWeekItems),
            MemoryTimelineSectionData(title: "This Month", items: thisMonthItems),
            MemoryTimelineSectionData(title: "This Year", items: thisYearItems)
        ]
        .filter { !$0.items.isEmpty }
    }

    private var dateChipLabel: String {
        if let selectedDate {
            return selectedDate.formatted(.dateTime.month().day())
        }
        return selectedDatePreset?.title ?? "Dates"
    }

    private var genreChipLabel: String {
        selectedGenre ?? "Genres"
    }

    private var filterAnimationKey: String {
        [
            selectedLocation ?? "",
            selectedGenre ?? "",
            selectedDate?.formatted(date: .abbreviated, time: .omitted) ?? "",
            selectedDatePreset?.rawValue ?? ""
        ]
        .joined(separator: "|")
    }

    private func initialLoad() async {
        async let library: Void = viewModel.refreshLibrary()
        async let environment: Void = viewModel.fetchEnvironment()
        _ = await (library, environment)
    }

    private func matchesLocation(_ item: MemoryLibraryItem) -> Bool {
        guard let selectedLocation else { return true }
        return item.locationName == selectedLocation
    }

    private func matchesGenre(_ item: MemoryLibraryItem) -> Bool {
        guard let selectedGenre else { return true }
        return item.typeLabel == selectedGenre
    }

    private func matchesDate(_ item: MemoryLibraryItem) -> Bool {
        if let selectedDate {
            return calendar.isDate(item.createdAt, inSameDayAs: selectedDate)
        }

        guard let selectedDatePreset else { return true }
        let date = item.createdAt

        switch selectedDatePreset {
        case .today:
            return calendar.isDateInToday(date)
        case .thisWeekend:
            return isInWeekend(date, weekOffset: 0)
        case .thisMonth:
            return calendar.isDate(date, equalTo: Date(), toGranularity: .month)
        }
    }

    private func isInWeekend(_ date: Date, weekOffset: Int) -> Bool {
        guard let referenceWeek = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: Date()),
              let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceWeek) else {
            return false
        }

        return calendar.isDateInWeekend(date) && weekInterval.contains(date)
    }

    private func timelineSections(
        titled title: String,
        items: [MemoryLibraryItem]
    ) -> [MemoryTimelineSectionData] {
        guard !items.isEmpty else { return [] }
        return [MemoryTimelineSectionData(title: title, items: items)]
    }

    private func timelineTitle(forSelectedDate date: Date) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        }

        return date.formatted(.dateTime.month(.wide).day().year())
    }

    private func isInCurrentWeekExcludingToday(_ item: MemoryLibraryItem) -> Bool {
        let date = item.createdAt
        guard calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) else {
            return false
        }
        return !calendar.isDateInToday(date)
    }

    private func isInCurrentMonthExcludingCurrentWeek(_ item: MemoryLibraryItem) -> Bool {
        let date = item.createdAt
        guard calendar.isDate(date, equalTo: Date(), toGranularity: .month) else {
            return false
        }
        return !calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }

    private func isOutsideCurrentMonth(_ item: MemoryLibraryItem) -> Bool {
        !calendar.isDate(item.createdAt, equalTo: Date(), toGranularity: .month)
    }

    private func handleSongTap(_ item: MemoryLibraryItem) {
        playerManager.currentMusic = item.music
        playerManager.lyrics = []
        playerManager.currentLineIndex = 0
        playerManager.showLyrics = false
        playerManager.lyricsControlsVisible = true
        playerManager.play()
    }

    private func toggleFavorite(_ item: MemoryLibraryItem) {
        Task {
            await viewModel.toggleFavorite(musicId: item.id, ownerId: item.music.ownerId)
        }
    }

    private func promptDelete(_ item: MemoryLibraryItem) {
        pendingDeletionItem = item
    }

    private func presentFilterSheet(_ sheet: MemoryFilterSheet) {
        presentedFilterSheet = sheet
    }

    private func presentComposer() {
        isComposerPresented = true
    }

    private func togglePaletteExpanded() {
        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
            isPaletteExpanded.toggle()
        }
    }

    private func toggleTimelineSection(_ title: String) {
        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
            if collapsedTimelineSections.contains(title) {
                collapsedTimelineSections.remove(title)
            } else {
                collapsedTimelineSections.insert(title)
            }
        }
    }
}

private enum MemoryFilterSheet: String, Identifiable {
    case location
    case date
    case genre

    var id: String { rawValue }
}

private struct MemoryTimelineSectionData: Identifiable {
    let title: String
    let items: [MemoryLibraryItem]

    var id: String { title }
}

private enum MemoryEmptyState {
    case yet
    case here
    case future

    var title: String {
        switch self {
        case .yet:
            return "No Memories yet ..."
        case .here:
            return "No Memories here ..."
        case .future:
            return "No Memories From Future"
        }
    }
}

private enum MemoriesPalette {
    static let accent = Color(uiColor: .systemIndigo)
}

private struct MemoriesTheme {
    let colorScheme: ColorScheme

    private let groupedBackground = Color(uiColor: .systemGray6)

    var backgroundTop: Color {
        groupedBackground
    }

    var backgroundBottom: Color {
        groupedBackground
    }

    var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.64) : Color(red: 0.47, green: 0.47, blue: 0.49)
    }

    var tertiaryText: Color {
        colorScheme == .dark ? .white.opacity(0.52) : Color(red: 0.60, green: 0.60, blue: 0.63)
    }

    var pillBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : .white
    }

    var pillBorder: Color {
        colorScheme == .dark ? .white.opacity(0.10) : Color.black.opacity(0.08)
    }

    var divider: Color {
        colorScheme == .dark ? .white.opacity(0.10) : Color.black.opacity(0.08)
    }

    var softSurface: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.56)
    }

    var softStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.68)
    }

    var chipBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.72)
    }

    var glassTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.22) : Color.white.opacity(0.18)
    }
}

private struct MemoriesHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            Text("MEMORIES")
                .font(.systemExpanded(size: 34, weight: .regular))
                .foregroundStyle(theme.primaryText)
                .tracking(0.05)
                .lineLimit(1)

            Text("PALACE")
                .font(.systemExpanded(size: 32, weight: .ultraLight))
                .foregroundStyle(theme.primaryText)
                .tracking(0.46)
                .padding(.top, 6)

            Text("Where moments fade, it turns them into music that stay.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(theme.secondaryText)
                .padding(.top, 24)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 264, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 42)
    }
}

private struct MemoryFilterChipRow: View {
    let dateLabel: String
    let genreLabel: String
    let hasSelectedLocation: Bool
    let hasSelectedDate: Bool
    let hasSelectedGenre: Bool
    let onLocationTap: () -> Void
    let onDateTap: () -> Void
    let onGenreTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MemoryLocationOrbButton(
                isSelected: hasSelectedLocation,
                action: onLocationTap
            )
            .frame(width: 48, height: 46)

            MemoryFilterChip(
                title: dateLabel,
                isSelected: hasSelectedDate,
                action: onDateTap
            )

            MemoryFilterChip(
                title: genreLabel,
                isSelected: hasSelectedGenre,
                action: onGenreTap
            )
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MemoryLocationOrbButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "location")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 46)
                .background(MemoriesPalette.accent, in: Capsule(style: .continuous))
        }
        .buttonStyle(MemoriesPressStyle())
    }
}

private struct MemoryFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
        Button(action: action) {
            chipLabel
        }
        .buttonStyle(MemoriesPressStyle())
    }

    @ViewBuilder
    private var chipLabel: some View {
        if #available(iOS 26, *) {
            Text(title)
                .font(.system(size: 15, weight: .regular))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .white : theme.primaryText)
                .frame(width: 116)
                .frame(height: 46)
                .glassEffect(
                    isSelected
                    ? .regular.tint(MemoriesPalette.accent.opacity(0.92)).interactive()
                    : .regular.tint(theme.glassTint.opacity(1.15)).interactive(),
                    in: .capsule
                )
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? MemoriesPalette.accent.opacity(0.94) : theme.pillBackground)
                }
                .shadow(
                    color: isSelected
                    ? MemoriesPalette.accent.opacity(colorScheme == .dark ? 0.24 : 0.14)
                    : .black.opacity(colorScheme == .dark ? 0.12 : 0.04),
                    radius: isSelected ? 14 : 10,
                    y: 5
                )
        } else {
            Group {
                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : theme.primaryText)
                    .frame(width: 116)
                    .frame(height: 46)
            }
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? MemoriesPalette.accent : theme.pillBackground)
            )
        }
    }
}

private struct MemoryPaletteSection: View {
    let items: [MemoryLibraryItem]
    let favoriteIds: Set<String>
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onPlay: (MemoryLibraryItem) -> Void
    let onFavorite: (MemoryLibraryItem) -> Void
    let onAdd: () -> Void
    let onOpenCoCreation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MemorySectionHeader(title: "Collection", isExpanded: isExpanded, action: onToggleExpanded)

            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    memoryCardRow
                        .padding(.vertical, 2)
                }
                .scrollClipDisabled()
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
    }

    private var memoryCardRow: some View {
        HStack(spacing: 16) {
            MemoryComposerLaunchCard(onCreate: onAdd)
            MemoryFutureCollectionCard(action: onOpenCoCreation)

            ForEach(items) { item in
                MemoryCollectionCard(
                    item: item,
                    isFavorite: favoriteIds.contains(item.id),
                    onPlay: { onPlay(item) },
                    onFavorite: { onFavorite(item) }
                )
            }
        }
    }
}

private struct MemorySectionHeader: View {
    let title: String
    let isExpanded: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
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
            }
            .buttonStyle(.plain)
        }
    }
}

private struct MemoryTopCreateButtonRow: View {
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            MemoryNewMemoriesButton(action: action)
            Spacer(minLength: 0)
        }
    }
}

private struct MemoryNewMemoriesButton: View {
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let buttonWidth: CGFloat = 352
    private let buttonHeight: CGFloat = 50

    @ViewBuilder
    private var buttonBackground: some View {
        if #available(iOS 26, *) {
            Capsule(style: .continuous)
                .fill(MemoriesPalette.accent)
                .glassEffect(
                    .regular.tint(MemoriesPalette.accent).interactive(),
                    in: .capsule
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.16), lineWidth: 0.9)
                }
                .shadow(
                    color: MemoriesPalette.accent.opacity(colorScheme == .dark ? 0.28 : 0.18),
                    radius: 14,
                    y: 7
                )
        } else {
            Capsule(style: .continuous)
                .fill(MemoriesPalette.accent)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.16), lineWidth: 0.9)
                }
                .shadow(color: MemoriesPalette.accent.opacity(colorScheme == .dark ? 0.28 : 0.18), radius: 14, y: 7)
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.96))
                .frame(width: buttonWidth, height: buttonHeight)
                .background(buttonBackground)
        }
        .buttonStyle(MemoriesPressStyle())
    }
}

private struct MemoryComposerLaunchCard: View {
    let onCreate: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MemoryStaticArtworkCard(
            title: "Compose Music",
            subtitle: "All the content you provide becomes part of the memory.",
            artwork: composeArtwork,
            action: onCreate
        )
    }

    private var composeArtwork: some View {
        Group {
            if let uiImage = composeUIImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .saturation(1.06)
                    .contrast(1.14)
                    .brightness(-0.02)
            } else {
                LinearGradient(
                    colors: [
                        MemoriesPalette.accent.opacity(0.18),
                        Color(uiColor: .systemGray6),
                        Color(uiColor: .systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.74))
                }
            }
        }
    }

    private var composeUIImage: UIImage? {
        UIImage(named: "compose")
            ?? UIImage(named: "compose.png")
            ?? Bundle.main.url(forResource: "compose", withExtension: "png")
                .flatMap { UIImage(contentsOfFile: $0.path) }
    }
}

private struct MemoryStaticArtworkCard<Artwork: View>: View {
    let title: String
    let subtitle: String
    let artwork: Artwork
    var action: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }
    private let imageHeight: CGFloat = 196
    private let transitionHeight: CGFloat = 64
    private let cardWidth: CGFloat = 252
    private let cardHeight: CGFloat = 292

    @ViewBuilder
    private var cardBackground: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.18))
                .glassEffect(
                    .regular,
                    in: .rect(cornerRadius: 24)
                )
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18), lineWidth: 0.8)
                }
        }
    }

    private var lowerSurfaceColor: Color {
        colorScheme == .dark ? theme.softSurface.opacity(0.88) : Color.white.opacity(0.72)
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    cardBody
                }
                .buttonStyle(MemoriesPressStyle())
            } else {
                cardBody
            }
        }
    }

    private var cardBody: some View {
        cardBackground
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(theme.pillBorder.opacity(colorScheme == .dark ? 0.90 : 0.58), lineWidth: 0.8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.26), lineWidth: 0.6)
                    .padding(1.1)
            }
            .overlay {
                VStack(spacing: 0) {
                    imageLayer
                        .frame(maxWidth: .infinity)
                        .frame(height: imageHeight)
                        .clipped()

                    Spacer(minLength: 0)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(theme.primaryText)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.07), radius: 16, y: 8)
    }

    private var imageLayer: some View {
        artwork
            .frame(maxWidth: .infinity)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.70),
                        .init(color: .black.opacity(0.80), location: 0.82),
                        .init(color: .black.opacity(0.34), location: 0.93),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .bottom) {
                transitionLayer
                    .frame(height: transitionHeight)
                    .offset(y: transitionHeight * 0.18)
            }
    }

    private var transitionLayer: some View {
        artwork
            .frame(maxWidth: .infinity)
            .blur(radius: 18)
            .scaleEffect(1.05)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.45), location: 0.20),
                        .init(color: .black, location: 0.58),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: lowerSurfaceColor.opacity(0.00), location: 0.0),
                        .init(color: lowerSurfaceColor.opacity(0.18), location: 0.34),
                        .init(color: lowerSurfaceColor.opacity(0.76), location: 0.78),
                        .init(color: lowerSurfaceColor, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .opacity(0.92)
            .allowsHitTesting(false)
    }
}

private struct MemoryFeatureCardShell<Content: View>: View {
    let accentAlignment: Alignment
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(theme.softSurface.opacity(colorScheme == .dark ? 0.98 : 1))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(theme.softStroke.opacity(colorScheme == .dark ? 1 : 0.92), lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(colorScheme == .dark ? 0.06 : 0.42), lineWidth: 0.6)
                    .padding(1.2)
            }
            .modifier(
                MemorySingleGlassModifier(
                    tint: colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.26),
                    cornerRadius: 24
                )
            )
            .overlay(alignment: accentAlignment) {
                Circle()
                    .fill(MemoriesPalette.accent.opacity(colorScheme == .dark ? 0.18 : 0.14))
                    .frame(width: 152, height: 152)
                    .blur(radius: 18)
                    .offset(x: accentAlignment == .topTrailing ? 36 : 16, y: accentAlignment == .topTrailing ? -24 : 18)
            }
            .overlay(alignment: .bottomLeading) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(18)
            }
        .frame(width: 252, height: 292)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.07), radius: 16, y: 8)
    }
}

private struct MemorySingleGlassModifier: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(
                    .regular.tint(tint).interactive(),
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

private struct MemoryFeaturePill: View {
    let title: String
    var systemImage: String? = nil
    var symbolColor: Color? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(symbolColor ?? theme.primaryText.opacity(0.84))
            }

            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
            .foregroundStyle(theme.primaryText.opacity(0.84))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(theme.pillBackground.opacity(colorScheme == .dark ? 0.56 : 0.92), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(theme.pillBorder.opacity(0.8), lineWidth: 1)
            }
    }
}

private struct MemoryFutureCollectionCard: View {
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MemoryStaticArtworkCard(
            title: "Co-creation",
            subtitle: "Open the collaboration workspace with your friends.",
            artwork: shareArtwork,
            action: action
        )
    }

    private var shareArtwork: some View {
        Group {
            if let uiImage = shareUIImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .saturation(1.04)
                    .contrast(1.05)
            } else {
                LinearGradient(
                    colors: [
                        MemoriesPalette.accent.opacity(0.30),
                        Color(uiColor: .systemGray5),
                        Color(uiColor: .systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.74))
                }
            }
        }
    }

    private var shareUIImage: UIImage? {
        UIImage(named: "share")
            ?? UIImage(named: "share.png")
            ?? Bundle.main.url(forResource: "share", withExtension: "png")
                .flatMap { UIImage(contentsOfFile: $0.path) }
    }
}

private struct MemoryCollectionCard: View {
    let item: MemoryLibraryItem
    let isFavorite: Bool
    let onPlay: () -> Void
    let onFavorite: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }
    private let imageHeight: CGFloat = 196
    private let transitionHeight: CGFloat = 64

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onPlay) {
                cardShell
            }
            .buttonStyle(MemoriesPressStyle())

            if isFavorite {
                Button(action: onFavorite) {
                    MemoryFeaturePill(
                        title: "Saved",
                        systemImage: "heart.fill",
                        symbolColor: .red
                    )
                }
                .buttonStyle(.plain)
                .padding(18)
            }
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.07), radius: 16, y: 8)
        .contextMenu {
            Button(isFavorite ? "Remove from Collection" : "Add to Collection",
                   systemImage: isFavorite ? "heart.slash" : "heart") {
                onFavorite()
            }
        }
    }

    private var cardShell: some View {
        cardBackground
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(theme.pillBorder.opacity(colorScheme == .dark ? 0.90 : 0.58), lineWidth: 0.8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.26), lineWidth: 0.6)
                    .padding(1.1)
            }
            .overlay {
                VStack(spacing: 0) {
                    imageLayer
                        .frame(height: imageHeight)
                        .clipped()

                    Spacer(minLength: 0)
                }
            }
            .overlay(alignment: .topLeading) {
                MemoryDateSticker(date: item.createdAt, compactMonth: false)
                    .padding(18)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(2)

                    Text(memoryCollectionDetailLine(for: item))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            .frame(width: 252, height: 292)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var cardBackground: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.18))
                .glassEffect(
                    .regular,
                    in: .rect(cornerRadius: 24)
                )
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18), lineWidth: 0.8)
                }
        }
    }

    private var lowerSurfaceColor: Color {
        colorScheme == .dark ? theme.softSurface.opacity(0.88) : Color.white.opacity(0.72)
    }

    private var cardArtwork: some View {
        artworkContent
            .frame(maxWidth: .infinity)
    }

    private var imageLayer: some View {
        cardArtwork
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.70),
                        .init(color: .black.opacity(0.80), location: 0.82),
                        .init(color: .black.opacity(0.34), location: 0.93),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .bottom) {
                transitionLayer
                    .frame(height: transitionHeight)
                    .offset(y: transitionHeight * 0.18)
            }
    }

    private var transitionLayer: some View {
        cardArtwork
            .blur(radius: 18)
            .scaleEffect(1.05)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.45), location: 0.20),
                        .init(color: .black, location: 0.58),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: lowerSurfaceColor.opacity(0.00), location: 0.0),
                        .init(color: lowerSurfaceColor.opacity(0.18), location: 0.34),
                        .init(color: lowerSurfaceColor.opacity(0.76), location: 0.78),
                        .init(color: lowerSurfaceColor, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .opacity(0.92)
            .allowsHitTesting(false)
    }

    private var artworkContent: some View {
        Group {
            if let url = item.music.imageURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        fallbackArtwork
                    }
                }
            } else {
                fallbackArtwork
            }
        }
    }

    private var fallbackArtwork: some View {
        let colors = memoryArtworkColors(for: item.id)

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 140, height: 140)
                .blur(radius: 6)
                .offset(x: 54, y: 30)
        }
    }
}

private struct MemoryTimelineSectionView: View {
    let title: String
    let items: [MemoryLibraryItem]
    let favoriteIds: Set<String>
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onPlay: (MemoryLibraryItem) -> Void
    let onFavorite: (MemoryLibraryItem) -> Void
    let onDelete: (MemoryLibraryItem) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MemorySectionHeader(
                title: title,
                isExpanded: isExpanded,
                action: onToggleExpanded
            )

            if isExpanded {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        MemorySongRow(
                            item: item,
                            isFavorite: favoriteIds.contains(item.id),
                            onPlay: { onPlay(item) },
                            onFavorite: { onFavorite(item) },
                            onDelete: { onDelete(item) }
                        )

                        if index != items.count - 1 {
                            Divider()
                                .overlay(theme.divider)
                                .padding(.leading, 92)
                        }
                    }
                }
            }
        }
    }
}

private struct MemorySongRow: View {
    let item: MemoryLibraryItem
    let isFavorite: Bool
    let onPlay: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onPlay) {
                HStack(alignment: .top, spacing: 16) {
                    MemorySongArtwork(item: item)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)

                        Text(item.typeLabel)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)

                        Text(memoryRowDetailLine(for: item))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MemoriesPressStyle())

            HStack(alignment: .center, spacing: 4) {
                if isFavorite {
                    Button(action: onFavorite) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove favorite")
                }

                MemorySongMoreMenu(
                    item: item,
                    isFavorite: isFavorite,
                    onFavorite: onFavorite,
                    onDelete: onDelete
                )
            }
            .padding(.top, 10)
        }
        .padding(.vertical, 12)
    }
}

private struct MemorySongMoreMenu: View {
    let item: MemoryLibraryItem
    let isFavorite: Bool
    let onFavorite: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
        Menu {
            Button("Share", systemImage: "square.and.arrow.up") {}
            Button("Set for Widget", systemImage: "apps.iphone") {
                SystemSongSnapshotStore().pin(
                    SystemSongSnapshot.from(item.music, kind: .memory)
                )
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
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("More actions")
    }
}

private struct MemorySongArtwork: View {
    let item: MemoryLibraryItem

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            artwork
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05), lineWidth: 1)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.06), radius: 8, y: 4)

            MemoryDateSticker(date: item.createdAt, compactMonth: true)
                .offset(x: 4, y: 4)
        }
    }

    private var artwork: some View {
        Group {
            if let url = item.music.imageURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        fallbackArtwork
                    }
                }
            } else {
                fallbackArtwork
            }
        }
    }

    private var fallbackArtwork: some View {
        let colors = memoryArtworkColors(for: item.id)

        return Circle()
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white.opacity(0.72))
            }
    }
}

private struct MemoryDateSticker: View {
    let date: Date
    let compactMonth: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: compactMonth ? 1 : 2) {
            Text(date.formatted(.dateTime.month(.abbreviated)))
                .font(.system(size: compactMonth ? 9 : 10, weight: .bold))
                .foregroundStyle(MemoriesPalette.accent)
                .textCase(.uppercase)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: compactMonth ? 21 : 27, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
        }
        .frame(width: compactMonth ? 34 : 44, height: compactMonth ? 40 : 50)
        .background((colorScheme == .dark ? Color.black.opacity(0.70) : .white), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.04), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 10, y: 4)
    }
}

private struct MemoryLoadingSection: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(MemoriesPalette.accent)
            Text("Loading memories...")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

private struct MemoryEmptySection: View {
    let state: MemoryEmptyState
    let onCreate: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                titleLabel(fontSize: 28)
                titleLabel(fontSize: 26)
                titleLabel(fontSize: 24)
                titleLabel(fontSize: 22)
            }
            .frame(maxWidth: 344)
            .frame(maxWidth: .infinity)

            Text("Capture the moment before it fades.")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 28)

            Text("Create a memory today.")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 18)

            MemoryLiquidGlassPlusButton(action: onCreate)
                .padding(.top, 36)
        }
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity)
        .padding(.top, 86)
        .padding(.bottom, 28)
    }

    private func titleLabel(fontSize: CGFloat) -> some View {
        Text(state.title)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(theme.primaryText)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .allowsTightening(true)
    }
}

private struct MemoryLiquidGlassPlusButton: View {
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Group {
                if #available(iOS 26, *) {
                    ZStack {
                        Circle()
                            .fill(MemoriesPalette.accent.opacity(colorScheme == .dark ? 0.52 : 0.46))

                        Image(systemName: "plus")
                            .font(.system(size: 23, weight: .light))
                            .foregroundStyle(.white.opacity(0.98))
                    }
                    .frame(width: 45, height: 45)
                    .glassEffect(
                        .regular
                            .tint(MemoriesPalette.accent.opacity(colorScheme == .dark ? 0.92 : 0.84))
                            .interactive(),
                        in: .circle
                    )
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.34), lineWidth: 0.8)
                    }
                } else {
                    ZStack {
                        Circle()
                            .fill(MemoriesPalette.accent.opacity(colorScheme == .dark ? 0.82 : 0.88))

                        Image(systemName: "plus")
                            .font(.system(size: 23, weight: .light))
                            .foregroundStyle(.white.opacity(0.98))
                    }
                    .frame(width: 45, height: 45)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.26), lineWidth: 0.8)
                    }
                }
            }
        }
        .buttonStyle(MemoriesPressStyle())
    }
}

private struct MemoriesPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.18, extraBounce: 0), value: configuration.isPressed)
    }
}

private func memoryArtworkColors(for key: String) -> [Color] {
    let palettes: [[Color]] = [
        [Color(red: 0.89, green: 0.71, blue: 0.29), Color(red: 0.49, green: 0.29, blue: 0.13)],
        [Color(red: 0.25, green: 0.35, blue: 0.56), Color(red: 0.09, green: 0.15, blue: 0.29)],
        [Color(red: 0.57, green: 0.27, blue: 0.38), Color(red: 0.19, green: 0.07, blue: 0.15)],
        [Color(red: 0.27, green: 0.47, blue: 0.42), Color(red: 0.09, green: 0.22, blue: 0.18)]
    ]

    let scalarSum = key.unicodeScalars.map(\.value).reduce(0, +)
    return palettes[Int(scalarSum % UInt32(palettes.count))]
}

private func memoryTimestampLine(for date: Date) -> String {
    let day = date.formatted(.dateTime.weekday(.wide))
    let time = date.formatted(date: .omitted, time: .shortened)
    return "\(day) · \(time)"
}

private func memoryCollectionDetailLine(for item: MemoryLibraryItem) -> String {
    "\(item.typeLabel) · \(memoryTimestampLine(for: item.createdAt))"
}

private func memoryRowDetailLine(for item: MemoryLibraryItem) -> String {
    let timestamp = memoryTimestampLine(for: item.createdAt)
    guard let location = memoryDisplayLocation(for: item) else {
        return timestamp
    }
    return "\(location) · \(timestamp)"
}

private func memoryDisplayLocation(for item: MemoryLibraryItem) -> String? {
    let trimmed = item.metadata.locationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty, trimmed != MemorySongMetadata.unknownLocationLabel else {
        return nil
    }
    return trimmed
}

#Preview {
    MemoriesView(
        viewModel: MemoryViewModel(),
        profileViewModel: ProfileViewModel(),
        onOpenCoCreation: {}
    )
        .environment(PlayerManager())
}
