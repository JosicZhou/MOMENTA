//
//  SongRow.swift
//  MOMENTA
//
//  歌单详情页中的歌曲行组件。
//  作为 PlaylistDetailView 歌曲列表的每一行，统一展示：
//  歌曲封面、标题、时长，以及右侧操作入口（点赞、分享、添加到日历）。
//  使用 SF Symbols：heart / heart.fill、square.and.arrow.up、calendar.badge.plus
//

import SwiftUI

struct SongRow: View {
    let title: String
    let duration: String
    var artworkImage: UIImage? = nil
    var isLiked: Bool = false
    var onLike: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    var onAddToCalendar: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            // 封面
            Group {
                if let image = artworkImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color(white: 0.18))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // 标题 + 时长
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(duration)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 操作按钮
            HStack(spacing: 16) {
                Button(action: { onLike?() }) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isLiked ? .red : .secondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                Button(action: { onShare?() }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                Button(action: { onAddToCalendar?() }) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(height: 80)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }
}

#Preview {
    ZStack {
        IridescentBackground()
        SongRow(
            title: "Air Currents",
            duration: "3:24",
            isLiked: false
        )
        .padding(.horizontal, 20)
    }
}
