//
//  MemoryViewModel.swift
//  MOMENTA
//
//  Memory 功能的 ViewModel：串联 HealthKit / 环境 / 用户输入 → Memory2MusicManager。
//

import Foundation
import SwiftUI
import PhotosUI

@MainActor
class MemoryViewModel: ObservableObject {

    // MARK: - 用户输入

    @Published var prompt: String = ""
    @Published var selectedImage: UIImage?
    @Published var instrumentalOnly: Bool = false
    @Published var language: String = "en"

    // MARK: - 生成状态

    @Published var isGenerating: Bool = false
    @Published var generationProgress: String = "Preparing..."
    @Published var generatedMusic: GeneratedMusic?
    @Published var errorMessage: String?
    @Published var showErrorAlert: Bool = false

    // MARK: - 健康数据状态

    @Published var heartRate: Double?
    @Published var hrv: Double?
    @Published var healthAuthorized: Bool = false
    @Published var healthHints: HealthMusicHints?

    // MARK: - 环境数据（来自共享 Service）

    let locationWeather = LocationWeatherService.shared

    // MARK: - Dependencies

    private let manager: Memory2MusicManager
    private let healthKit = HealthKitService()
    private let emotionML = EmotionMLService()

    init(manager: Memory2MusicManager? = nil) {
        self.manager = manager ?? Memory2MusicManager.createDefault()
    }

    // MARK: - HealthKit

    func requestHealthAccess() async {
        do {
            try await healthKit.requestAuthorization()
            healthAuthorized = true
            print("✅ [MemoryVM] HealthKit 授权成功")
            await fetchHealthData()
        } catch {
            print("❌ [MemoryVM] HealthKit 授权失败: \(error.localizedDescription)")
            healthAuthorized = false
        }
    }

    func fetchHealthData() async {
        guard healthAuthorized else {
            print("⚠️ [MemoryVM] HealthKit 未授权，跳过健康数据读取")
            return
        }

        // HR 和 HRV 独立查询，互不阻塞
        async let hrTask = healthKit.fetchLatestHeartRate()
        async let hrvTask = healthKit.fetchLatestHRV()

        heartRate = await hrTask
        hrv = await hrvTask

        print("📊 [MemoryVM] 健康数据: HR=\(heartRate.map { String(format: "%.1f", $0) } ?? "无"), HRV=\(hrv.map { String(format: "%.1f", $0) } ?? "无")")

        // 只要有 HR 就尝试推理；HRV 没有时用默认值（中间值）
        guard let hr = heartRate else {
            print("⚠️ [MemoryVM] 无心率数据，跳过 CoreML 推理")
            return
        }

        let hrvForModel = hrv ?? 50.0  // HRV 缺失时用中间值降级
        if hrv == nil {
            print("ℹ️ [MemoryVM] HRV 缺失，使用默认值 50.0ms 进行推理")
        }

        do {
            let hints = try emotionML.predict(heartRate: hr, hrv: hrvForModel)
            healthHints = hints
            print("🧠 [MemoryVM] CoreML 推理成功 → 象限: \(hints.quadrant.rawValue), V: \(String(format: "%.2f", hints.valence)), A: \(String(format: "%.2f", hints.arousal))")
            print("🎵 [MemoryVM] Style fragment: \(hints.styleFragment)")
        } catch {
            print("❌ [MemoryVM] CoreML 推理失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 环境

    func fetchEnvironment() async {
        await locationWeather.requestOnce()
    }

    // MARK: - 生成

    func generate() async {
        let hasAnyInput = !prompt.isEmpty
            || selectedImage != nil
            || healthHints != nil
            || locationWeather.locationName != nil
            || locationWeather.weather != nil
            || locationWeather.temperature != nil

        guard hasAnyInput else {
            showError("至少需要一项输入（描述、图片、健康数据或环境数据）")
            return
        }

        isGenerating = true
        errorMessage = nil
        generationProgress = "Preparing..."

        var photoBase64: String?
        if let image = selectedImage {
            photoBase64 = ImageUtility.toBase64(image: image)
        }

        let bpm: Int? = heartRate.map { min(max(Int($0.rounded()), 60), 160) }

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "EEEE HH:mm"
        timeFmt.locale = Locale(identifier: language == "zh" ? "zh_CN" : "en_US")
        let localTime = timeFmt.string(from: Date())

        print("📋 [MemoryVM] 生成上下文摘要:")
        print("   - prompt: \(prompt.isEmpty ? "(空)" : "\(prompt.prefix(50))...")")
        print("   - photo: \(selectedImage != nil ? "有" : "无")")
        print("   - health: \(healthHints != nil ? healthHints!.quadrant.rawValue + " / " + healthHints!.styleFragment : "无")")
        print("   - bpm: \(heartRate.map { "\(Int($0.rounded())) → clamped \(min(max(Int($0.rounded()), 60), 160))" } ?? "无")")
        print("   - location: \(locationWeather.locationName ?? "无")")
        print("   - weather: \(locationWeather.weather ?? "无"), temp: \(locationWeather.temperature.map { String(format: "%.0f°C", $0) } ?? "无")")
        print("   - localTime: \(localTime)")
        print("   - instrumental: \(instrumentalOnly), language: \(language)")

        let context = MemoryMusicContext(
            photo: photoBase64,
            story: prompt.isEmpty ? nil : prompt,
            language: language,
            instrumentalOnly: instrumentalOnly,
            heartRate: heartRate,
            hrv: hrv,
            healthHints: healthHints,
            suggestedBPM: bpm,
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
            generationProgress = "Complete!"
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

    func reset() {
        prompt = ""
        selectedImage = nil
        instrumentalOnly = false
        generatedMusic = nil
        errorMessage = nil
        generationProgress = "Preparing..."
    }
}
