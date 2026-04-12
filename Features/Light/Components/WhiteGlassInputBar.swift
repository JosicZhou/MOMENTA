//玻璃感输入框

import SwiftUI
import UIKit

struct WhiteGlassInputBar: View {
    @Binding var prompt: String
    var isTextFieldFocused: FocusState<Bool>.Binding
    let hasSelectedImage: Bool
    let isGenerating: Bool
    let hasVocals: Bool
    let selectedInstrument: String
    let useAIRecommendation: Bool
    let onCameraPress: () -> Void
    let onPhotoPress: () -> Void
    let onVocalsChange: (Bool) -> Void
    let onInstrumentSelect: (String) -> Void
    let onAIToggle: () -> Void
    let onGeneratePress: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let instrumentOptions = ["Piano", "Synth", "Guitar", "Strings", "Drums"]

    private var canGenerate: Bool {
        !(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasSelectedImage) && !isGenerating
    }

    private var instrumentSelection: Binding<String> {
        Binding(
            get: { selectedInstrument },
            set: { onInstrumentSelect($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                LightComposerCameraButton(
                    hasSelectedImage: hasSelectedImage,
                    onTap: {
                        onCameraPress()
                    },
                    onLongPress: onPhotoPress
                )

                Button {
                    onVocalsChange(!hasVocals)
                } label: {
                    LightComposerOptionButton(
                        systemName: hasVocals ? "mic.fill" : "mic.slash",
                        isHighlighted: hasVocals
                    )
                }
                .buttonStyle(LightComposerIconButtonStyle())

                LightComposerInstrumentMenu(
                    selectedInstrument: selectedInstrument,
                    instrumentOptions: instrumentOptions,
                    selection: instrumentSelection
                )

                Button {
                    onAIToggle()
                } label: {
                    LightComposerOptionButton(
                        content: {
                            IntelligenceGlyph(
                                size: 14,
                                color: useAIRecommendation ? Color(uiColor: .systemIndigo) : Color.black.opacity(0.56)
                            )
                        },
                        isHighlighted: useAIRecommendation
                    )
                }
                .buttonStyle(LightComposerIconButtonStyle())

                Spacer(minLength: 0)

                Button(action: {
                    isTextFieldFocused.wrappedValue = false
                    onGeneratePress()
                }) {
                    LightComposerSubmitButton()
                }
                .disabled(!canGenerate)
                .opacity(canGenerate ? 1 : 0.42)
            }
            .padding(.leading, -4)
            .padding(.bottom, 1)
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

private struct LightComposerCameraButton: View {
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
            LightComposerOptionButton(
                systemName: "camera.aperture",
                isHighlighted: hasSelectedImage
            )
        }
        .buttonStyle(LightComposerIconButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    didTriggerLongPress = true
                    onLongPress()
                }
        )
    }
}

private struct LightComposerIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct LightComposerInstrumentMenu: View {
    let selectedInstrument: String
    let instrumentOptions: [String]
    let selection: Binding<String>

    var body: some View {
        Menu {
            Picker("Instrument", selection: selection) {
                Text("No Music Preference")
                    .tag("")

                ForEach(instrumentOptions, id: \.self) { option in
                    Text(option)
                        .tag(option)
                }
            }
        } label: {
            LightComposerOptionButton(
                systemName: "music.note.list",
                isHighlighted: !selectedInstrument.isEmpty
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(LightComposerIconButtonStyle())
        .accessibilityLabel("Instrument")
        .accessibilityValue(selectedInstrument.isEmpty ? "No Music Preference" : selectedInstrument)
    }
}

private struct LightComposerOptionButton<Content: View>: View {
    let content: Content
    let isHighlighted: Bool

    init(systemName: String, isHighlighted: Bool = false) where Content == Image {
        self.content = Image(systemName: systemName)
        self.isHighlighted = isHighlighted
    }

    init(@ViewBuilder content: () -> Content, isHighlighted: Bool = false) {
        self.content = content()
        self.isHighlighted = isHighlighted
    }

    var body: some View {
        content
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isHighlighted ? Color(uiColor: .systemIndigo) : Color.black.opacity(0.58))
            .frame(width: 30, height: 22)
            .contentShape(Rectangle())
    }
}

private struct LightComposerSubmitButton: View {
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
                            .tint(Color(uiColor: .systemIndigo))
                            .interactive(),
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
