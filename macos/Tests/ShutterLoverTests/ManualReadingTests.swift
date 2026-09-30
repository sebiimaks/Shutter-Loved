import XCTest
import MeasurementCore
@testable import ShutterLover

final class ManualReadingTests: XCTestCase {
    private func session(model: TesterModel = .babyShutterTesterMkII, measurement: ManualMeasurement = ManualMeasurement(enteredValue: 8)) -> CaptureSession {
        let tester = TesterSnapshot(tester: OwnedTester(name: "My Baby", model: model))
        var record = MeasurementRecord(rawLine: "", manual: measurement, tester: tester, direction: .unknown, nominalDenominator: 125, isDemo: false)
        record.derivedSnapshot = record.recalculatedResult
        return CaptureSession(cameraName: "Camera", demo: false, records: [record], tester: tester)
    }

    func testEquivalentUnitsRetainOriginalInputAndProduceSingleSensorResults() throws {
        let measurements = [ManualMeasurement(enteredValue: 8, unit: .milliseconds),
                            ManualMeasurement(enteredValue: 0.008, unit: .seconds),
                            ManualMeasurement(enteredValue: 125, unit: .reciprocalSeconds)]
        for measurement in measurements {
            let source = session(measurement: measurement)
            let data = try SessionStore.encoder().encode(SessionArchive(sessions: [source]))
            let saved = try XCTUnwrap(SessionStore.decode(data).first?.records.first)
            XCTAssertEqual(saved.manual, measurement)
            XCTAssertNil(saved.packet)
            XCTAssertTrue(saved.rawLine.isEmpty)
            XCTAssertEqual(saved.result.center.durationMS, 8)
            XCTAssertEqual(saved.result.center.reciprocalSeconds, 125)
            XCTAssertEqual(try XCTUnwrap(saved.result.exposureErrorStops), 0, accuracy: 1e-12)
            XCTAssertEqual(saved.result.quality, .complete)
            XCTAssertNil(saved.result.bottomLeft.durationMS)
            XCTAssertNil(saved.result.topRight.durationMS)
            XCTAssertNil(saved.result.openingTravelMS)
            XCTAssertNil(saved.result.closingTravelMS)
            XCTAssertNil(saved.result.openingFullFrameMS)
            XCTAssertNil(saved.result.closingFullFrameMS)
            XCTAssertEqual(saved.measurementLabel, "Effective exposure")
        }
    }

    func testRejectsInvalidTimeIlluminationAndUnsupportedModelModes() throws {
        for value in [0, -1, .nan, .infinity, 0.0000009, 1000.0001] {
            XCTAssertThrowsError(try SessionStore.validateManualMeasurement(ManualMeasurement(enteredValue: value, unit: .seconds), model: .babyShutterTesterMkII))
        }
        for unit in ManualTimeUnit.allCases {
            XCTAssertThrowsError(try SessionStore.validateManualMeasurement(ManualMeasurement(enteredValue: 0, unit: unit), model: .babyShutterTesterMkII))
        }
        for value in [0.000001, 1000] {
            XCTAssertNoThrow(try SessionStore.validateManualMeasurement(ManualMeasurement(enteredValue: value, unit: .seconds), model: .babyShutterTesterMkII))
        }
        for value in [-0.01, 100.01, .nan, .infinity] {
            XCTAssertThrowsError(try SessionStore.validateManualMeasurement(ManualMeasurement(enteredValue: 8, illumination: value), model: .babyShutterTesterMkII))
        }
        XCTAssertThrowsError(try SessionStore.validateManualMeasurement(ManualMeasurement(enteredValue: 8, mode: .automatic, seriesIllumination: 40), model: .babyShutterTesterMkII))
        XCTAssertNoThrow(try SessionStore.validateManualMeasurement(ManualMeasurement(enteredValue: 8, mode: .global, illumination: 20, seriesIllumination: 40), model: .babyShutterTesterMkII))
        XCTAssertThrowsError(try SessionStore.validateManualMeasurement(ManualMeasurement(enteredValue: 8), model: .shutterLover))
        XCTAssertNoThrow(try SessionStore.validate([session(model: .babyShutterTesterMkI)]))
        XCTAssertEqual(session(model: .babyShutterTesterMkI).records[0].measurementLabel, "Measured exposure")
        for measurement in [ManualMeasurement(enteredValue: 8, mode: .automatic), ManualMeasurement(enteredValue: 8, illumination: 20), ManualMeasurement(enteredValue: 8, mode: .global, seriesIllumination: 40)] {
            XCTAssertThrowsError(try SessionStore.validate([session(model: .babyShutterTesterMkI, measurement: measurement)]))
        }
    }

