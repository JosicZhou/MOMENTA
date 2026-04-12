//
//  MemoryComposerSheet.swift
//  MOMENTA
//
//  Memories 手动生成 sheet：
//  回退到固定布局版本，保持长条输入栏和稳定的图标排布。
//

import SwiftUI
import MapKit
import UIKit

struct MemoryComposerSheet: View {
    @ObservedObject var viewModel: MemoryViewModel
    @ObservedObject var profileViewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @FocusState private var isPromptFocused: Bool
    @State private var isMapExpanded = false
    @State private var isHealthSheetPresented = false
    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    private var theme: MemoryComposerTheme { MemoryComposerTheme(colorScheme: colorScheme) }
    private let composerContentInset: CGFloat = 14
    private let contentWidth: CGFloat = 349

    private var promptPlaceholder: String {
        if viewModel.language == "zh" {
            return "描述你想听见的回忆"
        }

        return "Describe the memory you want to hear"
    }

    private var locationTitle: String {
        viewModel.locationWeather.locationName ?? "Current location"
    }

    private var identityTitle: String {
        viewModel.language == "zh" ? "这段回忆属于" : "This memory belongs to"
    }

    private var identityName: String {
        profileViewModel.displayName
    }

    private var locationControlLabel: String {
        isMapExpanded ? locationTitle : "Location"
    }

    private var dateChipText: String {
        if viewModel.language == "zh" {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_HK")
            formatter.dateFormat = "M月d日"
            return formatter.string(from: Date())
        }

        return Date().formatted(.dateTime.month(.abbreviated).day())
    }

    private var timeChipText: String {
        if viewModel.language == "zh" {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_HK")
            formatter.dateFormat = "ah:mm"
            return formatter.string(from: Date())
        }

        return Date().formatted(.dateTime.hour().minute())
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = min(max(proxy.size.width - (composerContentInset * 2), 349), 385)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    MemoryComposerInputBar(
                        contentWidth: contentWidth,
                        prompt: $viewModel.prompt,
                        placeholder: promptPlaceholder,
                        isPromptFocused: $isPromptFocused,
                        isGenerating: viewModel.isGenerating,
                        hasSelectedImage: viewModel.selectedImage != nil,
                        onTakePhoto: viewModel.openCamera,
                        onChooseFromLibrary: viewModel.openPhotoLibrary,
                        onRemoveImage: viewModel.removeImage,
                        onGenerateTap: generate
                    )

                    Spacer()
                        .frame(height: 28)

                    MemoryComposerControlStrip(
                        contentWidth: contentWidth,
                        currentLanguage: viewModel.language,
                        instrumentalOnly: viewModel.instrumentalOnly,
                        healthEnabled: viewModel.usePsychologicalProfile,
                        locationLabel: locationControlLabel,
                        isLocationExpanded: isMapExpanded,
                        onLanguageToggle: toggleLanguage,
                        onVoiceToggle: toggleVoiceMode,
                        onHealthTap: { isHealthSheetPresented = true },
                        onLocationTap: toggleMap
                    )

                    if isMapExpanded {
                        memoryMap(contentWidth: contentWidth)
                            .padding(.top, 24)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Spacer(minLength: isMapExpanded ? 56 : 0)

                    MemoryComposerIdentitySection(
                        avatarImage: profileViewModel.profileAvatarImage,
                        title: identityTitle,
                        name: identityName,
                        isLowered: false
                    )

                    Spacer()
                        .frame(height: 18)

                    MemoryComposerContextFooter(
                        dateText: dateChipText,
                        timeText: timeChipText,
                        isLowered: false
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: max(proxy.size.height - (composerContentInset * 2), 0), alignment: .top)
                .padding(.horizontal, composerContentInset)
                .padding(.top, composerContentInset)
                .padding(.bottom, 6)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .scrollDisabled(!isMapExpanded)
        .memorySheetChrome(
            detents: [.custom(MemoryComposerCompactDetent.self)],
            dragIndicator: .visible,
            cornerRadius: 36
        )
        .sheet(isPresented: $viewModel.showImagePicker) {
            ImagePicker(
                sourceType: viewModel.imagePickerSourceType,
                selectedImage: $viewModel.selectedImage
            )
        }
        .sheet(isPresented: $isHealthSheetPresented) {
            MemoryHealthAccessSheet(viewModel: viewModel)
        }
        .task {
            await viewModel.fetchEnvironment()
            syncMapPosition(with: viewModel.locationWeather.coordinate)
        }
        .onReceive(viewModel.locationWeather.$coordinate) { coordinate in
            syncMapPosition(with: coordinate)
        }
    }

    @ViewBuilder
    private func memoryMap(contentWidth: CGFloat) -> some View {
        if let coordinate = viewModel.locationWeather.coordinate {
            Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
                Annotation(locationTitle, coordinate: coordinate) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.red, .white)
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(width: contentWidth)
            .frame(height: 238)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(theme.mapBorder, lineWidth: 1)
            }
        } else {
            MemoryComposerMapPlaceholder()
                .frame(width: contentWidth)
                .frame(height: 238)
        }
    }

    private func generate() {
        isPromptFocused = false

        Task {
            await viewModel.generate()

            if viewModel.errorMessage == nil, viewModel.generatedMusic != nil {
                viewModel.resetComposer()
                dismiss()
            }
        }
    }

    private func toggleMap() {
        Task {
            await viewModel.fetchEnvironment()
            syncMapPosition(with: viewModel.locationWeather.coordinate)
        }

        withAnimation(.easeOut(duration: 0.20)) {
            isMapExpanded.toggle()
        }
    }

    private func toggleLanguage() {
        viewModel.language = viewModel.language == "zh" ? "en" : "zh"
    }

    private func toggleVoiceMode() {
        viewModel.instrumentalOnly.toggle()
    }

    private func syncMapPosition(with coordinate: CLLocationCoordinate2D?) {
        guard let coordinate else { return }

        mapPosition = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        )
    }
}

