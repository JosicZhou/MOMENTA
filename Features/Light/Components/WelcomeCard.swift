//
//  WelcomeCard.swift
//  MOMENTA
//
//  Created by Gong on 2025-12-22.
//  Modified by Josic on 2026-01-26.


import SwiftUI
import WeatherKit

struct WelcomeCard: View {
    let userName: String
    let isGenerating: Bool
    let isRefreshingWeather: Bool
    let weatherSymbolName: String?
    
    var onWeatherTap: (() -> Void)? = nil
    var onDateTap: (() -> Void)? = nil
    
    // 获取当前日期 (格式: January 22, 2026)
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM dd, yyyy"
        return formatter.string(from: Date())
    }
    
    // 获取当前星期 (如: Thursday)
    private var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: Date())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 欢迎标题
            Text("WELCOME, \(userName.uppercased())")
                .font(.systemExpanded(size: 36, weight: .bold))
                .foregroundStyle(.white)
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 49)
            
            VStack(alignment: .leading, spacing: 1) {
                // 动态日期 (January 22, 2026)
                Text(formattedDate)
                    .font(.systemExpanded(size: 18, weight: .ultraLight))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                // 动态星期 (Thursday)
                Text(dayOfWeek)
                    .font(.systemExpanded(size: 18, weight: .ultraLight))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .contentShape(Rectangle()) // 使空白区域也可点击
            .onTapGesture {
                onDateTap?()
            }
            .padding(.top, 3)
            
            // 天气图标展示区域
            ZStack {
                if let symbol = weatherSymbolName {
                    Image(systemName: symbol)
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 46)
                        .transition(.opacity.combined(with: .scale))
                        // 当生成音乐或刷新天气时，图标都会有呼吸效果
                        .symbolEffect(.pulse, isActive: isGenerating || isRefreshingWeather)
                } else {
                    // 数据未加载时的占位符
                    Image(systemName: "cloud")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 52, height: 46)
                        .symbolEffect(.pulse, isActive: isRefreshingWeather)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onWeatherTap?()
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: weatherSymbolName)
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        WelcomeCard(
            userName: "JOSIC",
            isGenerating: false,
            isRefreshingWeather: false,
            weatherSymbolName: "sun.max.fill"
        )
        .padding()
    }
}

