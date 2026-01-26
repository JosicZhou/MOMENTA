// 通用 AI音乐加载视图
//

import SwiftUI

struct AILoadingView: View {
    let progress: String
    @State private var animate = false
    
    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        RoundedRectangle(cornerRadius: 25)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.9),
                                        Color.white.opacity(0.7)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 6)
                            .frame(height: animate ? getAnimatedHeight(index: index) : 30)
                            .shadow(color: .white.opacity(0.3), radius: 4)
                            .animation(
                                Animation.easeInOut(duration: getAnimationDuration(index: index))
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.15),
                                value: animate
                            )
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    Text("AI is creating...")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.bottom, 125)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
        .onAppear {
            animate = true
        }
    }
    
    func getAnimatedHeight(index: Int) -> CGFloat {
        switch index {
        case 0: return 40
        case 1: return 55
        case 2: return 48
        default: return 30
        }
    }
    
    func getAnimationDuration(index: Int) -> Double {
        switch index {
        case 0: return 0.6
        case 1: return 0.8
        case 2: return 0.7
        default: return 0.6
        }
    }
}

