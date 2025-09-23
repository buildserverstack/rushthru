# ShelfTrack

ShelfTrack is an offline-first SwiftUI application for liquor-store teams who need to keep shelves stocked without a back-office server. It combines on-device OCR, a live refill engine, full-text search, and CSV backup/restore while remaining private to a single store-owned iPhone.

## Architecture Overview

- **Layers** – Each feature (Capture, Inventory, Refill, Search, CSV, Activity Log, Bulk Counts, Locations, Authentication, Settings) owns its SwiftUI views, MVVM view models, and domain services. Shared adapters wrap OS frameworks such as Vision, AVFoundation, LocalAuthentication, and document pickers.
- **Persistence** – The production target uses GRDB + SQLite with FTS5 for typo-tolerant search. A lightweight in-memory fallback keeps unit tests and Linux builds compiling.
- **State flow** – `AppEnvironment` composes feature services and exposes them through SwiftUI environment objects. Structured concurrency keeps long-running work (OCR, CSV validation, shelf analysis) off the main actor.

## Dependency Injection

`AppEnvironment` now accepts a `Dependencies` value so previews, tests, and future integrations can supply fakes without touching production wiring.

```swift
let environment = AppEnvironment(
    dependencies: .init(
        database: .shared,
        auth: StubAuthService(),
        inventory: previewInventory,
        refill: previewRefill,
        search: previewSearch,
        locations: previewLocations,
        csv: previewCSV,
        activity: previewActivity,
        capture: previewCapture,
        bulkCounts: previewBulkCounts
    )
)
```

The default factory (`Dependencies.standard()`) wires the production recognizers, services, and view models, but tests can override any subset to exercise edge cases deterministically.

## Memory Management Practices

- **Autorelease Pools** – OCR parsing, ML Kit bridging, and shelf-recognition batches wrap heavy operations in `autoreleasepool { ... }` blocks so large `UIImage` and Core ML buffers are reclaimed immediately after use.
- **Stateless Adapters** – Camera frames and gallery imports are converted to JPEG `Data`, processed, and then discarded. Nothing persists photos to disk or keeps them in memory past the recognition call.
- **Shared Encoders** – JSON coders and normalization utilities reuse single static instances to avoid repeated allocations during logging and CSV work.

## Feature Highlights

- **Capture** – Uses the Donut-small pipeline (with Vision fallback) for live camera scans and ML Kit for gallery imports. After recognition, clerks can tap the exact text that belongs in each field before saving.
- **Inventory & Search** – Tracks items per store, normalizes size/type identity, and exposes FTS-backed lookups with recent-search history and dynamic filters.
- **Refill** – Computes below-minimum items, supports manual tasks with inventory suggestions, and lets shelf scans promote DinoV3 recommendations straight into the refill list.
- **Bulk Counts** – Session-oriented counting with resumable state, plus undoable commits.
- **CSV Backup/Restore** – Streams exports, stages imports for validation, and performs atomic replace-on-success with rollback on error.
- **Activity Log** – Append-only audit trail with filters and optional compaction.

## Testing Strategy

- **Unit Tests** – Located under `rushthruTests/Unit`, covering normalization, inventory rules, refill flows, CSV validation, and bootstrapping.
- **UI & Performance Hooks** – Placeholder targets exist for UI/perf tests; enable them once a macOS runner with Xcode is available.
- **Preview Seeds** – `AppEnvironment(preview: true)` hydrates sample inventory, shelf locations, and search data for SwiftUI previews.

## App Store Submission Checklist

1. **Prepare Signing Assets** – Create the bundle identifier `app.rushthru.www`, generate an App Store provisioning profile, and add the signing certificate to your machine or CI.
2. **App Store Connect Setup** – Create the app record with localized metadata, pricing, and the privacy nutrition label. Upload screenshots from key flows (Capture, Refill, Search, Settings).
3. **Archive & Validate** – On a Mac with Xcode, archive the app in Release configuration, run `Product ▸ Validate App`, and resolve any warnings (e.g., missing icons, privacy usage strings).
4. **Run the Full Test Suite** – Execute unit/UI/performance tests plus manual smoke tests for OCR, refill strikes, CSV import/export, and lock flows. Confirm memory usage stays under target by profiling on a test device.
5. **Upload via Transporter or Xcode** – Submit the validated archive to App Store Connect and wait for processing. Address any issues flagged by automated checks (encryption export compliance, Info.plist completeness).
6. **App Review Notes** – Document that the app is offline-only, explain why camera/photo-library/Face ID access is required, and reiterate that images are never stored on disk.
7. **Release & Monitor** – Once approved, release manually or schedule. Monitor TestFlight feedback and App Store ratings; iterate via semantic versioning and keep the changelog current.

## Contributing & Next Steps

- Implement the remaining GRDB repositories so the in-memory scaffolding can be swapped for true persistence.
- Expand snapshot, UI, and performance tests on Xcode Cloud or a macOS CI runner.
- Integrate the compiled Donut-small and DinoV3 Core ML models once available and calibrate thresholds with real store photos.
- Evaluate SQLCipher if encrypted-at-rest storage becomes a requirement.

For any questions about structure or future enhancements, start with `README.md`, then explore the feature folders under `rushthru/Features/`.
