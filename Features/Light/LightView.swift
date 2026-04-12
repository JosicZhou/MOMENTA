//
//  LightView.swift
//  Light 功能模块的主视图 - 已进行组件化重构
//

import SwiftUI
import AVFoundation
import UIKit

struct LightView: View {
    @ObservedObject var viewModel: LightViewModel
    @FocusState private var isInputFocused: Bool

    private var resolvedName: String {
        let fullName = ProfileIdentityStore.resolvedDisplayName(email: AuthService.shared.currentUser?.email)
        return fullName
            .split(separator: " ")
            .first
            .map(String.init) ?? fullName
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = min(340.0, proxy.size.width - 40)
            let topPadding = proxy.safeAreaInsets.top + 24
            let headerToPromptSpacing = max(52, proxy.size.height * 0.13)
            let promptToComposerSpacing = max(34, proxy.size.height * 0.075)
            let lowerInset = max(proxy.safeAreaInsets.bottom + 88, 108)

            ZStack {
                Color(uiColor: .systemGray6)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    WelcomeCard(
                        userName: resolvedName,
                        isGenerating: viewModel.isGenerating,
                        isRefreshingWeather: viewModel.isRefreshingWeather,
                        weatherSymbolName: viewModel.weatherSymbolName,
                        onWeatherTap: {
                            viewModel.refreshWeather()
                        },
                        onDateTap: {
                            if let url = URL(string: "calshow://") {
                                UIApplication.shared.open(url)
                            }
                        }
                    )
                    .frame(width: contentWidth)
                    .padding(.top, topPadding)

                    Spacer(minLength: headerToPromptSpacing)

                    LightCenterPrompt()
                        .frame(width: contentWidth)

                    Spacer(minLength: promptToComposerSpacing)

                    WhiteGlassInputBar(
                        prompt: $viewModel.prompt,
                        isTextFieldFocused: $isInputFocused,
                        hasSelectedImage: viewModel.selectedImage != nil,
                        isGenerating: viewModel.isGenerating,
                        hasVocals: viewModel.hasVocals,
                        selectedInstrument: viewModel.instrument,
                        useAIRecommendation: viewModel.useAIRecommendation,
                        onCameraPress: { viewModel.openCamera() },
                        onPhotoPress: { viewModel.openPhotoLibrary() },
                        onVocalsChange: { viewModel.hasVocals = $0 },
                        onInstrumentSelect: { viewModel.instrument = $0 },
                        onAIToggle: { viewModel.useAIRecommendation.toggle() },
                        onGeneratePress: {
                            Task { await viewModel.generateMusic() }
                        }
                    )
                    .frame(width: contentWidth)

                    HStack(spacing: 9) {
                        PresetCard(
                            title: "Today's my pet's birthday",
                            icon: "dog.fill",
                            action: {
                                viewModel.prompt = "Today's my pet's birthday."
                            }
                        )

                        PresetCard(
                            title: "It's a raining day.",
                            icon: "cloud.rain",
                            action: {
                                viewModel.prompt = "It's a raining day."
                            }
                        )

                        PresetCard(
                            title: "Play some piano.",
                            icon: "pianokeys",
                            action: {
                                viewModel.prompt = "Play some piano."
                            }
                        )
                    }
                    .frame(width: contentWidth)
                    .padding(.top, 12)

                    Spacer(minLength: lowerInset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .onTapGesture {
                    isInputFocused = false
                }
            }
        }
    }
}

private struct LightCenterPrompt: View {
    var body: some View {
        VStack(spacing: 14) {
            IntelligenceGlyph(size: 24, color: Color(uiColor: .systemIndigo))

            VStack(spacing: 4) {
                Text("Create with MOMENTA MUSIC.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)

                Text("Let your personal context be your melody.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct IntelligenceGlyph: View {
    let size: CGFloat
    let color: Color

    private var symbolName: String {
        UIImage(systemName: "apple.intelligence") == nil ? "sparkles" : "apple.intelligence"
    }

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(color)
    }
}
