//
//  SettingsViewModel.swift
//  MOMENTA
//
//  设置页面的状态管理与业务逻辑。
//  所有偏好持久化到 UserDefaults，全局可通过 @AppStorage 读取。
//

import SwiftUI
import Foundation

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// 返回 nil 表示跟随系统
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Font Size Level

enum FontSizeLevel: String, CaseIterable, Identifiable {
    case small
    case standard
    case large
    case extraLarge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small:      return "Small"
        case .standard:   return "Standard"
        case .large:      return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small:      return .small
        case .standard:   return .medium
        case .large:      return .large
        case .extraLarge: return .xLarge
        }
    }
}

// MARK: - App Language

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case zhHans
    case zhHant
    case ja

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .en:     return "English"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .ja:     return "日本語"
        }
    }
}

// MARK: - SettingsViewModel

@MainActor
class SettingsViewModel: ObservableObject {

    // MARK: - Preferences (同步到 UserDefaults)

    @Published var appearanceMode: AppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode") }
    }

    @Published var fontSizeLevel: FontSizeLevel {
        didSet { UserDefaults.standard.set(fontSizeLevel.rawValue, forKey: "fontSizeLevel") }
    }

    @Published var appLanguage: AppLanguage {
        didSet { UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage") }
    }

    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    // MARK: - UI State

    @Published var showSignOutConfirmation = false
    @Published var showDeleteConfirmation = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - User Info

    var userEmail: String {
        AuthService.shared.currentUser?.email ?? ""
    }

    var displayName: String {
        if let email = AuthService.shared.currentUser?.email {
            return email.components(separatedBy: "@").first?.capitalized ?? "User"
        }
        return "User"
    }

    // MARK: - Init

    init() {
        let appearance = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        self.appearanceMode = AppearanceMode(rawValue: appearance) ?? .system

        let fontSize = UserDefaults.standard.string(forKey: "fontSizeLevel") ?? "standard"
        self.fontSizeLevel = FontSizeLevel(rawValue: fontSize) ?? .standard

        let language = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        self.appLanguage = AppLanguage(rawValue: language) ?? .system

        if let saved = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool {
            self.notificationsEnabled = saved
        } else {
            self.notificationsEnabled = true
        }
    }

    // MARK: - Account Actions

    func signOut() async {
        do {
            try await AuthService.shared.signOut()
        } catch {
            errorMessage = "退出登录失败: \(error.localizedDescription)"
        }
    }

    func switchAccount() async {
        // 退出当前账号，回到登录页面供用户选择新账号
        await signOut()
    }

    func deleteAccount() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // TODO: 调用 Supabase Admin API 真正删除用户数据
            // 目前先退出登录作为占位
            try await AuthService.shared.signOut()
        } catch {
            errorMessage = "删除账号失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }
}
