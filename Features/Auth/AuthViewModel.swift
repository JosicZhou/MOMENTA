//
//  AuthViewModel.swift
//  MOMENTA
//
//  认证功能状态管理
//

import Foundation
import Supabase
import AuthenticationServices
import GoogleSignIn
import UIKit

@MainActor
class AuthViewModel: NSObject, ObservableObject, ASAuthorizationControllerDelegate {
    // 邮箱登录相关
    @Published var email = ""
    @Published var password = ""
    
    // 状态相关
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isAuthenticated = false
    
    private let authService = AuthService.shared
    
    // 用于 Apple 登录的 Nonce
    var currentNonce: String?
    
    override init() {
        super.init()
        // 初始化时检查当前状态
        self.isAuthenticated = authService.currentUser != nil
    }
    
    // MARK: - Email Login
    
    func signInWithEmail() async {
        guard !email.isEmpty && !password.isEmpty else {
            errorMessage = "请输入邮箱和密码"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await authService.signIn(email: email, password: password)
            isAuthenticated = true
        } catch {
            errorMessage = "登录失败: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func signUpWithEmail() async {
        guard !email.isEmpty && !password.isEmpty else {
            errorMessage = "请输入邮箱和密码"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await authService.signUp(email: email, password: password)
            // 注意：如果开启了邮箱验证，这里可能还不是 isAuthenticated
            errorMessage = "注册成功，请检查邮箱验证"
        } catch {
            errorMessage = "注册失败: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Apple Login
    
    func signInWithApple() {
        // 生成 nonce
        let nonce = authService.generateNonce()
        currentNonce = nonce
        
        // 创建 Apple ID 授权请求
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = authService.sha256(nonce)
        
        // 启动授权流程
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }
    
    // MARK: - ASAuthorizationControllerDelegate
    
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            handleAppleSignIn(result: .success(authorization))
        }
    }
    
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            handleAppleSignIn(result: .failure(error))
        }
    }
    
    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            if let appleIDCredential = auth.credential as? ASAuthorizationAppleIDCredential {
                guard let idTokenData = appleIDCredential.identityToken,
                      let idToken = String(data: idTokenData, encoding: .utf8),
                      let nonce = currentNonce else {
                    errorMessage = "无法获取 Apple ID 令牌"
                    return
                }
                
                Task {
                    isLoading = true
                    do {
                        try await authService.signInWithApple(idToken: idToken, nonce: nonce)
                        isAuthenticated = true
                    } catch {
                        errorMessage = "Apple 登录失败: \(error.localizedDescription)"
                    }
                    isLoading = false
                }
            }
        case .failure(let error):
            errorMessage = "Apple 授权失败: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Google Login
    
    /// 触发 Google 登录流程
    func signInWithGoogle() async {
        // 1. 获取当前最上层的 ViewController
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            self.errorMessage = "无法获取界面句柄"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // 2. 调用 Google SDK 进行登录
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            
            // 3. 从结果中提取 Token
            guard let idToken = result.user.idToken?.tokenString else {
                throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "获取 Google ID Token 失败"])
            }
            
            let accessToken = result.user.accessToken.tokenString
            
            // 4. 将 Token 传给 Supabase
            try await authService.signInWithGoogle(idToken: idToken, accessToken: accessToken)
            
            // 5. 更新状态
            self.isAuthenticated = true
            
        } catch {
            let nsError = error as NSError
            if nsError.code == GIDSignInError.canceled.rawValue {
                print("用户取消了登录")
            } else {
                self.errorMessage = "Google 登录失败: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
    
    // MARK: - Sign Out
    
    func signOut() async {
        do {
            try await authService.signOut()
            isAuthenticated = false
        } catch {
            errorMessage = "退出登录失败: \(error.localizedDescription)"
        }
    }
}
