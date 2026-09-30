import Foundation
import IOKit
import IOKit.serial

/// A serial callout device. Discovery does not establish that a device is a Shutter Lover.
public struct SerialDevice: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let usbVendorID: Int?
    public let usbProductID: Int?
    public let usbSerialNumber: String?
    public let usbLocationID: UInt32?
    public let usbManufacturer: String?
    public let usbProductName: String?

    public init(name: String, path: String, usbVendorID: Int? = nil, usbProductID: Int? = nil,
                usbSerialNumber: String? = nil, usbLocationID: UInt32? = nil,
                usbManufacturer: String? = nil, usbProductName: String? = nil) {
        self.name = name
        self.path = path
        self.usbVendorID = usbVendorID.flatMap { (0...0xffff).contains($0) ? $0 : nil }
        self.usbProductID = usbProductID.flatMap { (0...0xffff).contains($0) ? $0 : nil }
        self.usbSerialNumber = Self.nonempty(usbSerialNumber)
        self.usbLocationID = usbLocationID
        self.usbManufacturer = Self.nonempty(usbManufacturer)
        self.usbProductName = Self.nonempty(usbProductName)
    }

    /// A reported USB identity, usable across changes of cable, port and device node.
    /// A serial number alone is not globally unique: scope it to the USB vendor/product.
    /// Firmware may omit or reuse serials, so callers must handle ambiguous matches.
    /// Paths and USB locations describe connections, never the identity of a tester.
    public var stableIdentityKey: String? {
        guard let vendor = usbVendorID, let product = usbProductID,
              let serial = usbSerialNumber else { return nil }
        // Preserve case and interior whitespace. Base64 avoids separator collisions.
        return String(format: "usb:%04x:%04x:", vendor, product)
            + Data(serial.utf8).base64EncodedString()
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
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
                devicesByPath[path] = device(name: name, path: path, service: service)
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

    private static func integerProperty(_ key: String, of service: io_registry_entry_t) -> Int64? {
        (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber)?.int64Value
    }

    private static func device(name: String, path: String, service: io_registry_entry_t) -> SerialDevice {
        // The serial client is usually several levels below its USB device. Stop at
        // the nearest physical USB device even when it has no serial; proceeding
        // farther could incorrectly identify the tester as its hub or host port.
        var entry = service
        IOObjectRetain(entry)
        defer { IOObjectRelease(entry) }
        for _ in 0..<64 {
            if IOObjectConformsTo(entry, "IOUSBHostDevice") != 0
                || IOObjectConformsTo(entry, "IOUSBDevice") != 0 {
                let vendor = integerProperty("idVendor", of: entry).flatMap(Int.init(exactly:))
                let product = integerProperty("idProduct", of: entry).flatMap(Int.init(exactly:))
                let location = integerProperty("locationID", of: entry).flatMap(UInt32.init(exactly:))
                return SerialDevice(name: name, path: path,
                                    usbVendorID: vendor, usbProductID: product,
                                    usbSerialNumber: stringProperty("USB Serial Number", of: entry),
                                    usbLocationID: location,
                                    usbManufacturer: stringProperty("USB Vendor Name", of: entry),
                                    usbProductName: stringProperty("USB Product Name", of: entry))
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS,
                  parent != 0 else { break }
            IOObjectRelease(entry)
            entry = parent
        }
        return SerialDevice(name: name, path: path)
    }
}
