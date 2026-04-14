//
//  PlayerManager.swift
//  MOMENTA
//
//  播放器全局状态管理：管理 AVPlayer 实例、播放进度追踪、展开/折叠 UI 状态。
//  从 LightViewModel 中抽离播放逻辑，通过 .environment() 注入子视图。
//

import SwiftUI
import AVFoundation
import MediaPlayer

enum LyricsFollowMode: Equatable {
    case follow
    case browse
}

enum PlaybackSurfaceMode: Equatable {
    case collapsed
    case expandedArtwork
    case expandedLyrics
}

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
    var currentMusic: GeneratedMusic? {
        didSet {
            guard oldValue?.id != currentMusic?.id else { return }
            handleCurrentMusicChanged()
        }
    }
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
    /// 播放器使用的歌词展示模型
    var lyricsPresentation: LyricsPresentationModel = .empty
    /// 当前高亮的歌词行索引
    var currentLineIndex: Int = 0
    /// 是否正在加载歌词
    var isLoadingLyrics: Bool = false
    /// 是否拿到了真实时间戳歌词；否则仅展示全文，不做动态逐行同步。
    var lyricsAreTimeSynced: Bool = false
    /// 歌词模式下底部控件是否可见（滚动方向控制：向下隐藏，向上/停止显示）
    var lyricsControlsVisible: Bool = true
    /// 自动跟随当前歌词，或用户正在手动浏览
    var lyricsFollowMode: LyricsFollowMode = .follow
    
    // MARK: - 私有
    
    private var audioPlayer: AVPlayer?
    private var timeObserver: Any?
    private var lyricsBoundaryObserver: Any?
    private let sunoService = SunoDirectService()
    nonisolated(unsafe) private var endObserver: NSObjectProtocol?
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?
    nonisolated(unsafe) private var routeChangeObserver: NSObjectProtocol?
    private var artworkLoadTask: Task<Void, Never>?
    private var cachedArtworkURL: URL?
    private var currentArtworkImage: UIImage?
    private var lastLiveActivitySyncDate: Date = .distantPast
    private var lastLiveActivityProgress: Double = -1
    private var lyricsFetchTask: Task<Void, Never>?
    private let systemSongSnapshotStore = SystemSongSnapshotStore()
    private let lyricTrackingInterval = CMTime(seconds: 0.05, preferredTimescale: 600)
    private let lyricLeadCompensation: TimeInterval = 0
    private var pendingLyricSeekIndex: Int?
    private var pendingLyricSeekEffectiveTime: TimeInterval?
    #if canImport(ActivityKit)
    private let liveActivityManager = PlaybackLiveActivityManager()
    #endif

    var playbackSurfaceMode: PlaybackSurfaceMode {
        get {
            guard isExpanded else { return .collapsed }
            return showLyrics ? .expandedLyrics : .expandedArtwork
        }
        set {
            switch newValue {
            case .collapsed:
                isExpanded = false
            case .expandedArtwork:
                isExpanded = true
                showLyrics = false
            case .expandedLyrics:
                isExpanded = true
                showLyrics = true
            }
        }
    }

    init() {
        configureRemoteCommands()
        observeAudioSessionLifecycle()
    }

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
            removeLyricsBoundaryObserver()
            audioPlayer = AVPlayer(url: audioURL)
            observePlayerItemEnd()
        }
        
        audioPlayer?.play()
        isPlaying = true
        startProgressTracking()
        updateNowPlayingInfo()
        syncWidgetPlaybackState()
        updateLiveActivity(force: true)
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        updateNowPlayingInfo()
        syncWidgetPlaybackState()
        updateLiveActivity(force: true)
    }
    
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    /// 跳转到指定进度 (0.0 ~ 1.0)
    func seek(to progress: Double, preferredLyricIndex: Int? = nil) {
        guard let player = audioPlayer,
              let duration = player.currentItem?.duration,
              duration.seconds.isFinite, duration.seconds > 0 else { return }
        
        let targetTime = CMTime(seconds: duration.seconds * progress, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        
        // 立即更新 UI
        let newTime = duration.seconds * progress
        currentTime = newTime
        playbackProgress = progress

        if let preferredLyricIndex,
           lyricsAreTimeSynced,
           lyricsPresentation.phrases.indices.contains(preferredLyricIndex) {
            currentLineIndex = preferredLyricIndex
            pendingLyricSeekIndex = preferredLyricIndex
            pendingLyricSeekEffectiveTime = lyricsPresentation.effectivePhraseStartTime(
                at: preferredLyricIndex,
                compensation: lyricLeadCompensation
            )
        } else {
            pendingLyricSeekIndex = nil
            pendingLyricSeekEffectiveTime = nil
            updateCurrentLyricIndex(for: newTime)
        }

        updateNowPlayingInfo()
        updateLiveActivity(force: true)
    }
    
    // MARK: - 进度追踪
    
    private func startProgressTracking() {
        removeProgressTracking()
        guard let player = audioPlayer else { return }
        
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: lyricTrackingInterval,
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self = self,
                      let duration = self.audioPlayer?.currentItem?.duration,
                      duration.seconds.isFinite, duration.seconds > 0 else { return }

                self.currentTime = time.seconds
                self.totalDuration = duration.seconds
                self.playbackProgress = time.seconds / duration.seconds
                self.updateCurrentLyricIndex(for: time.seconds)
                self.updateNowPlayingInfo()
                self.updateLiveActivity()
            }
        }
    }
    
    private func removeProgressTracking() {
        if let observer = timeObserver {
            audioPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func installLyricBoundaryObserver() {
        removeLyricsBoundaryObserver()
        guard lyricsAreTimeSynced,
              let player = audioPlayer,
              lyricsPresentation.phrases.count > 1 else { return }

        let boundaryTimes = lyricsPresentation.phrases.indices
            .dropFirst()
            .map { lyricsPresentation.effectivePhraseStartTime(at: $0, compensation: lyricLeadCompensation) }
            .filter { $0.isFinite && $0 >= 0 }
            .map { NSValue(time: CMTime(seconds: $0, preferredTimescale: 600)) }

        guard !boundaryTimes.isEmpty else { return }

        lyricsBoundaryObserver = player.addBoundaryTimeObserver(
            forTimes: boundaryTimes,
            queue: .main
        ) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let playbackTime = self.audioPlayer?.currentTime().seconds ?? self.currentTime
                self.currentTime = playbackTime
                self.updateCurrentLyricIndex(for: playbackTime)
            }
        }
    }

    private func removeLyricsBoundaryObserver() {
        if let observer = lyricsBoundaryObserver {
            audioPlayer?.removeTimeObserver(observer)
            lyricsBoundaryObserver = nil
        }
    }
    
    // MARK: - 歌词加载
    
    /// 从 Suno API 获取时间戳歌词；失败时降级为纯文本歌词。
    /// 当 sunoAudioId 不可用时，先通过 record-info API 查询正确的 audioId。
    func fetchLyrics() async {
        guard let music = currentMusic else { return }
        let musicID = music.id
        // 已拿到真实时间戳歌词时，不重复请求；纯文本降级允许后续重试。
        if !lyrics.isEmpty && lyricsAreTimeSynced { return }
        
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
                    guard currentMusic?.id == musicID else { return }
                    lyrics = lines
                    lyricsAreTimeSynced = true
                    lyricsPresentation = LyricsPresentationModel.build(from: lines, isTimeSynced: true)
                    lyricsFollowMode = .follow
                    installLyricBoundaryObserver()
                    updateCurrentLyricIndex(for: currentTime)
                    isLoadingLyrics = false
                    return
                }
            } catch {
                print("⚠️ [PlayerManager] 时间戳歌词获取失败: \(error.localizedDescription)")
            }
        }
        
        // 第三步：所有 API 路径失败，降级为纯文本歌词
        print("📝 [PlayerManager] 降级为纯文本歌词")
        guard currentMusic?.id == musicID else { return }
        lyrics = LyricLine.parseFromPlainText(music.prompt, totalDuration: totalDuration)
        lyricsAreTimeSynced = false
        lyricsPresentation = LyricsPresentationModel.build(from: lyrics, isTimeSynced: false)
        lyricsFollowMode = .follow
        removeLyricsBoundaryObserver()
        updateCurrentLyricIndex(for: currentTime)
        isLoadingLyrics = false
    }
    
    // MARK: - 清理

    func reset() {
        pause()
        removeProgressTracking()
        audioPlayer = nil
        removePlayerEndObserver()
        currentMusic = nil
        playbackProgress = 0
        currentTime = 0
        totalDuration = 0
        isExpanded = false
        dragOffset = .zero
        showLyrics = false
        lyrics = []
        lyricsPresentation = .empty
        currentLineIndex = 0
        lyricsAreTimeSynced = false
        lyricsControlsVisible = true
        lyricsFollowMode = .follow
        pendingLyricSeekIndex = nil
        pendingLyricSeekEffectiveTime = nil
        currentArtworkImage = nil
        cachedArtworkURL = nil
        lastLiveActivitySyncDate = .distantPast
        lastLiveActivityProgress = -1
        lyricsFetchTask?.cancel()
        removeLyricsBoundaryObserver()
        artworkLoadTask?.cancel()
        systemSongSnapshotStore.updateCurrentPlayback(songID: nil, isPlaying: false)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
        Task {
            #if canImport(ActivityKit)
            await liveActivityManager.end()
            #endif
        }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("⚠️ [PlayerManager] Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
    }

    private func handleCurrentMusicChanged() {
        currentTime = 0
        playbackProgress = 0
        totalDuration = currentMusic?.duration ?? 0
        lyrics = []
        lyricsPresentation = .empty
        currentLineIndex = 0
        lyricsAreTimeSynced = false
        isLoadingLyrics = false
        lyricsControlsVisible = true
        lyricsFollowMode = .follow
        pendingLyricSeekIndex = nil
        pendingLyricSeekEffectiveTime = nil
        currentArtworkImage = nil
        cachedArtworkURL = nil
        artworkLoadTask?.cancel()
        lyricsFetchTask?.cancel()
        removeLyricsBoundaryObserver()
        guard currentMusic != nil else {
            updateNowPlayingInfo()
            syncWidgetPlaybackState()
            updateLiveActivity(force: true)
            return
        }
        updateNowPlayingInfo()
        syncWidgetPlaybackState()
        loadArtworkIfNeeded()
        updateLiveActivity(force: true)
        if showLyrics {
            lyricsFetchTask = Task { [weak self] in
                await self?.fetchLyrics()
            }
        }
    }

    private func updateCurrentLyricIndex(for time: TimeInterval) {
        guard !lyricsPresentation.phrases.isEmpty else {
            currentLineIndex = 0
            return
        }

        guard lyricsAreTimeSynced else {
            pendingLyricSeekIndex = nil
            pendingLyricSeekEffectiveTime = nil
            currentLineIndex = 0
            return
        }

        if let pendingIndex = pendingLyricSeekIndex,
           let effectiveTime = pendingLyricSeekEffectiveTime {
            if time < effectiveTime {
                currentLineIndex = pendingIndex
                return
            }

            pendingLyricSeekIndex = nil
            pendingLyricSeekEffectiveTime = nil
        }

        currentLineIndex = lyricsPresentation.phraseIndex(at: time, compensation: lyricLeadCompensation)
    }

    func beginLyricsBrowseMode() {
        lyricsFollowMode = .browse
        lyricsControlsVisible = true
        effectiveLyricDuration = nil
    }

    // MARK: - 歌词工具

    /// 若 effectiveLyricDuration 已设置，过滤掉超出该时长的歌词行
    private func filterLyrics(_ lines: [LyricLine]) -> [LyricLine] {
        guard let maxSec = effectiveLyricDuration else { return lines }
        return lines.filter { $0.startTime < maxSec }
    }

    func resumeLyricsFollowMode() {
        lyricsFollowMode = .follow
        lyricsControlsVisible = true
    }

    func revealLyricsControls() {
        lyricsControlsVisible = true
    }

    func collapseExpandedPlayer() {
        dragOffset = .zero
        isExpanded = false
        showLyrics = false
        lyricsControlsVisible = true
        lyricsFollowMode = .follow
    }

    private func observePlayerItemEnd() {
        removePlayerEndObserver()
        guard let item = audioPlayer?.currentItem else { return }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = false
                self.playbackProgress = 1
                self.updateNowPlayingInfo()
                self.syncWidgetPlaybackState()
                self.updateLiveActivity(force: true)
            }
        }
    }

    private func removePlayerEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func observeAudioSessionLifecycle() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue),
                      type == .began else {
                    return
                }
                self.pause()
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
                      reason == .oldDeviceUnavailable else {
                    return
                }
                self.pause()
            }
        }
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false

        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.play()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.pause()
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.togglePlayback()
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(toTime: event.positionTime)
            return .success
        }
    }

    private func seek(toTime time: TimeInterval) {
        guard let player = audioPlayer else { return }
        let targetTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        if totalDuration > 0 {
            playbackProgress = min(max(time / totalDuration, 0), 1)
        }
        updateCurrentLyricIndex(for: time)
        updateNowPlayingInfo()
        updateLiveActivity(force: true)
    }

    private func updateNowPlayingInfo() {
        guard let currentMusic else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = currentMusic.title.isEmpty ? "Untitled Song" : currentMusic.title
        if !currentMusic.style.isEmpty {
            info[MPMediaItemPropertyArtist] = currentMusic.style
        } else {
            info[MPMediaItemPropertyArtist] = "MOMENTA"
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = max(totalDuration, currentMusic.duration ?? totalDuration)
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if let currentArtworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: currentArtworkImage.size) { _ in
                currentArtworkImage
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        }
    }

    private func loadArtworkIfNeeded() {
        guard let artworkURL = currentMusic?.imageURL, artworkURL != cachedArtworkURL else { return }
        cachedArtworkURL = artworkURL
        artworkLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: artworkURL)
                guard !Task.isCancelled, let image = UIImage(data: data) else { return }
                await MainActor.run {
                    self.currentArtworkImage = image
                    self.updateNowPlayingInfo()
                }
            } catch {
                print("⚠️ [PlayerManager] Failed to load now playing artwork: \(error.localizedDescription)")
            }
        }
    }

    private func updateLiveActivity(force: Bool = false) {
        guard let currentMusic else {
            Task {
                #if canImport(ActivityKit)
                await liveActivityManager.end()
                #endif
            }
            return
        }

        let now = Date()
        let shouldSync = force
            || now.timeIntervalSince(lastLiveActivitySyncDate) >= 2
            || abs(playbackProgress - lastLiveActivityProgress) >= 0.04

        guard shouldSync else { return }
        lastLiveActivitySyncDate = now
        lastLiveActivityProgress = playbackProgress
        Task {
            #if canImport(ActivityKit)
            await liveActivityManager.startOrUpdate(
                song: currentMusic,
                isPlaying: isPlaying,
                progress: playbackProgress,
                elapsedTime: currentTime,
                remainingTime: max(0, totalDuration - currentTime)
            )
            #endif
        }
    }

    private func syncWidgetPlaybackState() {
        systemSongSnapshotStore.updateCurrentPlayback(songID: currentMusic?.id, isPlaying: isPlaying)
    }
}
