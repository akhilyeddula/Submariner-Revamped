# Changelog

All notable changes to the revamped Submariner client will be documented in this file.

## [v0.1.0] - 2026-07-17

### Added
- **Menu Icons:** Added support for menu icons on macOS 26+.
- **Ratings Overhaul:** Redesigned track ratings to show stars, which can be modified directly from the inspector.
- **Volume Display:** Added a volume percentage label to the volume control popover.
- **Query Type Selector:** Added a popover to easily switch between viewing all tracks and starred tracks.
- **Playlist Management:** Added support for dragging and re-ordering playlists.

### Fixed
- **Playback Startup Latency:** Drastically reduced playback initiation latency (from 2-3 seconds to near-instant) and eliminated benign `-12864` console network errors. This was achieved by implementing a custom `AVAssetResourceLoaderDelegate` that intercepts `AVPlayer` streaming requests and feeds the audio stream directly via `URLSession`, bypassing AVFoundation's strict and incompatible HTTP byte-range probing.
- **Repeated Keychain Prompts:** Fixed an issue where accessing the secure keychain on background tasks prompted the user for their password repeatedly for every concurrent album thumbnail load. Now uses context-stable identifiers and thread-safe caching.
- **Playlist Bug:** Fixed a bug that prevented users from adding tracks to newly created empty playlists.
- **Accessibility:** Added VoiceOver accessibility annotations to various tables and labels, and fixed an issue where VoiceOver would not read the albums in the collection view.
