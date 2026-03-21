//
//  OpenAILyricsService.swift
//  AI music
//
//  使用OpenAI API生成歌词

import Foundation
import UIKit

class OpenAILyricsService: LLMServiceProtocol {
    
    private let apiKey: String
    private let baseURL: String
    private let model = "gpt-4o" // 支持vision的稳定模型
    
    // 配置更长的超时时间
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 请求超时：120秒
        config.timeoutIntervalForResource = 500 // 资源超时：300秒
        return URLSession(configuration: config)
    }()
    
    init(apiKey: String = "", baseURL: String = APIConfiguration.openAIBaseURL) {
        self.apiKey = apiKey
        self.baseURL = "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/chat/completions"
    }
    
    func generateLyrics(request: LyricsGenerationRequest) async throws -> LLMMusicResponse {
        guard !apiKey.isEmpty else {
            throw LLMServiceError.missingAPIKey
        }
        
        print("🎵 [LLM] 开始构建请求...")
        
        // 构建OpenAI请求
        let messages = buildMessages(from: request)
        
        // 不使用function calling，改用普通prompt
        let requestBody: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 2000
        ]
        
        // 发送请求
        guard let url = URL(string: baseURL) else {
            throw LLMServiceError.invalidResponse
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        print("🚀 [LLM] 发送请求到: \(url)")
        print("📦 [LLM] 模型: \(model)")
        
        do {
            let (data, response) = try await urlSession.data(for: urlRequest)
            
            print("✅ [LLM] 收到响应")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMServiceError.invalidResponse
            }
            
            print("📊 [LLM] HTTP状态码: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ [LLM] API错误: \(errorMessage)")
                throw LLMServiceError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
            }
            
            // 解析响应
            print("📝 [LLM] 开始解析响应...")
            
            // 打印原始响应（用于调试）
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 [LLM] 原始响应: \(responseString.prefix(500))...") // 只打印前500字符
            }
            
            let result = try parseResponse(data: data)
            print("✅ [LLM] 解析成功")
            return result
            
        } catch let error as LLMServiceError {
            throw error
        } catch let error as NSError {
            // 检查是否是超时错误
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorTimedOut {
                print("⏱️ [LLM] 请求超时 - 可能是网络慢或API响应慢")
                throw LLMServiceError.apiError("请求超时，请检查网络连接或稍后重试")
            }
            print("❌ [LLM] 网络错误: \(error.localizedDescription)")
            throw LLMServiceError.networkError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func buildMessages(from request: LyricsGenerationRequest) -> [[String: Any]] {
        var content: [[String: Any]] = []
        
        // 添加文本内容
        content.append([
            "type": "text",
            "text": request.buildPrompt()
        ])
        
        // 如果有图片，添加图片
        if let photoBase64 = request.photo, request.photoPresent {
            print("🖼️ [LLM] 包含图片，大小约: \(photoBase64.count / 1024)KB")
            content.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(photoBase64)"
                ]
            ])
        }
        
        return [
            [
                "role": "user",
                "content": content
            ]
        ]
    }
    
    private func parseResponse(data: Data) throws -> LLMMusicResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [LLM] 无法解析为JSON对象")
            throw LLMServiceError.jsonParsingError
        }
        
        print("🔍 [LLM] JSON结构: \(json.keys)")
        
        guard let choices = json["choices"] as? [[String: Any]] else {
            print("❌ [LLM] 缺少choices字段")
            throw LLMServiceError.jsonParsingError
        }
        
        guard let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            print("❌ [LLM] 无法获取content字段")
            throw LLMServiceError.jsonParsingError
        }
        
        print("📄 [LLM] 收到content: \(content.prefix(300))...")
        
        // 提取JSON（可能包含markdown代码块）
        var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 移除可能的markdown代码块标记
        if jsonString.hasPrefix("```json") {
            jsonString = jsonString.replacingOccurrences(of: "```json", with: "")
            jsonString = jsonString.replacingOccurrences(of: "```", with: "")
        } else if jsonString.hasPrefix("```") {
            jsonString = jsonString.replacingOccurrences(of: "```", with: "")
        }
        
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 修复JSON中的换行符问题：将实际换行符转换为\n
        // 这是因为LLM可能在prompt字段中输出了实际的换行符，而不是"\n"
        jsonString = fixJSONNewlines(jsonString)
        
        print("🧹 [LLM] 清理后的JSON: \(jsonString.prefix(300))...")
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ [LLM] 无法将content转为Data")
            throw LLMServiceError.jsonParsingError
        }
        
        // 解析JSON
        let decoder = JSONDecoder()
        do {
            let result = try decoder.decode(LLMMusicResponse.self, from: jsonData)
            print("✅ [LLM] 成功解码LLMMusicResponse")
            print("   - Title: \(result.title)")
            print("   - Style: \(result.style)")
            if let prompt = result.prompt {
                print("   - Prompt length: \(prompt.count) chars")
            }
            return result
        } catch {
            print("❌ [LLM] 解码失败: \(error)")
            print("   原始JSON: \(jsonString)")
            throw LLMServiceError.jsonParsingError
        }
    }
    
    /// 修复JSON中的换行符问题
    /// 将prompt字段中的实际换行符转换为\n转义序列
    private func fixJSONNewlines(_ jsonString: String) -> String {
        // 使用正则表达式找到"prompt"字段的值，并转义其中的换行符
        guard let regex = try? NSRegularExpression(
            pattern: "\"prompt\"\\s*:\\s*\"([^\"]*(?:\\\\.[^\"]*)*?)\"",
            options: [.dotMatchesLineSeparators]
        ) else {
            return jsonString
        }
        
        let nsString = jsonString as NSString
        let range = NSRange(location: 0, length: nsString.length)
        
        guard let match = regex.firstMatch(in: jsonString, range: range),
              match.numberOfRanges > 1 else {
            return jsonString
        }
        
        let promptRange = match.range(at: 1)
        let promptValue = nsString.substring(with: promptRange)
        
        // 转义换行符和其他特殊字符
        let escapedPrompt = promptValue
            .replacingOccurrences(of: "\\", with: "\\\\") // 先转义反斜杠
            .replacingOccurrences(of: "\n", with: "\\n")  // 转义换行符
            .replacingOccurrences(of: "\r", with: "\\r")  // 转义回车
            .replacingOccurrences(of: "\t", with: "\\t")  // 转义制表符
            .replacingOccurrences(of: "\"", with: "\\\"") // 转义引号
        
        // 替换原始字符串
        let fullMatchRange = match.range(at: 0)
        let replacement = "\"prompt\": \"\(escapedPrompt)\""
        
        return nsString.replacingCharacters(in: fullMatchRange, with: replacement)
    }
}
