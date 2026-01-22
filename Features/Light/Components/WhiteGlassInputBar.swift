//玻璃感输入框

import SwiftUI

struct WhiteGlassInputBar: View {
    @Binding var prompt: String
    let hasSelectedImage: Bool
    let isGenerating: Bool
    let onCameraPress: () -> Void
    let onPhotoPress: () -> Void
    let onGeneratePress: () -> Void
    
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onCameraPress) {
                Image(systemName: hasSelectedImage ? "camera.fill" : "camera")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 34)
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in onPhotoPress() }
            )
            
            TextField("", text: $prompt)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.black)
                .focused($isTextFieldFocused)
                .submitLabel(.done)
                .onSubmit {
                    if !prompt.isEmpty {
                        isTextFieldFocused = false
                        onGeneratePress()
                    }
                }
                .padding(.horizontal, 8)
            
            Spacer(minLength: 0)
            
            Button(action: {
                isTextFieldFocused = false
                onGeneratePress()
            }) {
                ZStack {
                    Circle()
                        .fill(.black)
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
            }
            .disabled(prompt.isEmpty || isGenerating)
            .opacity((prompt.isEmpty || isGenerating) ? 0.5 : 1.0)
            .padding(.trailing, 4)
        }
        .frame(width: 340, height: 50)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .circular)
                .fill(.white.opacity(0.96))
        )
        .shadow(color: Color.black.opacity(0.12), radius: 0, x: 0, y: 2)
    }
}

