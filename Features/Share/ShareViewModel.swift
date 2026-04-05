//
//  ShareViewModel.swift
//  MOMENTA
//
//  Cocreate 测试页面 ViewModel。
//  职责：好友管理 + A 端生成半首歌 + B 端续写(extend)。
//

import Foundation
import SwiftUI
import UIKit
import Supabase

@MainActor
final class ShareViewModel: ObservableObject {

    // MARK: - Friends (on-demand for sending)

    @Published var friends: [FriendProfile] = []

    // MARK: - A Side: Generate Half Song

    @Published var prompt: String = ""
    @Published var selectedImage: UIImage?
    @Published var instrumentalOnly: Bool = false
    @Published var language: String = "en"
    @Published var usePsychologicalProfile: Bool = false
    @Published var isGeneratingHalf: Bool = false
    @Published var generationProgress: String = ""
    @Published var halfSongResult: GeneratedMusic?
    @Published var cocreateSessionId: UUID?
    @Published var selectedFriend: FriendProfile?

    // MARK: - B Side: Extend

    @Published var pendingSessions: [CocreateSession] = []
    @Published var isExtending: Bool = false
    @Published var extendProgress: String = ""
    @Published var extendedMusic: GeneratedMusic?
    @Published var bPrompt: String = ""
    @Published var bSelectedImage: UIImage?
    @Published var bInstrumentalOnly: Bool = false
    @Published var bLanguage: String = "en"

    // MARK: - A Side: Completed Cocreates

    struct CompletedCocreate: Identifiable {
        let id: UUID            // session ID
        let music: GeneratedMusic
        let inviteeName: String?
    }

    @Published var completedItems: [CompletedCocreate] = []
    @Published var completionNotice: String? = nil
    private var noticeTask: Task<Void, Never>?

    // MARK: - General

    @Published var errorMessage: String?
    @Published var showErrorAlert: Bool = false

    // MARK: - Health

    @Published var heartRate: Double?
    @Published var hrv: Double?
    @Published var healthAuthorized: Bool = false
    @Published var healthHints: HealthMusicHints?

    // MARK: - Dependencies

    let locationWeather = LocationWeatherService.shared
    private let friendService = FriendService.shared
    private let cocreateService = CocreateService.shared
    private let memoryManager = Memory2MusicManager.createDefault()
    private let extendManager = CocreateExtendManager.createDefault()
    private let musicDb = MusicDatabaseService.shared
    private let healthKit = HealthKitService()
    private let emotionML = EmotionMLService()

    /// 共创邀请 Realtime 订阅任务（持久存活，ShareViewModel 销毁时自动取消）
    private var invitationSubscriptionTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func onAppear() async {
        await refreshFriends()
        await loadPendingSessions()
        await loadCompletedItems()
        // 启动 Realtime 订阅：B 端实时接收共创邀请 / A 端实时收到完成通知
        if let userId = await SupabaseService.shared.getCurrentUserId() {
            subscribeToInvitations(userId: userId)
        }
    }

    func refreshFriends() async {
        do {
            friends = try await friendService.loadFriends()
        } catch {
            print("[ShareVM] Failed to load friends: \(error.localizedDescription)")
        }
    }

    // MARK: - HealthKit

    func requestHealthAccess() async {
        do {
            try await healthKit.requestAuthorization()
            healthAuthorized = true
            await fetchHealthData()
        } catch {
            healthAuthorized = false
        }
    }

    func fetchHealthData() async {
        guard healthAuthorized else { return }
        async let hrTask = healthKit.fetchLatestHeartRate()
        async let hrvTask = healthKit.fetchLatestHRV()
        heartRate = await hrTask
        hrv = await hrvTask

        guard let hr = heartRate else { return }
        do {
            healthHints = try emotionML.predict(heartRate: hr, hrv: hrv ?? 50.0)
        } catch {
            healthHints = nil
        }
    }

    func fetchEnvironment() async {
        await locationWeather.requestOnce()
    }

    // MARK: - A Side: Generate Half Song

