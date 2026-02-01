//
//  SupabaseService.swift
//  MOMENTA
//
//  处理与 Supabase 的通用数据和存储交互（如用户 ID、通用上传等）
//

import Foundation
import Supabase

class SupabaseService {
    static let shared = SupabaseService()
    private let client = SupabaseConfig.client
    
    private init() {}
    
    /// 获取当前用户 ID
    func getCurrentUserId() async -> UUID? {
        return try? await client.auth.session.user.id
    }
    
    /// 将音乐生成记录存入数据库 (保留旧方法以兼容)
    func saveMusicRecord(music: GeneratedMusic, audioPublicURL: String, userId: UUID) async throws {
        let record: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString.lowercased()),
            "prompt": .string(music.prompt),
            "style": .string(music.style),
            "audio_url": .string(audioPublicURL),
            "status": .string(music.status.rawValue),
            "created_at": .string(ISO8601DateFormatter().string(from: music.createdAt))
        ]
        
        try await client
            .from("music_generations")
            .insert(record)
            .execute()
    }
    
    /// 上传音频文件到 Storage
    func uploadMusic(fileData: Data, fileName: String, userId: UUID) async throws -> String {
        let path = "\(userId.uuidString.lowercased())/\(fileName)"
        
        _ = try await client.storage
            .from("music-files")
            .upload(
                path,
                data: fileData,
                options: FileOptions(contentType: "audio/mpeg")
            )
        
        let publicURL = try client.storage
            .from("music-files")
            .getPublicURL(path: path)
            
        return publicURL.absoluteString
    }
    
    /// 工具方法：从 URL 下载 Data
    func downloadData(from url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}
