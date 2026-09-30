import Foundation

public struct SensorExposure: Codable, Equatable, Sendable {
    public let durationMS: Double?
    public let reciprocalSeconds: Double?

    public init(durationMS: Double?, reciprocalSeconds: Double?) {
        self.durationMS = durationMS
        self.reciprocalSeconds = reciprocalSeconds
    }
}

public enum ReadingQuality: String, Codable, Sendable {
    case complete, partial, invalid

    public var title: String {
        switch self {
        case .complete: "Complete"
        case .partial: "Partial"
        case .invalid: "Invalid"
        }
    }
}

public struct MeasurementResult: Codable, Equatable, Sendable {
    public let center: SensorExposure
    public let bottomLeft: SensorExposure
    public let topRight: SensorExposure
    public let openingTravelMS: Double?
    public let closingTravelMS: Double?
    public let openingFullFrameMS: Double?
    public let closingFullFrameMS: Double?
    /// Fixed sensor pairs, not a claim about which sensor the curtain reached first.
    public let openingFirstSegmentMS: Double?
    public let openingSecondSegmentMS: Double?
    public let closingFirstSegmentMS: Double?
    public let closingSecondSegmentMS: Double?
    public let exposureErrorStops: Double?
    public let exposureErrorPercent: Double?
    public let quality: ReadingQuality
    public let issues: [String]

    /// A complete single-sensor measurement has no curtain travel or corner
    /// timing. The absence of those metrics does not make it a partial reading.
    public static func manualResult(durationSeconds: Double, nominalDenominator: Double) -> MeasurementResult {
        guard durationSeconds.isFinite, (0.000001...1_000).contains(durationSeconds) else {
            return unavailableResult(issues: ["Entered exposure must be between 1 microsecond and 1,000 seconds."])
        }
        var issues: [String] = []
        var stops: Double?
        var percent: Double?
        if nominalDenominator.isFinite, nominalDenominator > 0 {
            let difference = log2(durationSeconds) + log2(nominalDenominator)
            stops = difference.isFinite ? difference : nil
            let percentage = (durationSeconds * nominalDenominator - 1) * 100
            percent = percentage.isFinite ? percentage : nil
        } else {
            issues.append("Camera setting must be a positive, finite reciprocal exposure to calculate its difference.")
        }
        let unavailable = SensorExposure(durationMS: nil, reciprocalSeconds: nil)
        return MeasurementResult(
            center: SensorExposure(durationMS: durationSeconds * 1_000, reciprocalSeconds: 1 / durationSeconds),
            bottomLeft: unavailable, topRight: unavailable,
            openingTravelMS: nil, closingTravelMS: nil, openingFullFrameMS: nil, closingFullFrameMS: nil,
            openingFirstSegmentMS: nil, openingSecondSegmentMS: nil,
            closingFirstSegmentMS: nil, closingSecondSegmentMS: nil,
            exposureErrorStops: stops, exposureErrorPercent: percent,
            quality: .complete, issues: issues
        )
    }

