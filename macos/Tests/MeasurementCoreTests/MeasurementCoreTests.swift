import Foundation
import XCTest
@testable import MeasurementCore

final class MeasurementCoreTests: XCTestCase {
    // Verbatim values from testMeasureThread() in the original Python application.
    // This is a synthetic source-code fixture, not a hardware capture.
    private let pythonFixture = #"{"eventType":"MultiSensorMeasure","unit":"microsecond","firmware_version":"1.0.0","bottomLeftOpen":0,"bottomLeftClose":987,"centerOpen":3456,"centerClose":4567,"topRightOpen":5678,"topRightClose":6789,"bottomLeftOpenOffset":-25,"bottomLeftCloseOffset":32,"topRightOpenOffset":40,"topRightCloseOffset":10}"#

    func testPythonFixtureMatchesEveryLegacyMeasurement() throws {
        let parsed = PacketParser.parse(Data(pythonFixture.utf8))
        guard case .measurement(let packet) = parsed else { return XCTFail("Expected valid source fixture") }
        let result = MeasurementResult.calculate(packet: packet, direction: .vertical, nominalDenominator: 1_000)
        XCTAssertEqual(result.quality, .complete)
        XCTAssertTrue(result.issues.isEmpty)
        assertNear(result.center.durationMS, 1.111)
        assertNear(result.center.reciprocalSeconds, 1_000_000.0 / 1_111)
        assertNear(result.bottomLeft.durationMS, 1.044)
        assertNear(result.bottomLeft.reciprocalSeconds, 1_000_000.0 / 1_044)
        assertNear(result.topRight.durationMS, 1.081)
        assertNear(result.topRight.reciprocalSeconds, 1_000_000.0 / 1_081)
        assertNear(result.openingTravelMS, 5.743)
        assertNear(result.closingTravelMS, 5.780)
        assertNear(result.openingFullFrameMS, 6.8916)
        assertNear(result.closingFullFrameMS, 6.936)
        assertNear(result.openingFirstSegmentMS, 3.481)
        assertNear(result.openingSecondSegmentMS, 2.262)
        assertNear(result.closingFirstSegmentMS, 3.548)
        assertNear(result.closingSecondSegmentMS, 2.232)
        assertNear(result.exposureErrorStops, log2(1.111))
        assertNear(result.exposureErrorPercent, 11.1)
        XCTAssertEqual(try JSONDecoder().decode(MeasurementPacket.self, from: JSONEncoder().encode(packet)), packet)
    }

    func testDirectionOnlyChangesFullFrameEstimates() {
        let horizontal = calculate(direction: .horizontal)
        let unknown = calculate(direction: .unknown)
        assertNear(horizontal.openingFullFrameMS, 5.743 * 36 / 32)
        assertNear(horizontal.closingFullFrameMS, 5.780 * 36 / 32)
        XCTAssertNil(unknown.openingFullFrameMS)
        XCTAssertNil(unknown.closingFullFrameMS)
        assertNear(unknown.center.durationMS, 1.111)
        XCTAssertEqual(unknown.quality, .complete)
    }

    func testEveryMissingEventCombinationPreservesIndependentMetrics() {
        let original: [Int64] = [0, 987, 3456, 4567, 5678, 6789]
        for mask in 0..<64 {
            let raw = original.enumerated().map { index, value in mask & (1 << index) == 0 ? value : -1 }
            let result = MeasurementResult.calculate(
                packet: packet(blOpen: raw[0], blClose: raw[1], centerOpen: raw[2], centerClose: raw[3], trOpen: raw[4], trClose: raw[5]),
                direction: .vertical, nominalDenominator: 1_000
            )
            XCTAssertEqual(result.quality, mask == 0 ? .complete : .partial, "Missing mask \(mask)")
            XCTAssertEqual(result.bottomLeft.durationMS != nil, mask & 0b000011 == 0)
            XCTAssertEqual(result.center.durationMS != nil, mask & 0b001100 == 0)
            XCTAssertEqual(result.topRight.durationMS != nil, mask & 0b110000 == 0)
            XCTAssertEqual(result.openingTravelMS != nil, mask & 0b010001 == 0)
            XCTAssertEqual(result.closingTravelMS != nil, mask & 0b100010 == 0)
            XCTAssertEqual(result.openingFirstSegmentMS != nil, mask & 0b000101 == 0)
            XCTAssertEqual(result.openingSecondSegmentMS != nil, mask & 0b010100 == 0)
            XCTAssertEqual(result.closingFirstSegmentMS != nil, mask & 0b001010 == 0)
            XCTAssertEqual(result.closingSecondSegmentMS != nil, mask & 0b101000 == 0)
        }
    }

    func testNegativeRawEventIsMissingEvenWhenItsOffsetWouldMakeItPositive() {
        let result = calculate(packet: packet(trOpen: -1))
        XCTAssertEqual(result.quality, .partial)
        XCTAssertNil(result.topRight.durationMS)
        XCTAssertNil(result.openingTravelMS)
        assertNear(result.center.durationMS, 1.111)
        assertNear(result.closingTravelMS, 5.780)
    }

