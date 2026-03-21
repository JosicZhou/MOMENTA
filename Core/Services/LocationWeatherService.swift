//
//  LocationWeatherService.swift
//  MOMENTA
//
//  共享的定位 + WeatherKit 服务。Light 和 Memory 均可注入使用。
//

import Foundation
import CoreLocation
import WeatherKit

@MainActor
final class LocationWeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = LocationWeatherService()

    // MARK: - Published State

    @Published var locationName: String?
    @Published var weather: String?
    @Published var temperature: Double?
    @Published var symbolName: String?

    // MARK: - Internal

    private let locationManager = CLLocationManager()
    private let weatherService = WeatherService.shared
    private var continuation: CheckedContinuation<Void, Never>?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // MARK: - Public API

    /// 单次定位 → 天气 + 反地理编码。若权限未授予会先请求。
    func requestOnce() async {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }

        locationManager.requestLocation()

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            self.continuation = c
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        Task { @MainActor in
            await self.processLocation(location)
            self.continuation?.resume()
            self.continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("❌ [LocationWeather] 定位失败: \(error.localizedDescription)")
            self.continuation?.resume()
            self.continuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    // MARK: - Private

    private func processLocation(_ location: CLLocation) async {
        async let weatherTask: Void = fetchWeather(for: location)
        async let geoTask: Void = reverseGeocode(location)
        _ = await (weatherTask, geoTask)
    }

    private func fetchWeather(for location: CLLocation) async {
        do {
            let w = try await weatherService.weather(for: location)
            let current = w.currentWeather
            self.weather = current.condition.description
            self.temperature = current.temperature.value
            self.symbolName = current.symbolName
            print("✅ [LocationWeather] \(current.condition.description), \(String(format: "%.1f", current.temperature.value))°C, symbol: \(current.symbolName)")
        } catch {
            print("❌ [LocationWeather] 天气获取失败: \(error.localizedDescription)")
        }
    }

    private func reverseGeocode(_ location: CLLocation) async {
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            self.locationName = placemarks.first?.locality ?? placemarks.first?.name
        } catch {
            print("❌ [LocationWeather] 反地理编码失败: \(error.localizedDescription)")
        }
    }
}
