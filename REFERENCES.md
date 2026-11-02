# REFERENCES.md — API References and Design Source Notes

External references are development pointers. **Check actual installed SDK signatures and availability at implementation time**. Where docs change, prefer current official SDK types, compilation and Apple guidance over this dated example.

## Apple platforms and processing

- [AVVideoComposition.init(applyingFiltersTo:applier:)](https://developer.apple.com/documentation/avfoundation/avvideocomposition/init%28applyingfiltersto%3Aapplier%3A%29) — newer async Core Image video composition initializer. **Availability warning:** part of the macOS/iOS 26 SDK-era additions; do not use unguarded on the macOS 15 deployment target.
- [AVVideoComposition.videoComposition(with:applyingCIFiltersWithHandler:completionHandler:)](https://developer.apple.com/documentation/avfoundation/avvideocomposition/videocomposition%28with%3Aapplyingcifilterswithhandler%3Acompletionhandler%3A%29) — macOS 15-compatible candidate when targeting pre-26; validate against installed SDK.
- [AVCIImageFilteringResult](https://developer.apple.com/documentation/avfoundation/avciimagefilteringresult) — result image and CIContext for async composition.
- [AVAssetExportSession.export(to:as:isolation:)](https://developer.apple.com/documentation/AVFoundation/AVAssetExportSession/export%28to%3Aas%3Aisolation%3A%29) — modern async video export, supported file types and cancellation/progress considerations.
- [Core Image workingColorSpace](https://developer.apple.com/documentation/coreimage/cicontextoption/workingcolorspace) — explicit working space and managed input/output conversions.
- [Foreground instance mask request](https://developer.apple.com/documentation/vision/generateforegroundinstancemaskrequest) — category-independent prominent subject segmentation; validate on underwater wildlife rather than assuming successful output.
- [Security-scoped NSURL bookmarks](https://developer.apple.com/documentation/Foundation/NSURL) — persistent user-authorized file access in macOS sandbox.
- [App-scope security bookmarks](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access?language=objc) — entitlement/security-scope considerations.

## Product/styling background

- `reference/FOUNDATION_v0.1.md`: earlier agreed product goals, initial architecture/roadmap. Background only; current package resolves more recent decisions.
- `reference/STYLE_GUIDE_v0.1.md`: adaptation of the user's Watermark visual identity to neutral macOS editor; preserve primary palette/type, use neutral editing surfaces.
- `reference/UI_REFERENCE.png`: approved general photo workspace proportion and appearance. A static mockup, not a screenshot of a functioning app or a source asset.

## Contract precedence

If docs conflict, use this order: `AGENTS.md` and user's **latest explicit requirements** > `PRODUCT_MVP.md` > `UX_SPEC.md` > `COLOR_ENGINE.md` > `ARCHITECTURE.md` > `MEDIA_AND_TESTS.md` > `IMPLEMENTATION_PLAN.md` > `reference/` background. Within a single feature, prefer a more specific contract over a generic prior phrase. Do not silently resolve consequential uncertainty by dropping functionality.
