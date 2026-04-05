//
//  CocreateProfileSnapshot.swift
//  MOMENTA
//
//  共创参数快照。A 端生成时存一份，B 端续写时存一份。
//  B 缺省字段继承 A 的值。
//

import Foundation

struct CocreateProfileSnapshot: Codable {
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

    /// 用 B 的值覆盖 A 的缺省值，返回合并结果
    func merging(with other: CocreateProfileSnapshot?) -> CocreateProfileSnapshot {
        guard let other else { return self }
        return CocreateProfileSnapshot(
            language: other.language ?? language,
            instrumental: instrumental,
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
