//
//  MemoryViewModel.swift
//  MOMENTA
//
//  Memory 功能的数据与生成协调层。
//

import Foundation
import SwiftUI
import UIKit

@MainActor
final class MemoryViewModel: ObservableObject {

    // MARK: - Composer Input

    @Published var prompt: String = ""
    @Published var selectedImage: UIImage?
    @Published var instrumentalOnly: Bool = false
    @Published var language: String = "en"
    @Published var usePsychologicalProfile: Bool = false

    // MARK: - Composer Presentation

    @Published var showImagePicker = false
    @Published var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary

    // MARK: - Generation State

    @Published var isGenerating: Bool = false
    @Published var generationProgress: String = "Preparing..."
    @Published var generatedMusic: GeneratedMusic?
    @Published var errorMessage: String?
    @Published var showErrorAlert: Bool = false

    // MARK: - Library State

    @Published private(set) var memorySongs: [GeneratedMusic] = []
    @Published private(set) var favoriteSongs: [GeneratedMusic] = []
    @Published private(set) var favoriteIds: Set<String> = []
    @Published private(set) var isLoadingLibrary = false

    // MARK: - Health State

    @Published var heartRate: Double?
    @Published var hrv: Double?
    @Published var healthAuthorized: Bool = false
    @Published var healthHints: HealthMusicHints?

    // MARK: - Dependencies

    let locationWeather = LocationWeatherService.shared

    private let manager: Memory2MusicManager
    private let healthKit = HealthKitService()
    private let emotionML = EmotionMLService()
    private let musicDb = MusicDatabaseService.shared
    private let profileService = ProfileService.shared
    private let metadataStore = MemorySongMetadataStore.shared
    private let memoryCalendarService = MemoryCalendarService.shared

    init(manager: Memory2MusicManager? = nil) {
        self.manager = manager ?? Memory2MusicManager.createDefault()
    }

    // MARK: - Derived Items

    var libraryItems: [MemoryLibraryItem] {
        memorySongs.map(makeLibraryItem)
    }

    var collectionItems: [MemoryLibraryItem] {
        favoriteSongs.map(makeLibraryItem)
    }

    var availableLocations: [String] {
        Array(Set(libraryItems.map(\.locationName)))
            .filter { !$0.isEmpty && $0 != MemorySongMetadata.unknownLocationLabel }
            .sorted()
    }

    var availableTypes: [String] {
        Array(Set(libraryItems.map(\.typeLabel)))
            .filter { !$0.isEmpty }
            .sorted()
    }

    var availableJournals: [String] {
        Array(Set(libraryItems.map(\.journal)))
            .filter { !$0.isEmpty && $0 != "No journal note" }
            .sorted()
    }

    // MARK: - Library Loading

    func refreshLibrary() async {
        guard let userId = await SupabaseService.shared.getCurrentUserId() else { return }

        isLoadingLibrary = true
        defer { isLoadingLibrary = false }

        do {
            async let memory = musicDb.fetchMemorySongs(userId: userId)
            async let favorites = profileService.fetchFavoriteSongs(userId: userId)
            async let ids = profileService.fetchFavoriteMusicIds(userId: userId)

            let (memorySongs, favoriteSongs, favoriteIds) = try await (memory, favorites, ids)
            self.memorySongs = memorySongs
            self.favoriteSongs = favoriteSongs
                .filter { $0.source == "memory" }
                .sorted { $0.createdAt > $1.createdAt }
            self.favoriteIds = favoriteIds
        } catch {
            showError(error.localizedDescription)
        }
    }

    func toggleFavorite(musicId: String, ownerId: UUID?) async {
        guard let userId = await SupabaseService.shared.getCurrentUserId() else { return }
        let owner = ownerId ?? userId

        do {
            if favoriteIds.contains(musicId) {
                try await profileService.removeFavorite(userId: userId, musicId: musicId)
            } else {
                try await profileService.addFavorite(userId: userId, musicId: musicId, ownerId: owner)
            }
            await refreshLibrary()
        } catch {
            showError(error.localizedDescription)
        }
    }

    // MARK: - Camera

