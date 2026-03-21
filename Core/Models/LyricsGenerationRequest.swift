//
//  LyricsGenerationRequest.swift
//  AI music
//
//  用于向LLM请求生成歌词的数据结构

import Foundation

struct LyricsGenerationRequest {
    let photo: String? // base64编码的图片，可选
    let photoPresent: Bool // 是否提供了图片
    let storyShare: String // 用户的描述
    let instrumentalOnly: Bool // 是否纯音乐
    let language: String // 语言，默认"en"
    /// 由外部 PromptBuilder 注入的完整 prompt（Memory 流程使用）。
    /// 若非 nil，buildPrompt() 直接返回此值，跳过内置模板。
    let rawPrompt: String?

    init(photo: String?, photoPresent: Bool, storyShare: String, instrumentalOnly: Bool, language: String, rawPrompt: String? = nil) {
        self.photo = photo
        self.photoPresent = photoPresent
        self.storyShare = storyShare
        self.instrumentalOnly = instrumentalOnly
        self.language = language
        self.rawPrompt = rawPrompt
    }

    /// 构建发送给LLM的完整prompt
    func buildPrompt() -> String {
        if let rawPrompt { return rawPrompt }

        let photoValue = photo ?? ""
        let photoPresentValue = photoPresent ? "true" : "false"
        let instrumentalValue = instrumentalOnly ? "yes" : "no"
        
        return """
        You are a professional songwriter and AI-music prompt engineer.
        Analyze the Photo's visible elements and mood together with the user's description to create a song.

        User Input:
        - Story/Description: \(storyShare)
        - Photo Provided: \(photoPresentValue)
        - Instrumental Only: \(instrumentalValue)
        - Language: \(language)

        Core Image Extraction (keep internal; do not list explicitly in output):
        - Guidance Note: Scaffold only, not exhaustive. Record any clearly visible, high‑confidence element that could enrich lyrical imagery; skip or mark uncertain if unclear; never fabricate.
        - Main Subject / Archetype: Identify primary presence (person(s), animal, object focus, landscape/nature, city/architecture, abstract/stylized figure). Mention clear expression only if unmistakable; else neutral.
        - Setting: Concise environment + time of day + weather/light condition (e.g., indoor warm lamp; dusk shoreline haze; night city lights; overcast field).
        - Color / Light Mood: Up to 2–3 dominant hues or tonal qualities (warm, cool, muted, high contrast, monochrome, neon) plus a brief mood mapping (hopeful, calm, isolated, nostalgic, electric, solemn).
        - Motion vs Stillness: Note stillness or specific action / gesture / subtle movement; assign a simple energy tag (calm, steady, dynamic, explosive).
        - Objects / Symbols: Only clearly visible items with metaphor potential (e.g., ring, path, horizon, instrument, trophy, camera, bouquet, cap, tool, mirror). Give one-word metaphor cue if obvious (journey, memory, commitment, voice, achievement, reflection).
        - Emotional Tone: Synthesize colors + expression + motion + symbols into 2–4 concise tags (e.g., quiet resolve; radiant celebration; muted longing; kinetic ascent). If contrasting layers exist, format as surface / undertone (bright poise / inward drift).
        - Additional Salient Features: Any other clear high-impact cues (texture, scale contrast, silhouette/rim light, reflections, patterns, negative space, perspective depth). Include only what is plain to see; no over-detailing.

        Output Requirements:
        Reply ONLY with a valid JSON object in this exact format:
        {
          "title": "string",
          "style": "string",
          "prompt": "string"
        }

        Field Specifications:

        1. "title": 
           - Concise, evocative, symbolic title
           - Maximum 6 words (English) or 16 CJK characters
           - Avoid generic words like "Song" or "Track"

        2. "style": 
           - Single-line comma-separated string
           - Must include: genre, mood, primary instrument feel, vocal gender (if vocals), extra stylistic tags
           - If Instrumental_only = "yes": MUST include "Instrumental" and NO vocal gender
           - If Instrumental_only = "no": MUST include vocal gender (male vocals / female vocals / male and female vocals)
           - Example: "Indie Pop, whimsical, light acoustic guitar, male vocals, playful"

        3. "prompt": 
           - The FULL lyrics, formatted with section headers like [Chorus], [Verse 1], [Verse 2], [Bridge], [Outro]
           - Write solely in the specified Language
           - Keep 36-56 lines total (Chorus≈6-8, Verse≈10-16)
           - Do NOT output any extra keys, comments, or explanations
           - Do NOT hallucinate or invent narrative details: no new characters, locations, events, brands, backstories, or symbolic objects beyond what is explicitly visible in the Photo or stated in the User Description
           - If Instrumental_only = "yes": set to empty string ""

        CRITICAL: Output ONLY the JSON object, no explanations, no markdown code blocks, no extra text.
        """
    }
}

/// LLM 返回的音乐元数据（title / style / prompt），歌词与纯音乐通用。
struct LLMMusicResponse: Codable {
    let title: String
    let style: String
    let prompt: String? // 当instrumental_only="no"时才有
    
    /// 转换为Suno API的请求参数
    func toSunoRequest(
        model: MusicGenerationRequest.SunoModel,
        callBackUrl: String,
        isInstrumental: Bool
    ) -> MusicGenerationRequest {
        return MusicGenerationRequest(
            prompt: prompt ?? "", // 纯音乐时为空
            style: style,
            title: title,
            customMode: true,
            instrumental: isInstrumental,
            model: model,
            callBackUrl: callBackUrl,
            negativeTags: nil,
            vocalGender: extractVocalGender(from: style),
            styleWeight: nil,
            weirdnessConstraint: nil,
            audioWeight: nil
        )
    }
    
    /// 从style字符串中提取vocal gender
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