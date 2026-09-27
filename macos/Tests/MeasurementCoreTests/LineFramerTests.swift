import Foundation
import XCTest
@testable import MeasurementCore

final class LineFramerTests: XCTestCase {
    func testSplitCRLFCoalescedLinesAndEmptyLines() {
        var framer = LineFramer()
        XCTAssertEqual(framer.append(Data("first\r".utf8)), [])
        XCTAssertEqual(strings(framer.append(Data("\nsecond\n\nthi".utf8))), ["first", "second", ""])
        XCTAssertEqual(strings(framer.append(Data("rd\n".utf8))), ["third"])
        XCTAssertEqual(framer.droppedLineCount, 0)
    }

    func testEveryChunkBoundaryProducesIdenticalPackets() {
        let stream = Data("boot\r\n{\"first\":1}\n{\"second\":2}\r\n".utf8)
        for chunkLength in 1...stream.count {
            var framer = LineFramer()
            var actual: [Data] = []
            var position = 0
            while position < stream.count {
                let end = min(position + chunkLength, stream.count)
                actual += framer.append(stream.subdata(in: position..<end))
                position = end
            }
            XCTAssertEqual(strings(actual), ["boot", "{\"first\":1}", "{\"second\":2}"])
        }
    }

    func testOverflowDiscardsEntireLineUntilNewlineAndThenRecovers() {
        var framer = LineFramer(maxLineBytes: 4)
        XCTAssertEqual(framer.append(Data("12345".utf8)), [])
        XCTAssertEqual(framer.droppedLineCount, 1)
        XCTAssertEqual(framer.append(Data(repeating: 0x61, count: 100_000)), [])
        XCTAssertEqual(framer.droppedLineCount, 1)
        XCTAssertEqual(strings(framer.append(Data("fake\nOK\r\n12345\nYES\n".utf8))), ["OK", "YES"])
        XCTAssertEqual(framer.droppedLineCount, 2)
    }

    func testExactLimitAllowsBothLFAndCRLF() {
        var framer = LineFramer(maxLineBytes: 4)
        XCTAssertEqual(strings(framer.append(Data("1234\n1234\r\n1234\rX\n".utf8))), ["1234", "1234"])
        XCTAssertEqual(framer.droppedLineCount, 1)
    }

    func testResetPreventsFragmentsFromCrossingConnections() {
        var framer = LineFramer(maxLineBytes: 4)
        _ = framer.append(Data("12345".utf8))
        framer.reset()
        XCTAssertEqual(framer.droppedLineCount, 0)
        XCTAssertEqual(strings(framer.append(Data("new\nold".utf8))), ["new"])
        framer.reset()
        XCTAssertEqual(strings(framer.append(Data("new\n".utf8))), ["new"])
    }

    private func strings(_ lines: [Data]) -> [String] {
        lines.map { String(decoding: $0, as: UTF8.self) }
    }
}