    func testRejectsMissingMixedOrFabricatedEvidenceAndRequiresTesterModel() {
        var invalid = session()
        invalid.records[0].manual = nil
        XCTAssertThrowsError(try SessionStore.validate([invalid]))
        invalid = session()
        invalid.records[0].packet = DemoPackets.sample(nominalDenominator: 125, index: 0)
        XCTAssertThrowsError(try SessionStore.validate([invalid]))
        invalid = session()
        invalid.records[0].tester = nil
        XCTAssertThrowsError(try SessionStore.validate([invalid]))
        invalid = session()
        invalid.records[0].tester?.model = .shutterLover
        XCTAssertThrowsError(try SessionStore.validate([invalid]))
        invalid = session()
        invalid.records[0].rawLine = "fabricated packet"
        XCTAssertThrowsError(try SessionStore.validate([invalid]))
        invalid = session()
        invalid.records[0].direction = .horizontal
        XCTAssertThrowsError(try SessionStore.validate([invalid]))
        invalid = session()
        invalid.demo = true
        invalid.records[0].isDemo = true
        XCTAssertThrowsError(try SessionStore.validate([invalid]))
    }

    func testSettingCorrectionKeepsEnteredValueAndChecksDerivedSnapshot() throws {
        var source = session()
        let original = source.records[0].manual
        source.records[0].settingCorrections = [SettingCorrection(changedAt: Date(), previousValue: 125, newValue: 250)]
        source.records[0].nominalDenominator = 250
        XCTAssertThrowsError(try SessionStore.validate([source]))
        source.records[0].derivedSnapshot = source.records[0].recalculatedResult
        XCTAssertNoThrow(try SessionStore.validate([source]))
        XCTAssertEqual(source.records[0].manual, original)
        XCTAssertEqual(try XCTUnwrap(source.records[0].result.exposureErrorStops), 1, accuracy: 1e-12)
        XCTAssertEqual(source.records[0].result.exposureErrorPercent, 100)
    }

    func testCSVPreservesSourceAndMetadataWithoutInventingGeometry() throws {
        let source = session(measurement: ManualMeasurement(enteredValue: 125, unit: .reciprocalSeconds, mode: .global, illumination: 24, seriesIllumination: 40, notes: "Copied from display"))
        let lines = SessionExport.table(source.records, separator: "\t").split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        XCTAssertEqual(lines[0].count, lines[1].count)
        let fields = Dictionary(uniqueKeysWithValues: zip(lines[0], lines[1]))
        XCTAssertEqual(fields["Reading source"], "Manual")
        XCTAssertEqual(fields["Tester model"], "Baby Shutter Tester Mk II")
        XCTAssertEqual(fields["Entered value"], "125.0")
        XCTAssertEqual(fields["Entered unit"], "reciprocalSeconds")
        XCTAssertEqual(fields["Baby mode"], "global")
        XCTAssertEqual(fields["Illumination E0 (unitless)"], "24.0")
        XCTAssertEqual(fields["Series illumination E0 (unitless)"], "40.0")
        XCTAssertEqual(fields["Tester UUID"], source.records[0].tester?.id?.uuidString)
        XCTAssertEqual(fields["Sensor width (mm)"], "")
        XCTAssertEqual(fields["Frame height (mm)"], "")
        XCTAssertEqual(fields["Open (ms)"], "")
    }
}
