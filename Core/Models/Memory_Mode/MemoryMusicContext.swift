//
//  MemoryMusicContext.swift
//  MOMENTA
//
//  Memory 音乐生成的统一输入上下文。
//  所有字段均为可选（除 language / instrumentalOnly），
//  由 ViewModel 按实际可用数据填充。
//

import Foundation

struct MemoryMusicContext {

    // MARK: - 基础输入（与 Light 共有）

    var photo: String?              // base64 图片，可选
    var story: String?              // 用户文字描述，可选
    var language: String = "en"
    var instrumentalOnly: Bool = false

    // MARK: - 健康 / 情绪（HealthKit → Core ML）

    var heartRate: Double?          // 原始 HR（BPM）
    var hrv: Double?                // 原始 HRV SDNN
    var healthHints: HealthMusicHints?  // ML 推理后的结果
    /// 从心率映射的音乐 BPM（钳位到 60–160），style 中最高优先级参数
    var suggestedBPM: Int?

    // MARK: - 环境

    var localTime: String?          // 格式化的本地时间，如 "Saturday 21:35"
    var locationName: String?       // 反地理编码地名，如 "Shanghai"
    var weather: String?            // 天气描述，如 "Cloudy"
    var temperature: Double?        // 摄氏度

    // MARK: - 便捷判断

    var hasPhoto: Bool { photo != nil }
    var hasStory: Bool { !(story ?? "").isEmpty }
    var hasHealth: Bool { healthHints != nil }
    var hasBPM: Bool { suggestedBPM != nil }
    var hasEnvironment: Bool { localTime != nil || locationName != nil || weather != nil || temperature != nil }

    /// 温度 → 氛围描述词（供 prompt 引导 LLM）
    var temperatureMood: String? {
        guard let t = temperature else { return nil }
        switch t {
        case ...5:    return "Freezing — cold, stark, crystalline, sparse textures"
        case 6...15:  return "Cool — crisp, introspective, acoustic warmth"
        case 16...25: return "Mild — balanced, warm, organic, flowing"
        case 26...33: return "Hot — bright, energetic, tropical, vibrant"
        default:      return "Scorching — intense, hazy, heavy, percussive"
        }
    }
}
