//
//  LoginView.swift
//  MOMENTA
//
//  iOS 26 Liquid Glass Style Login Interface - Bottom Sheet
//  与 ProfileView 保持一致的 glassEffect 设计语言
//

import SwiftUI
import AuthenticationServices
import GoogleSignInSwift

struct LoginView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var dragOffset: CGFloat = 0
    @State private var showSheet = false
    
    // Alert 状态
    @State private var showErrorAlert = false
    @State private var showSuccessAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        ZStack {
            // Background - Using desert background
            Image("desert_background")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            
            // Bottom Sheet
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    
                    // Login Sheet with Liquid Glass Effect
                    VStack(spacing: 24) {
                        // Handle - Draggable
                        Capsule()
                            .fill(.white.opacity(0.4))
                            .frame(width: 36, height: 5)
                            .padding(.top, 12)
                        
                        // Header Section
                        VStack(spacing: 8) {
                            Text("MOMENTA")
                                .font(.system(size: 34, weight: .bold, design: .default))
                                .tracking(2)
                                .foregroundStyle(.white)
                            
                            Text("Welcome to your moments")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        
                        // Input Section - Glass Effect Style
                        VStack(spacing: 14) {
                            // Email Field
                            HStack(spacing: 12) {
                                Image(systemName: "envelope")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .frame(width: 20)
                                
                                TextField("", text: $viewModel.email, prompt: Text("Email address").foregroundStyle(.white.opacity(0.4)))
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                                    .tint(.white)
                                    .autocapitalization(.none)
                                    .keyboardType(.emailAddress)
                                    .textContentType(.emailAddress)
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 52)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            
                            // Password Field
                            HStack(spacing: 12) {
                                Image(systemName: "lock")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .frame(width: 20)
                                
                                SecureField("", text: $viewModel.password, prompt: Text("Password").foregroundStyle(.white.opacity(0.4)))
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                                    .tint(.white)
                                    .textContentType(.password)
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 52)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        
                        // Continue Button
                        Button(action: {
                            Task { await viewModel.signInWithEmail() }
                        }) {
                            HStack(spacing: 8) {
                                Text("Continue")
                                    .font(.system(size: 17, weight: .semibold))
                                
                                if viewModel.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.8)
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(.white.opacity(0.2), in: Capsule())
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .disabled(viewModel.isLoading)
                        .opacity(viewModel.isLoading ? 0.7 : 1.0)
                        
                        // Sign Up Link
                        Button(action: {
                            Task { await viewModel.signUpWithEmail() }
                        }) {
                            Text("Don't have an account? **Sign up**")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .disabled(viewModel.isLoading)
                        
                        // Divider
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(.white.opacity(0.15))
                                .frame(height: 0.5)
                            
                            Text("or")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.4))
                            
                            Rectangle()
                                .fill(.white.opacity(0.15))
                                .frame(height: 0.5)
                        }
                        
                        // Social Login Icons - Glass Effect Style
                        HStack(spacing: 16) {
                            // Apple Sign In
                            Button(action: {
                                viewModel.signInWithApple()
                            }) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(width: 56, height: 56)
                                    .glassEffect(.regular.interactive(), in: .circle)
                            }
                            .buttonStyle(.plain)
                            
                            // Google Sign In
                            Button(action: {
                                Task { await viewModel.signInWithGoogle() }
                            }) {
                                Image("google_icon")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 22, height: 22)
                                    .frame(width: 56, height: 56)
                                    .glassEffect(.regular.interactive(), in: .circle)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, 8)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 32,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 32
                        )
                        .fill(.ultraThinMaterial.opacity(0.6))
                    )
                    .overlay(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 32,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 32
                        )
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                    )
                    .offset(y: dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Only allow dragging down
                                if value.translation.height > 0 {
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                // If dragged more than 150 points, dismiss
                                if value.translation.height > 150 {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        dragOffset = UIScreen.main.bounds.height
                                    }
                                } else {
                                    // Snap back
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .ignoresSafeArea()
        // Error Alert - 参考 SettingsView 的 alert 风格
        .alert("Oops", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        // Success Alert
        .alert("Success", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        // 监听 ViewModel 的 errorMessage 变化，转化为 alert
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if let message = newValue {
                // 判断是成功提示还是错误提示
                if message.contains("成功") || message.contains("Success") {
                    alertMessage = message
                    showSuccessAlert = true
                } else {
                    alertMessage = message
                    showErrorAlert = true
                }
                // 清除 viewModel 中的消息，避免重复弹出
                viewModel.errorMessage = nil
            }
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView(viewModel: AuthViewModel())
    }
}
