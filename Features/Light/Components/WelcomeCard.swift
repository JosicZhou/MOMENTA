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
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: Date()).uppercased()
    }

    private var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: Date()).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WELCOME, \(userName.uppercased())")
                .font(.systemExpanded(size: 28, weight: .regular))
                .foregroundStyle(.primary)
                .tracking(0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)
                .layoutPriority(1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(formattedDate)
                        .font(.systemExpanded(size: 18, weight: .ultraLight))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(dayOfWeek)
                        .font(.systemExpanded(size: 18, weight: .ultraLight))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onDateTap?()
                }

                weatherSymbol
                    .frame(width: 32, height: 32, alignment: .leading)
                    .padding(.top, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onWeatherTap?()
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var weatherSymbol: some View {
        if let symbol = weatherSymbolName {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(.primary)
                .transition(.opacity.combined(with: .scale))
                .symbolEffect(.pulse, isActive: isGenerating || isRefreshingWeather)
        } else {
            Image(systemName: "cloud")
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, isActive: isRefreshingWeather)
        }
    }
}

#Preview {
    ZStack {
        Color(uiColor: .systemGray6).ignoresSafeArea()
        WelcomeCard(
            userName: "JOSIC",
            isGenerating: false,
            isRefreshingWeather: false,
            weatherSymbolName: "sun.max.fill"
        )
        .padding()
    }
}
