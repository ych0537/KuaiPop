// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KuaiPop",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KuaiPop",
            path: "Sources/KuaiPop",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("EventKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
