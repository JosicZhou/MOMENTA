//
//  ExpandablePlayerContainer.swift
//  MOMENTA
//
//  可展开播放器容器：持有 @Namespace，管理迷你 bar ↔ 全屏播放器的转场动画。
//  参考 leopoldubzq/AppleMusicPlayerAnimation 的 3 层 overlay 模式。
//

import SwiftUI

struct ExpandablePlayerContainer: View {
    
    // MARK: - 外部参数（来自 LightViewModel）
    
    let music: GeneratedMusic?
    let isGenerating: Bool
    let generationProgress: String
    
    // MARK: - 播放器状态
    
    @Environment(PlayerManager.self) private var playerManager
    @Namespace private var animation
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // 占位层：展开时撑满全屏，确保 overlay 有正确的参考尺寸
            Color.clear
                .frame(
                    maxWidth: .infinity,
                    maxHeight: playerManager.isExpanded ? .infinity : 0
                )
                .allowsHitTesting(false)
            
            // 迷你播放条（不展开时显示）
            if !playerManager.isExpanded {
                miniPlayerBar
                    .padding(.bottom, 56) // TabBar 高度
            }
        }
        .overlay {
            // 全屏播放器（展开时覆盖全屏）
            if playerManager.isExpanded {
                MusicPlayerDetails(animation: animation)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.35, extraBounce: 0.04), value: playerManager.isExpanded)
    }
    
    // MARK: - 迷你播放条
    
    private var miniPlayerBar: some View {
        MusicPlayerBar(
            songTitle: music?.title ?? "Creating...",
            artistName: music?.style ?? "",
            imageURL: music?.imageURL,
            progress: generationProgress,
            isGenerating: isGenerating,
            isPlaying: playerManager.isPlaying,
            onPlayPauseTap: {
                playerManager.togglePlayback()
            },
            onLyricsTap: nil,
            onTap: isGenerating ? nil : {
                // 触觉反馈
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                
                withAnimation(.snappy(duration: 0.35, extraBounce: 0.04)) {
                    playerManager.isExpanded = true
                }
            },
            animation: animation
        )
        .frame(maxWidth: 390)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }
}
