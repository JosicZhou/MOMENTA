//
//  CustomProgressBar.swift
//  MOMENTA
//
//  Apple Music 风格可拖拽进度条：默认 4pt 细线，拖拽时膨胀到 7pt。
//  使用 GeometryReader 自适应宽度，Capsule 圆角端点。
//

import SwiftUI

struct CustomProgressBar: View {
    /// 当前播放进度 (0.0 ~ 1.0)
    let progress: Double
    /// 拖拽结束后的回调，返回 0.0 ~ 1.0 的目标进度
    var onSeek: ((Double) -> Void)?
    
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    
    /// 轨道高度：默认 4pt，拖拽时 7pt
    private var trackHeight: CGFloat { isDragging ? 7 : 4 }
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let currentProgress = isDragging ? dragProgress : progress
            
            ZStack(alignment: .leading) {
                // 轨道背景
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(height: trackHeight)
                
                // 已播放部分
                Capsule()
                    .fill(Color.primary.opacity(0.9))
                    .frame(
                        width: max(trackHeight, width * CGFloat(currentProgress)),
                        height: trackHeight
                    )
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        dragProgress = min(max(0, value.location.x / width), 1.0)
                    }
                    .onEnded { value in
                        let finalProgress = min(max(0, value.location.x / width), 1.0)
                        onSeek?(finalProgress)
                        isDragging = false
                    }
            )
            .animation(.easeOut(duration: 0.15), value: isDragging)
            .animation(.linear(duration: 0.3), value: progress)
        }
        .frame(height: 20) // 热区高度
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 40) {
            CustomProgressBar(progress: 0.3)
                .padding(.horizontal, 24)
            
            CustomProgressBar(progress: 0.7)
                .padding(.horizontal, 24)
        }
    }
}