    func testNegativeCalibratedEventRemainsValid() {
        let result = calculate(packet: packet(blOpen: 0, blClose: 10, blOpenOffset: -200, blCloseOffset: -100))
        XCTAssertEqual(result.quality, .complete)
        assertNear(result.bottomLeft.durationMS, 0.11)
        assertNear(result.openingTravelMS, 5.918)
    }

    func testZeroAndReversedExposureAreFlaggedAndOtherSensorsRemainAvailable() {
        for close: Int64 in [3456, 3455] {
            let result = calculate(packet: packet(centerClose: close))
            XCTAssertEqual(result.quality, .invalid)
            XCTAssertNil(result.center.durationMS)
            XCTAssertNil(result.center.reciprocalSeconds)
            XCTAssertNil(result.exposureErrorStops)
            XCTAssertFalse(result.issues.isEmpty)
            assertNear(result.bottomLeft.durationMS, 1.044)
            assertNear(result.topRight.durationMS, 1.081)
        }
    }

    func testOppositeCurtainDirectionUsesAbsoluteTravel() {
        let result = calculate(packet: packet(
            blOpen: 5678, blClose: 6789, trOpen: 0, trClose: 987,
            blOpenOffset: 40, blCloseOffset: 10, trOpenOffset: -25, trCloseOffset: 32
        ))
        XCTAssertEqual(result.quality, .complete)
        assertNear(result.openingTravelMS, 5.743)
        assertNear(result.closingTravelMS, 5.780)
    }

    func testCalibrationOverflowIsInvalidWithoutTrapping() {
        let result = calculate(packet: packet(blOpen: .max, blOpenOffset: 1))
        XCTAssertEqual(result.quality, .invalid)
        XCTAssertNil(result.bottomLeft.durationMS)
        XCTAssertNil(result.openingTravelMS)
        assertNear(result.center.durationMS, 1.111)
        XCTAssertTrue(result.issues.contains { $0.contains("integer range") })
    }

    func testExtremeIntegerArithmeticPreservesSmallAndLargeDurations() {
        let short = calculate(packet: packet(centerOpen: .max - 1, centerClose: .max))
        assertNear(short.center.durationMS, 0.001)
        assertNear(short.center.reciprocalSeconds, 1_000_000)
        let wide = calculate(packet: packet(blOpen: 0, blClose: 0, blOpenOffset: .min, blCloseOffset: .max))
        XCTAssertEqual(wide.quality, .complete)
        assertNear(wide.bottomLeft.durationMS, Double(UInt64.max) / 1_000, accuracy: 1)
        XCTAssertTrue(wide.bottomLeft.reciprocalSeconds?.isFinite == true)
    }

    func testExposureDifferenceAndInvalidReference() {
        let sample = packet(centerOpen: 1_000, centerClose: 9_200)
        let result = MeasurementResult.calculate(packet: sample, direction: .vertical, nominalDenominator: 125)
        assertNear(result.exposureErrorStops, log2(1.025))
        assertNear(result.exposureErrorPercent, 2.5)
        for denominator: Double in [0, -1, .infinity, .nan] {
            let result = MeasurementResult.calculate(packet: sample, direction: .vertical, nominalDenominator: denominator)
            XCTAssertEqual(result.quality, .complete)
            XCTAssertNil(result.exposureErrorStops)
            XCTAssertNil(result.exposureErrorPercent)
            XCTAssertFalse(result.issues.isEmpty)
        }
        let huge = MeasurementResult.calculate(packet: sample, direction: .vertical, nominalDenominator: .greatestFiniteMagnitude)
        XCTAssertTrue(huge.exposureErrorStops?.isFinite == true)
        XCTAssertTrue(huge.exposureErrorPercent == nil || huge.exposureErrorPercent!.isFinite)
        let tiny = MeasurementResult.calculate(packet: sample, direction: .vertical, nominalDenominator: .leastNonzeroMagnitude)
        XCTAssertTrue(tiny.exposureErrorStops?.isFinite == true)
    }

    func testParserRequiresOffsetsAndRejectsBooleansFractionalValuesAndOverflow() {
        for name in ["bottomLeftOpenOffset", "bottomLeftCloseOffset", "topRightOpenOffset", "topRightCloseOffset"] {
            var object = try! JSONSerialization.jsonObject(with: Data(pythonFixture.utf8)) as! [String: Any]
            object.removeValue(forKey: name)
            assertInvalid(try! JSONSerialization.data(withJSONObject: object), contains: name)
        }
        for name in ["bottomLeftOpen", "bottomLeftClose", "centerOpen", "centerClose", "topRightOpen", "topRightClose", "bottomLeftOpenOffset", "bottomLeftCloseOffset", "topRightOpenOffset", "topRightCloseOffset"] {
            for value: Any in [true, 1.5, NSNull()] {
                var object = try! JSONSerialization.jsonObject(with: Data(pythonFixture.utf8)) as! [String: Any]
                object[name] = value
                assertInvalid(try! JSONSerialization.data(withJSONObject: object))
            }
        }
        assertInvalid(Data(pythonFixture.replacingOccurrences(of: "\"centerOpen\":3456", with: "\"centerOpen\":9223372036854775808").utf8))
    }

