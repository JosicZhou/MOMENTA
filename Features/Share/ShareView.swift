//
//  ShareView.swift
//  Butterfly
//

import SwiftUI

struct ShareView: View {
    // 导航到 LightView（测试用）
    @State private var showLightView = false
    // 测试用 ViewModel
    @StateObject private var testViewModel = LightViewModel()

    var body: some View {
        ZStack {
            IridescentBackground()

            // 用 ScrollView 包住前景内容，让系统检测到可滚动区域，底部栏自动变通透
            ScrollView {
                VStack(spacing: 30) {
                    Spacer().frame(height: 120)

                    Image(systemName: "person.2.fill")
                        .font(.system(size: 80, weight: .light))
                        .foregroundStyle(.primary.opacity(0.6))

                    Text("SHARE")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Share your musical creations with friends")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Spacer().frame(height: 300)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            // 迷你播放条（通用组件）
            MusicPlayerBar(
                songTitle: "测试歌曲名称",
                artistName: "Artist Name",
                onPlayPauseTap: {
                    showLightView = true
                },
                onLyricsTap: {
                    showLightView = true
                }
            )
            .padding(.horizontal, 24)
        }
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $showLightView) {
            NavigationStack {
                LightView(viewModel: testViewModel)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("返回") {
                                showLightView = false
                            }
                        }
                    }
            }
        }
    }
}

