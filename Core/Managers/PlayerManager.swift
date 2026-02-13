//
//  PlayerManager.swift
//  MOMENTA
//
//  播放器全局状态管理：管理 AVPlayer 实例、播放进度追踪、展开/折叠 UI 状态。
//  从 LightViewModel 中抽离播放逻辑，通过 .environment() 注入子视图。
//

import SwiftUI
import AVFoundation

@Observable
@MainActor
final class PlayerManager {
    
    // MARK: - UI 状态
    
    /// 播放器是否展开为全屏
    var isExpanded: Bool = false
    /// 下拉手势偏移量
    var dragOffset: CGFloat = .zero
    
    // MARK: - 播放状态
    
    /// 是否正在播放
    var isPlaying: Bool = false
    /// 当前播放的音乐
    var currentMusic: GeneratedMusic?
    /// 播放进度 (0.0 ~ 1.0)
    var playbackProgress: Double = 0
    /// 当前播放时间（秒）
    var currentTime: TimeInterval = 0
    /// 总时长（秒）
    var totalDuration: TimeInterval = 0
    
    // MARK: - 歌词状态
    
    /// 是否显示歌词模式（vs 专辑封面模式）
    var showLyrics: Bool = false
    /// 解析后的时间戳歌词
    var lyrics: [LyricLine] = []
    /// 当前高亮的歌词行索引
    var currentLineIndex: Int = 0
    /// 是否正在加载歌词
    var isLoadingLyrics: Bool = false
    /// 歌词模式下底部控件是否可见（滚动方向控制：向下隐藏，向上/停止显示）
    var lyricsControlsVisible: Bool = true
    
    // MARK: - 私有
    
    private var audioPlayer: AVPlayer?
    private var timeObserver: Any?
    private let sunoService = SunoDirectService()
    
    // MARK: - 播放控制
    
    func play() {
        guard let music = currentMusic, let audioURL = music.audioURL else { return }
        
        // 配置音频会话
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ [PlayerManager] 设置音频会话失败: \(error.localizedDescription)")
        }
        
        // 如果 URL 变了或 player 不存在，重新创建
        let currentURL = (audioPlayer?.currentItem?.asset as? AVURLAsset)?.url
        if audioPlayer == nil || currentURL != audioURL {
            removeProgressTracking()
            audioPlayer = AVPlayer(url: audioURL)
        }
        
        audioPlayer?.play()
        isPlaying = true
        startProgressTracking()
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
    }
    
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    /// 跳转到指定进度 (0.0 ~ 1.0)
    func seek(to progress: Double) {
        guard let player = audioPlayer,
              let duration = player.currentItem?.duration,
              duration.seconds.isFinite, duration.seconds > 0 else { return }
        
        let targetTime = CMTime(seconds: duration.seconds * progress, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        
        // 立即更新 UI
        let newTime = duration.seconds * progress
        currentTime = newTime
        playbackProgress = progress
        
        // 立即更新歌词行索引，不等待 0.5s 定时器
        if !lyrics.isEmpty {
            let newIndex = lyrics.lastIndex(where: { $0.startTime <= newTime }) ?? 0
            if newIndex != currentLineIndex {
                currentLineIndex = newIndex
            }
        }
    }
    
    // MARK: - 进度追踪
    
    private func startProgressTracking() {
        removeProgressTracking()
        guard let player = audioPlayer else { return }
        
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self = self,
                      let duration = self.audioPlayer?.currentItem?.duration,
                      duration.seconds.isFinite, duration.seconds > 0 else { return }
                
                self.currentTime = time.seconds
                self.totalDuration = duration.seconds
                self.playbackProgress = time.seconds / duration.seconds
                
                // 更新当前歌词行索引
                if !self.lyrics.isEmpty {
                    let newIndex = self.lyrics.lastIndex(where: { $0.startTime <= time.seconds }) ?? 0
                    if newIndex != self.currentLineIndex {
                        self.currentLineIndex = newIndex
                    }
                }
            }
        }
    }
    
    private func removeProgressTracking() {
        if let observer = timeObserver {
            audioPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    // MARK: - 歌词加载
    
    /// 从 Suno API 获取时间戳歌词；失败时降级为纯文本歌词。
    /// 当 sunoAudioId 不可用时，先通过 record-info API 查询正确的 audioId。
    func fetchLyrics() async {
        guard let music = currentMusic else { return }
        // 如果已经加载过，不重复请求
        if !lyrics.isEmpty { return }
        
        isLoadingLyrics = true
        
        // 第一步：确保拿到正确的 audioId
        // sunoAudioId 可能为 nil（Realtime 路径下 payload 未包含）
        // 此时通过 getTaskStatus(record-info) API 实时获取
        var audioId = music.sunoAudioId
        if audioId == nil {
            do {
                print("🔍 [PlayerManager] sunoAudioId 为空，通过 record-info 查询...")
                let statusResponse = try await sunoService.getTaskStatus(taskId: music.id)
                audioId = statusResponse.data?.response?.sunoData?.first?.id
                if let aid = audioId {
                    print("✅ [PlayerManager] 获取到 audioId: \(aid)")
                } else {
                    print("⚠️ [PlayerManager] record-info 未返回 sunoData.id")
                }
            } catch {
                print("⚠️ [PlayerManager] 查询 audioId 失败: \(error.localizedDescription)")
            }
        }
        
        // 第二步：用正确的 taskId + audioId 调用时间戳歌词 API
        if let audioId = audioId {
            do {
                let lines = try await sunoService.getTimestampedLyrics(
                    taskId: music.id,
                    audioId: audioId
                )
                if !lines.isEmpty {
                    lyrics = lines
                    isLoadingLyrics = false
                    return
                }
            } catch {
                print("⚠️ [PlayerManager] 时间戳歌词获取失败: \(error.localizedDescription)")
            }
        }
        
        // 第三步：所有 API 路径失败，降级为纯文本歌词
        print("📝 [PlayerManager] 降级为纯文本歌词")
        lyrics = LyricLine.parseFromPlainText(music.prompt, totalDuration: totalDuration)
        isLoadingLyrics = false
    }
    
    // MARK: - 清理
    
    func reset() {
        pause()
        removeProgressTracking()
        audioPlayer = nil
        currentMusic = nil
        playbackProgress = 0
        currentTime = 0
        totalDuration = 0
        isExpanded = false
        dragOffset = .zero
        showLyrics = false
        lyrics = []
        currentLineIndex = 0
        lyricsControlsVisible = true
    }
}
