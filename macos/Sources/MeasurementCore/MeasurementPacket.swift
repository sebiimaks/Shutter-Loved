import Foundation

public enum CurtainDirection: String, Codable, CaseIterable, Sendable {
    case unknown, horizontal, vertical

    public var title: String {
        switch self {
        case .unknown: "Unknown"
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        }
    }

    /// Scales the documented 32 × 20 mm sensor rectangle to a 36 × 24 mm frame.
    public var factor: Double? {
        switch self {
        case .unknown: nil
        case .horizontal: 36.0 / 32.0
        case .vertical: 24.0 / 20.0
        }
    }
}

/// The original microsecond values are retained, including negative missing-event sentinels.
public struct MeasurementPacket: Codable, Equatable, Sendable {
    public let eventType: String
    public let unit: String
    public let firmware_version: String
    public let bottomLeftOpen: Int64
    public let bottomLeftClose: Int64
    public let centerOpen: Int64
    public let centerClose: Int64
    public let topRightOpen: Int64
    public let topRightClose: Int64
    public let bottomLeftOpenOffset: Int64
    public let bottomLeftCloseOffset: Int64
    public let topRightOpenOffset: Int64
    public let topRightCloseOffset: Int64

    public init(
        eventType: String = "MultiSensorMeasure",
        unit: String = "microsecond",
        firmware_version: String = "1.0.0",
        bottomLeftOpen: Int64,
        bottomLeftClose: Int64,
        centerOpen: Int64,
        centerClose: Int64,
        topRightOpen: Int64,
        topRightClose: Int64,
        bottomLeftOpenOffset: Int64,
        bottomLeftCloseOffset: Int64,
        topRightOpenOffset: Int64,
        topRightCloseOffset: Int64
    ) {
        self.eventType = eventType
        self.unit = unit
        self.firmware_version = firmware_version
        self.bottomLeftOpen = bottomLeftOpen
        self.bottomLeftClose = bottomLeftClose
        self.centerOpen = centerOpen
        self.centerClose = centerClose
        self.topRightOpen = topRightOpen
        self.topRightClose = topRightClose
        self.bottomLeftOpenOffset = bottomLeftOpenOffset
        self.bottomLeftCloseOffset = bottomLeftCloseOffset
        self.topRightOpenOffset = topRightOpenOffset
        self.topRightCloseOffset = topRightCloseOffset
    }
}

public enum PacketParseResult: Sendable {
    case measurement(MeasurementPacket)
    case ignored(String)
    case invalid(String)
}

public enum PacketParser {
    public static func parse(_ line: Data) -> PacketParseResult {
        guard let text = String(data: line, encoding: .utf8) else {
            return .invalid("Received bytes are not valid UTF-8 text.")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .ignored("Empty line.") }
        guard trimmed.first == "{" || trimmed.first == "[" else {
            return .ignored("Device text: \(trimmed.prefix(160))")
        }

        struct Header: Decodable { let eventType: String }
        let decoder = JSONDecoder()
        do {
            let header = try decoder.decode(Header.self, from: line)
            guard header.eventType == "MultiSensorMeasure" else {
                return .ignored("Unsupported event: \(header.eventType.prefix(80)).")
            }
            // Int64 decoding rejects boolean, nonintegral, missing, and out-of-range values.
            // Offsets have no decoding defaults: a missing calibration must never become zero.
            let packet = try decoder.decode(MeasurementPacket.self, from: line)
            guard packet.unit == "microsecond" else {
                return .invalid("Unsupported measurement unit: \(packet.unit.prefix(80)). Expected microsecond.")
            }
            guard !packet.firmware_version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .invalid("Measurement has no firmware version.")
            }
            return .measurement(packet)
        } catch DecodingError.keyNotFound(let key, _) {
            return .invalid("Measurement is missing required field ‘\(key.stringValue)’.")
        } catch DecodingError.typeMismatch(_, let context) {
            let name = context.codingPath.last?.stringValue ?? "measurement"
            return .invalid("Invalid value for ‘\(name)’; timestamps and offsets must be integers.")
        } catch DecodingError.valueNotFound(_, let context) {
            let name = context.codingPath.last?.stringValue ?? "measurement"
            return .invalid("Required field ‘\(name)’ is null.")
        } catch {
            return .invalid("Malformed JSON or an invalid integer in the measurement.")
        }
    }
}
