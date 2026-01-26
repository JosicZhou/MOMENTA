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
import CoreLocation
import WeatherKit

@MainActor
class LightViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    
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
    @Published var isRefreshingWeather: Bool = false
    @Published var generationProgress: String = "Preparing..."
    @Published var generatedMusic: GeneratedMusic?
    @Published var generatedSongs: [GeneratedMusic] = []
    @Published var errorMessage: String?
    @Published var isPlaying: Bool = false
    
    // Weather & Location state
    @Published var weatherSymbolName: String?
    
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
    
    private let locationManager = CLLocationManager()
    private let weatherService = WeatherService.shared
    
    init(aiGenerator: Photo2MusicManager? = nil) {
        if let aiGenerator = aiGenerator {
            self.aiGenerator = aiGenerator
        } else {
            self.aiGenerator = Photo2MusicManager.createDefault()
        }
        super.init()
        setupLocationManager()
    }
    
    // MARK: - Location & Weather
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        locationManager.stopUpdatingLocation() // Get location once
        
        Task {
            await fetchWeather(for: location)
            self.isRefreshingWeather = false
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            print("❌ Location access denied")
            self.isRefreshingWeather = false
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            break
        }
    }
    
    func refreshWeather() {
        print("🔄 Manually refreshing weather...")
        isRefreshingWeather = true
        locationManager.startUpdatingLocation()
        
        // Safety timeout to stop animation if something goes wrong
        Task {
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            if isRefreshingWeather {
                isRefreshingWeather = false
            }
        }
    }
    
    private func fetchWeather(for location: CLLocation) async {
        print("🌍 Fetching weather for location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        do {
            let weather = try await weatherService.weather(for: location)
            let symbol = weather.currentWeather.symbolName
            print("✅ Weather fetched successfully: \(weather.currentWeather.condition.description), symbol: \(symbol)")
            self.weatherSymbolName = symbol
        } catch {
            print("❌ Failed to fetch weather: \(error.localizedDescription)")
            print("💡 Hint: Check if WeatherKit capability is enabled and location permissions are granted.")
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
