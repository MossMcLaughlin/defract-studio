# Development notes

Gate 0 establishes a macOS 15 compatible rendering path. `EditorCore/Core.swift` owns the Core Image grade, and `EditorApp/MediaIO.swift` adapts still images and AVFoundation frames to that same function. The AVFoundation handler is `AVVideoComposition.videoComposition(with:applyingCIFiltersWithHandler:completionHandler:)`, available on macOS 15; the macOS 26 only initializer is not used. Export first writes a sibling temporary file and moves it into place after success.

The current project is a feasibility checkpoint, not the finished editor. `BasicGrade` and the two visible sliders will be replaced by the complete recipe and controls in Gate 1. `EditorTests` currently compiles `MediaIO.swift` directly to test the platform adapter without launching a GUI test host; this should be revisited if the target grows. The shared core never imports AppKit.

The Xcode project has one app, one framework, and one test target. `EditorApp/App.swift` is the app entry point. Build artifacts belong outside the repository (the commands use `/private/tmp/defract-derived`). Private fixtures and generated exports are ignored by Git.
