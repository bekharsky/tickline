// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TimedNotes",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Tickline", targets: ["TimedNotes"])
    ],
    targets: [
        // Timer, stamps and their bookkeeping. No UI, fully testable.
        .target(
            name: "TimedNotesCore",
            path: "Sources/TimedNotesCore"
        ),
        // The AppKit text editor with the timestamp gutter.
        .target(
            name: "TimedNotesEditor",
            dependencies: ["TimedNotesCore"],
            path: "Sources/TimedNotesEditor"
        ),
        .executableTarget(
            name: "TimedNotes",
            dependencies: ["TimedNotesCore", "TimedNotesEditor"],
            path: "Sources/TimedNotes"
        ),
        .testTarget(
            name: "TimedNotesCoreTests",
            dependencies: ["TimedNotesCore"],
            path: "Tests/TimedNotesCoreTests"
        ),
        .testTarget(
            name: "TimedNotesEditorTests",
            dependencies: ["TimedNotesEditor"],
            path: "Tests/TimedNotesEditorTests"
        )
    ]
)