    func generateHalfSong() async {
        if locationWeather.locationName == nil {
            await fetchEnvironment()
        }

        let hasInput = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedImage != nil
            || healthHints != nil
            || locationWeather.locationName != nil

        guard hasInput else {
            showError("Please provide at least one input (text, photo, or enable health).")
            return
        }

        isGeneratingHalf = true
        generationProgress = "Preparing..."

        let photoBase64 = selectedImage.flatMap { ImageUtility.toBase64(image: $0) }
        let bpm = heartRate.map { min(max(Int($0.rounded()), 60), 160) }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "EEEE HH:mm"
        timeFormatter.locale = Locale(identifier: language == "zh" ? "zh_CN" : "en_US")
        let localTime = timeFormatter.string(from: Date())

        let context = MemoryMusicContext(
            photo: photoBase64,
            story: prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : prompt,
            language: language,
            instrumentalOnly: instrumentalOnly,
            heartRate: usePsychologicalProfile ? heartRate : nil,
            hrv: usePsychologicalProfile ? hrv : nil,
            healthHints: usePsychologicalProfile ? healthHints : nil,
            suggestedBPM: usePsychologicalProfile ? bpm : nil,
            localTime: localTime,
            locationName: locationWeather.locationName,
            weather: locationWeather.weather,
            temperature: locationWeather.temperature
        )

        do {
            let music = try await memoryManager.generate(context: context) { [weak self] progress in
                Task { @MainActor in self?.generationProgress = progress }
            }

            let totalDuration = music.duration ?? 180.0
            let effectiveBPM = bpm ?? 120
            let cutPoint = CocreateExtendManager.computeContinueAt(
                totalDuration: totalDuration,
                bpm: effectiveBPM
            )

            try await musicDb.updateContinueAt(taskId: music.id, continueAtSec: cutPoint)

            var halfMusic = music
            halfMusic.continueAtSec = cutPoint

            let profileA = CocreateProfileSnapshot(
                language: language,
                instrumental: instrumentalOnly,
                style: music.style,
                title: music.title,
                prompt: music.prompt,
                bpm: effectiveBPM,
                vocalGender: nil,
                locationName: locationWeather.locationName,
                weather: locationWeather.weather,
                healthQuadrant: healthHints?.quadrant.rawValue
            )

            let sessionId = try await cocreateService.createSession(
                sourceTaskId: music.id,
                sunoAudioId: music.sunoAudioId,
                continueAtSec: cutPoint,
                model: MusicGenerationRequest.SunoModel.v5.rawValue,
                profileA: profileA
            )

            halfSongResult = halfMusic
            cocreateSessionId = sessionId
            generationProgress = "Half song ready!"
        } catch {
            showError(error.localizedDescription)
        }

        isGeneratingHalf = false
    }

    // MARK: - A Side: Send to Friend

    func sendToFriend(_ friend: FriendProfile) async {
        guard let sessionId = cocreateSessionId else {
            showError("No cocreate session. Generate a half song first.")
            return
        }
        do {
            try await cocreateService.inviteFriend(sessionId: sessionId, friendId: friend.id)
            selectedFriend = friend
            generationProgress = "Sent to \(friend.resolvedName)!"
        } catch {
            showError(error.localizedDescription)
        }
    }

    // MARK: - A Side: Load completed cocreates

