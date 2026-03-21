//
//  MemoryLyricsPromptBuilder.swift
//  MOMENTA
//
//  歌词版 prompt 构建器（instrumental = false）。
//  按条件拼块：角色说明 + (图片分析)? + (故事)? + (健康/情绪)? + (地点天气)? + 输出格式。
//  输出要求 LLM 返回 {"title","style","prompt"} JSON。
//
//  ⚠️ 这是草稿，你可以直接在此文件内调整措辞和细节。
//

import Foundation

enum MemoryLyricsPromptBuilder {

    static func build(from ctx: MemoryMusicContext) -> String {
        var sections: [String] = []

        // ── 1. 角色与任务 ──
        sections.append("""
        You are a professional songwriter and AI-music prompt engineer.
        Your task: analyze all available context below and create a song with lyrics.
        """)

        // ── 2. 图片分析（仅当有图片时） ──
        if ctx.hasPhoto {
            sections.append("""
            Photo Analysis (keep internal; do not list explicitly in output):
            - Main Subject / Archetype: Identify primary presence (person(s), animal, object, landscape, architecture, abstract figure).
            - Setting: Environment + time of day + weather/light condition.
            - Color / Light Mood: 2–3 dominant hues or tonal qualities + brief mood mapping.
            - Motion vs Stillness: Note action or stillness; assign energy tag (calm, steady, dynamic, explosive).
            - Objects / Symbols: Clearly visible items with metaphor potential.
            - Emotional Tone: Synthesize into 2–4 concise tags.
            """)
        }

        // ── 3. 用户故事 / 记忆描述 ──
        sections.append("""
        User Input:
        - Story/Description: \(ctx.story ?? "(none)")
        - Photo Provided: \(ctx.hasPhoto ? "true" : "false")
        - Language: \(ctx.language)
        """)

        // ── 4. 健康 / 情绪上下文（仅当有 HR/HRV 数据时） ──
        if ctx.hasHealth || ctx.hasBPM {
            var healthLines: [String] = ["Biometric Emotional Context (from real-time heart data):"]
            if let bpm = ctx.suggestedBPM {
                healthLines.append("- **MANDATORY BPM: \(bpm)** — The music tempo MUST be exactly \(bpm) BPM. This is the HIGHEST PRIORITY constraint derived from the user's live heart rate. It overrides any other tempo suggestion.")
            }
            if let hints = ctx.healthHints {
                healthLines.append("- Valence: \(String(format: "%.2f", hints.valence)) (0 = negative, 1 = positive)")
                healthLines.append("- Arousal: \(String(format: "%.2f", hints.arousal)) (0 = calm, 1 = excited)")
                healthLines.append("- Emotion Quadrant: \(hints.quadrant.rawValue)")
                healthLines.append("- Suggested Musical Traits: \(hints.styleFragment)")
            }
            healthLines.append("Use these biometric cues to shape the song's emotional arc and harmonic choices.")
            healthLines.append("Do NOT mention heart rate or biometrics explicitly in the lyrics.")
            sections.append(healthLines.joined(separator: "\n"))
        }

        // ── 5. 环境上下文（本地时间 / 地点 / 天气 / 温度） ──
        if ctx.hasEnvironment {
            var envLines: [String] = ["Environmental Context (SECONDARY reference — if any conflict with Biometric cues above, Biometric cues ALWAYS win):"]
            if let time = ctx.localTime { envLines.append("- Local Time: \(time)") }
            if let loc = ctx.locationName { envLines.append("- Location: \(loc)") }
            if let w = ctx.weather { envLines.append("- Weather: \(w)") }
            if let t = ctx.temperature {
                envLines.append("- Temperature: \(String(format: "%.0f", t))°C")
                if let mood = ctx.temperatureMood {
                    envLines.append("  Thermal mood hint: \(mood)")
                }
            }
            envLines.append("Use environmental atmosphere as subtle coloring for imagery and mood; never let it override the biometric-driven style choices.")
            sections.append(envLines.joined(separator: "\n"))
        }

        // ── 6. 输出格式要求（固定） ──
        sections.append("""
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
           \(ctx.hasBPM ? "- The FIRST tag MUST be \"\(ctx.suggestedBPM!) BPM\" — this is non-negotiable and highest priority" : "")
           - Must include: genre, mood, primary instrument feel, vocal gender, extra stylistic tags
           - MUST include vocal gender (male vocals / female vocals / male and female vocals)
           \(ctx.hasHealth ? "- MUST incorporate the Suggested Musical Traits from Biometric Emotional Context above" : "")
           - Example: \(ctx.hasBPM ? "\"\(ctx.suggestedBPM!) BPM, Indie Pop, whimsical, light acoustic guitar, male vocals, playful\"" : "\"Indie Pop, whimsical, light acoustic guitar, male vocals, playful\"")

        3. "prompt":
           - The FULL lyrics, formatted with section headers like [Chorus], [Verse 1], [Verse 2], [Bridge], [Outro]
           - Write solely in the specified Language (\(ctx.language))
           - Keep 36-56 lines total (Chorus ≈ 6-8, Verse ≈ 10-16)
           - Do NOT output any extra keys, comments, or explanations
           - Do NOT hallucinate or invent narrative details beyond what is visible in the Photo or stated in the User Description

        CRITICAL: Output ONLY the JSON object, no explanations, no markdown code blocks, no extra text.
        """)

        return sections.joined(separator: "\n\n")
    }
}
