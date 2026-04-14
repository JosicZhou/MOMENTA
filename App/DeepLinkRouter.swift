//
//  DeepLinkRouter.swift
//  MOMENTA
//
//  处理 app 内部深链，目前用于从系统日历回跳到指定 Memory 歌曲。
//

import Foundation
import SwiftUI
#if canImport(AppIntents)
import AppIntents
#endif

@MainActor
final class DeepLinkRouter: ObservableObject {
    @Published var pendingMemoryTaskId: String?
    @Published var pendingSystemSongRoute: SystemSongRoute?
    @Published var pendingShareRoute: ShareRoute?
    @Published var pendingFriendCode: String?

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "momenta" else { return false }

        if let shareRoute = shareRoute(from: url) {
            pendingShareRoute = shareRoute
            return true
        }

        if let systemSongRoute = systemSongRoute(from: url) {
            pendingSystemSongRoute = systemSongRoute
            return true
        }

        if let friendCode = friendCode(from: url) {
            pendingFriendCode = friendCode
            return true
        }

        if let taskId = memoryTaskId(from: url) {
            pendingMemoryTaskId = taskId
            return true
        }

        if let code = friendCode(from: url) {
            pendingFriendCode = code
            return true
        }

        return false
    }

    func clearPendingMemoryTaskId() {
        pendingMemoryTaskId = nil
    }

    func clearPendingSystemSongRoute() {
        pendingSystemSongRoute = nil
    }

    func clearPendingShareRoute() {
        pendingShareRoute = nil
    }

    func clearPendingFriendCode() {
        pendingFriendCode = nil
    }

    private func memoryTaskId(from url: URL) -> String? {
        guard url.host == "memory-song" else { return nil }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let taskId = components.queryItems?.first(where: { $0.name == "taskId" })?.value,
           !taskId.isEmpty {
            return taskId
        }

        let pathTaskId = url.pathComponents.dropFirst().first
        return pathTaskId?.isEmpty == false ? pathTaskId : nil
    }

    private func systemSongRoute(from url: URL) -> SystemSongRoute? {
        guard url.host == "song" else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let autoplay = components?.queryItems?.contains(where: { $0.name == "autoplay" && $0.value == "1" }) == true
        let kind = components?.queryItems?.first(where: { $0.name == "kind" })?.value
        let taskId = url.pathComponents.dropFirst().first

        guard let taskId, !taskId.isEmpty else { return nil }
        return SystemSongRoute(taskId: taskId, kind: kind, autoplay: autoplay)
    }

    private func shareRoute(from url: URL) -> ShareRoute? {
        guard url.host == "share" else { return nil }

        let components = url.pathComponents.filter { $0 != "/" }
        guard let first = components.first else { return nil }

        switch first {
        case "invitations":
            if components.count > 1,
               let id = UUID(uuidString: components[1]) {
                return .invitationDetail(id)
            }
            return .invitations
        case "start":
            return .start
        case "shared":
            guard components.count > 1 else { return .invitations }
            return .sharedSongDetail(components[1])
        case "activity":
            if components.count > 1,
               let id = UUID(uuidString: components[1]) {
                return .activityDetail(id)
            }
            return .start
        default:
            return nil
        }
    }

    private func friendCode(from url: URL) -> String? {
        guard url.host == "add-friend",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            return nil
        }
        return code
    }
}

enum ShareRoute: Equatable {
    case invitations
    case start
    case invitationDetail(UUID)
    case sharedSongDetail(String)
    case activityDetail(UUID)
}

struct SystemSongRoute: Equatable {
    let taskId: String
    let kind: String?
    let autoplay: Bool
}

#if canImport(AppIntents)
enum ShareAppDestination: String, AppEnum {
    case invitations
    case start

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Share Destination"
    }

    static var caseDisplayRepresentations: [ShareAppDestination: DisplayRepresentation] {
        [
            .invitations: DisplayRepresentation(title: "Invitations", subtitle: "Open incoming requests"),
            .start: DisplayRepresentation(title: "Start to Co-create", subtitle: "Open your songs and send flow")
        ]
    }

    var deepLink: URL {
        switch self {
        case .invitations:
            return URL(string: "momenta://share/invitations")!
        case .start:
            return URL(string: "momenta://share/start")!
        }
    }
}

struct OpenShareDestinationIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Share Destination"
    static var description = IntentDescription("Open one of MOMENTA's Share destinations.")
    static var openAppWhenRun = true

    @Parameter(title: "Destination")
    var destination: ShareAppDestination

    init() {}

    init(destination: ShareAppDestination) {
        self.destination = destination
    }

    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(destination.deepLink))
    }
}

struct MomentaAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: OpenShareDestinationIntent(destination: .invitations),
                phrases: [
                    "Open invitations in \(.applicationName)",
                    "Show my Share invitations in \(.applicationName)"
                ],
                shortTitle: "Invitations",
                systemImageName: "tray.full"
            ),
            AppShortcut(
                intent: OpenShareDestinationIntent(destination: .start),
                phrases: [
                    "Start co-creating in \(.applicationName)",
                    "Open Share in \(.applicationName)"
                ],
                shortTitle: "Start to Co-create",
                systemImageName: "sparkles.rectangle.stack"
            )
        ]
    }
}
#endif
