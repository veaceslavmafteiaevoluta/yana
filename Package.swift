// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "YANA",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "YANA",
            path: "Sources/YANA",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
