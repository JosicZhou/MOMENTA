//
//  MemoryFilterSheets.swift
//  MOMENTA
//
//  Memories 的地点、日期、类型筛选 sheet。
//

import SwiftUI
import UIKit

struct MemoryLocationSheet: View {
    let locations: [String]
    let currentLocation: String?
    @Binding var selectedLocation: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""

    private var theme: MemorySheetTheme { MemorySheetTheme(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            MemorySheetTitleBar(title: "Location") {
                dismiss()
            }
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Nearby Location")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.subtleText)

                    VStack(spacing: 12) {
                        if let currentLocation {
                            locationButton(
                                title: currentLocation,
                                subtitle: "Current location",
                                isSelected: selectedLocation == currentLocation
                            )
                        }

                        ForEach(filteredLocations, id: \.self) { location in
                            locationButton(
                                title: location,
                                subtitle: "Saved memory place",
                                isSelected: selectedLocation == location
                            )
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            MemoryLocationSearchBar(searchText: $searchText)
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .memoryFilterSheetChrome(detents: [.large], dragIndicator: .hidden, cornerRadius: 34)
    }

    private var filteredLocations: [String] {
        let uniqueLocations = Array(Set(locations))
            .filter { $0 != currentLocation }
            .sorted()

        guard !searchText.isEmpty else { return uniqueLocations }
        return uniqueLocations.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private func locationButton(title: String, subtitle: String, isSelected: Bool) -> some View {
        Button {
            selectedLocation = selectedLocation == title ? nil : title
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(MemorySheetPalette.accent, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.subtleText)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MemorySheetPalette.accent)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 72)
            .background(theme.secondarySurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(MemorySheetPressStyle())
    }
}

struct MemoryDateSheet: View {
    @Binding var selectedDate: Date?
    @Binding var selectedPreset: MemoryDatePreset?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var displayedMonth = Date()

    private let quickPresets: [MemoryDatePreset] = [.today, .thisWeekend, .thisMonth]
    private var theme: MemorySheetTheme { MemorySheetTheme(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    MemorySheetTitleBar(title: "Dates") {
                        dismiss()
                    }
                    .padding(.top, 12)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                        Button {
                            selectedPreset = nil
                            selectedDate = nil
                        } label: {
                            MemoryDateQuickChip(
                                title: "All",
                                isSelected: selectedPreset == nil && selectedDate == nil
                            )
                        }
                        .buttonStyle(MemorySheetPressStyle())

                        ForEach(quickPresets) { preset in
                            Button {
                                selectedPreset = preset
                                selectedDate = nil
                            } label: {
                                MemoryDateQuickChip(
                                    title: preset.title,
                                    isSelected: selectedPreset == preset
                                )
                            }
                            .buttonStyle(MemorySheetPressStyle())
                        }
                    }

                    MemoryMonthCalendar(
                        displayedMonth: $displayedMonth,
                        selectedDate: $selectedDate,
                        selectedPreset: $selectedPreset
                    )
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .top)
            }

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                MemorySheetPrimaryActionLabel(title: "Show Memories")
            }
            .buttonStyle(MemorySheetPressStyle())
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            displayedMonth = monthStart(for: selectedDate ?? Date())
        }
        .memoryFilterSheetChrome(detents: [.fraction(0.72), .large], dragIndicator: .hidden, cornerRadius: 34)
    }

    private func monthStart(for date: Date) -> Date {
        Calendar.memorySheet.date(from: Calendar.memorySheet.dateComponents([.year, .month], from: date)) ?? date
    }
}

struct MemoryGenreSheet: View {
    let genres: [String]
    @Binding var selectedGenre: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemorySheetTheme { MemorySheetTheme(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    MemorySheetTitleBar(title: "Genres") {
                        dismiss()
                    }
                    .padding(.top, 12)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                        Button {
                            selectedGenre = nil
                        } label: {
                            MemoryTypeChip(title: "All Genres", isSelected: selectedGenre == nil)
                        }
                        .buttonStyle(MemorySheetPressStyle())

                        ForEach(genres, id: \.self) { genre in
                            Button {
                                selectedGenre = selectedGenre == genre ? nil : genre
                            } label: {
                                MemoryTypeChip(title: genre, isSelected: selectedGenre == genre)
                            }
                            .buttonStyle(MemorySheetPressStyle())
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .top)
            }

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                MemorySheetPrimaryActionLabel(title: "Show Memories")
            }
            .buttonStyle(MemorySheetPressStyle())
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .memoryFilterSheetChrome(detents: [.fraction(0.52), .large], dragIndicator: .hidden, cornerRadius: 34)
    }
}

