//
//  LyricLine.swift
//  MOMENTA
//
//  歌词数据模型：单行歌词 + Suno 时间戳歌词 API 响应 + 解析逻辑。
//

import Foundation

// MARK: - 单行歌词模型

struct LyricLine: Identifiable {
    let id = UUID()
    /// 歌词文本，如 "Bite chunks out of me"
    let text: String
    /// 开始时间（秒）
    let startTime: Double
    /// 结束时间（秒）
    let endTime: Double
    /// 是否是段落标记，如 [Verse]、[Chorus]
    let isSection: Bool
}

// MARK: - Suno 时间戳歌词 API 响应

struct TimestampedLyricsResponse: Codable {
    let code: Int
    let msg: String
    let data: TimestampedLyricsData?
    
    struct TimestampedLyricsData: Codable {
        let alignedWords: [AlignedWord]?
    }
    
    struct AlignedWord: Codable {
        let word: String
        let success: Bool?
        let startS: Double
        let endS: Double
    }
}

// MARK: - 解析 alignedWords → [LyricLine]

extension LyricLine {
    
    /// 将 Suno API 返回的 alignedWords 解析为按行分组的歌词数组
    static func parse(from words: [TimestampedLyricsResponse.AlignedWord]) -> [LyricLine] {
        guard !words.isEmpty else { return [] }
        
        // ===== 第一步：预处理，合并跨 word 的换行标记 =====
        // Suno API 可能将 \n 拆分到两个相邻 word：
        //   word[i] = "[Chorus]\"（末尾反斜杠）
        //   word[i+1] = "nIt's "（开头 n）
        // 需要先合并回来，否则单 word 内的 replacingOccurrences 永远找不到 \n
        struct MergedWord {
            let text: String
            let startS: Double
            let endS: Double
        }
        
        var mergedWords: [MergedWord] = []
        var i = 0
        while i < words.count {
            var text = words[i].word
            var endS = words[i].endS
            let startS = words[i].startS
            
            // 合并跨 word 的 \n：当前 word 以 \ 结尾 + 下一个 word 以 n 开头
            while text.hasSuffix("\\") && i + 1 < words.count && words[i + 1].word.hasPrefix("n") {
                text = String(text.dropLast()) + "\n" + String(words[i + 1].word.dropFirst())
                endS = words[i + 1].endS
                i += 1
            }
            
            // 处理单 word 内的各种 \n 变体
            text = text
                .replacingOccurrences(of: "\\ n", with: "\n")  // 反斜杠+空格+n
                .replacingOccurrences(of: "\\n", with: "\n")    // 反斜杠+n
            
            mergedWords.append(MergedWord(text: text, startS: startS, endS: endS))
            i += 1
        }
        
        // ===== 第二步：按换行符分行，构建 LyricLine 数组 =====
        var lines: [LyricLine] = []
        var currentLineWords: [String] = []
        var lineStartTime: Double = mergedWords[0].startS
        var lineEndTime: Double = mergedWords[0].endS
        
        for word in mergedWords {
            let parts = word.text.split(separator: "\n", omittingEmptySubsequences: false)
            
            for (partIndex, part) in parts.enumerated() {
                if partIndex > 0 {
                    // 遇到换行：把当前积累的行输出
                    if !currentLineWords.isEmpty {
                        let lineText = currentLineWords.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                        if !lineText.isEmpty {
                            lines.append(LyricLine(
                                text: lineText,
                                startTime: lineStartTime,
                                endTime: lineEndTime,
                                isSection: isSectionHeader(lineText)
                            ))
                        }
                    }
                    // 重置，开始新行
                    currentLineWords = []
                    lineStartTime = word.startS
                }
                
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    if currentLineWords.isEmpty {
                        lineStartTime = word.startS
                    }
                    currentLineWords.append(trimmed)
                    lineEndTime = word.endS
                }
            }
        }
        
        // 输出最后一行
        if !currentLineWords.isEmpty {
            let lineText = currentLineWords.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !lineText.isEmpty {
                lines.append(LyricLine(
                    text: lineText,
                    startTime: lineStartTime,
                    endTime: lineEndTime,
                    isSection: isSectionHeader(lineText)
                ))
            }
        }
        
        return lines
    }
    
    /// 判断是否是段落标记：[Verse], [Chorus], [Bridge], [Outro], [Intro] 等
    private static func isSectionHeader(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let pattern = #"^\[.+\]$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
    
    /// 从纯文本歌词（GeneratedMusic.prompt）解析为无时间戳的歌词行
    /// 作为时间戳 API 失败时的降级方案，按总时长均匀分配时间
    static func parseFromPlainText(_ text: String, totalDuration: Double) -> [LyricLine] {
        // 先将字面 "\n"（反斜杠+n 两个字符）替换为真正的换行符
        // 数据库中的 prompt 字段可能存储的是转义后的字面字符串
        let normalized = text
            .replacingOccurrences(of: "\\ n", with: "\n")  // 反斜杠+空格+n
            .replacingOccurrences(of: "\\n", with: "\n")    // 反斜杠+n
            .replacingOccurrences(of: "\\r", with: "")
        
        let rawLines = normalized.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard !rawLines.isEmpty, totalDuration > 0 else { return [] }
        
        let interval = totalDuration / Double(rawLines.count)
        
        return rawLines.enumerated().map { index, line in
            LyricLine(
                text: line,
                startTime: Double(index) * interval,
                endTime: Double(index + 1) * interval,
                isSection: isSectionHeader(line)
            )
        }
    }
}
