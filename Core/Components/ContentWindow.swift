//
//  LiquidWindow2.swift
//  MOMENTA
//
//  复刻系统底部栏 / Tab 选中态：Liquid Glass 液态玻璃效果、自定义文字、可调宽度，无切换按钮。
//

import SwiftUI

/// 复刻系统底部栏 / Tab 选中态外观的条状窗口：Liquid Glass 液态玻璃、自定义内容、可调宽度。
struct LiquidWindow2<Content: View>: View {
    let content: () -> Content
    var width: CGFloat?
    var cornerRadius: CGFloat
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat

    init(
        width: CGFloat? = nil,
        cornerRadius: CGFloat = 24,
        horizontalPadding: CGFloat = 24,
        verticalPadding: CGFloat = 16,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.width = width
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: width ?? .infinity)
            .glassEffect(.clear, in: .capsule)
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [.purple.opacity(0.6), .orange.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack {
            Spacer()
            LiquidWindow2(width: 280) {
                Text("自定义文字内容")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}