private struct MemoryComposerCompactDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        min(max(context.maxDetentValue * 0.66, 500), 580)
    }
}

private enum MemoryComposerPalette {
    static let accent = Color(uiColor: .systemIndigo)
}

private struct MemoryComposerTheme {
    let colorScheme: ColorScheme

    var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.92) : Color.black.opacity(0.84)
    }

    var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color.black.opacity(0.44)
    }

    var tertiaryText: Color {
        colorScheme == .dark ? .white.opacity(0.42) : Color.black.opacity(0.32)
    }

    var iconTint: Color {
        colorScheme == .dark ? .white.opacity(0.86) : Color.black.opacity(0.84)
    }

    var cameraTint: Color {
        colorScheme == .dark ? .white.opacity(0.70) : Color.black.opacity(0.68)
    }

    var inputFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.78)
    }

    var fallbackInputFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.94)
    }

    var inputBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.04)
    }

    var mapBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    var placeholderFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.05)
    }

    var placeholderIcon: Color {
        colorScheme == .dark ? .white.opacity(0.34) : Color.black.opacity(0.34)
    }

    var avatarFallbackFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    var avatarFallbackIcon: Color {
        colorScheme == .dark ? .white.opacity(0.44) : Color.black.opacity(0.42)
    }

    var footerChipFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }
}

private struct MemoryComposerInputBar: View {
    let contentWidth: CGFloat
    @Binding var prompt: String
    let placeholder: String
    @FocusState.Binding var isPromptFocused: Bool
    let isGenerating: Bool
    let hasSelectedImage: Bool
    let onTakePhoto: () -> Void
    let onChooseFromLibrary: () -> Void
    let onRemoveImage: () -> Void
    let onGenerateTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MemoryComposerTheme { MemoryComposerTheme(colorScheme: colorScheme) }
    private let inputHeight: CGFloat = 56
    private let inputCornerRadius: CGFloat = 28

    private var barShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: inputCornerRadius, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                Button("Take Photo", action: onTakePhoto)
                Button("Choose from Library", action: onChooseFromLibrary)

                if hasSelectedImage {
                    Button("Remove Current Photo", role: .destructive, action: onRemoveImage)
                }
            } label: {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(hasSelectedImage ? MemoryComposerPalette.accent : theme.cameraTint)
                    .frame(width: 46, height: inputHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ZStack(alignment: .leading) {
                if prompt.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                        .padding(.leading, 4)
                        .padding(.trailing, 4)
                        .allowsHitTesting(false)
                }

                TextField("", text: $prompt)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(theme.primaryText)
                    .focused($isPromptFocused)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(false)
                    .submitLabel(.go)
                    .onSubmit(onGenerateTap)
                    .padding(.leading, 4)
            }

            Spacer(minLength: 0)

            Button(action: onGenerateTap) {
                Circle()
                    .fill(isGenerating ? MemoryComposerPalette.accent : MemoryComposerPalette.accent.opacity(0.16))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Circle()
                            .stroke(MemoryComposerPalette.accent.opacity(isGenerating ? 0 : 0.22), lineWidth: 0.8)
                    }
                    .overlay {
                        if isGenerating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "music.note")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(MemoryComposerPalette.accent.opacity(0.96))
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
            .opacity(isGenerating ? 0.72 : 1)
            .padding(.trailing, 2)
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(width: contentWidth)
        .frame(height: inputHeight)
        .background {
            if #available(iOS 26, *) {
                barShape
                    .fill(theme.inputFill)
                    .glassEffect(.clear, in: .rect(cornerRadius: inputCornerRadius))
            } else {
                barShape
                    .fill(theme.fallbackInputFill)
            }
        }
        .overlay {
            barShape
                .stroke(theme.inputBorder, lineWidth: 0.5)
        }
    }
}

