//
//  AuthService.swift
//  MOMENTA
//
//  用户认证服务，支持 Apple、Google 和邮箱登录
//

import Foundation
import Supabase
import AuthenticationServices
import CryptoKit

class AuthService {
    static let shared = AuthService()
    private let client = SupabaseConfig.client
    
    private init() {}
    
    // MARK: - Session Management
    
    /// 获取当前用户
    var currentUser: User? {
        return client.auth.currentUser
    }
    
    /// 监听认证状态变化
    func authStateChanges() -> AsyncStream<(event: AuthChangeEvent, session: Session?)> {
        return client.auth.authStateChanges.eraseToStream()
    }
    
    // MARK: - Email Authentication
    
    /// 邮箱密码登录
    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }
    
    /// 邮箱密码注册
    func signUp(email: String, password: String) async throws {
        try await client.auth.signUp(email: email, password: password)
    }
    
    // MARK: - Apple Authentication
    
    /// Apple 登录逻辑
    /// 注意：这里需要配合 AuthenticationServices 的授权结果
    func signInWithApple(idToken: String, nonce: String) async throws {
        try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )
    }
    
    // MARK: - Google Authentication
    
    /// Google 登录逻辑
    /// 注意：这里需要配合 GoogleSignIn SDK 获取 idToken
    func signInWithGoogle(idToken: String, accessToken: String?) async throws {
        try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .google,
                idToken: idToken,
                accessToken: accessToken
            )
        )
    }
    
    // MARK: - Sign Out
    
    /// 退出登录
    func signOut() async throws {
        try await client.auth.signOut()
    }
    
    // MARK: - Helpers
    
    /// 生成用于 OAuth 的随机 Nonce
    func generateNonce() -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = 32
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in UInt8.random(in: 0...255) }
            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }
    
    /// 对 Nonce 进行 SHA256 哈希处理（Apple 登录需要）
    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap { String(format: "%02x", $0) }.joined()
        return hashString
    }
}
