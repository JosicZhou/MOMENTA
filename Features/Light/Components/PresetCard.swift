//预设卡片

import SwiftUI

struct PresetCard: View {
    let title: String
    let icon: String
    let width: CGFloat
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 0) { }
                .frame(width: width, height: 95, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .circular)
                        .fill(.ultraThinMaterial.opacity(0.4))
                )
                .overlay(alignment: .center) {
                    ZStack(alignment: .center) {
                        Text(title)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .padding(.vertical, 1)
                            .frame(
                                width: getTextWidth(cardWidth: width),
                                height: 32,
                                alignment: .topLeading
                            )
                            .zIndex(10)
                            .offset(x: getTextOffsetX(cardWidth: width), y: -13)
                        
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .zIndex(10)
                            .offset(
                                x: getIconOffsetX(cardWidth: width),
                                y: getIconOffsetY(cardWidth: width)
                            )
                    }
                }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func getTextWidth(cardWidth: CGFloat) -> CGFloat {
        switch cardWidth {
        case 89: return 74
        case 101: return 79
        case 129: return 118
        default: return cardWidth - 15
        }
    }
    
    private func getTextOffsetX(cardWidth: CGFloat) -> CGFloat {
        switch cardWidth {
        case 89: return 0
        case 101: return 0
        case 129: return 2
        default: return 0
        }
    }
    
    private func getIconOffsetX(cardWidth: CGFloat) -> CGFloat {
        switch cardWidth {
        case 89: return -24
        case 101: return -26
        case 129: return -37
        default: return -(cardWidth / 2 - 22)
        }
    }
    
    private func getIconOffsetY(cardWidth: CGFloat) -> CGFloat {
        switch cardWidth {
        case 89: return 20
        case 101: return 19
        case 129: return 19
        default: return 20
        }
    }
}

