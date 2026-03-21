//
//  HealthMusicHints.swift
//  MOMENTA
//
//  Core ML 情绪推理输出：valence/arousal + 四象限 + 对应 Suno style 片段。
//

import Foundation

// MARK: - 四象限枚举

enum EmotionQuadrant: String, Codable {
    case hapv = "HAPV"  // 高唤醒 + 高愉悦
    case hanv = "HANV"  // 高唤醒 + 低愉悦
    case lanv = "LANV"  // 低唤醒 + 低愉悦
    case lapv = "LAPV"  // 低唤醒 + 高愉悦

    /// 四象限对应的 Suno style 原子片段
    var styleFragment: String {
        switch self {
        case .hapv: return "Fast Tempo, Major Mode, High Energy"
        case .hanv: return "Fast Tempo, Dissonant, Marcato"
        case .lanv: return "Slow Tempo, Minor Mode, Vague Rhythm"
        case .lapv: return "Slow Tempo, Legato, Consonance"
        }
    }
}

// MARK: - 推理结果

struct HealthMusicHints {
    let valence: Double   // 0–1
    let arousal: Double   // 0–1
    let quadrant: EmotionQuadrant

    var styleFragment: String { quadrant.styleFragment }
}
