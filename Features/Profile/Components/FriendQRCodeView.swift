//
//  FriendQRCodeView.swift
//  MOMENTA
//
//  展示个人好友二维码，支持复制好友码和分享邀请链接。
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

struct FriendQRCodeView: View {
    let friendCode: String
    let displayName: String
    let avatarImage: UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var deepLinkURL: URL {
        URL(string: "momenta://add-friend?code=\(friendCode)")!
    }

    private var shareText: String {
        "Join me on MOMENTA! Add me with code: \(friendCode)\n\(deepLinkURL.absoluteString)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                avatarSection

                qrCodeImage
                    .frame(width: 220, height: 220)
                    .padding(20)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 20, y: 10)

                codeSection

                actionButtons

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("My QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var avatarSection: some View {
        VStack(spacing: 10) {
            Group {
                if let avatarImage {
                    Image(uiImage: avatarImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(uiColor: .systemIndigo), Color(uiColor: .systemPink)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 28, weight: .regular))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

            Text(displayName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var qrCodeImage: some View {
        if let image = generateQRCode(from: deepLinkURL.absoluteString) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
        } else {
            Image(systemName: "qrcode")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
        }
    }

    private var codeSection: some View {
        VStack(spacing: 6) {
            Text("Friend Code")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text(friendCode)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .tracking(3)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                UIPasteboard.general.string = friendCode
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
            } label: {
                Label(copied ? "Copied!" : "Copy Code", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(uiColor: .systemGray5), in: Capsule())
            }
            .buttonStyle(.plain)

            ShareLink(item: shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(.white)
                    .background(Color(uiColor: .systemIndigo), in: Capsule())
            }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scale = 1024.0 / outputImage.extent.width
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
