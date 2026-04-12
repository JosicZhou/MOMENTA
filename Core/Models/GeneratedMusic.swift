//
//  GeneratedMusic.swift
//  MOMENTA
//
//  单曲数据模型。用于 Light/Memory 生成、歌单展示与播放。
//  - source: 来源 "mine" | "cocreate"，用于归类到 Mine / Cocreate 歌单
//

import Foundation

struct GeneratedMusic: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let style: String
    let prompt: String
    let audioURL: URL?
    /// Suno 返回的专辑封面图片 URL（imageUrl / imageUrl2）
    var imageURL: URL? = nil
    /// Suno 音频 track ID，用于歌词 API（与 id/taskId 不同）
    var sunoAudioId: String?
    let status: GenerationStatus
    let createdAt: Date
    /// 来源：mine = 自己生成（Light/Memory），cocreate = 共创。缺省视为 mine。
    var source: String?
    /// 歌曲归属用户（music_generations.user_id），收藏/分享时用
    var ownerId: UUID?
    /// 歌曲时长（秒），用于共创 handoff 与播放器裁剪
    var duration: Double? = nil
    /// 共创 handoff 点（秒）；完整歌曲为空，待续写歌曲有值
    var continueAtSec: Double? = nil

    enum GenerationStatus: String, Codable {
        case pending = "pending"
        case generating = "generating"
        case completed = "completed"
        case failed = "failed"
    }

    /// 是否为「自己生成」（含缺省）
    var isMine: Bool { source == nil || source == "mine" || source == "memory" }
    /// 是否为「共创」
    var isCocreate: Bool { source == "cocreate" }
    /// 是否为「分享给我」
    var isShared: Bool { source == "shared" }
    /// 是否允许作为本地歌曲暴露到桌面组件
    var isWidgetEligible: Bool { isMine }
}

struct CocreateProfileSnapshot: Codable, Equatable {
    var language: String?
    var instrumental: Bool?
    var style: String?
    var title: String?
    var prompt: String?
    var bpm: Int?
    var vocalGender: String?
    var locationName: String?
    var weather: String?
    var healthQuadrant: String?

    func merging(with other: CocreateProfileSnapshot?) -> CocreateProfileSnapshot {
        guard let other else { return self }
        return CocreateProfileSnapshot(
            language: other.language ?? language,
            instrumental: other.instrumental ?? instrumental,
            style: other.style ?? style,
            title: other.title ?? title,
            prompt: other.prompt ?? prompt,
            bpm: other.bpm ?? bpm,
            vocalGender: other.vocalGender ?? vocalGender,
            locationName: other.locationName ?? locationName,
            weather: other.weather ?? weather,
            healthQuadrant: other.healthQuadrant ?? healthQuadrant
        )
    }
}

struct CocreateSession: Identifiable, Codable, Equatable {
    let id: UUID
    let creatorId: UUID
    var inviteeId: UUID?
    var status: Status
    let sourceTaskId: String
    var sunoAudioId: String?
    let continueAtSec: Double
    let model: String
    var profileA: CocreateProfileSnapshot
    var extendTaskId: String?
    var profileB: CocreateProfileSnapshot?
    let createdAt: Date
    let expiresAt: Date?
    var creatorDisplayName: String?
    var sourceTitle: String?
    var sourceImageURL: URL?
    var inviteeDisplayName: String?

    enum Status: String, Codable {
        case halfReady = "half_ready"
        case invited = "invited"
        case extending = "extending"
        case completed = "completed"
        case expired = "expired"
    }
}
