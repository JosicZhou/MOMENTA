//
//  LyricsScrollView.swift
//  MOMENTA
//
//  Apple Music 风格同步滚动歌词视图。
//  当前行白色粗体清晰，其他行灰色模糊，自动跟随播放进度滚动。
//  用户手动滚动时暂停自动滚动，3 秒后恢复。
//  向下滚动隐藏底部控件，向上滚动或停止滚动后重新显示。
//  参考：https://github.com/HuangRunHua/Apple-Music-Lyric-Animation
//

import SwiftUI

struct LyricsScrollView: View {
    
    @Environment(PlayerManager.self) private var playerManager
    
    /// 用户是否正在手动滚动（暂停自动滚动）
    @State private var isUserScrolling = false
    /// 上一次自动滚动触发的时间，用于区分用户滚动和程序滚动
    @State private var lastAutoScrollTime: Date = .distantPast
    /// 用户滚动恢复计时器
    @State private var scrollResetTask: Task<Void, Never>?
    /// 上一次检测到的滚动偏移，用于计算滚动方向
    @State private var lastScrollOffset: CGFloat = 0
    
    private let lyricAnimation = Animation.spring(response: 0.42, dampingFraction: 0.9)
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    // 顶部留白，让第一句歌词不贴顶
                    Spacer().frame(height: 34)
                    
                    ForEach(Array(playerManager.lyrics.enumerated()), id: \.element.id) { index, line in
                        lyricLineView(line: line, index: index)
                            .id(line.id)
                    }
                    
                    // 底部留白：需要足够空间让歌词滚到浮动控件上方
                    Spacer().frame(height: 300)
                }
                .padding(.top, 8)
                .background(scrollDetector)
            }
            .coordinateSpace(name: "lyricsScroll")
            // 当 currentLineIndex 变化时自动滚动
            .onChange(of: playerManager.currentLineIndex) { _, newIndex in
                guard !isUserScrolling,
                      newIndex >= 0,
                      newIndex < playerManager.lyrics.count else { return }
                
                lastAutoScrollTime = Date()
                withAnimation(.easeInOut(duration: 0.6)) {
                    // anchor 约 1/3 处，让当前行显示在上方，下方留出预览空间（Apple Music 风格）
                    proxy.scrollTo(playerManager.lyrics[newIndex].id, anchor: UnitPoint(x: 0.5, y: 0.35))
                }
            }
        }
    }
    
    // MARK: - 单行歌词视图
    
    @ViewBuilder
    private func lyricLineView(line: LyricLine, index: Int) -> some View {
        let isCurrent = index == playerManager.currentLineIndex
        
        if line.isSection {
            // 段落标记：小号、半透明、不模糊
            Text(line.text.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: ""))
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.3))
                .textCase(.uppercase)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 8)
        } else {
            Text(line.text)
                .font(.system(size: isCurrent ? 31 : 24, weight: isCurrent ? .semibold : .medium))
                .foregroundColor(.white.opacity(isCurrent ? 0.98 : 0.32))
                .scaleEffect(isCurrent ? 1.0 : 0.96, anchor: .leading)
                .offset(y: isCurrent ? 0 : -1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .animation(lyricAnimation, value: playerManager.currentLineIndex)
        }
    }
    
    // MARK: - 滚动检测
    
    /// 通过 GeometryReader + PreferenceKey 检测用户手动滚动及方向
    private var scrollDetector: some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: geo.frame(in: .named("lyricsScroll")).minY
                )
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { newOffset in
            handleScrollChange(newOffset: newOffset)
        }
    }
    
    /// 当检测到滚动偏移变化时调用
    private func handleScrollChange(newOffset: CGFloat) {
        // 如果是程序触发的自动滚动（0.8 秒内），仅更新 offset 但不处理
        if Date().timeIntervalSince(lastAutoScrollTime) < 0.8 {
            lastScrollOffset = newOffset
            return
        }
        
        // 计算滚动方向
        let delta = newOffset - lastScrollOffset
        lastScrollOffset = newOffset
        
        // delta > 5 → 用户向上滚动（内容向下移动）→ 显示控件
        // delta < -5 → 用户向下滚动（内容向上移动）→ 隐藏控件
        if delta > 5 {
            if !playerManager.lyricsControlsVisible {
                withAnimation(.easeInOut(duration: 0.25)) {
                    playerManager.lyricsControlsVisible = true
                }
            }
        } else if delta < -5 {
            if playerManager.lyricsControlsVisible {
                withAnimation(.easeInOut(duration: 0.25)) {
                    playerManager.lyricsControlsVisible = false
                }
            }
        }
        
        // 标记为用户滚动
        isUserScrolling = true
        
        // 取消之前的恢复计时
        scrollResetTask?.cancel()
        
        // 3 秒后恢复自动滚动 + 重新显示控件
        scrollResetTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                isUserScrolling = false
                withAnimation(.easeInOut(duration: 0.3)) {
                    playerManager.lyricsControlsVisible = true
                }
            }
        }
    }
}

// MARK: - ScrollOffset PreferenceKey

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
