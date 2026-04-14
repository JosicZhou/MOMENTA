//
//  MusicExtendRequest.swift
//  MOMENTA
//
//  Suno extend API (/api/v1/generate/extend) 的请求体。
//

import Foundation

struct MusicExtendRequest: Codable {
    let defaultParamFlag: Bool
    let audioId: String
    let model: MusicGenerationRequest.SunoModel
    let callBackUrl: String

    let prompt: String?
    let style: String?
    let title: String?
    let continueAt: Double?

    let negativeTags: String?
    let vocalGender: MusicGenerationRequest.VocalGender?
    let styleWeight: Double?
    let weirdnessConstraint: Double?
    let audioWeight: Double?

    /// 使用源音频原始参数的便捷构造（defaultParamFlag = false）
    static func inheritingSource(
        audioId: String,
        model: MusicGenerationRequest.SunoModel,
        callBackUrl: String
    ) -> MusicExtendRequest {
        MusicExtendRequest(
            defaultParamFlag: false,
            audioId: audioId,
            model: model,
            callBackUrl: callBackUrl,
            prompt: nil,
            style: nil,
            title: nil,
            continueAt: nil,
            negativeTags: nil,
            vocalGender: nil,
            styleWeight: nil,
            weirdnessConstraint: nil,
            audioWeight: nil
        )
    }
}