private struct MemoryComposerControlStrip: View {
    let contentWidth: CGFloat
    let currentLanguage: String
    let instrumentalOnly: Bool
    let healthEnabled: Bool
    let locationLabel: String
    let isLocationExpanded: Bool
    let onLanguageToggle: () -> Void
    let onVoiceToggle: () -> Void
    let onHealthTap: () -> Void
    let onLocationTap: () -> Void

    private var vocalLabel: String {
        instrumentalOnly ? "Instrumental" : "Vocal"
    }

    var body: some View {
        VStack(spacing: 28) {
            HStack(alignment: .top, spacing: 0) {
                MemoryComposerControlSlot {
                    MemoryComposerLanguageControl(
                        language: currentLanguage,
                        label: "Language",
                        action: onLanguageToggle
                    )
                }
                MemoryComposerControlSlot {
                    MemoryComposerSymbolControl(
                        symbolName: instrumentalOnly ? "mic.slash" : "mic.fill",
                        iconSize: 30,
                        label: vocalLabel,
                        labelLineLimit: 1,
                        labelFontSize: 12,
                        accessibilityLabel: vocalLabel,
                        action: onVoiceToggle
                    )
                }
                MemoryComposerControlSlot {
                    MemoryComposerSymbolControl(
                        symbolName: healthEnabled ? "heart.text.square.fill" : "heart.text.square",
                        iconSize: 30,
                        label: "Health",
                        labelLineLimit: 1,
                        labelFontSize: 12,
                        accessibilityLabel: "Health Data",
                        action: onHealthTap
                    )
                }
            }
            .frame(width: contentWidth)

            MemoryComposerSymbolControl(
                symbolName: "globe.europe.africa.fill",
                iconSize: 31,
                label: locationLabel,
                labelLineLimit: isLocationExpanded ? 2 : 1,
                labelFontSize: isLocationExpanded ? 11 : 12,
                accessibilityLabel: "Location",
                action: onLocationTap,
                width: isLocationExpanded ? 154 : 118
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MemoryComposerControlSlot<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 66)
    }
}

private struct MemoryComposerLabeledControl<Content: View>: View {
    let label: String
    let labelLineLimit: Int
    let labelFontSize: CGFloat
    let width: CGFloat
    let action: () -> Void
    let accessibilityLabel: String
    let accessibilityValue: String?
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    private var theme: MemoryComposerTheme { MemoryComposerTheme(colorScheme: colorScheme) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                content()
                    .frame(width: 64, height: 64)

                Text(label)
                    .font(.system(size: labelFontSize, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(labelLineLimit)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue ?? "")
    }
}

private struct MemoryComposerLanguageControl: View {
    let language: String
    let label: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: MemoryComposerTheme { MemoryComposerTheme(colorScheme: colorScheme) }

    var body: some View {
        MemoryComposerLabeledControl(
            label: label,
            labelLineLimit: 1,
            labelFontSize: 12,
            width: 102,
            action: action,
            accessibilityLabel: "Language",
            accessibilityValue: language == "zh" ? "Chinese" : "English"
        ) {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottomTrailing) {
                    outlineBubble
                        .offset(x: -4, y: -1)

                    filledBubble
                        .offset(x: 6, y: 4)
                }
                .frame(width: 42, height: 31, alignment: .center)

                Text(language == "zh" ? "中" : "EN")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(height: 16)
                    .background(
                        Capsule(style: .continuous)
                            .fill(MemoryComposerPalette.accent)
                    )
                    .offset(x: 8, y: -5)
            }
            .frame(width: 46, height: 34, alignment: .center)
        }
    }

