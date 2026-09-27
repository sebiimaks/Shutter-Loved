import Darwin
import Dispatch
import Foundation

public enum SerialEvent: Sendable {
    case opened
    /// An arbitrary byte chunk, which may contain part of a JSON line or multiple lines.
    case bytes(Data)
    case closed
    /// A terminal error. A separate `closed` event is not emitted after a failure.
    case failed(String)
}

/// A receive-only serial connection. All callbacks run on its private serial queue.
/// Callers should dispatch UI updates to the main actor and return promptly from callbacks.
public final class SerialConnection: @unchecked Sendable {
    private let state: ConnectionState

    public init() { state = ConnectionState() }

    /// A narrow test seam: real pseudo terminals can exercise the complete adapter
    /// without exposing arbitrary device paths through the public initializer.
    internal init(allowedTestDevicePath: String) {
        state = ConnectionState(allowedTestDevicePath: allowedTestDevicePath)
    }

    /// Explicitly opens the selected callout path using the legacy app's 9600/8N1 defaults.
    /// Replacing a connection fully closes its descriptor before opening the next one.
    public func connect(path: String, onEvent: @escaping @Sendable (SerialEvent) -> Void) {
        let state = state
        state.queue.async { state.connect(path: path, onEvent: onEvent) }
    }

    public func disconnect() {
        let state = state
        state.queue.async { state.disconnect() }
    }

    deinit {
        let state = state
        state.queue.async { state.disconnect() }
    }
}

private final class ConnectionState: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.shutterlover.serial", qos: .userInitiated)
    private var active: OpenPort?
    private var pending: OpenRequest?
    private let allowedTestDevicePath: String?

    init(allowedTestDevicePath: String? = nil) {
        self.allowedTestDevicePath = allowedTestDevicePath
    }

    private struct OpenRequest {
        let path: String
        let onEvent: @Sendable (SerialEvent) -> Void
    }

    private final class OpenPort {
        let descriptor: Int32
        let originalSettings: termios
        let onEvent: @Sendable (SerialEvent) -> Void
        var source: DispatchSourceRead?
        var isClosing = false
        var terminalEvent: SerialEvent = .closed

        init(descriptor: Int32, originalSettings: termios,
             onEvent: @escaping @Sendable (SerialEvent) -> Void) {
            self.descriptor = descriptor
            self.originalSettings = originalSettings
            self.onEvent = onEvent
        }
    }

    func connect(path: String, onEvent: @escaping @Sendable (SerialEvent) -> Void) {
        pending = OpenRequest(path: path, onEvent: onEvent)
        if let active {
            retire(active, event: .closed)
        } else {
            openPendingRequest()
        }
    }

    func disconnect() {
        pending = nil
        if let active { retire(active, event: .closed) }
    }

    private func openPendingRequest() {
        guard active == nil, let request = pending else { return }
        pending = nil
        let path = request.path
        guard (path.hasPrefix("/dev/cu.") || path == allowedTestDevicePath),
              !path.dropFirst("/dev/".count).contains("/"),
              !path.utf8.contains(0) else {
            request.onEvent(.failed("Choose an available /dev/cu. serial device."))
            return
        }

        let descriptor = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            request.onEvent(.failed(Self.errorMessage("Could not open \(path)", code: errno)))
            return
        }

        var original = termios()
        guard tcgetattr(descriptor, &original) == 0 else {
            let message = Self.errorMessage("Could not read serial settings", code: errno)
            Darwin.close(descriptor)
            request.onEvent(.failed(message))
            return
        }
        // Prevent later clients from opening this port while we own it. A client that
        // already has a nonexclusive descriptor cannot be reliably detected this way.
        guard ioctl(descriptor, TIOCEXCL) == 0 else {
            let message = Self.errorMessage("Could not reserve the serial device", code: errno)
            Darwin.close(descriptor)
            request.onEvent(.failed(message))
            return
        }

        var settings = original
        cfmakeraw(&settings)
        settings.c_cflag &= ~tcflag_t(CSIZE | PARENB | CSTOPB | CRTSCTS | CDTR_IFLOW | CDSR_OFLOW | CCAR_OFLOW)
        settings.c_cflag |= tcflag_t(CS8 | CLOCAL | CREAD)
        settings.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
        withUnsafeMutableBytes(of: &settings.c_cc) { characters in
            characters[Int(VMIN)] = 1
            characters[Int(VTIME)] = 0
        }
        guard cfsetispeed(&settings, speed_t(B9600)) == 0,
              cfsetospeed(&settings, speed_t(B9600)) == 0,
              tcsetattr(descriptor, TCSANOW, &settings) == 0 else {
            let message = Self.errorMessage("Could not configure 9600 baud, 8N1", code: errno)
            _ = tcsetattr(descriptor, TCSANOW, &original)
            _ = ioctl(descriptor, TIOCNXCL)
            Darwin.close(descriptor)
            request.onEvent(.failed(message))
            return
        }

        let port = OpenPort(descriptor: descriptor, originalSettings: original, onEvent: request.onEvent)
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        port.source = source
        active = port
        source.setEventHandler { [weak self, weak port] in
            guard let self, let port, self.active === port, !port.isClosing else { return }
            self.readAvailableBytes(from: port)
        }
        // The descriptor is closed only here once the source has finished using it.
        // Capturing the port preserves it during cancellation; retire breaks its source link.
        source.setCancelHandler { [weak self, port] in
            var original = port.originalSettings
            _ = tcsetattr(port.descriptor, TCSANOW, &original)
            _ = ioctl(port.descriptor, TIOCNXCL)
            Darwin.close(port.descriptor)
            port.onEvent(port.terminalEvent)
            if let self, self.active === port {
                self.active = nil
                self.openPendingRequest()
            }
        }
        source.resume()
        request.onEvent(.opened)
    }

    private func readAvailableBytes(from port: OpenPort) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        // Bound each turn so a busy device cannot indefinitely delay disconnect/replacement.
        for _ in 0..<64 {
            let count = Darwin.read(port.descriptor, &buffer, buffer.count)
            if count > 0 {
                port.onEvent(.bytes(Data(buffer.prefix(count))))
                continue
            }
            if count == 0 {
                retire(port, event: .failed("The serial device disconnected. Reconnect the tester and choose Connect."))
                return
            }
            let code = errno
            if code == EINTR { continue }
            if code == EAGAIN || code == EWOULDBLOCK { return }
            retire(port, event: .failed(Self.errorMessage("Serial reading stopped", code: code)))
            return
        }
    }

    private func retire(_ port: OpenPort, event: SerialEvent) {
        guard !port.isClosing else { return }
        port.isClosing = true
        port.terminalEvent = event
        let source = port.source
        port.source = nil
        source?.cancel()
    }

    private static func errorMessage(_ context: String, code: Int32) -> String {
        switch code {
        case EBUSY:
            return "\(context): the device is busy. Close any other app using this port."
        case EACCES, EPERM:
            return "\(context): macOS denied access to this serial device."
        case ENOENT, ENXIO, ENODEV:
            return "\(context): the device is unavailable or was unplugged."
        default:
            return "\(context): \(String(cString: strerror(code))) (\(code))."
        }
    }
}
