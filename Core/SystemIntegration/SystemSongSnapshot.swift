import Foundation

enum SystemSongKind: String, Codable, CaseIterable, Hashable {
    case mine
    case memory
    case cocreate
    case shared

    var title: String {
        switch self {
        case .mine:
            return "Light"
        case .memory:
            return "Memories"
        case .cocreate:
            return "Co-create"
        case .shared:
            return "Shared"
        }
    }

    var symbolName: String {
        switch self {
        case .mine:
            return "rays"
        case .memory:
            return "photo.on.rectangle.angled"
        case .cocreate:
            return "person.2.fill"
        case .shared:
            return "square.and.arrow.down"
        }
    }
}

struct SystemSongSnapshot: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let prompt: String
    let style: String
    let audioURLString: String?
    let imageURLString: String?
    let createdAt: Date
    let kind: SystemSongKind
    let ownerId: UUID?
    let continueAtSec: Double?
    let duration: Double?

    var audioURL: URL? { audioURLString.flatMap(URL.init(string:)) }
    var imageURL: URL? { imageURLString.flatMap(URL.init(string:)) }

    var deepLinkURL: URL {
        var components = URLComponents()
        components.scheme = "momenta"
        components.host = "song"
        components.path = "/\(id)"
        components.queryItems = [
            URLQueryItem(name: "kind", value: kind.rawValue),
        ]
        return components.url ?? URL(string: "momenta://song/\(id)")!
    }

    var autoplayDeepLinkURL: URL {
        var components = URLComponents(url: deepLinkURL, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "autoplay", value: "1"))
        components?.queryItems = queryItems
        return components?.url ?? deepLinkURL
    }

    var widgetSubtitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d · h:mm a"
        return "\(kind.title) · \(formatter.string(from: createdAt))"
    }

    var sharedByLine: String? {
        guard kind == .shared else { return nil }
        let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Shared with you" : "Shared by \(trimmed)"
    }

    static var placeholder: SystemSongSnapshot {
        SystemSongSnapshot(
            id: "placeholder-song",
            title: "Evening Bloom",
            subtitle: "Josic",
            prompt: "Placeholder song for widgets",
            style: "Dream Pop",
            audioURLString: nil,
            imageURLString: nil,
            createdAt: Date(),
            kind: .shared,
            ownerId: nil,
            continueAtSec: nil,
            duration: nil
        )
    }
}

#if !APP_EXTENSION
extension SystemSongSnapshot {
    func asGeneratedMusic() -> GeneratedMusic {
        GeneratedMusic(
            id: id,
            title: title,
            style: style,
            prompt: prompt,
            audioURL: audioURL,
            imageURL: imageURL,
            sunoAudioId: nil,
            status: .completed,
            createdAt: createdAt,
            source: kind.generatedMusicSource,
            ownerId: ownerId,
            duration: duration,
            continueAtSec: continueAtSec
        )
    }

    static func from(_ music: GeneratedMusic, kind: SystemSongKind, subtitle: String? = nil) -> SystemSongSnapshot {
        SystemSongSnapshot(
            id: music.id,
            title: music.title.isEmpty ? "Untitled Song" : music.title,
            subtitle: subtitle ?? kind.title,
            prompt: music.prompt,
            style: music.style,
            audioURLString: music.audioURL?.absoluteString,
            imageURLString: music.imageURL?.absoluteString,
            createdAt: music.createdAt,
            kind: kind,
            ownerId: music.ownerId,
            continueAtSec: music.continueAtSec,
            duration: music.duration
        )
    }
}

private extension SystemSongKind {
    var generatedMusicSource: String {
        switch self {
        case .mine:
            return "mine"
        case .memory:
            return "memory"
        case .cocreate:
            return "cocreate"
        case .shared:
            return "shared"
        }
    }
}
#endif
