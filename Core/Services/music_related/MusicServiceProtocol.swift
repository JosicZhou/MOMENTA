//
//  MusicServiceProtocol.swift
//  AI music
//

import Foundation

protocol MusicServiceProtocol {
    /// 生成音乐
    func generateMusic(request: MusicGenerationRequest) async throws -> String
    
    /// 查询任务状态
    func getTaskStatus(taskId: String) async throws -> MusicTaskStatusResponse
    
    /// 轮询等待任务完成
    func waitForCompletion(taskId: String) async throws -> GeneratedMusic
}

enum MusicServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(code: Int, message: String)
    case timeout
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的API地址"
        case .invalidResponse:
            return "服务器响应格式错误"
        case .apiError(let code, let message):
            return "API错误 (\(code)): \(message)"
        case .timeout:
            return "生成超时，请稍后重试"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}
