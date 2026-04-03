//
//  MemoryLibraryModels.swift
//  MOMENTA
//
//  Memory 歌曲展示与本地标签存储模型。
//

import Foundation

struct MemorySongMetadata: Codable, Equatable {
    static let unknownLocationLabel = "Unknown Location"

    let journal: String
    let locationName: String?
    let typeLabel: String
    let createdAt: Date

    var resolvedLocationName: String {
        let trimmed = locationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? Self.unknownLocationLabel : trimmed
    }
}

struct MemoryLibraryItem: Identifiable, Equatable {
    let music: GeneratedMusic
    let metadata: MemorySongMetadata

    var id: String { music.id }
    var title: String { music.title }
    var journal: String { metadata.journal }
    var typeLabel: String { metadata.typeLabel }
    var locationName: String { metadata.resolvedLocationName }
    var createdAt: Date { music.createdAt }
}

enum MemoryDatePreset: String, CaseIterable, Identifiable {
    case today
    case tomorrow
    case thisWeekend
    case nextWeekend
    case thisMonth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "Today"
        case .tomorrow:
            return "Tomorrow"
        case .thisWeekend:
            return "This Weekend"
        case .nextWeekend:
            return "Next Weekend"
        case .thisMonth:
            return "This Month"
        }
    }
}

@MainActor
final class MemorySongMetadataStore {
    static let shared = MemorySongMetadataStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "memory-song-metadata.v1"
    private var cache: [String: MemorySongMetadata]

    private init() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: MemorySongMetadata].self, from: data) {
            cache = decoded
        } else {
            cache = [:]
        }
    }

    func metadata(for music: GeneratedMusic) -> MemorySongMetadata {
        if let stored = cache[music.id] {
            return stored
        }
        return fallbackMetadata(for: music)
    }

    func save(
        musicId: String,
        journal: String,
        locationName: String?,
        typeLabel: String,
        createdAt: Date
    ) {
        cache[musicId] = MemorySongMetadata(
            journal: normalizedJournal(from: journal),
            locationName: normalizedLocation(from: locationName),
            typeLabel: normalizedType(from: typeLabel),
            createdAt: createdAt
        )
        persist()
    }

    private func fallbackMetadata(for music: GeneratedMusic) -> MemorySongMetadata {
        MemorySongMetadata(
            journal: normalizedJournal(from: music.prompt),
            locationName: nil,
            typeLabel: primaryType(from: music.style),
            createdAt: music.createdAt
        )
    }

    private func normalizedJournal(from input: String) -> String {
        let collapsed = input
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if collapsed.isEmpty {
            return "No journal note"
        }

        return String(collapsed.prefix(72))
    }

    private func normalizedLocation(from input: String?) -> String? {
        let trimmed = input?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }

    private func normalizedType(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Memory" : trimmed
    }

    private func primaryType(from style: String) -> String {
        let candidates = style
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for candidate in candidates {
            let uppercased = candidate.uppercased()
            let lowercased = candidate.lowercased()
            if uppercased.contains("BPM") { continue }
            if lowercased.contains("vocal") { continue }
            if lowercased.contains("instrumental") { continue }
            return candidate
        }

        return "Memory"
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