    private var outlineBubble: some View {
        ZStack {
            Image(systemName: "bubble.left")
                .resizable()
                .scaledToFit()
                .frame(width: 27, height: 22)
                .foregroundStyle(theme.iconTint)

            Text("A")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.iconTint)
                .offset(x: -0.2, y: 0)
        }
        .frame(width: 27, height: 22)
    }

    private var filledBubble: some View {
        ZStack {
            Image(systemName: "bubble.left.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 21)
                .foregroundStyle(theme.iconTint)

            Text("文")
                .font(.system(size: 9.4, weight: .bold, design: .rounded))
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                .offset(x: -0.1, y: 0)
        }
        .frame(width: 25, height: 21)
    }
}

private struct MemoryComposerSymbolControl: View {
    let symbolName: String
    let iconSize: CGFloat
    let label: String
    let labelLineLimit: Int
    let labelFontSize: CGFloat
    let accessibilityLabel: String
    let action: () -> Void
    var width: CGFloat = 98

    @Environment(\.colorScheme) private var colorScheme
    private var theme: MemoryComposerTheme { MemoryComposerTheme(colorScheme: colorScheme) }

    var body: some View {
        MemoryComposerLabeledControl(
            label: label,
            labelLineLimit: labelLineLimit,
            labelFontSize: labelFontSize,
            width: width,
            action: action,
            accessibilityLabel: accessibilityLabel,
            accessibilityValue: nil
        ) {
            Image(systemName: symbolName)
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(theme.iconTint)
        }
    }
}

private struct MemoryComposerMapPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: MemoryComposerTheme { MemoryComposerTheme(colorScheme: colorScheme) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.placeholderFill)

            Image(systemName: "location.slash")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(theme.placeholderIcon)
        }
    }
}

private struct MemoryComposerIdentitySection: View {
    let avatarImage: UIImage?
    let title: String
    let name: String
    let isLowered: Bool

    @Environment(\.colorScheme) private var colorScheme
    private var theme: MemoryComposerTheme { MemoryComposerTheme(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let avatarImage {
                    Image(uiImage: avatarImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Circle()
                        .fill(theme.avatarFallbackFill)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 26, weight: .regular))
                                .foregroundStyle(theme.avatarFallbackIcon)
                        }
                }
            }
            .frame(width: isLowered ? 62 : 72, height: isLowered ? 62 : 72)
            .clipShape(Circle())

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.secondaryText)

                Text(name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .offset(y: isLowered ? 4 : 0)
    }
}

private struct MemoryComposerContextFooter: View {
    let dateText: String
    let timeText: String
    let isLowered: Bool

    var body: some View {
        HStack(spacing: 8) {
            MemoryComposerContextChip(text: dateText)
            MemoryComposerContextChip(text: timeText)
        }
        .frame(maxWidth: .infinity)
        .offset(y: isLowered ? 4.4 : 0)
    }
}

private struct MemoryComposerContextChip: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme
    private var theme: MemoryComposerTheme { MemoryComposerTheme(colorScheme: colorScheme) }

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.footerChipFill)
            )
    }
}

private struct MemoryHealthAccessSheet: View {
    @ObservedObject var viewModel: MemoryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Source") {
                    Label("Apple Health", systemImage: "heart.text.square.fill")
                    Text("Memories reads the latest heart rate and heart rate variability samples that Apple Health already stores on this device.")
                        .foregroundStyle(.secondary)
                }

                Section("How It Is Used") {
                    Text("These signals help infer a calmer or more activated musical direction for the generated track.")
                        .foregroundStyle(.secondary)
                }

                if viewModel.healthAuthorized || viewModel.heartRate != nil || viewModel.hrv != nil {
                    Section("Current Status") {
                        Label(viewModel.healthAuthorized ? "Access Allowed" : "Access Pending", systemImage: viewModel.healthAuthorized ? "checkmark.circle.fill" : "clock")
                        if let heartRate = viewModel.heartRate {
                            Text("Heart rate: \(Int(heartRate.rounded())) bpm")
                        }
                        if let hrv = viewModel.hrv {
                            Text("HRV: \(Int(hrv.rounded())) ms")
                        }
                    }
                }
            }
            .navigationTitle("Health Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.usePsychologicalProfile ? "Refresh" : "Allow") {
                        Task {
                            viewModel.usePsychologicalProfile = true
                            await viewModel.requestHealthAccess()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    MemoryComposerSheet(viewModel: MemoryViewModel(), profileViewModel: ProfileViewModel())
}
