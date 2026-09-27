import Foundation

/// Incremental LF/CRLF framing with a bounded buffer. An oversized record is discarded
/// through its terminating LF, so its suffix can never become a different measurement.
public struct LineFramer: Sendable {
    private let maxLineBytes: Int
    private var buffer = Data()
    private var discarding = false
    public private(set) var droppedLineCount = 0

    public init(maxLineBytes: Int = 65_536) {
        self.maxLineBytes = max(1, maxLineBytes)
    }

    public mutating func append(_ data: Data) -> [Data] {
        var lines: [Data] = []
        for byte in data {
            if byte == 0x0A {
                if !discarding {
                    if buffer.last == 0x0D { buffer.removeLast() }
                    lines.append(buffer)
                }
                buffer.removeAll(keepingCapacity: true)
                discarding = false
            } else if !discarding {
                // Allow one extra trailing CR without counting it against the payload cap.
                if buffer.count < maxLineBytes || (buffer.count == maxLineBytes && byte == 0x0D) {
                    buffer.append(byte)
                } else {
                    buffer.removeAll(keepingCapacity: true)
                    discarding = true
                    if droppedLineCount < Int.max { droppedLineCount += 1 }
                }
            }
        }
        return lines
    }

    /// Clears incomplete bytes and counters when the connection changes.
    public mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
        discarding = false
        droppedLineCount = 0
    }
}
