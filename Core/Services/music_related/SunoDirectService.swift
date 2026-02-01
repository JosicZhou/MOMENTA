//
//  SunoDirectService.swift
//  AI music
//

import Foundation

class SunoDirectService: MusicServiceProtocol {
    
    private let baseURL = APIConfiguration.baseURL
    private let apiKey = APIConfiguration.apiKey
    
    // MARK: - Generate Music
    
    func generateMusic(request: MusicGenerationRequest) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/v1/generate") else {
            throw MusicServiceError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MusicServiceError.invalidResponse
        }
        
        // 添加日志：打印原始响应
        print("📡 [Suno] 生成音乐响应状态码: \(httpResponse.statusCode)")
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📡 [Suno] 生成音乐原始响应: \(jsonString)")
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(MusicGenerationResponse.self, from: data)
        
        if result.code == 200, let taskId = result.data?.taskId {
            return taskId
        } else {
            // 提供友好的错误信息
            let friendlyMessage: String
            switch result.code {
            case 433:
                friendlyMessage = "API调用次数已达上限，请稍后再试（每小时限制）"
            case 429:
                friendlyMessage = "请求过于频繁，请稍后再试"
            case 402:
                friendlyMessage = "账户余额不足，请充值后继续使用"
            case 401:
                friendlyMessage = "API密钥无效，请检查配置"
            case 422:
                friendlyMessage = "请求参数错误: \(result.msg)"
            default:
                friendlyMessage = result.msg
            }
            throw MusicServiceError.apiError(code: result.code, message: friendlyMessage)
        }
    }
    
    // MARK: - Get Task Status
    
    func getTaskStatus(taskId: String) async throws -> MusicTaskStatusResponse {
        // 正确的API路径：GET /api/v1/generate/record-info?taskId={taskId}
        guard var urlComponents = URLComponents(string: "\(baseURL)/api/v1/generate/record-info") else {
            throw MusicServiceError.invalidURL
        }
        
        // 添加taskId作为query参数
        urlComponents.queryItems = [URLQueryItem(name: "taskId", value: taskId)]
        
        guard let url = urlComponents.url else {
            throw MusicServiceError.invalidURL
        }
        
        print("🔍 [Suno] 查询URL: \(url.absoluteString)")
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MusicServiceError.invalidResponse
        }
        
        // 添加日志：打印原始响应
        print("📡 [Suno] 查询任务状态响应码: \(httpResponse.statusCode)")
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📡 [Suno] 查询任务原始响应:")
            print(jsonString)
        }
        
        // 处理HTTP错误
        if httpResponse.statusCode == 404 {
            throw MusicServiceError.apiError(code: 404, message: "任务未找到")
        } else if httpResponse.statusCode >= 400 {
            // 尝试解析错误信息
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] as? String ?? errorJson["error"] as? String {
                throw MusicServiceError.apiError(code: httpResponse.statusCode, message: message)
            }
            throw MusicServiceError.apiError(code: httpResponse.statusCode, message: "HTTP错误")
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        // 尝试解析响应
        do {
            let result = try decoder.decode(MusicTaskStatusResponse.self, from: data)
            
            if result.code != 200 {
                throw MusicServiceError.apiError(code: result.code, message: result.msg)
            }
            
            return result
        } catch {
            print("❌ [Suno] 解析响应失败: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("   缺少字段: \(key.stringValue)")
                    print("   路径: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                case .typeMismatch(let type, let context):
                    print("   类型不匹配: 期望 \(type)")
                    print("   路径: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                case .valueNotFound(let type, let context):
                    print("   值为null: 期望 \(type)")
                    print("   路径: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                case .dataCorrupted(let context):
                    print("   数据损坏: \(context.debugDescription)")
                    print("   路径: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                @unknown default:
                    print("   未知解码错误")
                }
            }
            throw MusicServiceError.invalidResponse
        }
    }
    
    // MARK: - Wait for Completion
    
    func waitForCompletion(taskId: String) async throws -> GeneratedMusic {
        var attempts = 0
        let maxAttempts = APIConfiguration.maxPollingAttempts
        
        while attempts < maxAttempts {
            let statusResponse = try await getTaskStatus(taskId: taskId)
            
            guard let taskData = statusResponse.data else {
                throw MusicServiceError.invalidResponse
            }
            
            print("📊 [Suno] 任务状态: \(taskData.status)")
            
            // 检查成功状态（SUCCESS, FIRST_SUCCESS）
            if taskData.status == "SUCCESS" || taskData.status == "FIRST_SUCCESS" {
                guard let sunoData = taskData.response?.sunoData?.first else {
                    throw MusicServiceError.invalidResponse
                }
                
                // 优先使用 audioUrl，如果为空则使用 streamAudioUrl
                let audioURLString = sunoData.audioUrl ?? sunoData.streamAudioUrl
                
                // 确保有可用的音频URL
                guard let urlString = audioURLString, !urlString.isEmpty,
                      let audioURL = URL(string: urlString) else {
                    print("⚠️ [Suno] 任务成功但音频URL还未准备好，继续等待...")
                    print("   - 状态: \(taskData.status)")
                    print("   - audioUrl: \(sunoData.audioUrl ?? "空")")
                    print("   - streamAudioUrl: \(sunoData.streamAudioUrl ?? "空")")
                    
                    // 如果是 FIRST_SUCCESS，继续等待 SUCCESS 状态或 URL 准备好
                    if taskData.status == "FIRST_SUCCESS" {
                        // 继续循环，等待下一次检查
                        attempts += 1
                        try await Task.sleep(nanoseconds: UInt64(APIConfiguration.pollingInterval * 1_000_000_000))
                        continue
                    } else {
                        // 如果是 SUCCESS 但还是没有 URL，再等待几次
                        attempts += 1
                        try await Task.sleep(nanoseconds: UInt64(APIConfiguration.pollingInterval * 1_000_000_000))
                        continue
                    }
                }
                
                print("✅ [Suno] 音乐生成完成！")
                print("   - 标题: \(sunoData.title ?? "未命名")")
                print("   - 音频URL: \(sunoData.audioUrl ?? "无")")
                print("   - 流媒体URL: \(sunoData.streamAudioUrl ?? "无")")
                print("   - 最终使用URL: \(urlString)")
                print("   - URL对象: \(audioURL.absoluteString)")
                
                return GeneratedMusic(
                    id: sunoData.id,
                    title: sunoData.title ?? "未命名",
                    style: sunoData.tags ?? "Unknown",
                    prompt: sunoData.prompt ?? "",
                    audioURL: audioURL,
                    status: .completed,
                    createdAt: Date()
                )
            }
            // 检查失败状态
            else if taskData.status == "CREATE_TASK_FAILED" || 
                    taskData.status == "GENERATE_AUDIO_FAILED" ||
                    taskData.status == "SENSITIVE_WORD_ERROR" {
                let errorMsg = taskData.errorMessage ?? "音乐生成失败"
                throw MusicServiceError.apiError(code: taskData.errorCode ?? 500, message: errorMsg)
            }
            // PENDING, TEXT_SUCCESS 等中间状态，继续等待
            else {
                print("⏳ [Suno] 等待生成中... (\(attempts + 1)/\(maxAttempts))")
            }
            
            attempts += 1
            try await Task.sleep(nanoseconds: UInt64(APIConfiguration.pollingInterval * 1_000_000_000))
        }
        
        throw MusicServiceError.timeout
    }
}
