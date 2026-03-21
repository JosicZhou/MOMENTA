//
//  MemoriesView.swift
//  MOMENTA
//
//  ContentWindow 组件原型：Liquid Glass 容器内嵌
//  InputBar + Instrument/Style/Vocal 选项 + Globe + 日期时间。
//  遵循 Jony Ive 同心圆弧设计：外层 36 → 内层 26 → 圆形，
//  所有圆角使用 .continuous 超椭圆曲率。
//

import SwiftUI

struct MemoriesView: View {

    @State private var prompt: String = ""
    @FocusState private var isInputFocused: Bool

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let bottomInset = geometry.safeAreaInsets.bottom
            
            ZStack {
                // 背景图片 — 与 LightView 完全一致的嵌入方式
                // GeometryReader 提供精确尺寸 → .fill + .frame + .clipped 防溢出
                Image("ferris_wheel_night")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea()
                
                // 单屏固定布局：上部品牌 + 下部 ContentWindow
                VStack(spacing: 0) {
                    
                    // ── 上半部：Memory Palace 品牌居中 ──
                    Spacer()
                    
                    memoryPalaceHeader
                    
                    Spacer()
                    
                    // ── 下半部：ContentWindow 玻璃容器 ──
                    LiquidWindow2(
                        cornerRadius: 36,
                        horizontalPadding: 16,
                        verticalPadding: 20
                    ) {
                        VStack(spacing: 0) {
                            inputBar
                                .padding(.bottom, 28)
                            optionsRow
                                .padding(.bottom, 28)
                            globeIcon
                                .padding(.bottom, 16)
                            dateTimeRow
                        }
                    }
                    .padding(.horizontal, 24)
                    // 底部留出空间：safe area + tab bar(~56) + mini player(~56) + 呼吸间距(~20)
                    .padding(.bottom, bottomInset + 130)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Memory Palace Header

    /// 上半区域品牌标识：图标 + 标题
    private var memoryPalaceHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.systemExpanded(size: 28, weight: .light))
            Text("Memory\nPalace")
                .font(.systemExpanded(size: 28, weight: .semibold))
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(.white)
    }

    // MARK: - Layer 1: InputBar

    /// 白色半透明输入条（同心内圆角 26 = 外层 36 - padding 10）
    private var inputBar: some View {
        HStack(spacing: 0) {
            // 相机按钮
            Button {} label: {
                Image(systemName: "camera")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.black.opacity(0.7))
                    .frame(width: 44, height: 44)
            }

             // 文本输入
            TextField("", text: $prompt)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.black)
                .focused($isInputFocused)
                .submitLabel(.done)
                .onSubmit { isInputFocused = false }
                .padding(.horizontal, 4)

            Spacer(minLength: 0)

            // 音乐生成按钮（黑色圆形）
            Button {} label: {
                Circle()
                    .fill(.black)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.white)
                    )
            }
            .padding(.trailing, 4)
        }
        .frame(height: 50)
        .padding(.leading, 8)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.white.opacity(0.85))
        )
    }

    // MARK: - Layer 2: Options Row

    /// Instrument / Style / Vocal·Pure 三列选项
    private var optionsRow: some View {
        HStack(spacing: 0) {
            optionColumn(icon: "music.note.list", label: "Instrument")
            optionColumn(icon: "music.quarternote.3", label: "Style")
            optionColumn(icon: "mic", label: "Vocal/Pure")
        }
        .frame(maxWidth: .infinity)
    }

    private func optionColumn(icon: String, label: String) -> some View {
        Button {} label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                Text(label)
                    .font(.systemExpanded(size: 11, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Layer 3: Globe

    /// 居中地球图标，暗色圆形背景
    private var globeIcon: some View {
        Image(systemName: "globe.americas")
            .font(.system(size: 32, weight: .thin))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 52, height: 52)
            .background(
                Circle()
                    .fill(.black.opacity(0.15))
            )
    }

    // MARK: - Layer 4: Date + Time

    /// 日期与时间胶囊标签
    private var dateTimeRow: some View {
        HStack(spacing: 8) {
            Text(formattedDate)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(.black.opacity(0.12)))

            Text(formattedTime)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(.black.opacity(0.12)))
        }
        .font(.systemExpanded(size: 14, weight: .medium))
        .foregroundStyle(.white)
    }

    // MARK: - Formatters

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: Date())
    }

    private var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: Date())
    }
}

// MARK: - Preview

#Preview {
    MemoriesView()
}
