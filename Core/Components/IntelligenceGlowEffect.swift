//
//  IntelligenceGlowEffect.swift
//  MOMENTA
//
//  Apple Intelligence 风格光晕效果（内联实现，参考 Livsy90/IntelligenceGlow）
//  用于生成中时的 MusicPlayerBar 描边光晕
//

import SwiftUI

// MARK: - View Extension

extension View {
    /// 在指定形状上应用 Apple Intelligence 风格光晕作为背景
    func intelligenceBackground<S: InsettableShape>(
        in shape: S,
        lineWidths: [CGFloat] = [4, 6, 8],
        blurs: [CGFloat] = [0, 2, 6],
        updateInterval: TimeInterval = 0.4,
        animationDurations: [TimeInterval] = [0.5, 0.6, 0.8]
    ) -> some View {
        background(
            shape.intelligenceStroke(
                lineWidths: lineWidths,
                blurs: blurs,
                updateInterval: updateInterval,
                animationDurations: animationDurations
            )
        )
    }
    
    /// 在指定形状上应用 Apple Intelligence 风格光晕作为 overlay
    func intelligenceOverlay<S: InsettableShape>(
        in shape: S,
        lineWidths: [CGFloat] = [4, 6, 8],
        blurs: [CGFloat] = [0, 2, 6],
        updateInterval: TimeInterval = 0.4,
        animationDurations: [TimeInterval] = [0.5, 0.6, 0.8]
    ) -> some View {
        overlay(
            shape.intelligenceStroke(
                lineWidths: lineWidths,
                blurs: blurs,
                updateInterval: updateInterval,
                animationDurations: animationDurations
            )
        )
    }
}

// MARK: - Shape Extension

extension InsettableShape {
    /// Apple Intelligence 风格发光描边
    func intelligenceStroke(
        lineWidths: [CGFloat] = [4, 6, 8],
        blurs: [CGFloat] = [0, 2, 6],
        updateInterval: TimeInterval = 0.4,
        animationDurations: [TimeInterval] = [0.5, 0.6, 0.8]
    ) -> some View {
        IntelligenceStrokeView(
            shape: self,
            lineWidths: lineWidths,
            blurs: blurs,
            updateInterval: updateInterval,
            animationDurations: animationDurations
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Intelligence Style Gradient

private extension Array where Element == Gradient.Stop {
    static var intelligenceStyle: [Gradient.Stop] {
        [
            Color(red: 188/255, green: 130/255, blue: 243/255),
            Color(red: 245/255, green: 185/255, blue: 234/255),
            Color(red: 141/255, green: 159/255, blue: 255/255),
            Color(red: 255/255, green: 103/255, blue: 120/255),
            Color(red: 255/255, green: 186/255, blue: 113/255),
            Color(red: 198/255, green: 134/255, blue: 255/255)
        ]
        .map { Gradient.Stop(color: $0, location: Double.random(in: 0...1)) }
        .sorted { $0.location < $1.location }
    }
}

// MARK: - Stroke View

private struct IntelligenceStrokeView<S: InsettableShape>: View {
    let shape: S
    let lineWidths: [CGFloat]
    let blurs: [CGFloat]
    let updateInterval: TimeInterval
    let animationDurations: [TimeInterval]
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stops: [Gradient.Stop] = [Gradient.Stop].intelligenceStyle
    
    var body: some View {
        let layerCount = min(lineWidths.count, blurs.count, animationDurations.count)
        let gradient = AngularGradient(
            gradient: Gradient(stops: stops),
            center: .center
        )
        
        ZStack {
            ForEach(0..<layerCount, id: \.self) { i in
                shape
                    .strokeBorder(gradient, lineWidth: lineWidths[i])
                    .blur(radius: blurs[i])
                    .animation(
                        reduceMotion ? .linear(duration: 0) : .easeInOut(duration: animationDurations[i]),
                        value: stops
                    )
            }
        }
        .task(id: updateInterval) {
            while !Task.isCancelled {
                stops = [Gradient.Stop].intelligenceStyle
                try? await Task.sleep(for: .seconds(updateInterval))
            }
        }
    }
}
