//
//  Photo2MusicManager.swift
//  Butterfly
//
//  输入：图片+描述；输出：音乐
//

import Foundation
import UIKit
import Combine

@MainActor
class Photo2MusicManager: ObservableObject {
    private let baseManager: MusicBaseManager
    private let llmService: LLMServiceProtocol
    
    init(baseManager: MusicBaseManager, llmService: LLMServiceProtocol) {
        self.baseManager = baseManager
        self.llmService = llmService
    }
    
    /// 提供一个方便的默认创建方法
    static func createDefault() -> Photo2MusicManager {
        let base = MusicBaseManager.createDefault()
        let llm = OpenAILyricsService(
            apiKey: APIConfiguration.openAIAPIKey,
            baseURL: APIConfiguration.openAIBaseURL
        )
        return Photo2MusicManager(baseManager: base, llmService: llm)
    }
    
    /// 智能生成流程：图片/描述 -> LLM解析 -> MusicBaseManager生成
    func generate(
        userInput: String,
        selectedImage: UIImage?,
        parameters: MusicParameters,
        onProgress: (String) -> Void
    ) async throws -> GeneratedMusic {
        
        // 1. 调用 LLM 生成歌词和建议风格
        onProgress("正在通过 AI 解析灵感...")
        let lyricsResponse = try await generateLyrics(
            userInput: userInput,
            selectedImage: selectedImage,
            parameters: parameters
        )
        
        // 2. 构建最终的生成请求
        onProgress("正在准备音乐生成...")
        let sunoRequest = buildSunoRequest(
            lyricsResponse: lyricsResponse,
            parameters: parameters
        )
        
        // 3. 调用底层总管执行生成
        onProgress("正在创作音乐中...")
        return try await baseManager.generateMusic(request: sunoRequest)
    }
    
    // MARK: - 私有辅助方法
    
    private func generateLyrics(
        userInput: String,
        selectedImage: UIImage?,
        parameters: MusicParameters
    ) async throws -> LyricsGenerationResponse {
        var photoBase64: String?
        if let image = selectedImage {
            photoBase64 = ImageUtility.toBase64(image: image)
        }
        
        let request = LyricsGenerationRequest(
            photo: photoBase64,
            photoPresent: selectedImage != nil,
            storyShare: userInput,
            instrumentalOnly: !parameters.hasVocals,
            language: parameters.language
        )
        
        return try await llmService.generateLyrics(request: request)
    }
    
    private func buildSunoRequest(
        lyricsResponse: LyricsGenerationResponse,
        parameters: MusicParameters
    ) -> MusicGenerationRequest {
        let finalStyle: String
        
        if parameters.useAIRecommendation {
            finalStyle = lyricsResponse.style
        } else {
            var styleComponents: [String] = []
            if let userStyle = parameters.style { styleComponents.append(userStyle) }
            if let userInstrument = parameters.instrument { styleComponents.append(userInstrument) }
            if parameters.hasVocals {
                styleComponents.append("male vocals")
            } else {
                styleComponents.append("Instrumental")
            }
            finalStyle = styleComponents.joined(separator: ", ")
        }
        
        return MusicGenerationRequest(
            prompt: lyricsResponse.prompt ?? "",
            style: finalStyle,
            title: lyricsResponse.title,
            customMode: true,
            instrumental: !parameters.hasVocals,
            model: .v5,
            callBackUrl: APIConfiguration.sunoCallbackURL,
            negativeTags: nil,
            vocalGender: extractVocalGender(from: finalStyle),
            styleWeight: nil,
            weirdnessConstraint: nil,
            audioWeight: nil
        )
    }
    
    private func extractVocalGender(from style: String) -> MusicGenerationRequest.VocalGender? {
        let lowercased = style.lowercased()
        if lowercased.contains("male vocal") && !lowercased.contains("female") {
            return .male
        } else if lowercased.contains("female vocal") {
            return .female
        }
        return nil
    }
}
