// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShutterLover",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ShutterLover", targets: ["ShutterLover"]),
        .library(name: "MeasurementCore", targets: ["MeasurementCore"]),
        .library(name: "DeviceTransport", targets: ["DeviceTransport"])
    ],
    targets: [
        .target(name: "MeasurementCore"),
        .target(name: "DeviceTransport", exclude: ["README.md"]),
        .executableTarget(name: "ShutterLover", dependencies: ["MeasurementCore", "DeviceTransport"]),
        .testTarget(name: "MeasurementCoreTests", dependencies: ["MeasurementCore"]),
        .testTarget(name: "DeviceTransportTests", dependencies: ["DeviceTransport"]),
        .testTarget(name: "ShutterLoverTests", dependencies: ["ShutterLover"])
    ],
    swiftLanguageModes: [.v5]
)
