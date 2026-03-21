//
//  LightView.swift
//  Light 功能模块的主视图 - 已进行组件化重构
//

import SwiftUI
import AVFoundation

struct LightView: View {
    @ObservedObject var viewModel: LightViewModel
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景图片 - 沙漠背景
                Image("desert_background")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea()

                // 用 ScrollView 让系统检测到可滚动区域，底部栏自动变通透
                ScrollView {
                    // 内容区域（最小高度 = 屏幕高度，保持原有 Spacer 布局）
                    VStack(spacing: 0) {
                        // 顶部文字区域
                        WelcomeCard(
                            userName: "JOSIC",
                            isGenerating: viewModel.isGenerating,
                            isRefreshingWeather: viewModel.isRefreshingWeather,
                            weatherSymbolName: viewModel.weatherSymbolName,
                            onWeatherTap: {
                                viewModel.refreshWeather()
                            },
                            onDateTap: {
                                // 跳转系统日历
                                if let url = URL(string: "calshow://") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        )
                        
                        Spacer()
                            .frame(maxHeight: viewModel.selectedImage != nil ? 60 : 120)
                        
                        // 图片预览
                        if let image = viewModel.selectedImage {
                            ImagePreview(image: image) {
                                viewModel.removeImage()
                            }
                            .frame(width: 200, height: 200)
                            .padding(.bottom, 12)
                        }
                        
                        // 输入框 (组件化)
                        WhiteGlassInputBar(
                            prompt: $viewModel.prompt,
                            isTextFieldFocused: $isInputFocused,
                            hasSelectedImage: viewModel.selectedImage != nil,
                            isGenerating: viewModel.isGenerating,
                            onCameraPress: { viewModel.openCamera() },
                            onPhotoPress: { viewModel.openPhotoLibrary() },
                            onGeneratePress: {
                                Task { await viewModel.generateMusic() }
                            }
                        )
                        .frame(width: 340, height: 50)
                        
                        // 预设卡片 (组件化)
                        HStack(spacing: 6) {
                            PresetCard(
                                title: "It's a\nthunderbolt day.",
                                icon: "cloud.bolt",
                                width: 89,
                                action: {
                                    viewModel.prompt = "It's a thunderbolt day."
                                }
                            )
                            
                            PresetCard(
                                title: "Play some Piano.",
                                icon: "pianokeys",
                                width: 101,
                                action: {
                                    viewModel.prompt = "Play some Piano."
                                }
                            )
                            
                            PresetCard(
                                title: "Today's my pet's birthday.",
                                icon: "dog",
                                width: 129,
                                action: {
                                    viewModel.prompt = "Today's my pet's birthday."
                                }
                            )
                        }
                        .frame(height: 95)
                        .padding(.top, 10)
                        .padding(.bottom, 100)
                    }
                    .frame(maxWidth: 390)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                    .padding(.horizontal, 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isInputFocused = false
                    }
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .ignoresSafeArea()
    }
}
