# Changelog

All notable changes to the revamped Submariner client will be documented in this file.

## [v0.2.0] - 2026-07-17

### Changed
- **Decoupled API Client:** Extracted networking methods from the `SBServer` Core Data model into a clean, testable `SubsonicClient` layer.
- **Modernized XML Parsing:** Replaced the 1,400-line monolithic `XMLParserDelegate` with a hybrid parsing system. Used modular DOM parsing for small standard endpoints and efficient streaming delegates for massive endpoints to prevent memory spikes.
- **Improved Thread Safety:** Replaced deprecated Objective-C `synchronized()` helper blocks with native locking classes (`NSRecursiveLock`, `NSLock`) and thread-safe Core Data `performAndWait` context boundaries.
- **Parallel Network Requests:** Increased concurrency on `sharedServerQueue` from 1 to 3 concurrent operations, allowing metadata to load in parallel.
- **SBViewController Migration Backup:** Created `SBViewController.swift.bak` to preserve translation work for future bottom-up subclass migrations.

## [v0.1.0] - 2026-07-17

### Added
- **Menu Icons:** Added support for menu icons on macOS 26+.
- **Ratings Overhaul:** Redesigned track ratings to show stars, which can be modified directly from the inspector.
- **Volume Display:** Added a volume percentage label to the volume control popover.
- **Query Type Selector:** Added a popover to easily switch between viewing all tracks and starred tracks.
- **Playlist Management:** Added support for dragging and re-ordering playlists.

### Fixed
- **Playback Startup Latency:** Drastically reduced playback initiation latency (from 2-3 seconds to near-instant) and eliminated benign `-12864` console network errors. This was achieved by implementing a custom `AVAssetResourceLoaderDelegate` that intercepts `AVPlayer` streaming requests and feeds the audio stream directly via `URLSession`, bypassing AVFoundation's strict and incompatible HTTP byte-range probing.
- **Auto-Download Disabled by Default:** The "Cache Streaming" setting (which silently downloaded every played track to local disk) now defaults to off. Downloads remain available as an explicit user action.
- **First-Play Failure on Cached Tracks:** Fixed a bug where clicking a track for the first time would fail with `err=-12848`. When a download was in progress, the partially-written local file was incorrectly preferred over the remote stream. The player now validates that a local file is fully written before using it, falling back to the remote stream otherwise.
- **Repeated Keychain Prompts:** Fixed an issue where accessing the secure keychain on background tasks prompted the user for their password repeatedly for every concurrent album thumbnail load. Now uses context-stable identifiers and thread-safe caching.
- **Playlist Bug:** Fixed a bug that prevented users from adding tracks to newly created empty playlists.
- **Accessibility:** Added VoiceOver accessibility annotations to various tables and labels, and fixed an issue where VoiceOver would not read the albums in the collection view.
