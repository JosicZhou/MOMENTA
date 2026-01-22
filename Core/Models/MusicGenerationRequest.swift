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
//
//  MusicGenerationRequest.swift
//  AI music
//
//  Created by Josic Zhou on 2025/10/6.
//