struct MemoryFloatingBackdrop: View {
    let onClose: () -> Void

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onClose)
    }
}

struct MemoryFloatingOverlay<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = max(proxy.safeAreaInsets.top + 64, proxy.size.height * 0.15)

            VStack {
                Spacer(minLength: topInset)

                content
                    .frame(maxWidth: min(420, proxy.size.width - 36))

                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
    }
}

struct MemoryFloatingCard<Content: View>: View {
    private let content: Content
    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemorySheetTheme { MemorySheetTheme(colorScheme: colorScheme) }

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                content
                    .padding(18)
                    .background(theme.floatingCardFill, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .glassEffect(.regular.tint(theme.glassTint), in: .rect(cornerRadius: 34))
            } else {
                content
                    .padding(18)
                    .background(theme.fallbackMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(theme.cardStroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.12), radius: 24, y: 10)
    }
}

struct MemoryNativeSheetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color(uiColor: .secondarySystemBackground) : Color(uiColor: .systemBackground))
            .ignoresSafeArea()
    }
}

struct MemorySheetPrimaryActionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(MemorySheetPalette.accent, in: Capsule(style: .continuous))
    }
}

extension View {
    func memoryFilterSheetChrome(
        detents: Set<PresentationDetent>,
        dragIndicator: Visibility,
        cornerRadius: CGFloat
    ) -> some View {
        self
            .presentationDetents(detents)
            .presentationDragIndicator(dragIndicator)
            .presentationCornerRadius(cornerRadius)
            .presentationBackground {
                MemoryNativeSheetBackground()
            }
    }

    func memorySheetChrome(
        detents: Set<PresentationDetent>,
        dragIndicator: Visibility,
        cornerRadius: CGFloat
    ) -> some View {
        self
            .presentationDetents(detents)
            .presentationDragIndicator(dragIndicator)
            .presentationCornerRadius(cornerRadius)
            .presentationBackground {
                MemoryNativeSheetBackground()
            }
    }
}

private enum MemorySheetPalette {
    static let accent = Color(uiColor: .systemIndigo)
}

private struct MemorySheetTheme {
    let colorScheme: ColorScheme

    var locationBackground: Color {
        colorScheme == .dark ? Color(uiColor: .secondarySystemBackground) : Color(uiColor: .systemBackground)
    }

    var sheetBackground: Color {
        colorScheme == .dark ? Color(uiColor: .secondarySystemBackground) : Color(uiColor: .systemBackground)
    }

    var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    var subtleText: Color {
        colorScheme == .dark ? .white.opacity(0.58) : Color(red: 0.53, green: 0.53, blue: 0.56)
    }

    var secondarySurface: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : .white
    }

    var border: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    var floatingCardFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.18)
    }

    var glassTint: Color {
        colorScheme == .dark ? .black.opacity(0.18) : .white.opacity(0.22)
    }

    var cardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.58)
    }

    var fallbackMaterial: Material {
        colorScheme == .dark ? .regularMaterial : .ultraThinMaterial
    }
}

private struct MemorySheetTitleBar: View {
    let title: String
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemorySheetTheme { MemorySheetTheme(colorScheme: colorScheme) }

    var body: some View {
        HStack {
            MemorySheetCloseButton(action: onClose)
            Spacer()
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Spacer()
            Color.clear
                .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
    }
}

private struct MemorySheetCloseButton: View {
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemorySheetTheme { MemorySheetTheme(colorScheme: colorScheme) }

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.primaryText.opacity(0.88))
                .frame(width: 40, height: 40)
                .background(theme.secondarySurface.opacity(colorScheme == .dark ? 1 : 0.82), in: Circle())
        }
        .buttonStyle(MemorySheetPressStyle())
    }
}

private struct MemoryLocationSearchBar: View {
    @Binding var searchText: String

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemorySheetTheme { MemorySheetTheme(colorScheme: colorScheme) }

