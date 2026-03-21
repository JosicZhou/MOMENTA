//
//  ShareView.swift
//  Butterfly
//
//  临时测试界面：验证 Memory 音乐生成全链路。
//  只保留最简交互：输入框 + 语言选择 + 纯音乐开关 + 生成按钮 + 结果。
//  未来把 vm.generate() 等调用迁移到正式 UI 即可。
//

import SwiftUI

struct ShareView: View {

    @StateObject private var vm = MemoryViewModel()
    @Environment(PlayerManager.self) private var playerManager
    @State private var showImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary

    var body: some View {
        VStack(spacing: 24) {

            Spacer()

            // 图片预览 / 选择
            if let image = vm.selectedImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Button {
                        vm.selectedImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .padding(8)
                }
                .padding(.horizontal)
            } else {
                HStack(spacing: 12) {
                    Button {
                        imagePickerSource = .camera
                        showImagePicker = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        imagePickerSource = .photoLibrary
                        showImagePicker = true
                    } label: {
                        Label("Photo", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                }
            }

            // 输入
            TextField("Describe a memory...", text: $vm.prompt, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            // 语言 + 纯音乐
            HStack(spacing: 16) {
                Picker("", selection: $vm.language) {
                    Text("EN").tag("en")
                    Text("中文").tag("zh")
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                Toggle(isOn: $vm.instrumentalOnly) {
                    Label("Instrumental", systemImage: "music.note")
                        .font(.subheadline)
                }
                .toggleStyle(.button)
                .tint(vm.instrumentalOnly ? .orange : .gray)
            }
            .padding(.horizontal)

            // 生成按钮
            Button {
                Task { await vm.generate() }
            } label: {
                Group {
                    if vm.isGenerating {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text(vm.generationProgress)
                        }
                    } else {
                        Label("Generate", systemImage: "wand.and.stars")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isGenerating)
            .padding(.horizontal)

            // 结果
            if let music = vm.generatedMusic {
                VStack(spacing: 6) {
                    Text(music.title)
                        .font(.headline)
                    Text(music.style)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(music.audioURL != nil ? "Audio Ready" : "No Audio URL")
                        .font(.caption2)
                        .foregroundStyle(music.audioURL != nil ? .green : .red)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
                .padding(.horizontal)
            }

            Spacer()
        }
        .alert("Error", isPresented: $vm.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: imagePickerSource, selectedImage: $vm.selectedImage)
        }
        .task {
            await vm.requestHealthAccess()
            await vm.fetchEnvironment()
        }
        .onChange(of: vm.generatedMusic) { _, newMusic in
            guard let music = newMusic else { return }
            playerManager.currentMusic = music
            playerManager.lyrics = []
            playerManager.currentLineIndex = 0
            playerManager.showLyrics = false
            playerManager.lyricsControlsVisible = true
            playerManager.play()
        }
    }
}
