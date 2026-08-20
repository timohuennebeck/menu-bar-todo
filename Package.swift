// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MenuBarToDo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MenuBarToDo",
            path: "Sources/MenuBarToDo"
        ),
        .testTarget(
            name: "MenuBarToDoTests",
            dependencies: ["MenuBarToDo"],
            path: "Tests/MenuBarToDoTests"
        )
    ]
)
