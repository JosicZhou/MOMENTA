//
//  MemoriesView.swift
//  Butterfly
//
//  ⚠️ 临时测试 LiquidWindow 组件 - 测试完成后恢复原代码
//

import SwiftUI

struct MemoriesView: View {
    var body: some View {
        ZStack {
            // 流光溢彩背景
            IridescentBackground()
                .ignoresSafeArea()

            // 用 ScrollView 让系统检测到可滚动区域，底部栏自动变通透
            ScrollView {
                VStack {
                    Spacer().frame(height: 120)

                    // LiquidWindow2 测试
                    LiquidWindow2(cornerRadius: 28, horizontalPadding: 24, verticalPadding: 24) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("User Info")
                                .font(.title2.bold())
                            
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(.gray.opacity(0.3))
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        Text("JD")
                                            .font(.headline)
                                    )
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("John Doe")
                                        .font(.headline)
                                    Text("Software Engineer")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Email:")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("john.doe@example.com")
                                }
                                HStack {
                                    Text("Location:")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("San Francisco, CA")
                                }
                                HStack {
                                    Text("Joined:")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("March 2023")
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(24)

                    Spacer().frame(height: 300)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - 原始代码（测试完成后恢复）
/*
struct MemoriesView: View {
    var body: some View {
        ZStack {
            IridescentBackground()
            
            VStack(spacing: 30) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(.primary.opacity(0.6))
                
                Text("MEMORIES")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("Your musical memories will appear here")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .ignoresSafeArea()
    }
}
*/