    func testParserDistinguishesDiagnosticsUnsupportedEventsAndInvalidMeasurements() {
        for text in ["Booting Shutter Lover", "", " \r\n"] {
            guard case .ignored = PacketParser.parse(Data(text.utf8)) else { return XCTFail("Expected diagnostic") }
        }
        guard case .ignored = PacketParser.parse(Data(#"{"eventType":"DeviceReady"}"#.utf8)) else { return XCTFail("Expected ignored event") }
        assertInvalid(Data(pythonFixture.replacingOccurrences(of: "microsecond", with: "millisecond").utf8), contains: "unit")
        assertInvalid(Data(pythonFixture.replacingOccurrences(of: "\"1.0.0\"", with: "\"\"").utf8), contains: "firmware")
        for text in ["{broken", "[]", "{\"unit\":\"microsecond\"}"] { assertInvalid(Data(text.utf8)) }
        assertInvalid(Data([0xFF]))
        // A newer firmware string is compatible when it supplies the documented schema.
        guard case .measurement = PacketParser.parse(Data(pythonFixture.replacingOccurrences(of: "1.0.0", with: "2.9.0").utf8)) else { return XCTFail("Firmware version alone must not reject a packet") }
    }

    func testDirectUnsupportedPacketCannotProducePlausibleMeasurements() {
        let unsupported = MeasurementPacket(eventType: "Other", unit: "seconds", bottomLeftOpen: 0, bottomLeftClose: 1, centerOpen: 0, centerClose: 1, topRightOpen: 0, topRightClose: 1, bottomLeftOpenOffset: 0, bottomLeftCloseOffset: 0, topRightOpenOffset: 0, topRightCloseOffset: 0)
        let result = calculate(packet: unsupported)
        XCTAssertEqual(result.quality, .invalid)
        XCTAssertNil(result.center.durationMS)
        XCTAssertNil(result.openingTravelMS)
    }

    func testDemoPacketsAreDeterministicCoherentAndSafeForExtremeInputs() {
        XCTAssertEqual(DemoPackets.sample(nominalDenominator: 125, index: 0), DemoPackets.sample(nominalDenominator: 125, index: 0))
        for denominator: Double in [125, 4_000, 0, -1, .nan, .infinity, .leastNonzeroMagnitude, .greatestFiniteMagnitude] {
            for index in [0, 1, Int.min, Int.max] {
                let sample = DemoPackets.sample(nominalDenominator: denominator, index: index)
                let result = calculate(packet: sample)
                XCTAssertEqual(result.quality, .complete)
                XCTAssertTrue(result.center.durationMS! > 0)
            }
        }
        XCTAssertEqual(calculate(packet: DemoPackets.sample(nominalDenominator: 125, index: 0, partial: true)).quality, .partial)
    }

    private func calculate(packet: MeasurementPacket? = nil, direction: CurtainDirection = .vertical) -> MeasurementResult {
        MeasurementResult.calculate(packet: packet ?? self.packet(), direction: direction, nominalDenominator: 1_000)
    }

    private func packet(
        blOpen: Int64 = 0, blClose: Int64 = 987, centerOpen: Int64 = 3456, centerClose: Int64 = 4567,
        trOpen: Int64 = 5678, trClose: Int64 = 6789, blOpenOffset: Int64 = -25,
        blCloseOffset: Int64 = 32, trOpenOffset: Int64 = 40, trCloseOffset: Int64 = 10
    ) -> MeasurementPacket {
        MeasurementPacket(bottomLeftOpen: blOpen, bottomLeftClose: blClose, centerOpen: centerOpen, centerClose: centerClose,
                          topRightOpen: trOpen, topRightClose: trClose, bottomLeftOpenOffset: blOpenOffset,
                          bottomLeftCloseOffset: blCloseOffset, topRightOpenOffset: trOpenOffset, topRightCloseOffset: trCloseOffset)
    }

    private func assertNear(_ actual: Double?, _ expected: Double, accuracy: Double = 0.000_000_01, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else { return XCTFail("Expected \(expected), got unavailable", file: file, line: line) }
        XCTAssertEqual(actual, expected, accuracy: accuracy, file: file, line: line)
    }

    private func assertInvalid(_ data: Data, contains: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        guard case .invalid(let reason) = PacketParser.parse(data) else { return XCTFail("Expected invalid packet", file: file, line: line) }
        if let contains { XCTAssertTrue(reason.contains(contains), reason, file: file, line: line) }
    }
}
