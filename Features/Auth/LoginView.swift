//
//  LoginView.swift
//  MOMENTA
//
//  iOS 26 Liquid Glass Style Login Interface - Bottom Sheet
//

import SwiftUI
import AuthenticationServices
import GoogleSignInSwift

struct LoginView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false
    
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
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color.black.opacity(0.15))
                            .frame(width: 40, height: 5)
                            .padding(.top, 8)
                        
                        // Header Section
                        VStack(spacing: 8) {
                            Text("MOMENTA")
                                .font(.system(size: 36, weight: .bold, design: .default))
                                .tracking(2)
                                .foregroundColor(.black)
                            
                            Text("Welcome to your moments")
                                .font(.system(size: 15))
                                .foregroundColor(.black.opacity(0.45))
                        }
                        
                        // Input Section - Liquid Glass Style
                        VStack(spacing: 12) {
                            // Email Field
                            TextField("", text: $viewModel.email, prompt: Text("Email address").foregroundColor(.black.opacity(0.5)))
                                .font(.system(size: 16))
                                .foregroundColor(.black)
                                .accentColor(.black)
                                .padding(.horizontal, 18)
                                .frame(height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 26, style: .circular)
                                        .fill(.white.opacity(0.96))
                                )
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)
                            
                            // Password Field
                            SecureField("", text: $viewModel.password, prompt: Text("Password").foregroundColor(.black.opacity(0.5)))
                                .font(.system(size: 16))
                                .foregroundColor(.black)
                                .accentColor(.black)
                                .padding(.horizontal, 18)
                                .frame(height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 26, style: .circular)
                                        .fill(.white.opacity(0.96))
                                )
                        }
                        
                        // Continue Button
                        Button(action: {
                            Task { await viewModel.signInWithEmail() }
                        }) {
                            Text("Continue")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.black)
                                .cornerRadius(26)
                                .shadow(color: Color.black.opacity(0.2), radius: 8, y: 2)
                        }
                        
                        // Sign Up Link
                        Button(action: {
                            Task { await viewModel.signUpWithEmail() }
                        }) {
                            Text("Don't have an account? Sign up")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                        }
                        
                        // Divider
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Color.black.opacity(0.15))
                                .frame(height: 1)
                            
                            Text("or")
                                .font(.system(size: 13))
                                .foregroundColor(.black.opacity(0.4))
                            
                            Rectangle()
                                .fill(Color.black.opacity(0.15))
                                .frame(height: 1)
                        }
                        
                        // Social Login Icons
                        HStack(spacing: 16) {
                            // Apple Sign In
                            Button(action: {
                                viewModel.signInWithApple()
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: 56, height: 56)
                                    
                                    // Apple logo
                                    Image("apple_icon")
                                        .resizable()
                                        .renderingMode(.template)
                                        .foregroundColor(.white)
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 24, height: 24)
                                }
                            }
                            
                            // Google Sign In
                            Button(action: {
                                Task { await viewModel.signInWithGoogle() }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 56, height: 56)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                        )
                                    
                                    // Google logo
                                    Image("google_icon")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 24, height: 24)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 32,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 32
                        )
                        .fill(.white.opacity(0.25))
                        .background(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 32,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 32
                            )
                            .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 32,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 32
                            )
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                        )
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 40, y: -10)
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
                                        dragOffset = geometry.size.height
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
            
            // Loading & Error States
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
            }
            
            if let errorMessage = viewModel.errorMessage {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(10)
                        .padding()
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView(viewModel: AuthViewModel())
    }
}
