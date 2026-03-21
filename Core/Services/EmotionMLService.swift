//
//  EmotionMLService.swift
//  MOMENTA
//
//  MinMaxScaler 归一化 → Core ML (arousal / valence) 推理 → 生理信号混合修正 → 四象限判定。
//
//  由于 WESAD 标签粒度太粗（同一被试所有片段共享相同 V/A），
//  DecisionTree 模型的 arousal 回归 R²≈0，实质上退化为"均值预测"。
//  因此引入 HR 驱动的混合修正层：用原始心率直接推导 arousal 信号，
//  与模型输出加权融合，使系统能在 HR>115 时切换到高唤醒象限。
//
//  Scaler 常量来自 CoreML_model_3 训练（清洗后数据）。
//

import Foundation
import CoreML

final class EmotionMLService {

    // MARK: - Scaler 常量（v3，清洗后 HR∈[45, 200]、HRV∈[0, 297]）

    private enum ScalerConstants {
        static let hrDataMin:    Double = 45.02512563
        static let hrDataRange:  Double = 154.97487437
        static let hrvDataMin:   Double = 0.0
        static let hrvDataRange: Double = 296.875
    }

    private static let quadrantThreshold: Double = 0.5

    // MARK: - 混合修正参数

    /// 模型 arousal 占比（模型 R²≈0，给予低权重）
    private static let modelArousalWeight: Double = 0.3
    /// HR 生理信号 arousal 占比
    private static let hrArousalWeight: Double = 0.7
    /// HR→Arousal 映射下界（静息心率附近，映射为 0）
    private static let hrArousalFloor: Double = 55
    /// HR→Arousal 映射上界（剧烈运动心率，映射为 1）
    private static let hrArousalCeiling: Double = 150

    // MARK: - Core ML 模型（懒加载）

    private lazy var arousalModel: model_arousal = {
        guard let m = try? model_arousal(configuration: MLModelConfiguration()) else {
            fatalError("无法加载 model_arousal.mlmodel")
        }
        return m
    }()

    private lazy var valenceModel: model_valence = {
        guard let m = try? model_valence(configuration: MLModelConfiguration()) else {
            fatalError("无法加载 model_valence.mlmodel")
        }
        return m
    }()

    // MARK: - 推理入口

    func predict(heartRate: Double, hrv: Double) throws -> HealthMusicHints {
        let (scaledHR, scaledHRV) = scale(heartRate: heartRate, hrv: hrv)

        let arousalInput = model_arousalInput(heart_rate: scaledHR, hrv_sdnn: scaledHRV)
        let valenceInput = model_valenceInput(heart_rate: scaledHR, hrv_sdnn: scaledHRV)

        let arousalOutput = try arousalModel.prediction(input: arousalInput)
        let valenceOutput = try valenceModel.prediction(input: valenceInput)

        let modelA = clip(arousalOutput.arousal, 0, 1)
        let modelV = clip(valenceOutput.valence, 0, 1)

        // HR→Arousal 生理信号：高心率 = 高唤醒，线性映射 [55, 150] → [0, 1]
        let hrArousal = clip(
            (heartRate - Self.hrArousalFloor) / (Self.hrArousalCeiling - Self.hrArousalFloor),
            0, 1
        )
        let blendedA = Self.modelArousalWeight * modelA + Self.hrArousalWeight * hrArousal

        // HRV→Valence 微调：高 HRV 通常对应放松/积极状态
        let hrvNudge = clip((hrv - 30) / 70, -0.5, 0.5) * 0.1
        let adjustedV = clip(modelV + hrvNudge, 0, 1)

        let quadrant = Self.classify(valence: adjustedV, arousal: blendedA)

        print("🔬 [EmotionML] 模型原始输出: V=\(f(modelV)), A=\(f(modelA))")
        print("🔬 [EmotionML] HR 生理信号: \(f(heartRate)) BPM → hrArousal=\(f(hrArousal))")
        print("🔬 [EmotionML] 混合修正后: V=\(f(adjustedV)), A=\(f(blendedA)) → \(quadrant.rawValue)")

        return HealthMusicHints(valence: adjustedV, arousal: blendedA, quadrant: quadrant)
    }

    // MARK: - Private

    private func scale(heartRate: Double, hrv: Double) -> (Double, Double) {
        let hrClipped  = clip(heartRate, ScalerConstants.hrDataMin, ScalerConstants.hrDataMin + ScalerConstants.hrDataRange)
        let hrvClipped = clip(hrv, ScalerConstants.hrvDataMin, ScalerConstants.hrvDataMin + ScalerConstants.hrvDataRange)

        let scaledHR  = (hrClipped  - ScalerConstants.hrDataMin)  / ScalerConstants.hrDataRange
        let scaledHRV = (hrvClipped - ScalerConstants.hrvDataMin) / ScalerConstants.hrvDataRange

        return (scaledHR, scaledHRV)
    }

    private func clip(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(value, lo), hi)
    }

    private func f(_ v: Double) -> String {
        String(format: "%.3f", v)
    }

    private static func classify(valence v: Double, arousal a: Double) -> EmotionQuadrant {
        switch (a >= quadrantThreshold, v >= quadrantThreshold) {
        case (true,  true):  return .hapv
        case (true,  false): return .hanv
        case (false, false): return .lanv
        case (false, true):  return .lapv
        }
    }
}
