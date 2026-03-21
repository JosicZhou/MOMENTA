//
//  MemoryInstrumentalPromptBuilder.swift
//  MOMENTA
//
//  纯音乐版 prompt 构建器（instrumental = true）。
//  不生成歌词，只输出 title + 极详细的 style 描述。
//  输出 {"title","style","prompt":""} — prompt 始终为空字符串。
//
//  ⚠️ 这是草稿，你可以直接在此文件内调整措辞和细节。
//

import Foundation

enum MemoryInstrumentalPromptBuilder {

    static func build(from ctx: MemoryMusicContext) -> String {
        var sections: [String] = []

        // ── 1. 角色与任务 ──
        sections.append("""
        You are a professional music producer and AI-music prompt engineer.
        Your task: analyze all available context below and design a purely instrumental track.
        No lyrics will be generated — focus entirely on musical style, mood, instrumentation, and sonic texture.
        """)

        // ── 2. 图片分析（仅当有图片时） ──
        if ctx.hasPhoto {
            sections.append("""
            Photo Analysis (keep internal; do not list explicitly in output):
            - Main Subject / Setting / Color-Light Mood / Motion vs Stillness / Objects-Symbols / Emotional Tone
            - Extract atmosphere and translate it into musical language (tempo, dynamics, timbre, space).
            """)
        }

        // ── 3. 用户故事 ──
        sections.append("""
        User Input:
        - Story/Description: \(ctx.story ?? "(none)")
        - Photo Provided: \(ctx.hasPhoto ? "true" : "false")
        """)

        // ── 4. 健康 / 情绪上下文 ──
        if ctx.hasHealth || ctx.hasBPM {
            var healthLines: [String] = ["Biometric Emotional Context (from real-time heart data):"]
            if let bpm = ctx.suggestedBPM {
                healthLines.append("- **MANDATORY BPM: \(bpm)** — The music tempo MUST be exactly \(bpm) BPM. This is the HIGHEST PRIORITY constraint derived from the user's live heart rate. It overrides any other tempo suggestion.")
            }
            if let hints = ctx.healthHints {
                healthLines.append("- Valence: \(String(format: "%.2f", hints.valence)), Arousal: \(String(format: "%.2f", hints.arousal))")
                healthLines.append("- Emotion Quadrant: \(hints.quadrant.rawValue)")
                healthLines.append("- Suggested Musical Traits: \(hints.styleFragment)")
            }
            healthLines.append("These biometric cues MUST strongly influence the style output: energy, harmonic character, and dynamic range.")
            sections.append(healthLines.joined(separator: "\n"))
        }

        // ── 5. 环境上下文 ──
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
            envLines.append("Use environmental atmosphere as subtle sonic coloring (reverb, texture, instrument palette); never let it override the biometric-driven style choices.")
            sections.append(envLines.joined(separator: "\n"))
        }

        // ── 6. 输出格式 ──
        sections.append("""
        Output Requirements:
        Reply ONLY with a valid JSON object in this exact format:
        {
          "title": "string",
          "style": "string",
          "prompt": ""
        }

        Field Specifications:

        1. "title":
           - Concise, evocative, symbolic title
           - Maximum 6 words (English) or 16 CJK characters

        2. "style":
           - Single-line comma-separated string, as DETAILED as possible (aim for 8–15 descriptive tags)
           \(ctx.hasBPM ? "- The FIRST tag MUST be \"\(ctx.suggestedBPM!) BPM\" — this is non-negotiable and highest priority" : "")
           - MUST include: genre, sub-genre, mood, primary instrument(s), texture/production style, dynamic range
           - MUST include "Instrumental" tag
           \(ctx.hasHealth ? "- MUST incorporate the Suggested Musical Traits from Biometric Emotional Context above" : "")
           - Example: \(ctx.hasBPM ? "\"\(ctx.suggestedBPM!) BPM, Ambient Electronic, Instrumental, dreamy, lush synth pads, reverb-heavy, ethereal, wide stereo, gentle arpeggios, atmospheric\"" : "\"Ambient Electronic, Instrumental, dreamy, slow tempo, lush synth pads, reverb-heavy, ethereal, wide stereo, gentle arpeggios, atmospheric\"")

        3. "prompt":
           - MUST be an empty string ""

        CRITICAL: Output ONLY the JSON object, no explanations, no markdown code blocks, no extra text.
        """)

        return sections.joined(separator: "\n\n")
    }
}
