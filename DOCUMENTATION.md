# Submariner — Technical Documentation

This document describes configuration parameters, architecture decisions, and operational
details for developers and contributors.

---

## Configuration Defaults

These values are registered in `SBAppDelegate.init()` via `UserDefaults.standard.register(defaults:)`.

### Cover Art

| Key | Default | Type | Description |
|-----|---------|------|-------------|
| `MaxCoverSize` | `300` | Integer | Maximum pixel dimension (width and height) for cover art thumbnails requested from the server via the Subsonic `getCoverArt` API. The server scales the original cover art to fit within this size. A value of `300` means covers are requested at 300×300 pixels. Set to `0` to request the full-resolution original (not recommended). |
| `coverSize` | `0.75` | Float | Controls the display size of album cover thumbnails in the UI grid. This is a scale factor, not a pixel value. |

### Playback

| Key | Default | Type | Description |
|-----|---------|------|-------------|
| `maxBitRate` | `0` | Integer | Maximum bitrate (in kbps) for streaming. `0` means no limit (server decides). Passed to the Subsonic `stream.view` API. |
| `playerVolume` | `0.5` | Float | Initial player volume (0.0 to 1.0). |
| `enableCacheStreaming` | `false` | Bool | When true, tracks are downloaded to the local cache while streaming, enabling offline playback later. Defaults to off — downloads are opt-in via explicit user action. |
| `deleteAfterPlay` | `false` | Bool | When true, cached tracks are deleted after playback completes. |
| `scrobbleToServer` | `true` | Bool | When true, playback events are scrobbled to the server. |
| `playRate` | `1.0` | Float | Playback speed multiplier. |
| `SkipIncrement` | `5.0` | Float | Number of seconds to skip forward/backward with rewind/fast-forward. |

### UI

| Key | Default | Type | Description |
|-----|---------|------|-------------|
| `albumSortOrder` | `"OldestFirst"` | String | Sort order for album lists. Options: `"OldestFirst"`, or any other value for alphabetical. |
| `playerBehavior` | `1` | Integer | Controls player behavior mode. |

### Server

| Key | Default | Type | Description |
|-----|---------|------|-------------|
| `clientIdentifier` | `"submariner"` | String | Client identifier sent with all Subsonic API requests. |
| `apiVersion` | `"1.16.1"` | String | Subsonic API version used in requests. |

---

## Operation Queues

Submariner uses three operation queues for background work:

| Queue | Max Concurrent | Purpose |
|-------|---------------|---------|
| `sharedServerQueue` | 3 (concurrent) | General Subsonic API requests (artist/album/track metadata, playlists, etc.) and XML parsing operations. Thread safety is handled via native locks. |
| `sharedCoverQueue` | 8 (concurrent) | Cover art (`getCoverArt`) HTTP downloads only. Concurrent because each download is independent. The XML parsing that follows still goes through `sharedServerQueue`. |
| `sharedDownloadQueue` | 1 (serial) | Track downloads and imports. Serial to avoid saturating the user's bandwidth. |

### Why Cover Art Uses a Separate Queue

Cover art fetches are pure HTTP downloads with no dependency on other requests. By running them on a dedicated concurrent queue, multiple covers load simultaneously instead of waiting behind metadata requests. The concurrency limit of 8 prevents overwhelming the server. Servers that rate-limit (HTTP 429) will have their requests automatically retried after the `Retry-After` delay.

---

## Known Limitations

- **Cover art resolution:** Covers are requested at the `MaxCoverSize` (300px) resolution. For Retina displays, this means covers may appear slightly soft when displayed at sizes larger than 150×150 logical points. A future enhancement could request at 2× the display size.
- **Objective-C Base Controller Migration:** Attempting to migrate the base `SBViewController` to Swift is blocked because Apple's runtime rules prohibit Objective-C classes (like `SBDatabaseController.m`) from subclassing Swift classes. Subclasses must be migrated bottom-up before `SBViewController` can be converted. A backup of the translated class is saved in `SBViewController.swift.bak`.

---

## Technical Debt & Optimizations

- **`unplayAllTracks()` Optimization:** Originally, clearing the `isPlaying` flag across the library involved fetching all tracks with `isPlaying == YES` via a Core Data query. To optimize playback startup time, this was replaced with a direct flag change on `self.currentTrack?.isPlaying = false` in `SBPlayer.swift`. While significantly faster, if any track erroneously gets stuck with `isPlaying == YES` (e.g., due to an unexpected crash or state desync), it will not be corrected automatically during normal playback initiation.
- **AVPlayer Playback Latency (`SBResourceLoaderDelegate`):** Native `AVPlayer` streaming from Subsonic servers often incurs a 2-3 second startup latency. This is because macOS's `mediaexperienced` daemon forcefully probes streams for `Content-Length` and byte-range support. Since Subsonic's `stream.view` often omits these headers, the probes timeout or fail (logging benign `-12864` / `nw_connection` errors in the console) before falling back to progressive downloading. To eliminate this latency and the console errors, Submariner uses a custom `SBResourceLoaderDelegate`. This class intercepts remote streaming requests by rewriting the URL scheme to `sbhttps://` and uses `URLSession` to manually stream the byte data directly into `AVPlayer`'s buffer, bypassing AVFoundation's buggy network probing entirely.
- **Local Track Safety Guard (`playRemote`):** A Core Data `localTrack` relationship may be set while the download operation is still writing the file to disk. Attempting to play a partially-written file produces `err=-12848` (Cannot Open). `playRemote(track:)` guards against this by checking the file's size via `FileManager.attributesOfItem` — if the file is zero bytes or does not yet exist, it falls back to the remote stream URL automatically.
- **Subsonic API Request Decoupling (`SubsonicClient`):** Network dispatching has been separated from Core Data models. `SBServer` functions as a database representation, and delegates API requests to its lazy-loaded `client` property (an instance of `SubsonicClient`). All database reads from inside the networking layer are wrapped in `performAndWait` block execution to prevent threading violations.
- **Hybrid DOM/Stream XML Parsing:** The 1,400-line monolithic `XMLParserDelegate` has been modularized. Smaller endpoints are parsed via standard XML DOM parsing (`XMLDocument`), while endpoints that scale with the user's library size (`getArtists`, `getIndexes`, `getDirectory`) use streaming delegate parsers (`XMLParserDelegate`). This guarantees high memory efficiency for large libraries without necessitating server-side pagination.
- **Deprecated `synchronized` Locks Replacement:** Replaced all runtime Objective-C `@synchronized` blocks with modern, performance-oriented locks: `NSRecursiveLock` (for `SBPlayer` play state), static `NSLock` (for Keychain password and base parameters caches in `SBServer`), and `performAndWait` context scheduling (for `NSManagedObjectContext` thread safety).