    func openCamera() {
        imagePickerSourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        showImagePicker = true
    }

    func openPhotoLibrary() {
        imagePickerSourceType = .photoLibrary
        showImagePicker = true
    }

    func removeImage() {
        selectedImage = nil
    }

    // MARK: - HealthKit

    func requestHealthAccess() async {
        do {
            try await healthKit.requestAuthorization()
            healthAuthorized = true
            await fetchHealthData()
        } catch {
            healthAuthorized = false
        }
    }

    func fetchHealthData() async {
        guard healthAuthorized else { return }

        async let hrTask = healthKit.fetchLatestHeartRate()
        async let hrvTask = healthKit.fetchLatestHRV()

        heartRate = await hrTask
        hrv = await hrvTask

        guard let hr = heartRate else { return }
        let hrvForModel = hrv ?? 50.0

        do {
            healthHints = try emotionML.predict(heartRate: hr, hrv: hrvForModel)
        } catch {
            healthHints = nil
        }
    }

    // MARK: - Environment

    func fetchEnvironment() async {
        await locationWeather.requestOnce()
    }

    // MARK: - Generation

    func generate() async {
        if locationWeather.locationName == nil {
            await fetchEnvironment()
        }

        let hasAnyInput = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedImage != nil
            || healthHints != nil
            || locationWeather.locationName != nil
            || locationWeather.weather != nil
            || locationWeather.temperature != nil

        guard hasAnyInput else {
            showError("At least one memory input is required.")
            return
        }

        isGenerating = true
        errorMessage = nil
        generationProgress = "Preparing..."

        let photoBase64 = selectedImage.flatMap { ImageUtility.toBase64(image: $0) }
        let bpm = heartRate.map { min(max(Int($0.rounded()), 60), 160) }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "EEEE HH:mm"
        timeFormatter.locale = Locale(identifier: language == "zh" ? "zh_CN" : "en_US")
        let localTime = timeFormatter.string(from: Date())

        let context = MemoryMusicContext(
            photo: photoBase64,
            story: prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : prompt,
            language: language,
            instrumentalOnly: instrumentalOnly,
            heartRate: usePsychologicalProfile ? heartRate : nil,
            hrv: usePsychologicalProfile ? hrv : nil,
            healthHints: usePsychologicalProfile ? healthHints : nil,
            suggestedBPM: usePsychologicalProfile ? bpm : nil,
            localTime: localTime,
            locationName: locationWeather.locationName,
            weather: locationWeather.weather,
            temperature: locationWeather.temperature
        )

        do {
            let music = try await manager.generate(context: context) { [weak self] progress in
                Task { @MainActor in
                    self?.generationProgress = progress
                }
            }

            generatedMusic = music
            rememberMetadata(for: music)
            await saveCalendarEventIfPossible(for: music, context: context)
            generationProgress = "Complete!"
            await refreshLibrary()
        } catch {
            showError(error.localizedDescription)
        }

        isGenerating = false
    }

    // MARK: - Helpers

    func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }

    func dismissError() {
        errorMessage = nil
        showErrorAlert = false
    }

    private func saveCalendarEventIfPossible(for music: GeneratedMusic, context: MemoryMusicContext) async {
        do {
            try await memoryCalendarService.saveGeneratedSong(music, context: context)
        } catch {
            print("⚠️ [MemoryViewModel] Failed to save generated song to Calendar: \(error.localizedDescription)")
        }
    }

    func resetComposer() {
        prompt = ""
        selectedImage = nil
        instrumentalOnly = false
        language = "en"
        usePsychologicalProfile = false
        errorMessage = nil
        showErrorAlert = false
    }

    private func rememberMetadata(for music: GeneratedMusic) {
        metadataStore.save(
            musicId: music.id,
            journal: prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? music.prompt : prompt,
            locationName: locationWeather.locationName,
            typeLabel: metadataStore.metadata(for: music).typeLabel,
            createdAt: music.createdAt
        )
    }

    private func makeLibraryItem(from music: GeneratedMusic) -> MemoryLibraryItem {
        MemoryLibraryItem(
            music: music,
            metadata: metadataStore.metadata(for: music)
        )
    }
}
