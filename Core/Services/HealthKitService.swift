//
//  HealthKitService.swift
//  MOMENTA
//
//  HealthKit 授权 + HR / HRV(SDNN) 读取。
//  HR 和 HRV 独立查询，各自使用合理窗口，互不阻塞。
//

import Foundation
import HealthKit

final class HealthKitService {

    private let store = HKHealthStore()

    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let hrvType       = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!

    // MARK: - 授权

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        let readTypes: Set<HKObjectType> = [heartRateType, hrvType]
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - 独立读取

    /// 读取最近一条心率样本。默认窗口 24 小时，兼容 Apple Watch 同步延迟和被动采样间隔。
    func fetchLatestHeartRate(windowHours: Double = 24) async -> Double? {
        let sample = await fetchLatestSample(
            type: heartRateType,
            unit: HKUnit.count().unitDivided(by: .minute()),
            window: windowHours * 3600
        )
        if let sample {
            print("💓 [HealthKit] HR 样本: \(String(format: "%.1f", sample.value)) bpm (采集于 \(sample.date))")
        } else {
            print("⚠️ [HealthKit] 最近 \(Int(windowHours))h 内无心率数据")
        }
        return sample?.value
    }

    /// 读取最近一条 HRV(SDNN) 样本。默认窗口 30 天，因为 HRV 采样非常稀疏（主要在睡眠时）。
    func fetchLatestHRV(windowDays: Double = 30) async -> Double? {
        let sample = await fetchLatestSample(
            type: hrvType,
            unit: HKUnit.secondUnit(with: .milli),
            window: windowDays * 86400
        )
        if let sample {
            print("💓 [HealthKit] HRV 样本: \(String(format: "%.1f", sample.value)) ms (采集于 \(sample.date))")
        } else {
            print("⚠️ [HealthKit] 最近 \(Int(windowDays)) 天内无 HRV 数据")
        }
        return sample?.value
    }

    // MARK: - Private

    private struct SampleResult {
        let value: Double
        let date: String
    }

    private func fetchLatestSample(type: HKQuantityType, unit: HKUnit, window: TimeInterval) async -> SampleResult? {
        let now = Date()
        let start = now.addingTimeInterval(-window)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let sortByDate = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortByDate]
            ) { _, samples, error in
                if let error {
                    print("❌ [HealthKit] 查询 \(type.identifier) 失败: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                let result = SampleResult(
                    value: sample.quantity.doubleValue(for: unit),
                    date: formatter.string(from: sample.endDate)
                )
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }
}

// MARK: - Errors

enum HealthKitError: LocalizedError {
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "当前设备不支持 HealthKit"
        }
    }
}
