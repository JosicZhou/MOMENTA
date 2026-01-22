//
//  MusicGenerationResponse.swift
//  AI music
//

import Foundation

struct MusicGenerationResponse: Codable {
    let code: Int
    let msg: String
    let data: TaskData?
    
    struct TaskData: Codable {
        let taskId: String
    }
}

