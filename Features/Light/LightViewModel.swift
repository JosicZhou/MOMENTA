//
//  LightViewModel.swift
//  Butterfly
//
//  Light 功能模块的 ViewModel，调用 Photo2MusicManager 进行业务处理
//

import Foundation
import Combine
import AVFoundation
import SwiftUI
import PhotosUI

@MainActor
class LightViewModel: ObservableObject {
    
    // UI binding variables
    @Published var selectedImage: UIImage?
    @Published var prompt: String = ""
    @Published var style: String = ""
    @Published var instrument: String = ""
    @Published var hasVocals: Bool = true
    @Published var language: String = "en"
    @Published var useAIRecommendation: Bool = true
    
    // UI state control
    @Published var genNonce: CGFloat = 0 // Trigger generation
    @Published var playtoggle: CGFloat = 0 // Play/pause toggle
    
    // Internal state
    @Published var isGenerating: Bool = false
    @Published var generationProgress: String = "Preparing..."
    @Published var generatedMusic: GeneratedMusic?
    @Published var generatedSongs: [GeneratedMusic] = []
    @Published var errorMessage: String?
    @Published var isPlaying: Bool = false
    
    // Camera control
    @Published var showImagePicker = false
    @Published var imagePickerSourceType: UIImagePickerController.SourceType = .camera
    
    // Error handling
    @Published var showErrorSheet = false
    
    // Video player (interface for dynamic video)
    @Published var videoPlayer: AVPlayer?
    @Published var isVideoPlaying: Bool = false
    
    private let aiGenerator: Photo2MusicManager
    private var audioPlayer: AVPlayer?
    
    init(aiGenerator: Photo2MusicManager? = nil) {
        if let aiGenerator = aiGenerator {
            self.aiGenerator = aiGenerator
        } else {
            self.aiGenerator = Photo2MusicManager.createDefault()
        }
    }
    
    // MARK: - Camera Actions
    
    func openCamera() {
        imagePickerSourceType = .camera
        showImagePicker = true
    }
    
    func openPhotoLibrary() {
        imagePickerSourceType = .photoLibrary
        showImagePicker = true
    }
    
    func removeImage() {
        selectedImage = nil
    }
    
    // MARK: - Video Player Interface
    
    func loadVideo(from url: URL) {
        videoPlayer = AVPlayer(url: url)
        videoPlayer?.play()
        isVideoPlaying = true
    }
    
    func loadVideo(from fileURL: URL, isLocal: Bool) {
        if isLocal {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                errorMessage = "Video file not found"
                return
            }
        }
        videoPlayer = AVPlayer(url: fileURL)
        videoPlayer?.play()
        isVideoPlaying = true
    }
    
    func toggleVideoPlayback() {
        guard let player = videoPlayer else { return }
        
        if isVideoPlaying {
            player.pause()
            isVideoPlaying = false
        } else {
            player.play()
            isVideoPlaying = true
        }
    }
    
    func removeVideo() {
        videoPlayer?.pause()
        videoPlayer = nil
        isVideoPlaying = false
    }
    
    // MARK: - Music Generation
    
    func generateMusic() async {
        isGenerating = true
        errorMessage = nil
        generationProgress = "Preparing..."
        
        let parameters = MusicParameters(
            style: style,
            instrument: instrument,
            hasVocals: hasVocals,
            language: language,
            useAIRecommendation: useAIRecommendation
        )
        
        do {
            let music = try await aiGenerator.generate(
                userInput: prompt,
                selectedImage: selectedImage,
                parameters: parameters,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.generationProgress = progress
                    }
                }
            )
            
            generatedMusic = music
            addGeneratedMusic(music)
            generationProgress = "Complete!"
            
        } catch {
            let errorMsg = error.localizedDescription
            print("❌ Generation failed: \(errorMsg)")
            errorMessage = errorMsg
            showError(errorMsg)
        }
        
        isGenerating = false
    }
    
    // MARK: - Playback
    
    func playMusic() {
        guard let music = generatedMusic else {
            showError("No music to play")
            return
        }
        
        guard let audioURL = music.audioURL else {
            showError("Invalid audio URL")
            return
        }
        
        if audioPlayer == nil {
            audioPlayer = AVPlayer(url: audioURL)
        }
        
        audioPlayer?.play()
        isPlaying = true
    }
    
    func pauseMusic() {
        audioPlayer?.pause()
        isPlaying = false
    }
    
    func togglePlayback() {
        if isPlaying {
            pauseMusic()
        } else {
            playMusic()
        }
    }
    
    // MARK: - Validation
    
    func validateInput() -> Bool {
        if prompt.isEmpty && selectedImage == nil {
            showError("Please enter a description or select an image")
            return false
        }
        return true
    }
    
    // MARK: - Error Handling
    
    func showError(_ message: String) {
        errorMessage = message
        showErrorSheet = true
    }
    
    func dismissError() {
        errorMessage = nil
        showErrorSheet = false
    }
    
    // MARK: - Reset
    
    func reset() {
        prompt = ""
        selectedImage = nil
        style = ""
        instrument = ""
        hasVocals = true
        language = "en"
        useAIRecommendation = true
        generatedMusic = nil
        errorMessage = nil
        showErrorSheet = false
        isPlaying = false
        audioPlayer = nil
    }

    // MARK: - Library Management

    private func addGeneratedMusic(_ music: GeneratedMusic) {
        if let index = generatedSongs.firstIndex(where: { $0.id == music.id }) {
            generatedSongs[index] = music
        } else {
            generatedSongs.insert(music, at: 0)
        }
    }

    func removeGeneratedMusic(_ music: GeneratedMusic) {
        generatedSongs.removeAll { $0.id == music.id }
    }
}
