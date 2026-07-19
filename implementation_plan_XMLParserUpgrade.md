# Parse OpenSubsonic Extensions (API v1.16+)

Subsonic API v1.16+ (and the OpenSubsonic extensions, heavily used by Navidrome and others) introduces new XML elements such as `genres`, `albumArtists`, and `contributors` to support multi-valued tags and richer metadata.

Currently, `SBSubsonicParsingOperation` skips these tags because they are not defined in the XML parser delegate. Additionally, because the parser does not track the "current track" being parsed, it's difficult to associate these child elements with the correct Core Data object.

## User Review Required

> [!IMPORTANT]
> **Core Data Schema Decisions**
> 
> Submariner currently only stores a single `genre` (String) per `SBTrack` and does not have a dedicated `albumArtist` field on tracks or albums (it relies on the `SBAlbum` -> `SBArtist` relationship).
>
> If we want to fully support multiple genres and multiple album artists in the UI and database, we will need to create a **Core Data Schema Migration (v10 -> v11)**. This migration would involve:
> 1. Adding a `genres` attribute (Transformable `NSArray`) or relationship to tracks.
> 2. Adding an `albumArtists` relationship to tracks/albums.
> 
> **Alternative (Low-Impact):** If the goal is simply to gracefully parse the data without crashing or logging errors—and perhaps map the *first* encountered genre/albumArtist to the existing single-value fields—we can do this *without* a database migration.
> 
> **Which approach do you prefer?** 
> A) Create a V11 Schema Migration to fully support multi-valued genres and album artists.
> B) Parse the data gracefully into the existing V10 schema (mapping what we can to single-value fields and ignoring the rest).

## Proposed Changes

### Component: SBSubsonicParsingOperation
- **State Tracking**: Add a `currentTrack: SBTrack?` property to the parser state.
- **Context Awareness**: Update `parseElementSong`, `parseElementEntry`, and `parseElementChild` to assign the newly created/fetched `SBTrack` to `currentTrack`.
- **New Element Parsers**:
  - `parseElementGenres(attributeDict:)`: If `currentTrack` exists, extract the genre name and map it.
  - `parseElementAlbumArtists(attributeDict:)`: Extract the album artist data. 
  - `parseElementContributors(attributeDict:)`: Extract contributors.
- **Cleanup**: In `didEndElement`, clear `currentTrack` if the element closing is `song`, `entry`, or `child`.

### Component: Core Data Model (Submariner.xcdatamodeld)
*(Subject to your decision above)*
- If **Option A**: Create `Submariner v11.xcdatamodel`, add `NSArray` transformable attributes for `genres` and `albumArtists` (or appropriate relationships), and create a Mapping Model.
- If **Option B**: No changes to `.xcdatamodeld`.

## Verification Plan

### Automated Tests
- N/A (Project does not have automated tests).

### Manual Verification
- Run the app against a Subsonic/Navidrome server that emits these tags.
- Verify that `SBSubsonicParsingOperation` no longer logs "Unknown XML element" errors for `genres` and `albumArtists`.
- Verify that track playback and playlist loading still function normally without regressions.
