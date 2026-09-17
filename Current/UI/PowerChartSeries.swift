import Foundation

enum ChartWindow: Int, CaseIterable {
    case recent
    case session
}

/// Display-only reduction. Statistics and exports always use original samples.
struct PowerChartSeries {
    let start: Date
    let end: Date
    let maximumWatts: Double
    let samples: [ChargingSample]
    let segments: [[ChargingSample]]

    init(samples all: [ChargingSample], window: ChartWindow, columns: Int) {
        let end = all.last?.timestamp ?? .now
        let proposedStart = window == .recent
            ? end.addingTimeInterval(-300) : all.first?.timestamp ?? end.addingTimeInterval(-300)
        let start = min(proposedStart, end.addingTimeInterval(-1))
        let first = all.firstIndex { $0.timestamp >= start } ?? all.count
        let visible = all.dropFirst(max(0, first - 1))
        var valid: [ChargingSample] = []
        var runs: [[ChargingSample]] = []
        var run: [ChargingSample] = []
        var peak = 0.0
        var previous: Date?

        func finishRun() {
            if run.contains(where: { $0.timestamp >= start && $0.timestamp <= end }) {
                runs.append(run)
            }
            run.removeAll(keepingCapacity: true)
        }
        for sample in visible {
            let gap = previous.map { sample.timestamp.timeIntervalSince($0) } ?? 0
            if previous != nil, gap <= 0 || gap > ChargingStatistics.maximumSampleGap {
                finishRun()
            }
            previous = sample.timestamp
            guard sample.timestamp.timeIntervalSinceReferenceDate.isFinite,
                  sample.timestamp <= end,
                  let watts = sample.powerWatts, watts.isFinite, watts >= 0
            else {
                finishRun()
                continue
            }
            run.append(sample)
            peak = max(peak, watts)
            if sample.timestamp >= start, sample.timestamp > (valid.last?.timestamp ?? .distantPast) {
                valid.append(sample)
            }
        }
        finishRun()
        self.start = start
        self.end = end
        let roundedPeak = ceil(peak / 5) * 5
        maximumWatts = max(10, roundedPeak.isFinite ? roundedPeak : peak)
        samples = valid
        segments = runs.map { Self.reduced($0, start: start, end: end, columns: columns) }
    }

    func nearestIndex(to date: Date) -> Int? {
        guard !samples.isEmpty else { return nil }
        var lower = 0
        var upper = samples.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if samples[middle].timestamp < date {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        if lower == 0 { return 0 }
        if lower == samples.count { return samples.count - 1 }
        return date.timeIntervalSince(samples[lower - 1].timestamp) <= samples[lower].timestamp.timeIntervalSince(date)
            ? lower - 1 : lower
    }

    private static func reduced(
        _ samples: [ChargingSample], start: Date, end: Date, columns: Int
    ) -> [ChargingSample] {
        let columns = max(1, min(2048, columns))
        guard samples.count > columns * 4 else { return samples }
        let duration = max(1, end.timeIntervalSince(start))
        var output: [ChargingSample] = []
        var bucket = -1
        var first = 0
        var minimum = 0
        var maximum = 0
        var last = 0

        func flush() {
            guard bucket >= 0 else { return }
            // Keep endpoints and both extrema in chronological order. Unlike
            // taking every nth point, this preserves short peaks and valleys.
            for index in Set([first, minimum, maximum, last]).sorted() {
                output.append(samples[index])
            }
        }
        for index in samples.indices {
            let fraction = min(1, max(0, samples[index].timestamp.timeIntervalSince(start) / duration))
            let nextBucket = min(columns - 1, Int(fraction * Double(columns)))
            if nextBucket != bucket {
                flush()
                bucket = nextBucket
                first = index
                minimum = index
                maximum = index
            } else {
                if (samples[index].powerWatts ?? 0) < (samples[minimum].powerWatts ?? 0) { minimum = index }
                if (samples[index].powerWatts ?? 0) > (samples[maximum].powerWatts ?? 0) { maximum = index }
            }
            last = index
        }
        flush()
        return output
    }
}
