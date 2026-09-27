import XCTest
import MeasurementCore
@testable import ShutterLover

final class CameraResultsTests: XCTestCase {
    private func reading(durationUS: Int64 = 8_000, direction: CurtainDirection = .horizontal, setting: Double = 125) -> MeasurementRecord {
        let packet = MeasurementPacket(firmware_version: "test", bottomLeftOpen: 1_000,
                                      bottomLeftClose: 1_000 + durationUS, centerOpen: 2_000,
                                      centerClose: 2_000 + durationUS, topRightOpen: 3_000,
                                      topRightClose: 3_000 + durationUS, bottomLeftOpenOffset: 0,
                                      bottomLeftCloseOffset: 0, topRightOpenOffset: 0, topRightCloseOffset: 0)
        return MeasurementRecord(rawLine: String(decoding: try! JSONEncoder().encode(packet), as: UTF8.self),
                                 packet: packet, direction: direction, nominalDenominator: setting, isDemo: false)
    }

    func testSummaryUsesCompleteIncludedRealReadingsAndKeepsDirectionsSeparate() throws {
        var session = CaptureSession(cameraName: "Body A", demo: false)
        let first = reading()
        let second = reading(durationUS: 10_000)
        let vertical = reading(direction: .vertical)
        let fasterSetting = reading(setting: 250)
        var excluded = reading(); excluded.isExcluded = true
        var simulated = reading(); simulated.isDemo = true
        let partialPacket = DemoPackets.sample(nominalDenominator: 125, index: 0, partial: true)
        let partial = MeasurementRecord(rawLine: "", packet: partialPacket, direction: .horizontal, nominalDenominator: 125, isDemo: false)
        session.records = [first, second, vertical, fasterSetting, excluded, simulated, partial]
        let groups = CameraResultGroup.groups(for: session)
        XCTAssertEqual(groups.count, 3)
        let horizontal = try XCTUnwrap(groups.first { $0.direction == .horizontal && $0.denominator == 125 })
        XCTAssertEqual(horizontal.count, 2)
        XCTAssertEqual(horizontal.meanMS, 9, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(horizontal.sampleSD), sqrt(2), accuracy: 0.000_001)
        XCTAssertEqual(horizontal.errorStops, log2(9.0 / 8.0), accuracy: 0.000_001)
        XCTAssertEqual(horizontal.errorPercent, 12.5, accuracy: 0.000_001)
        XCTAssertNil(groups.first { $0.direction == .vertical }?.sampleSD)
    }

    func testUnavailableEvidenceDoesNotBecomeZeroOrAHealthAssessment() {
        var session = CaptureSession(cameraName: "Body B", demo: false)
        XCTAssertTrue(CameraResultGroup.groups(for: session).isEmpty)
        var excluded = reading(); excluded.isExcluded = true
        session.records = [excluded]
        XCTAssertTrue(CameraResultGroup.groups(for: session).isEmpty)
    }

    func testSeparateTestsAreNotBlended() throws {
        var reference = CaptureSession(cameraName: "Body C", demo: false)
        reference.records = [reading(durationUS: 8_000)]
        var after = CaptureSession(cameraName: "Body C", demo: false)
        after.records = [reading(durationUS: 16_000)]
        XCTAssertEqual(try XCTUnwrap(CameraResultGroup.groups(for: reference).first).errorStops, 0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(CameraResultGroup.groups(for: after).first).errorStops, 1, accuracy: 0.000_001)
    }
}
