import Foundation
import IOKit
import IOKit.serial

/// A serial callout device. Discovery does not establish that a device is a Shutter Lover.
public struct SerialDevice: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public enum SerialDiscovery {
    /// Lists devices without opening them or sending identification commands.
    public static func devices() -> [SerialDevice] {
        var devicesByPath: [String: SerialDevice] = [:]
        var iterator: io_iterator_t = 0
        if let matching = IOServiceMatching(kIOSerialBSDServiceValue),
           IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                guard let path = stringProperty(kIOCalloutDeviceKey, of: service),
                      path.hasPrefix("/dev/cu.") else { continue }
                let name = stringProperty(kIOTTYDeviceKey, of: service)
                    ?? String(URL(fileURLWithPath: path).lastPathComponent.dropFirst(3))
                devicesByPath[path] = SerialDevice(name: name, path: path)
            }
        }

        // Some driver versions do not expose a usable IOSerialBSDClient registry entry.
        // This fallback only lists existing callout nodes; it does not probe them.
        if devicesByPath.isEmpty,
           let names = try? FileManager.default.contentsOfDirectory(atPath: "/dev") {
            for name in names where name.hasPrefix("cu.") {
                let path = "/dev/\(name)"
                devicesByPath[path] = SerialDevice(name: String(name.dropFirst(3)), path: path)
            }
        }
        return devicesByPath.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func stringProperty(_ key: String, of service: io_registry_entry_t) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }
}
