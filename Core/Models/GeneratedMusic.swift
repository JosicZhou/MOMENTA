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
    let status: GenerationStatus
    let createdAt: Date
    /// 来源：mine = 自己生成（Light/Memory），cocreate = 共创。缺省视为 mine。
    var source: String?
    /// 歌曲归属用户（music_generations.user_id），收藏/分享时用
    var ownerId: UUID?

    enum GenerationStatus: String, Codable {
        case pending = "pending"
        case generating = "generating"
        case completed = "completed"
        case failed = "failed"
    }

    /// 是否为「自己生成」（含缺省）
    var isMine: Bool { source != "cocreate" }
    /// 是否为「共创」
    var isCocreate: Bool { source == "cocreate" }
}

