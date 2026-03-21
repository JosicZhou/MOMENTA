//
//  LLMServiceProtocol.swift
//  AI music
//
//  LLM服务协议，用于生成歌词

import Foundation

protocol LLMServiceProtocol {
    /// 生成歌词
    func generateLyrics(request: LyricsGenerationRequest) async throws -> LLMMusicResponse
}

enum LLMServiceError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case networkError(Error)
    case jsonParsingError
    case missingAPIKey
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "LLM返回的响应无效"
        case .apiError(let message):
            return "API错误: \(message)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .jsonParsingError:
            return "解析响应失败"
        case .missingAPIKey:
            return "缺少API Key，请在设置中配置"
        }
    }
}

