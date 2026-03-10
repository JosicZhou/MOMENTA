//
//  Backgrounds.swift
//  背景效果存放在这；保留了 IridescentBackground（流光背景）之后要改成可定义背景
//

import SwiftUI
import AVKit

// MARK: - 视频背景

struct VideoBackgroundView: View {
    let videoName: String
    @State private var player: AVQueuePlayer?
    @State private var playerLooper: AVPlayerLooper?
    
    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .disabled(true)
            } else {
                IridescentBackground()
            }
            
            Rectangle()
                .fill(.black.opacity(0.3))
                .ignoresSafeArea()
        }
        .onAppear {
            setupVideoPlayer()
        }
        .onDisappear {
            player?.pause()
        }
    }
    
    private func setupVideoPlayer() {
        if let videoURL = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
            setupPlayer(with: videoURL)
        } else {
            // Try different paths if needed
        }
    }
    
    private func setupPlayer(with url: URL) {
        let playerItem = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)
        self.player = queuePlayer
        self.playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
        queuePlayer.play()
        queuePlayer.isMuted = true
    }
}

// MARK: - 城市街景背景

struct CityStreetBackground: View {
    var body: some View {
        ZStack {
            Image("city_street_sunset")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .ignoresSafeArea()
            
            Rectangle()
                .fill(.black.opacity(0.2))
                .ignoresSafeArea()
        }
    }
}

// MARK: - 流光异彩背景

// MARK: - 暗色丝绸背景（Profile 专用）

struct DarkSilkBackground: View {
    @State private var animateWaves = false
    @State private var animateGlow = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 底色：深炭黑到纯黑径向渐变
                RadialGradient(
                    colors: [
                        Color(red: 0.08, green: 0.08, blue: 0.12),
                        Color(red: 0.05, green: 0.05, blue: 0.08),
                        Color(red: 0.02, green: 0.02, blue: 0.05),
                        Color.black
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: animateGlow ? 800 : 500
                )
                .ignoresSafeArea()

                // 微弱紫色光晕（丝绸光泽）
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.15, green: 0.12, blue: 0.20).opacity(0.4),
                                Color(red: 0.10, green: 0.08, blue: 0.15).opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: animateGlow ? 600 : 300
                        )
                    )
                    .blur(radius: animateGlow ? 120 : 80)
                    .scaleEffect(animateGlow ? 1.3 : 0.9)
                    .offset(y: -geometry.size.height * 0.15)

                // 暗色丝绸波纹（椭圆流动）
                ForEach(0..<8, id: \.self) { index in
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.15, green: 0.13, blue: 0.22).opacity(0.3),
                                    Color(red: 0.10, green: 0.08, blue: 0.18).opacity(0.15),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: animateWaves ? 150 : 80
                            )
                        )
                        .frame(
                            width: animateWaves ? 250 : 150,
                            height: animateWaves ? 100 : 50
                        )
                        .position(
                            x: CGFloat.random(in: 0...geometry.size.width),
                            y: CGFloat.random(in: 0...geometry.size.height)
                        )
                        .blur(radius: animateWaves ? 40 : 20)
                        .opacity(animateWaves ? 0.6 : 0.2)
                        .animation(
                            .easeInOut(duration: Double.random(in: 5.0...9.0))
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.5),
                            value: animateWaves
                        )
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) { animateGlow = true }
                withAnimation(.easeInOut(duration: 7.0).repeatForever(autoreverses: true)) { animateWaves = true }
            }
        }
    }
}

// MARK: - 流光异彩背景

struct IridescentBackground: View {
    @State private var animateSunset = false
    @State private var animateWaves = false
    @State private var animateSparkles = false
    @State private var animateGlow = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.4, blue: 0.2),
                        Color(red: 1.0, green: 0.6, blue: 0.3),
                        Color(red: 0.8, green: 0.3, blue: 0.6),
                        Color(red: 0.4, green: 0.1, blue: 0.8),
                        Color(red: 0.1, green: 0.0, blue: 0.3)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: animateSunset ? 1000 : 400
                )
                .ignoresSafeArea()
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.8, blue: 0.4).opacity(0.8),
                                Color(red: 1.0, green: 0.6, blue: 0.2).opacity(0.6),
                                Color(red: 1.0, green: 0.4, blue: 0.1).opacity(0.4),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: animateGlow ? 800 : 300
                        )
                    )
                    .blur(radius: animateGlow ? 150 : 80)
                    .scaleEffect(animateGlow ? 1.4 : 0.9)
                
                ForEach(0..<12, id: \.self) { index in
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.9, blue: 0.6).opacity(0.7),
                                    Color(red: 1.0, green: 0.7, blue: 0.3).opacity(0.5),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: animateWaves ? 120 : 60
                            )
                        )
                        .frame(
                            width: animateWaves ? 200 : 100,
                            height: animateWaves ? 80 : 40
                        )
                        .position(
                            x: CGFloat.random(in: 0...geometry.size.width),
                            y: CGFloat.random(in: 0...geometry.size.height)
                        )
                        .scaleEffect(animateWaves ? 1.3 : 0.7)
                        .opacity(animateWaves ? 0.8 : 0.3)
                        .blur(radius: animateWaves ? 25 : 10)
                        .rotationEffect(.degrees(animateWaves ? Double.random(in: -15...15) : 0))
                        .animation(
                            .easeInOut(duration: Double.random(in: 4.0...8.0))
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.4),
                            value: animateWaves
                        )
                }
                
                ForEach(0..<25, id: \.self) { index in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.95, blue: 0.8).opacity(0.9),
                                    Color(red: 1.0, green: 0.8, blue: 0.4).opacity(0.6),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: animateSparkles ? 20 : 5
                            )
                        )
                        .frame(width: animateSparkles ? 8 : 2, height: animateSparkles ? 8 : 2)
                        .position(
                            x: CGFloat.random(in: 0...geometry.size.width),
                            y: CGFloat.random(in: 0...geometry.size.height)
                        )
                        .scaleEffect(animateSparkles ? 3.0 : 0.5)
                        .opacity(animateSparkles ? 1.0 : 0.2)
                        .blur(radius: animateSparkles ? 2 : 0)
                        .animation(
                            .easeInOut(duration: Double.random(in: 2.0...5.0))
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: animateSparkles
                        )
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) { animateSunset = true }
                withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) { animateWaves = true }
                withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) { animateSparkles = true }
                withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) { animateGlow = true }
            }
        }
    }
}

