//预设卡片

import SwiftUI

struct PresetCard: View {
    let title: String
    let icon: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.84)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 114, alignment: .topLeading)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.18))
                .glassEffect(
                    .regular.interactive(),
                    in: .rect(cornerRadius: 18)
                )
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18), lineWidth: 0.8)
                }
        }
    }
}

#Preview {
    ZStack {
        Color(uiColor: .systemGray6).ignoresSafeArea()
        HStack(spacing: 9) {
            PresetCard(
                title: "Today's my pet's birthday",
                icon: "music.note",
                action: {}
            )
            PresetCard(
                title: "It's a raining day.",
                icon: "cloud.rain",
                action: {}
            )
            PresetCard(
                title: "Play some piano.",
                icon: "pianokeys",
                action: {}
            )
        }
        .padding(.horizontal, 24)
    }
}