    var body: some View {
        baseField
            .background(theme.secondarySurface, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
    }

    private var baseField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.subtleText)

            TextField("Search Cities", text: $searchText)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.primaryText)

            Image(systemName: "mic")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.primaryText.opacity(0.78))
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}

private struct MemoryDateQuickChip: View {
    let title: String
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemorySheetTheme { MemorySheetTheme(colorScheme: colorScheme) }

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isSelected ? .white : theme.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? MemorySheetPalette.accent.opacity(colorScheme == .dark ? 0.78 : 0.72) : theme.secondarySurface.opacity(colorScheme == .dark ? 0.96 : 0.92))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(isSelected ? Color.clear : theme.border, lineWidth: 1)
            }
    }
}

private struct MemoryMonthCalendar: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date?
    @Binding var selectedPreset: MemoryDatePreset?

    private let calendar = Calendar.memorySheet
    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemorySheetTheme { MemorySheetTheme(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 4) {
                    Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 31, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MemorySheetPalette.accent)
                        .padding(.top, 2)
                }

                Spacer()

                HStack(spacing: 20) {
                    Button {
                        shiftMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.primaryText.opacity(0.78))
                    }
                    .buttonStyle(MemorySheetPressStyle())

                    Button {
                        shiftMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.primaryText.opacity(0.78))
                    }
                    .buttonStyle(MemorySheetPressStyle())
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 14) {
                ForEach(calendar.memoryWeekdayHeaders, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.subtleText)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(dayValues.enumerated()), id: \.offset) { _, value in
                    if let date = value.date {
                        Button {
                            selectedDate = date
                            selectedPreset = nil
                        } label: {
                            Text("\(value.number)")
                                .font(.system(size: 17, weight: isSelected(date) ? .semibold : .regular))
                                .foregroundStyle(dayColor(for: date))
                                .frame(maxWidth: .infinity)
                                .frame(height: 26)
                        }
                        .buttonStyle(MemorySheetPressStyle())
                    } else {
                        Color.clear
                            .frame(height: 26)
                    }
                }
            }
        }
    }

    private var dayValues: [MemoryCalendarDayValue] {
        guard let monthRange = calendar.range(of: .day, in: .month, for: displayedMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingBlankCount = (firstWeekday - calendar.firstWeekday + 7) % 7

        var values: [MemoryCalendarDayValue] = Array(repeating: .empty, count: leadingBlankCount)
        for day in monthRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                values.append(.day(number: day, date: date))
            }
        }

        let remainder = values.count % 7
        if remainder != 0 {
            values.append(contentsOf: Array(repeating: .empty, count: 7 - remainder))
        }

        return values
    }

    private func shiftMonth(by value: Int) {
        if let shifted = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = monthStart(for: shifted)
        }
    }

    private func monthStart(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let selectedDate else { return false }
        return calendar.isDate(selectedDate, inSameDayAs: date)
    }

    private func dayColor(for date: Date) -> Color {
        if isSelected(date) {
            return theme.primaryText
        }

        if calendar.isDateInToday(date) {
            return MemorySheetPalette.accent
        }

        return theme.subtleText.opacity(0.65)
    }
}

private struct MemoryCalendarDayValue {
    let number: Int
    let date: Date?

    static let empty = MemoryCalendarDayValue(number: 0, date: nil)

    static func day(number: Int, date: Date) -> MemoryCalendarDayValue {
        MemoryCalendarDayValue(number: number, date: date)
    }
}

private struct MemoryTypeChip: View {
    let title: String
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemorySheetTheme { MemorySheetTheme(colorScheme: colorScheme) }

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isSelected ? .white : theme.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? MemorySheetPalette.accent : theme.secondarySurface.opacity(colorScheme == .dark ? 0.9 : 0.88))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(isSelected ? Color.clear : theme.border, lineWidth: 1)
            }
    }
}

private struct MemorySheetPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.18, extraBounce: 0), value: configuration.isPressed)
    }
}

private extension Calendar {
    static var memorySheet: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale.current
        calendar.firstWeekday = 2
        return calendar
    }

    var memoryWeekdayHeaders: [String] {
        ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
    }
}
