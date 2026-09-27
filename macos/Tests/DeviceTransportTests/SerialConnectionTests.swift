import Darwin
import Foundation
import XCTest
@testable import DeviceTransport

final class SerialConnectionTests: XCTestCase {
    func testReceivesUnmodifiedChunksWithoutTransmittingAndRestoresSettings() throws {
        let terminal = try PseudoTerminal()
        let original = try terminal.settings()
        let connection = SerialConnection(allowedTestDevicePath: terminal.path)
        let events = EventJournal()
        defer { connection.disconnect() }

        connection.connect(path: terminal.path) { events.record($0) }
        try events.waitFor("port to open") { $0.contains(.opened) }
        try assertConfigured(terminal)
        XCTAssertEqual(try terminal.readHostOutput(), Data(), "Opening must not send probe or reset commands")

        let first = Data([0x7B, 0x22, 0x65, 0x76, 0x65, 0x6E, 0x74, 0x22, 0x3A])
        let second = Data([0x22, 0x74, 0x65, 0x73, 0x74, 0x22, 0x7D, 0x0D, 0x0A, 0x00, 0xFF])
        try terminal.sendToHost(first)
        try events.waitFor("first partial packet") { $0.receivedBytes == first }
        try terminal.sendToHost(second)
        try events.waitFor("remaining bytes") { $0.receivedBytes == first + second }
        XCTAssertEqual(try terminal.readHostOutput(), Data(), "Received bytes must not be echoed to the device")

        connection.disconnect()
        try events.waitFor("disconnect") { $0.contains(.closed) }
        XCTAssertEqual(try terminal.settings(), original, "Closing must restore the complete termios configuration")
        XCTAssertEqual(events.snapshot.filter(\.isTerminal), [.closed])
    }

    func testReplacingSamePathClosesBeforeReopeningAndDoesNotRestoreOverNewSettings() throws {
        let terminal = try PseudoTerminal()
        let original = try terminal.settings()
        let connection = SerialConnection(allowedTestDevicePath: terminal.path)
        defer { connection.disconnect() }
        var journals: [EventJournal] = []

        for iteration in 0..<12 {
            let events = EventJournal()
            journals.append(events)
            connection.connect(path: terminal.path) { events.record($0) }
            try events.waitFor("replacement \(iteration) to open") { $0.contains(.opened) }
            if iteration > 0 {
                XCTAssertEqual(journals[iteration - 1].snapshot.filter(\.isTerminal), [.closed],
                               "The old descriptor must close before the replacement opens")
            }
            try assertConfigured(terminal)
            let packet = Data("packet \(iteration)\n".utf8)
            try terminal.sendToHost(packet)
            try events.waitFor("replacement \(iteration) data") { $0.receivedBytes == packet }
            try assertConfigured(terminal)
            for previous in 0..<iteration {
                XCTAssertEqual(journals[previous].snapshot.receivedBytes, Data("packet \(previous)\n".utf8),
                               "A retired connection must never receive a replacement's data")
            }
        }

        connection.disconnect()
        try XCTUnwrap(journals.last).waitFor("final close") { $0.contains(.closed) }
        XCTAssertEqual(try terminal.settings(), original)
        XCTAssertEqual(try terminal.readHostOutput(), Data())
    }

