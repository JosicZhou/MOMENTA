//
//  DeepLinkRouter.swift
//  MOMENTA
//
//  处理 app 内部深链，目前用于从系统日历回跳到指定 Memory 歌曲。
//

import Foundation
import SwiftUI

@MainActor
final class DeepLinkRouter: ObservableObject {
    @Published var pendingMemoryTaskId: String?

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "momenta" else { return false }

        if let taskId = memoryTaskId(from: url) {
            pendingMemoryTaskId = taskId
            return true
        }

        return false
    }

    func clearPendingMemoryTaskId() {
        pendingMemoryTaskId = nil
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
}
