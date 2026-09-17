import Foundation

struct ChargingSample: Codable, Equatable {
    var timestamp: Date
    var level: Double?
    var powerWatts: Double?
    var temperatureCelsius: Double?

    init(snapshot: BatterySnapshot) {
        timestamp = snapshot.timestamp
        level = snapshot.level
        powerWatts = snapshot.chargingPowerWatts
        temperatureCelsius = snapshot.temperatureCelsius
    }

    init(timestamp: Date, level: Double? = nil, powerWatts: Double?, temperatureCelsius: Double? = nil) {
        self.timestamp = timestamp
        self.level = level
        self.powerWatts = powerWatts
        self.temperatureCelsius = temperatureCelsius
    }
}

enum SessionEndReason: String, Codable {
    case disconnected
    case monitoringPaused
    case sourceChanged
    case interrupted
    case durationLimit

    var title: String {
        switch self {
        case .disconnected: "Disconnected"
        case .monitoringPaused: "Monitoring paused"
        case .sourceChanged: "Data source changed"
        case .interrupted: "Observation interrupted"
        case .durationLimit: "8-hour observation limit"
        }
    }
}

struct ChargingSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date?
    var endReason: SessionEndReason?
    /// Legacy archive marker only. New recordings are always real; old demo
    /// sessions are discarded on restore, not presented as device observations.
    var isDemo = false
    // Version 1 sessions omitted this field and used battery intake.
    var powerMeasurement: PowerMeasurement?
    var samples: [ChargingSample]

    var measurement: PowerMeasurement {
        powerMeasurement ?? .batteryIntake
    }

    var lastSampleAt: Date {
        samples.last?.timestamp ?? startedAt
    }

    var duration: TimeInterval {
        max(0, (endedAt ?? lastSampleAt).timeIntervalSince(startedAt))
    }

    var statistics: ChargingStatistics {
        ChargingStatistics.calculate(samples)
    }

    var recentStatistics: ChargingStatistics {
        ChargingStatistics.calculate(
            samples,
            in: DateInterval(start: lastSampleAt.addingTimeInterval(-300), end: lastSampleAt)
        )
    }
}

struct ChargingStatistics: Equatable {
    static let maximumSampleGap: TimeInterval = 10

    var peakWatts: Double?
    var averageWatts: Double?
    var energyWh: Double?
    var coveredSeconds: TimeInterval = 0
    var levelGain: Double?
    var sampleCount: Int = 0
    var spanSeconds: TimeInterval = 0

    var coverage: Double {
        spanSeconds > 0 ? min(1, coveredSeconds / spanSeconds) : 0
    }

    static func calculate(
        _ samples: [ChargingSample],
        in window: DateInterval? = nil
    ) -> ChargingStatistics {
        var result = ChargingStatistics()
        guard let first = samples.first, let last = samples.last else { return result }
        let start = max(first.timestamp, window?.start ?? first.timestamp)
        let end = min(last.timestamp, window?.end ?? last.timestamp)
        guard start <= end else { return result }
        result.spanSeconds = end.timeIntervalSince(start)
        let selected = samples.filter { $0.timestamp >= start && $0.timestamp <= end }
        let validPowers = selected.compactMap(\.powerWatts).filter { $0.isFinite && $0 >= 0 }
        result.peakWatts = validPowers.max()
        result.sampleCount = selected.count
        var wattSeconds = 0.0
        var levelGain = 0.0
        var levelCoveredSeconds = 0.0

        // Clip each valid interval to the window and interpolate its endpoints.
        // Missing readings, clock reversals and long gaps never contribute energy.
        for (left, right) in zip(samples, samples.dropFirst()) {
            let duration = right.timestamp.timeIntervalSince(left.timestamp)
            guard duration > 0, duration <= maximumSampleGap else { continue }
            let clippedStart = max(left.timestamp, start)
            let clippedEnd = min(right.timestamp, end)
            let clippedDuration = clippedEnd.timeIntervalSince(clippedStart)
            guard clippedDuration > 0 else { continue }
            let startFraction = clippedStart.timeIntervalSince(left.timestamp) / duration
            let endFraction = clippedEnd.timeIntervalSince(left.timestamp) / duration

            if let leftPower = left.powerWatts, let rightPower = right.powerWatts,
               leftPower.isFinite, rightPower.isFinite, leftPower >= 0, rightPower >= 0
            {
                let startPower = leftPower + (rightPower - leftPower) * startFraction
                let endPower = leftPower + (rightPower - leftPower) * endFraction
                wattSeconds += (startPower + endPower) / 2 * clippedDuration
                result.coveredSeconds += clippedDuration
            }
            if let leftLevel = left.level, let rightLevel = right.level,
               (0 ... 1).contains(leftLevel), (0 ... 1).contains(rightLevel)
            {
                levelGain += (rightLevel - leftLevel) * (endFraction - startFraction) * 100
                levelCoveredSeconds += clippedDuration
            }
        }

        if result.coveredSeconds > 0 {
            result.averageWatts = wattSeconds / result.coveredSeconds
            result.energyWh = wattSeconds / 3600
        }
        if levelCoveredSeconds > 0 {
            result.levelGain = levelGain
        }
        return result
    }
}

struct SessionRecorder {
    private(set) var active: ChargingSession?
    private(set) var history: [ChargingSession] = []
    static let historyLimit = 30
    static let maximumSessionDuration: TimeInterval = 8 * 3600

    mutating func record(_ snapshot: BatterySnapshot) {
        guard snapshot.state != .unknown else {
            finish(reason: .interrupted)
            return
        }
        guard snapshot.state.isConnected else {
            finish(reason: .disconnected)
            return
        }
        if let active {
            let gap = snapshot.timestamp.timeIntervalSince(active.lastSampleAt)
            guard gap > 0 else { return }
            if active.measurement != snapshot.measurement {
                finish(reason: .sourceChanged)
            } else if gap > ChargingStatistics.maximumSampleGap {
                finish(reason: .interrupted)
            } else if snapshot.timestamp.timeIntervalSince(active.startedAt) >= Self.maximumSessionDuration {
                finish(reason: .durationLimit)
            }
        }
        if active == nil {
            active = ChargingSession(
                startedAt: snapshot.timestamp,
                powerMeasurement: snapshot.measurement,
                samples: []
            )
        }
        active?.samples.append(ChargingSample(snapshot: snapshot))
    }

    mutating func finish(reason: SessionEndReason) {
        guard var completed = active else { return }
        completed.endedAt = completed.lastSampleAt
        completed.endReason = reason
        if !completed.samples.isEmpty {
            history.insert(completed, at: 0)
        }
        active = nil
        trimHistory()
    }

    mutating func restore(history: [ChargingSession], interrupted: ChargingSession?) {
        self.history = history.filter { !$0.isDemo }
        active = interrupted?.isDemo == false ? interrupted : nil
        finish(reason: .interrupted)
        trimHistory()
    }

    mutating func clearHistory() {
        history.removeAll()
    }

    mutating func delete(id: UUID) {
        history.removeAll { $0.id == id }
    }

    private mutating func trimHistory() {
        history = Array(history.filter { !$0.isDemo }.prefix(Self.historyLimit))
    }
}
