// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UsageMonitorLogic",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "UsageMonitorLogic", targets: ["UsageMonitorLogic"]),
    ],
    targets: [
        .target(
            name: "UsageMonitorLogic",
            path: "UsageMonitorExtension/Logic",
            sources: ["MonitoringLogic.swift"]
        ),
        .testTarget(
            name: "UsageMonitorLogicTests",
            dependencies: ["UsageMonitorLogic"],
            path: "UsageMonitorExtensionTests"
        ),
    ]
)
