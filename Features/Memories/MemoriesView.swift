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
                    LazyVStack(alignment: .leading, spacing: 30) {
                        MemoriesHeader()

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

                        MemoryPaletteSection(
                            items: filteredCollectionItems,
                            favoriteIds: viewModel.favoriteIds,
                            isExpanded: isPaletteExpanded,
                            onToggleExpanded: togglePaletteExpanded,
                            onPlay: handleSongTap(_:),
                            onFavorite: toggleFavorite(_:),
                            onAdd: presentComposer
                        )

                        if viewModel.isLoadingLibrary && viewModel.libraryItems.isEmpty {
                            MemoryLoadingSection()
                        } else if timelineSections.isEmpty {
                            MemoryEmptySection(onCreate: presentComposer)
                        } else {
                            ForEach(timelineSections) { section in
                                MemoryTimelineSectionView(
                                    title: section.title,
                                    items: section.items,
                                    favoriteIds: viewModel.favoriteIds,
                                    isExpanded: !collapsedTimelineSections.contains(section.id),
                                    onToggleExpanded: { toggleTimelineSection(section.id) },
                                    onPlay: handleSongTap(_:),
                                    onFavorite: toggleFavorite(_:)
                                )
                            }
                        }
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.leading, 28)
                .padding(.trailing, 10)
                .padding(.top, 14)
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
        var groups: [(String, [MemoryLibraryItem])] = []

        for item in filteredItems {
            let title = sectionTitle(for: item.createdAt)
            if let index = groups.firstIndex(where: { $0.0 == title }) {
                groups[index].1.append(item)
            } else {
                groups.append((title, [item]))
            }
        }

        return groups.map { MemoryTimelineSectionData(title: $0.0, items: $0.1) }
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
        case .tomorrow:
            return calendar.isDateInTomorrow(date)
        case .thisWeekend:
            return isInWeekend(date, weekOffset: 0)
        case .nextWeekend:
            return isInWeekend(date, weekOffset: 1)
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

    private func sectionTitle(for date: Date) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        }

        if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            return "This Week"
        }

        if let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: Date()),
           calendar.isDate(date, equalTo: nextWeek, toGranularity: .weekOfYear) {
            return "Next Week"
        }

        return date.formatted(.dateTime.month(.wide).year())
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

private enum MemoriesPalette {
    static let accent = Color(uiColor: .systemIndigo)
}

private struct MemoriesTheme {
    let colorScheme: ColorScheme

    var backgroundTop: Color {
        colorScheme == .dark ? Color(red: 0.03, green: 0.03, blue: 0.04) : Color(red: 0.99, green: 0.99, blue: 0.995)
    }

    var backgroundBottom: Color {
        colorScheme == .dark ? Color(red: 0.01, green: 0.01, blue: 0.015) : .white
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
        VStack(alignment: .leading, spacing: 0) {
            Text("MEMORIES")
                .font(.systemExpanded(size: 30, weight: .regular))
                .foregroundStyle(theme.primaryText)
                .tracking(0.05)
                .lineLimit(1)

            Text("PALACE")
                .font(.systemExpanded(size: 28, weight: .ultraLight))
                .foregroundStyle(theme.primaryText)
                .tracking(0.42)
                .padding(.top, 4)

            Text("Where moments fade, it turns them into music that stay.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 231, alignment: .leading)
        }
        .padding(.top, 6)
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
            MemoryFutureCollectionCard()

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

private struct MemoryComposerLaunchCard: View {
    let onCreate: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
        Button(action: onCreate) {
            MemoryFeatureCardShell(
                accentAlignment: .topTrailing
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    MemoryDateSticker(date: Date.now, compactMonth: false)

                    Spacer()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Compose Music")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(theme.primaryText)

                        Text("All the content you provide becomes part of the memory.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(3)
                    }
                }
            }
        }
        .buttonStyle(MemoriesPressStyle())
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

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
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
    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
        MemoryFeatureCardShell(
            accentAlignment: .center
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Share")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(theme.primaryText)

                    Text("Let your friends know what your memory is.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MemoryCollectionCard: View {
    let item: MemoryLibraryItem
    let isFavorite: Bool
    let onPlay: () -> Void
    let onFavorite: () -> Void

    var body: some View {
        Button(action: onPlay) {
            ZStack(alignment: .topLeading) {
                cardArtwork

                LinearGradient(
                    colors: [.clear, .clear, Color.black.opacity(0.68)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 0) {
                    MemoryDateSticker(date: item.createdAt, compactMonth: false)
                    Spacer()
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(item.typeLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.84))
                            .lineLimit(1)
                        Text(memoryTimestampLine(for: item.createdAt))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                    }
                }
                .padding(18)
            }
            .frame(width: 252, height: 292)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(MemoriesPressStyle())
        .contextMenu {
            Button(isFavorite ? "Remove from Collection" : "Add to Collection",
                   systemImage: isFavorite ? "heart.slash" : "heart") {
                onFavorite()
            }
        }
    }

    private var cardArtwork: some View {
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
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
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

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MemorySectionHeader(title: title, isExpanded: isExpanded, action: onToggleExpanded)

            if isExpanded {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        MemorySongRow(
                            item: item,
                            isFavorite: favoriteIds.contains(item.id),
                            onPlay: { onPlay(item) },
                            onFavorite: { onFavorite(item) }
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

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
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
            .padding(.vertical, 12)
        }
        .buttonStyle(MemoriesPressStyle())
        .contextMenu {
            Button(isFavorite ? "Remove from Collection" : "Add to Collection",
                   systemImage: isFavorite ? "heart.slash" : "heart") {
                onFavorite()
            }
        }
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
    let onCreate: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoriesTheme { MemoriesTheme(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No memory songs yet")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(theme.primaryText)
            Text("Create your first memory track, then revisit it by place, date, and genre.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.secondaryText)
            Text("Build a memory by hand, and it will live here with the rest of your collection.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.secondaryText)
            Button("New Memory", action: onCreate)
                .buttonStyle(.borderedProminent)
                .tint(MemoriesPalette.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(theme.pillBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(theme.pillBorder, lineWidth: 1)
        }
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
    MemoriesView(viewModel: MemoryViewModel(), profileViewModel: ProfileViewModel())
        .environment(PlayerManager())
}
