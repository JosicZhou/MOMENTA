//
//  LightView.swift
//  Butterfly
//
//  Light 功能模块的主视图 - 已进行组件化重构
//

import SwiftUI
import AVFoundation

struct LightView: View {
    @ObservedObject var viewModel: LightViewModel
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景图片
                AsyncImage(url: URL(string: "https://images.unsplash.com/photo-1513569771920-c9e1d31714af?ixid=M3w4OTk0OHwwfDF8c2VhcmNofDh8fGRhcmt8ZW58MHx8fHwxNzYyOTY0Mjg4fDA&ixlib=rb-4.1.0")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    case .failure(_):
                        Color.black
                    case .empty:
                        Color.black
                    @unknown default:
                        Color.black
                    }
                }
                .ignoresSafeArea()
                
                // 内容区域
                VStack(spacing: 0) {
                    // 顶部文字区域
                    VStack(alignment: .leading, spacing: 0) {
                        Text("WELCOME,JOSIC")
                            .font(.systemExpanded(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                            .tracking(0.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 49)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Wednesday")
                                .font(.systemExpanded(size: 18, weight: .ultraLight))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            
                            Text("Thunderbolt")
                                .font(.systemExpanded(size: 18, weight: .ultraLight))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .padding(.top, 3)
                        
                        Image(systemName: viewModel.isGenerating ? "cloud.bolt.rain.fill" : "cloud.bolt.rain")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 46)
                            .padding(.top, 3)
                            .symbolEffect(.pulse, isActive: viewModel.isGenerating)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
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
                .padding(.horizontal, 20)
                
                // 加载动画 (组件化)
                if viewModel.isGenerating {
                    AILoadingView(progress: viewModel.generationProgress)
                }
            }
        }
        .ignoresSafeArea()
        .safeAreaInset(edge: .bottom) {
            if let music = viewModel.generatedMusic {
                MusicPlayerBar(
                    music: music,
                    isPlaying: viewModel.isPlaying,
                    onPlayPause: viewModel.togglePlayback
                )
                .frame(maxWidth: 390)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .background(Color.clear)
            } else {
                Color.clear.frame(height: 0)
            }
        }
    }
}
