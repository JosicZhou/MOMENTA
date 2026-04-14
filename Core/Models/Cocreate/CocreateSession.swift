//
//  CocreateSession.swift
//  MOMENTA
//
//  共创会话模型，对应 Supabase cocreate_sessions 表。
//

import Foundation

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

    /// 创建者的显示名（从 join 查询填充，不存库）
    var creatorDisplayName: String?
    /// A 端歌曲标题（从 music_generations join 填充）
    var sourceTitle: String?
    /// A 端歌曲封面 URL（从 music_generations join 填充，不存库）
    var sourceImageURL: URL?
    /// 被邀请者的显示名（从 profiles join 填充，不存库）
    var inviteeDisplayName: String?

    enum Status: String, Codable {
        case halfReady = "half_ready"
        case invited = "invited"
        case extending = "extending"
        case completed = "completed"
        case expired = "expired"
    }
}
