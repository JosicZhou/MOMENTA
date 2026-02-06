//
//  ProfileView.swift
//  Butterfly
//

import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: LightViewModel
    @ObservedObject var authViewModel: AuthViewModel
    
    var body: some View {
        ZStack {
            IridescentBackground()

            // 用 ScrollView 让系统检测到可滚动区域，底部栏自动变通透
            ScrollView {
                VStack(spacing: 30) {
                    Spacer().frame(height: 120)

                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 80, weight: .light))
                        .foregroundStyle(.primary.opacity(0.75))
                    
                    Text("PROFILE")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    
                    if let email = AuthService.shared.currentUser?.email {
                        Text(email)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    
                    Button(action: {
                        Task {
                            await authViewModel.signOut()
                        }
                    }) {
                        Text("退出登录")
                            .font(.headline)
                            .foregroundColor(.red)
                            .padding()
                            .frame(width: 200)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                    }
                    .padding(.top, 20)

                    Spacer().frame(height: 300)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea()
    }
}

