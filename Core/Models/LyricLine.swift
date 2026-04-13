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
    /// 是否是段落标记（当前默认会被清洗掉，保留字段兼容旧视图）
    let isSection: Bool
}

struct WordCue: Hashable {
    let text: String
    let startTime: Double
    let endTime: Double
}

struct DisplayLine: Identifiable, Hashable {
    let id = UUID()
    let text: String
}

struct PhraseCue: Identifiable, Hashable {
    let id = UUID()
    let startTime: Double
    let endTime: Double
    let lines: [DisplayLine]
    let words: [WordCue]

    var text: String {
        lines.map(\.text).joined(separator: " ")
    }
}

struct LyricsPresentationModel: Equatable {
    let phrases: [PhraseCue]
    let isTimeSynced: Bool

    static let empty = LyricsPresentationModel(phrases: [], isTimeSynced: false)

    func phraseIndex(at time: TimeInterval, compensation: TimeInterval = 0) -> Int {
        guard !phrases.isEmpty else { return 0 }

        let adjustedTime = max(0, time + compensation)
        var low = 0
        var high = phrases.count - 1

        while low < high {
            let mid = (low + high + 1) / 2
            if phrases[mid].startTime <= adjustedTime {
                low = mid
            } else {
                high = mid - 1
            }
        }

        return max(0, min(low, phrases.count - 1))
    }

    static func build(from lines: [LyricLine], isTimeSynced: Bool) -> LyricsPresentationModel {
        guard !lines.isEmpty else { return .empty }

        var phrases: [PhraseCue] = []

        for line in lines where !line.isSection {
            let displaySegments = [LyricSanitizer.sanitizeLine(line.text)].filter { !$0.isEmpty }
            guard !displaySegments.isEmpty else { continue }

            phrases.append(
                PhraseCue(
                    startTime: line.startTime,
                    endTime: line.endTime,
                    lines: displaySegments.map(DisplayLine.init(text:)),
                    words: buildWordCues(from: line.text, startTime: line.startTime, endTime: line.endTime)
                )
            )
        }

        return LyricsPresentationModel(phrases: phrases, isTimeSynced: isTimeSynced)
    }

    private static func buildWordCues(from text: String, startTime: Double, endTime: Double) -> [WordCue] {
        let cleanedWords = text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .map(LyricSanitizer.sanitizeToken(_:))
            .filter { !$0.isEmpty }

        guard !cleanedWords.isEmpty else { return [] }

        let totalWeight = Double(cleanedWords.reduce(0) { $0 + max(1, $1.count) })
        let duration = max(0.2, endTime - startTime)
        var consumedWeight = 0.0

        return cleanedWords.enumerated().map { index, word in
            let weight = Double(max(1, word.count))
            let wordStart = startTime + duration * (consumedWeight / totalWeight)
            consumedWeight += weight
            let wordEnd = index == cleanedWords.count - 1
                ? endTime
                : startTime + duration * (consumedWeight / totalWeight)

            return WordCue(text: word, startTime: wordStart, endTime: wordEnd)
        }
    }
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

// MARK: - 歌词清洗与重组

enum LyricSanitizer {
    private static let structuralPattern = #"\[(?:verse|chorus|bridge|intro|outro|pre-chorus|post-chorus|hook|refrain|interlude|instrumental)[^\]]*\]"#
    private static let genericBracketPatterns = [
        #"\[[^\]]*\]"#,
        #"\([^\)]*\)"#,
        #"（[^）]*）"#,
        #"【[^】]*】"#,
        #"「[^」]*」"#,
        #"『[^』]*』"#
    ]

