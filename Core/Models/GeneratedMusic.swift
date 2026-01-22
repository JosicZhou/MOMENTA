//
//  GeneratedMusic.swift
//  AI music
//

import Foundation

struct GeneratedMusic: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let style: String
    let prompt: String
    let audioURL: URL?
    let status: GenerationStatus
    let createdAt: Date
    
    enum GenerationStatus: String, Codable {
        case pending = "pending"
        case generating = "generating"
        case completed = "completed"
        case failed = "failed"
    }
}
//
//  GeneratedMusic.swift
//  AI music
//
//  Created by Josic Zhou on 2025/10/6.
//