    func testDisconnectThenReconnectAndDeinitializationReleaseExclusivePort() throws {
        let terminal = try PseudoTerminal()
        let original = try terminal.settings()
        var connection: SerialConnection? = SerialConnection(allowedTestDevicePath: terminal.path)
        let first = EventJournal()
        connection?.connect(path: terminal.path) { first.record($0) }
        try first.waitFor("first open") { $0.contains(.opened) }
        connection?.disconnect()
        try first.waitFor("explicit disconnect") { $0.contains(.closed) }
        XCTAssertEqual(try terminal.settings(), original)

        let second = EventJournal()
        connection?.connect(path: terminal.path) { second.record($0) }
        try second.waitFor("reconnect") { $0.contains(.opened) }
        let packet = Data("after reconnect\n".utf8)
        try terminal.sendToHost(packet)
        try second.waitFor("reconnected data") { $0.receivedBytes == packet }

        connection = nil
        try second.waitFor("deinitialization cleanup") { $0.contains(.closed) }
        XCTAssertEqual(try terminal.settings(), original)
        let newDescriptor = Darwin.open(terminal.path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        XCTAssertGreaterThanOrEqual(newDescriptor, 0, "Cleanup must release exclusive access")
        if newDescriptor >= 0 { Darwin.close(newDescriptor) }
    }

    func testExclusivePortFailsClearlyWithoutChangingItsSettings() throws {
        let terminal = try PseudoTerminal()
        guard ioctl(terminal.slaveDescriptor, TIOCEXCL) == 0 else {
            throw XCTSkip("This environment does not support exclusive PTY access: \(posixMessage())")
        }
        defer { _ = ioctl(terminal.slaveDescriptor, TIOCNXCL) }
        // Darwin PTY drivers vary in whether they enforce TIOCEXCL. Verify this
        // kernel can model a busy device before asserting the adapter's response.
        let probe = Darwin.open(terminal.path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        if probe >= 0 {
            Darwin.close(probe)
            throw XCTSkip("This macOS PTY driver allows a second open after TIOCEXCL; it cannot simulate a busy hardware port.")
        }
        guard errno == EBUSY else {
            throw XCTSkip("PTY exclusive-open probe failed with a non-busy error: \(posixMessage())")
        }
        let original = try terminal.settings()
        let connection = SerialConnection(allowedTestDevicePath: terminal.path)
        let events = EventJournal()
        connection.connect(path: terminal.path) { events.record($0) }
        try events.waitFor("busy-device failure") { $0.contains(where: \.isTerminal) }
        guard case .failed(let message) = try XCTUnwrap(events.snapshot.first) else {
            return XCTFail("An exclusively owned port must not open")
        }
        XCTAssertTrue(message.contains("busy"), message)
        XCTAssertEqual(events.snapshot.count, 1)
        XCTAssertEqual(try terminal.settings(), original)
    }

    func testClosingDeviceEndReportsOneTerminalFailure() throws {
        let terminal = try PseudoTerminal()
        let connection = SerialConnection(allowedTestDevicePath: terminal.path)
        let events = EventJournal()
        defer { connection.disconnect() }
        connection.connect(path: terminal.path) { events.record($0) }
        try events.waitFor("open before device hangup") { $0.contains(.opened) }
        terminal.closeDeviceEnd()
        try events.waitFor("device hangup") { $0.contains(where: \.isTerminal) }
        let terminalEvents = events.snapshot.filter(\.isTerminal)
        XCTAssertEqual(terminalEvents.count, 1)
        guard case .failed(let message) = try XCTUnwrap(terminalEvents.first) else {
            return XCTFail("A device hangup must report a failure")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testPublicConnectionRejectsNonCalloutPathWithoutOpeningIt() throws {
        let connection = SerialConnection()
        let events = EventJournal()
        connection.connect(path: "/dev/ttys-not-a-callout-device") { events.record($0) }
        try events.waitFor("path validation") { $0.contains(where: \.isTerminal) }
        guard case .failed(let message) = try XCTUnwrap(events.snapshot.first) else {
            return XCTFail("Public connections must require callout paths")
        }
        XCTAssertTrue(message.contains("/dev/cu."))
    }

    private func assertConfigured(_ terminal: PseudoTerminal, file: StaticString = #filePath,
                                  line: UInt = #line) throws {
        let settings = try terminal.settings()
        XCTAssertEqual(settings.inputSpeed, speed_t(B9600), file: file, line: line)
        XCTAssertEqual(settings.outputSpeed, speed_t(B9600), file: file, line: line)
        XCTAssertEqual(settings.controlFlags & tcflag_t(CSIZE), tcflag_t(CS8), file: file, line: line)
        XCTAssertEqual(settings.controlFlags & tcflag_t(PARENB | CSTOPB | CRTSCTS | CDTR_IFLOW | CDSR_OFLOW | CCAR_OFLOW),
                       0, file: file, line: line)
        XCTAssertEqual(settings.inputFlags & tcflag_t(IXON | IXOFF | IXANY), 0, file: file, line: line)
        XCTAssertEqual(settings.localFlags & tcflag_t(ICANON | ECHO), 0, file: file, line: line)
    }
}

private enum ObservedEvent: Equatable {
    case opened, bytes(Data), closed, failed(String)

    var isTerminal: Bool {
        switch self { case .closed, .failed: return true; default: return false }
    }
}

private extension Array where Element == ObservedEvent {
    var receivedBytes: Data {
        reduce(into: Data()) { result, event in
            if case .bytes(let bytes) = event { result.append(bytes) }
        }
    }
}

private final class EventJournal: @unchecked Sendable {
    private let condition = NSCondition()
    private var events: [ObservedEvent] = []

    var snapshot: [ObservedEvent] {
        condition.lock()
        defer { condition.unlock() }
        return events
    }

    func record(_ event: SerialEvent) {
        condition.lock()
        switch event {
        case .opened: events.append(.opened)
        case .bytes(let bytes): events.append(.bytes(bytes))
        case .closed: events.append(.closed)
        case .failed(let message): events.append(.failed(message))
        }
        condition.broadcast()
        condition.unlock()
    }

    func waitFor(_ description: String, timeout: TimeInterval = 3,
                 until predicate: ([ObservedEvent]) -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while !predicate(events) {
            if events.contains(where: { if case .failed = $0 { return true }; return false }) {
                throw HarnessError("Waiting for \(description) received an unexpected failure: \(events)")
            }
            guard condition.wait(until: deadline) else {
                if predicate(events) { return }
                throw HarnessError("Timed out after \(timeout)s waiting for \(description); events: \(events)")
            }
        }
    }
}

private struct TerminalSnapshot: Equatable {
    let inputFlags: tcflag_t
    let outputFlags: tcflag_t
    let controlFlags: tcflag_t
    let localFlags: tcflag_t
    let inputSpeed: speed_t
    let outputSpeed: speed_t
    let controlCharacters: [UInt8]

    init(_ value: termios) {
        var value = value
        inputFlags = value.c_iflag
        outputFlags = value.c_oflag
        controlFlags = value.c_cflag
        localFlags = value.c_lflag
        inputSpeed = cfgetispeed(&value)
        outputSpeed = cfgetospeed(&value)
        controlCharacters = withUnsafeBytes(of: &value.c_cc) { Array($0) }
    }
}

private final class PseudoTerminal {
    let path: String
    let slaveDescriptor: Int32
    private var masterDescriptor: Int32

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var name = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard openpty(&master, &slave, &name, nil, nil) == 0 else {
            throw XCTSkip("macOS openpty is unavailable in this environment: \(posixMessage())")
        }
        var configured = false
        defer {
            if !configured {
                Darwin.close(master)
                Darwin.close(slave)
            }
        }

        var settings = termios()
        guard tcgetattr(slave, &settings) == 0 else {
            throw XCTSkip("Cannot read PTY settings: \(posixMessage())")
        }
        // Deliberately differ from the adapter so restoration and late-cancel races
        // are observable. PTYs transport bytes in software regardless of baud rate.
        settings.c_lflag |= tcflag_t(ICANON | ECHO)
        _ = cfsetispeed(&settings, speed_t(B38400))
        _ = cfsetospeed(&settings, speed_t(B38400))
        guard tcsetattr(slave, TCSANOW, &settings) == 0,
              fcntl(master, F_SETFL, O_NONBLOCK) == 0 else {
            throw XCTSkip("Cannot configure a nonblocking PTY: \(posixMessage())")
        }
        masterDescriptor = master
        slaveDescriptor = slave
        path = String(cString: name)
        configured = true
    }

    deinit {
        if masterDescriptor >= 0 { Darwin.close(masterDescriptor) }
        Darwin.close(slaveDescriptor)
    }

    func closeDeviceEnd() {
        if masterDescriptor >= 0 { Darwin.close(masterDescriptor) }
        masterDescriptor = -1
    }

    func settings() throws -> TerminalSnapshot {
        var settings = termios()
        guard tcgetattr(slaveDescriptor, &settings) == 0 else {
            throw HarnessError("Reading PTY attributes failed: \(posixMessage())")
        }
        return TerminalSnapshot(settings)
    }

    func sendToHost(_ data: Data) throws {
        let written = data.withUnsafeBytes { Darwin.write(masterDescriptor, $0.baseAddress, $0.count) }
        guard written == data.count else {
            throw HarnessError("PTY wrote \(written)/\(data.count) bytes: \(posixMessage())")
        }
    }

    func readHostOutput() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = Darwin.read(masterDescriptor, &bytes, bytes.count)
        if count < 0, errno == EAGAIN || errno == EWOULDBLOCK { return Data() }
        guard count >= 0 else { throw HarnessError("PTY output read failed: \(posixMessage())") }
        return Data(bytes.prefix(count))
    }
}

private struct HarnessError: LocalizedError, CustomStringConvertible {
    let description: String
    var errorDescription: String? { description }
    init(_ description: String) { self.description = description }
}

private func posixMessage() -> String { String(cString: strerror(errno)) }