    func loadCompletedItems() async {
        guard let userId = await SupabaseService.shared.getCurrentUserId() else { return }
        do {
            var sessions = try await cocreateService.loadMyCompletedSessions(userId: userId)

            // Enrich: fetch invitee display names from profiles (public read)
            let inviteeIds = sessions.compactMap { $0.inviteeId?.uuidString.lowercased() }
            if !inviteeIds.isEmpty {
                let profileResponse = try? await SupabaseConfig.client
                    .from("profiles")
                    .select("id, display_name")
                    .in("id", values: inviteeIds)
                    .execute()
                if let data = profileResponse?.data {
                    struct ProfileRow: Decodable {
                        let id: UUID
                        let displayName: String?
                        enum CodingKeys: String, CodingKey {
                            case id
                            case displayName = "display_name"
                        }
                    }
                    let profiles = (try? JSONDecoder().decode([ProfileRow].self, from: data)) ?? []
                    let nameMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.displayName) })
                    for i in sessions.indices {
                        if let invId = sessions[i].inviteeId {
                            sessions[i].inviteeDisplayName = nameMap[invId] ?? nil
                        }
                    }
                }
            }

            // Fetch the completed extend music records
            let taskIds = sessions.compactMap { $0.extendTaskId }
            let musicList = taskIds.isEmpty ? [] : (try? await musicDb.fetchMusicRecords(taskIds: taskIds)) ?? []
            let musicByTask = Dictionary(uniqueKeysWithValues: musicList.map { ($0.id, $0) })

            completedItems = sessions.compactMap { session in
                guard let taskId = session.extendTaskId,
                      let music = musicByTask[taskId] else { return nil }
                return CompletedCocreate(id: session.id, music: music, inviteeName: session.inviteeDisplayName)
            }
        } catch {
            print("⚠️ [ShareVM] loadCompletedItems: \(error)")
        }
    }

    // MARK: - B Side: Load & Extend

    func loadPendingSessions() async {
        guard let userId = await SupabaseService.shared.getCurrentUserId() else {
            print("⚠️ [ShareVM] loadPendingSessions: no authenticated user")
            return
        }
        print("🔍 [ShareVM] loadPendingSessions for userId: \(userId.uuidString)")
        do {
            var sessions = try await cocreateService.loadInvitedSessions(userId: userId)
            // Enrich each session with album art and title from its source music record
            await withTaskGroup(of: (Int, String?, URL?).self) { group in
                for (i, session) in sessions.enumerated() {
                    group.addTask {
                        let music = try? await MusicDatabaseService.shared.fetchMusicRecord(taskId: session.sourceTaskId)
                        return (i, music?.title, music?.imageURL)
                    }
                }
                for await (i, title, imageURL) in group {
                    if sessions[i].sourceTitle == nil { sessions[i].sourceTitle = title }
                    sessions[i].sourceImageURL = imageURL
                }
            }
            pendingSessions = sessions
            print("✅ [ShareVM] loadPendingSessions: found \(sessions.count) pending session(s)")
        } catch {
            print("⚠️ [ShareVM] Failed to load pending sessions: \(error)")
        }
    }

    func extendSong(session: CocreateSession) async {
        if locationWeather.locationName == nil {
            await fetchEnvironment()
        }

        isExtending = true
        extendProgress = "Preparing continuation..."

        let photoBase64 = bSelectedImage.flatMap { ImageUtility.toBase64(image: $0) }
        let bpm = heartRate.map { min(max(Int($0.rounded()), 60), 160) }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "EEEE HH:mm"
        let localTime = timeFormatter.string(from: Date())

        let resolvedLanguage = bLanguage.isEmpty
            ? (session.profileA.language ?? "en")
            : bLanguage

        let context = MemoryMusicContext(
            photo: photoBase64,
            story: bPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : bPrompt,
            language: resolvedLanguage,
            instrumentalOnly: session.profileA.instrumental ?? bInstrumentalOnly,
            heartRate: heartRate,
            hrv: hrv,
            healthHints: healthHints,
            suggestedBPM: bpm,
            localTime: localTime,
            locationName: locationWeather.locationName,
            weather: locationWeather.weather,
            temperature: locationWeather.temperature
        )

        do {
            let music = try await extendManager.extend(
                session: session,
                context: context
            ) { [weak self] progress in
                Task { @MainActor in self?.extendProgress = progress }
            }
            extendedMusic = music
            extendProgress = "Song completed!"
            await loadPendingSessions()
        } catch {
            showError(error.localizedDescription)
        }

        isExtending = false
    }

    // MARK: - Helpers

    func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }

    // MARK: - Realtime: 共创邀请订阅

    /// 订阅 cocreate_sessions 表的变化（INSERT/UPDATE）。
    /// 当 A 端调用 inviteFriend 更新 invitee_id 后，B 端自动刷新 pendingSessions。
    /// 重复调用安全：先取消旧订阅再建新连接。
    ///
    /// 注意：Supabase Realtime filter 只能过滤已有的 column 值。
    /// 因为 A 初始化 session 时 invitee_id = NULL，等 A 调用 inviteFriend 后才变成 B 的 UUID，
    /// 所以这里监听整个表的 UPDATE，然后靠 loadPendingSessions 里的数据库查询做精确过滤。
    private func subscribeToInvitations(userId: UUID) {
        invitationSubscriptionTask?.cancel()

        // 使用完整 UUID 保证频道名唯一，避免多账号在同设备复用同一频道
        let channelName = "cocreate_invite_\(userId.uuidString.lowercased())"
        let creatorIdStr = userId.uuidString.lowercased()

        invitationSubscriptionTask = Task { [weak self] in
            let channel = SupabaseConfig.client.channel(channelName)

            // 监听 UPDATE（A 设置 invitee_id 触发 / B 续写完成触发）
            channel.onPostgresChange(
                UpdateAction.self,
                schema: "public",
                table: "cocreate_sessions"
            ) { [weak self] action in
                let record = action.record
                // 提取关键字段（同步完成，避免 Sendability 问题）
                let status = record["status"].flatMap { if case .string(let s) = $0 { return s } else { return nil } }
                let creatorId = record["creator_id"].flatMap { if case .string(let s) = $0 { return s } else { return nil } }
                let isMySession = creatorId == creatorIdStr

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if status == "completed" && isMySession {
                        // A 收到 B 续写完成通知
                        print("🎉 [ShareVM] cocreate completed! Refreshing completed items...")
                        await self.loadCompletedItems()
                        self.showCompletionNotice("Your cocreate song is ready!")
                    } else {
                        // 邀请状态变更：刷新 B 端待处理列表
                        print("📡 [ShareVM] cocreate_sessions UPDATE received, refreshing pending sessions...")
                        await self.loadPendingSessions()
                    }
                }
            }

            // 监听 INSERT（session 刚创建时）
            channel.onPostgresChange(
                InsertAction.self,
                schema: "public",
                table: "cocreate_sessions"
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    print("📡 [ShareVM] cocreate_sessions INSERT received, refreshing pending sessions...")
                    await self?.loadPendingSessions()
                }
            }

            await channel.subscribe()
            print("📡 [ShareVM] Subscribed to cocreate invitations channel: \(channelName)")
        }
    }

    private func showCompletionNotice(_ message: String) {
        noticeTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            completionNotice = message
        }
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                self?.completionNotice = nil
            }
        }
    }

    deinit {
        invitationSubscriptionTask?.cancel()
        noticeTask?.cancel()
    }
}
