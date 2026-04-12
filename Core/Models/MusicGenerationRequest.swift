//
//  MusicGenerationRequest.swift
//  AI music
//

import Foundation

struct MusicGenerationRequest: Codable {
    let prompt: String
    let style: String?
    let title: String?
    let customMode: Bool
    let instrumental: Bool
    let model: SunoModel
    let callBackUrl: String
    let negativeTags: String?
    let vocalGender: VocalGender?
    let styleWeight: Double?
    let weirdnessConstraint: Double?
    let audioWeight: Double?
    
    enum SunoModel: String, Codable {
        case v3_5 = "V3_5"
        case v4 = "V4"
        case v4_5 = "V4_5"
        case v4_5Plus = "V4_5PLUS"
        case v5 = "V5"
    }
    
    enum VocalGender: String, Codable {
        case male = "m"
        case female = "f"
    }
}

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
