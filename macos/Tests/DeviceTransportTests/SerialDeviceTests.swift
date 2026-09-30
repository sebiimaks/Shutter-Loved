import XCTest
@testable import DeviceTransport

final class SerialDeviceTests: XCTestCase {
    func testLegacyInitializerHasNoInventedUSBIdentity() {
        let device = SerialDevice(name: "USB tester", path: "/dev/cu.usbmodem123")
        XCTAssertEqual(device.id, device.path)
        XCTAssertNil(device.usbVendorID)
        XCTAssertNil(device.usbProductID)
        XCTAssertNil(device.usbSerialNumber)
        XCTAssertNil(device.usbLocationID)
        XCTAssertNil(device.stableIdentityKey)
    }

    func testStableIdentitySurvivesPortLocationAndDisplayNameChanges() throws {
        let first = SerialDevice(name: "Tester", path: "/dev/cu.usbmodemA",
                                 usbVendorID: 0x2e8a, usbProductID: 0x0005,
                                 usbSerialNumber: " AbC123 \n", usbLocationID: 0x01010000,
                                 usbManufacturer: " Manufacturer ", usbProductName: " Product ")
        let reconnected = SerialDevice(name: "Renamed", path: "/dev/cu.usbmodemB",
                                       usbVendorID: 0x2e8a, usbProductID: 0x0005,
                                       usbSerialNumber: "AbC123", usbLocationID: 0x03020000)
        XCTAssertEqual(first.usbSerialNumber, "AbC123")
        XCTAssertEqual(first.usbManufacturer, "Manufacturer")
        XCTAssertEqual(first.usbProductName, "Product")
        XCTAssertEqual(try XCTUnwrap(first.stableIdentityKey), reconnected.stableIdentityKey)
        XCTAssertEqual(first.stableIdentityKey, "usb:2e8a:0005:QWJDMTIz")
        XCTAssertNotEqual(first.id, reconnected.id)
    }

    func testSerialNumberRequiresVendorAndProductAndCannotBeReplacedByLocation() {
        for serial in [nil, "", " \t\n"] as [String?] {
            let device = SerialDevice(name: "Tester", path: "/dev/cu.usbmodem123",
                                      usbVendorID: 0x2e8a, usbProductID: 5,
                                      usbSerialNumber: serial, usbLocationID: 0x01010000)
            XCTAssertNil(device.stableIdentityKey)
        }
        XCTAssertNil(SerialDevice(name: "", path: "", usbProductID: 5,
                                  usbSerialNumber: "123").stableIdentityKey)
        XCTAssertNil(SerialDevice(name: "", path: "", usbVendorID: 0x2e8a,
                                  usbSerialNumber: "123").stableIdentityKey)
    }

    func testFingerprintScopesSerialAndPreservesMeaningfulCharacters() throws {
        func key(_ vendor: Int = 1, _ product: Int = 2, _ serial: String = "Ab C:123") throws -> String {
            try XCTUnwrap(SerialDevice(name: "", path: "", usbVendorID: vendor,
                                       usbProductID: product, usbSerialNumber: serial).stableIdentityKey)
        }
        let base = try key()
        XCTAssertNotEqual(base, try key(3))
        XCTAssertNotEqual(base, try key(1, 3))
        XCTAssertNotEqual(base, try key(1, 2, "ab c:123"))
        XCTAssertNotEqual(base, try key(1, 2, "AbC:123"))
        XCTAssertNotEqual(base, try key(1, 2, "Ab C:124"))
    }

    func testInvalidUSBIdentifiersCannotGenerateAnIdentity() {
        for invalid in [-1, 0x10000, Int.max] {
            let invalidVendor = SerialDevice(name: "", path: "", usbVendorID: invalid,
                                             usbProductID: 1, usbSerialNumber: "123")
            XCTAssertNil(invalidVendor.usbVendorID)
            XCTAssertNil(invalidVendor.stableIdentityKey)
            let invalidProduct = SerialDevice(name: "", path: "", usbVendorID: 1,
                                              usbProductID: invalid, usbSerialNumber: "123")
            XCTAssertNil(invalidProduct.usbProductID)
            XCTAssertNil(invalidProduct.stableIdentityKey)
        }
    }
}