    static func sanitizePrompt(_ raw: String) -> String {
        let normalized = raw
            .replacingOccurrences(of: "\\ n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized
            .components(separatedBy: "\n")
            .map(sanitizeLine(_:))
            .filter { !$0.isEmpty }

        return lines.joined(separator: "\n")
    }

    static func sanitizeLine(_ raw: String) -> String {
        sanitizeBracketedContent(in: sanitizeStructuralMarkers(in: raw))
            .replacingOccurrences(of: #"[\t ]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" ?([,.;:!?])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sanitizeToken(_ raw: String) -> String {
        sanitizeLine(raw)
    }

    static func isStructuralMarker(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(of: structuralPattern, options: [.regularExpression, .caseInsensitive]) != nil
            && sanitizeLine(trimmed).isEmpty
    }

    private static func sanitizeStructuralMarkers(in text: String) -> String {
        text.replacingOccurrences(
            of: structuralPattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func sanitizeBracketedContent(in text: String) -> String {
        genericBracketPatterns.reduce(text) { partial, pattern in
            partial.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
    }
}

// MARK: - 解析 alignedWords → [LyricLine]

extension LyricLine {
    private struct ParsedToken {
        let text: String
        let startS: Double
        let endS: Double
        let forcesLineBreakBefore: Bool
    }

    private static let hardPauseSplitThreshold = 0.5
    private static let softPauseSplitThreshold = 0.35
    private static let punctuationPauseThreshold = 0.24
    private static let longLineWordThreshold = 8
    private static let longLineCharacterThreshold = 42
    private static let displayLineCharacterThreshold = 56
    private static let displayLineWordThreshold = 11
    
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
        
        // ===== 第二步：按换行符拆成 token，并保留显式换行边界 =====
        var tokens: [ParsedToken] = []
        for word in mergedWords {
            let parts = word.text.split(separator: "\n", omittingEmptySubsequences: false)
            for (partIndex, part) in parts.enumerated() {
                let trimmed = LyricSanitizer.sanitizeToken(part.trimmingCharacters(in: .whitespaces))
                guard !trimmed.isEmpty else { continue }
                tokens.append(
                    ParsedToken(
                        text: trimmed,
                        startS: word.startS,
                        endS: word.endS,
                        forcesLineBreakBefore: partIndex > 0
                    )
                )
            }
        }

        guard !tokens.isEmpty else { return [] }

        // ===== 第三步：显式换行 + 停顿/标点启发式分行，构建 LyricLine 数组 =====
        var lines: [LyricLine] = []
        var currentLineWords: [String] = []
        var lineStartTime: Double = tokens[0].startS
        var lineEndTime: Double = tokens[0].endS
        var previousToken: ParsedToken?

        func flushCurrentLine() {
            let lineText = currentLineWords.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !lineText.isEmpty else { return }
            lines.append(
                LyricLine(
                    text: lineText,
                    startTime: lineStartTime,
                    endTime: lineEndTime,
                    isSection: isSectionHeader(lineText)
                )
            )
        }

        for token in tokens {
            if LyricSanitizer.isStructuralMarker(token.text) || isSectionHeader(token.text) {
                if !currentLineWords.isEmpty {
                    flushCurrentLine()
                    currentLineWords = []
                }

                previousToken = nil
                continue
            }

            if token.forcesLineBreakBefore && !currentLineWords.isEmpty {
                flushCurrentLine()
                currentLineWords = []
            }

            if let previousToken,
               shouldSplitLine(
                previousToken: previousToken,
                nextToken: token,
                currentLineWords: currentLineWords
               ) {
                flushCurrentLine()
                currentLineWords = []
            }

            if currentLineWords.isEmpty {
                lineStartTime = token.startS
            }
            currentLineWords.append(token.text)
            lineEndTime = token.endS
            previousToken = token
        }

        if !currentLineWords.isEmpty {
            flushCurrentLine()
        }

        return lines
    }
    
    /// 判断是否是段落标记：[Verse], [Chorus], [Bridge], [Outro], [Intro] 等
    private static func isSectionHeader(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let pattern = #"^\[.+\]$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private static func shouldSplitLine(
        previousToken: ParsedToken,
        nextToken: ParsedToken,
        currentLineWords: [String]
    ) -> Bool {
        guard !currentLineWords.isEmpty else { return false }

        let gap = max(0, nextToken.startS - previousToken.endS)
        let currentCharacterCount = currentLineWords.joined(separator: " ").count
        let previousText = previousToken.text.trimmingCharacters(in: .whitespaces)
        let endsWithStrongPunctuation = previousText.last.map { ".!?。！？".contains($0) } ?? false
        let endsWithSoftPunctuation = previousText.last.map { ",;:，；：".contains($0) } ?? false
        let nextStartsCapitalized = nextToken.text.first?.isUppercase ?? false

        if gap >= hardPauseSplitThreshold {
            return true
        }

        if currentCharacterCount >= 24,
           (endsWithStrongPunctuation || endsWithSoftPunctuation) {
            return true
        }

        if gap >= softPauseSplitThreshold,
           endsWithStrongPunctuation || currentLineWords.count >= longLineWordThreshold || currentCharacterCount >= longLineCharacterThreshold {
            return true
        }

        if gap >= punctuationPauseThreshold,
           (endsWithStrongPunctuation || endsWithSoftPunctuation),
           currentLineWords.count >= 3 {
            return true
        }

        if currentCharacterCount >= 38,
           currentLineWords.count >= 6,
           nextStartsCapitalized {
            return true
        }

        if currentCharacterCount >= 52 || currentLineWords.count >= 10 {
            return true
        }

        return false
    }
    
    /// 从纯文本歌词（GeneratedMusic.prompt）解析为无时间戳的歌词行
    /// 作为时间戳 API 失败时的降级方案，按总时长均匀分配时间
    static func parseFromPlainText(_ text: String, totalDuration: Double) -> [LyricLine] {
        let normalized = LyricSanitizer.sanitizePrompt(text)

        let rawLines = normalized.components(separatedBy: "\n")
            .map { LyricSanitizer.sanitizeLine($0) }
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

    static func rebalanceDisplayText(_ line: String) -> [String] {
        let cleaned = LyricSanitizer.sanitizeLine(line)
        guard !cleaned.isEmpty else { return [] }
        return [cleaned]
    }
}