    public static func calculate(
        packet: MeasurementPacket,
        direction: CurtainDirection,
        nominalDenominator: Double
    ) -> MeasurementResult {
        var issues: [String] = []
        var hasMissingEvents = false
        var hasInvalidEvents = false

        func corrected(_ raw: Int64, offset: Int64, name: String) -> Int64? {
            // Test the RAW event first. A valid event can be negative after calibration.
            guard raw >= 0 else {
                hasMissingEvents = true
                issues.append("\(name) was not measured.")
                return nil
            }
            let (value, overflow) = raw.addingReportingOverflow(offset)
            guard !overflow else {
                hasInvalidEvents = true
                issues.append("\(name) calibration exceeds the supported integer range.")
                return nil
            }
            return value
        }

        func exposure(open: Int64?, close: Int64?, name: String) -> SensorExposure {
            guard let open, let close else {
                return SensorExposure(durationMS: nil, reciprocalSeconds: nil)
            }
            guard close > open else {
                hasInvalidEvents = true
                issues.append(close == open
                    ? "\(name) exposure has zero duration."
                    : "\(name) closing event precedes its opening event after calibration.")
                return SensorExposure(durationMS: nil, reciprocalSeconds: nil)
            }
            let duration = distance(open, close)
            return SensorExposure(durationMS: duration / 1_000, reciprocalSeconds: 1_000_000 / duration)
        }

        func travel(_ first: Int64?, _ second: Int64?) -> Double? {
            guard let first, let second else { return nil }
            return distance(first, second) / 1_000
        }

        let blOpen = corrected(packet.bottomLeftOpen, offset: packet.bottomLeftOpenOffset, name: "Bottom-left opening")
        let blClose = corrected(packet.bottomLeftClose, offset: packet.bottomLeftCloseOffset, name: "Bottom-left closing")
        let centerOpen = corrected(packet.centerOpen, offset: 0, name: "Center opening")
        let centerClose = corrected(packet.centerClose, offset: 0, name: "Center closing")
        let trOpen = corrected(packet.topRightOpen, offset: packet.topRightOpenOffset, name: "Top-right opening")
        let trClose = corrected(packet.topRightClose, offset: packet.topRightCloseOffset, name: "Top-right closing")

        let center = exposure(open: centerOpen, close: centerClose, name: "Center")
        let bottomLeft = exposure(open: blOpen, close: blClose, name: "Bottom-left")
        let topRight = exposure(open: trOpen, close: trClose, name: "Top-right")
        let openingTravel = travel(blOpen, trOpen)
        let closingTravel = travel(blClose, trClose)
        var errorStops: Double?
        var errorPercent: Double?
        if nominalDenominator.isFinite, nominalDenominator > 0 {
            if let duration = center.durationMS {
                // Logarithms avoid an overflowing or underflowing ratio for extreme references.
                let stops = log2(duration) + log2(nominalDenominator) - log2(1_000)
                errorStops = stops.isFinite ? stops : nil
                let ratio = duration / 1_000 * nominalDenominator
                let percent = (ratio - 1) * 100
                errorPercent = percent.isFinite ? percent : nil
                if errorPercent == nil { issues.append("Exposure difference exceeds the supported percent range.") }
            }
        } else {
            issues.append("Camera setting must be a positive, finite reciprocal exposure to calculate its difference.")
        }

        if packet.eventType != "MultiSensorMeasure" || packet.unit != "microsecond" {
            // Protect callers constructing packets directly, as well as the validated parser path.
            return unavailableResult(issues: ["Unsupported measurement event or unit."])
        }
        let quality: ReadingQuality = hasInvalidEvents ? .invalid : (hasMissingEvents ? .partial : .complete)
        return MeasurementResult(
            center: center,
            bottomLeft: bottomLeft,
            topRight: topRight,
            openingTravelMS: openingTravel,
            closingTravelMS: closingTravel,
            openingFullFrameMS: direction.factor.flatMap { factor in openingTravel.map { $0 * factor } },
            closingFullFrameMS: direction.factor.flatMap { factor in closingTravel.map { $0 * factor } },
            openingFirstSegmentMS: travel(blOpen, centerOpen),
            openingSecondSegmentMS: travel(centerOpen, trOpen),
            closingFirstSegmentMS: travel(blClose, centerClose),
            closingSecondSegmentMS: travel(centerClose, trClose),
            exposureErrorStops: errorStops,
            exposureErrorPercent: errorPercent,
            quality: quality,
            issues: issues
        )
    }

    /// Exact unsigned subtraction covers the full distance between two Int64 values.
    /// Converting each timestamp to Double first would lose short durations near Int64.max.
    private static func distance(_ first: Int64, _ second: Int64) -> Double {
        let high = max(first, second)
        let low = min(first, second)
        return Double(UInt64(bitPattern: high) &- UInt64(bitPattern: low))
    }

    private static func unavailableResult(issues: [String]) -> MeasurementResult {
        let unavailable = SensorExposure(durationMS: nil, reciprocalSeconds: nil)
        return MeasurementResult(
            center: unavailable, bottomLeft: unavailable, topRight: unavailable,
            openingTravelMS: nil, closingTravelMS: nil,
            openingFullFrameMS: nil, closingFullFrameMS: nil,
            openingFirstSegmentMS: nil, openingSecondSegmentMS: nil,
            closingFirstSegmentMS: nil, closingSecondSegmentMS: nil,
            exposureErrorStops: nil, exposureErrorPercent: nil,
            quality: .invalid, issues: issues
        )
    }
}
