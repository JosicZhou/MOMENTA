//
//  MusicTaskStatusResponse.swift
//  AI music
//

import Foundation

struct MusicTaskStatusResponse: Codable {
    let code: Int
    let msg: String
    let data: TaskStatusData?
    
    struct TaskStatusData: Codable {
        let taskId: String
        let status: String  // PENDING, TEXT_SUCCESS, FIRST_SUCCESS, SUCCESS, etc.
        let response: TaskResponse?
        let errorCode: Int?
        let errorMessage: String?
        
        struct TaskResponse: Codable {
            let taskId: String?
            let sunoData: [SunoAudio]?
        }
        
        struct SunoAudio: Codable {
            let id: String
            let title: String?
            let audioUrl: String?
            let streamAudioUrl: String?
            let imageUrl: String?
            let imageUrl2: String?
            let prompt: String?
            let duration: Double?
            let tags: String?
            let modelName: String?
            let status: String?
        }
    }
}
