//
//  CommonUI.swift
//  Butterfly
//

import SwiftUI
import AVKit

// MARK: - GlassButtonStyle 实现

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 图片预览

struct ImagePreview: View {
    let image: UIImage
    let onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 280, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .black.opacity(0.35), radius: 30)
            
            Button(action: onRemove) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .offset(x: 12, y: -12)
        }
    }
}

// MARK: - 视频预览

struct VideoPreview: View {
    let player: AVPlayer
    let onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VideoPlayer(player: player)
                .frame(height: 400)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .black.opacity(0.35), radius: 30)
                .padding(.horizontal, 30)
            
            Button(action: onRemove) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.trailing, 42)
            .padding(.top, -12)
        }
    }
}

// MARK: - 音乐播放条

struct MusicPlayerBar: View {
    let music: GeneratedMusic
    let isPlaying: Bool
    let onPlayPause: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "music.note")
                .frame(width: 24, height: 24)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
            
            Text(music.title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white)
                .lineLimit(1)
            
            Spacer()
            
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .frame(width: 24, height: 24)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture {
            onPlayPause()
        }
    }
}

// MARK: - 图片选择器

struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.selectedImage = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.selectedImage = originalImage
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

