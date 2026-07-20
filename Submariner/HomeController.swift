//
//  HomeController.swift
//  Submariner
//

import AppKit
import CoreData
import SwiftUI

@MainActor
final class HomeController: SBViewController {
    private lazy var model = HomeViewModel()
    private var requestedServerRefresh = false
    private var refreshObservers: [NSObjectProtocol] = []

    override var title: String? {
        get { "Home" }
        set { super.title = newValue }
    }

    override func loadView() {
        model.loadCachedSnapshot()
        let homeView = HomeView(model: model) { [weak self] uriString in
            guard let self,
                  let uri = URL(string: uriString),
                  let objectID = managedObjectContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri),
                  let object = try? managedObjectContext.existingObject(with: objectID) else { return }
            databaseController?.switchToResource(object)
        }
        view = NSHostingView(rootView: homeView)
        let center = NotificationCenter.default
        for name in [
            Notification.Name.SBSubsonicAlbumsUpdated,
            Notification.Name.SBSubsonicPlaylistsUpdated,
            Notification.Name.SBSubsonicCoversUpdated,
        ] {
            refreshObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.reloadContent() }
            })
        }
    }

    deinit {
        refreshObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // Let the cached snapshot draw first, then reconcile it with Core Data.
        DispatchQueue.main.async { [weak self] in
            self?.reloadContent()
        }
        refreshServerContentIfNeeded()
    }

    private func refreshServerContentIfNeeded() {
        guard !requestedServerRefresh,
              let server = try? managedObjectContext.fetch(SBServer.fetchRequest()).first else { return }
        requestedServerRefresh = true
        server.getAlbumListFor(type: .recent)
        server.getAlbumListFor(type: .newest)
        server.getServerPlaylists()
    }

    private func reloadContent() {
        let albumRequest = NSFetchRequest<SBAlbum>(entityName: "Album")
        let albums = (try? managedObjectContext.fetch(albumRequest)) ?? []

        let playedAlbums = albums.filter { $0.played != nil }
        let sortedPlayedAlbums = playedAlbums.sorted {
            ($0.played ?? .distantPast) > ($1.played ?? .distantPast)
        }
        model.recentlyPlayedAlbums = sortedPlayedAlbums.prefix(20).map(AlbumSummary.init)

        // The Subsonic schema does not retain an album creation date. Permanent
        // object IDs reflect the order albums entered the local catalog, which is
        // the closest stable definition of "recently added" available locally.
        model.recentlyAddedAlbums = albums
            .sorted { $0.insertionOrder > $1.insertionOrder }
            .prefix(20)
            .map(AlbumSummary.init)

        let playlistRequest = NSFetchRequest<SBPlaylist>(entityName: "Playlist")
        model.recentlyPlayedPlaylists = ((try? managedObjectContext.fetch(playlistRequest)) ?? [])
            .filter { $0.server != nil }
            .sorted { $0.mostRecentTrackPlay > $1.mostRecentTrackPlay }
            .prefix(40)
            .map(PlaylistSummary.init)
        model.saveSnapshot()
    }
}

private extension SBAlbum {
    var insertionOrder: Int64 {
        let component = objectID.uriRepresentation().lastPathComponent
        return Int64(component.drop(while: { !$0.isNumber })) ?? 0
    }
}

private extension SBPlaylist {
    var mostRecentTrackPlay: Date {
        tracks?.compactMap(\.played).max() ?? .distantPast
    }
}

@MainActor
private final class HomeViewModel: ObservableObject {
    private static let cacheKey = "HomeSnapshotV1"

    @Published var recentlyPlayedAlbums: [AlbumSummary] = []
    @Published var recentlyPlayedPlaylists: [PlaylistSummary] = []
    @Published var recentlyAddedAlbums: [AlbumSummary] = []

    func loadCachedSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let snapshot = try? JSONDecoder().decode(HomeSnapshot.self, from: data) else { return }
        recentlyPlayedAlbums = snapshot.recentlyPlayedAlbums
        recentlyPlayedPlaylists = snapshot.recentlyPlayedPlaylists
        recentlyAddedAlbums = snapshot.recentlyAddedAlbums
    }

    func saveSnapshot() {
        let snapshot = HomeSnapshot(
            recentlyPlayedAlbums: recentlyPlayedAlbums,
            recentlyPlayedPlaylists: recentlyPlayedPlaylists,
            recentlyAddedAlbums: recentlyAddedAlbums
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }
}

private struct HomeSnapshot: Codable {
    let recentlyPlayedAlbums: [AlbumSummary]
    let recentlyPlayedPlaylists: [PlaylistSummary]
    let recentlyAddedAlbums: [AlbumSummary]
}

private struct AlbumSummary: Identifiable, Codable {
    let id: String
    let name: String
    let artistName: String
    let coverPath: String?

    var image: NSImage {
        if let coverPath, let image = NSImage(contentsOfFile: coverPath) {
            return image
        }
        return SBAlbum.nullCover ?? NSImage()
    }

    init(_ album: SBAlbum) {
        id = album.objectID.uriRepresentation().absoluteString
        name = album.itemName ?? "Untitled Album"
        artistName = album.artist?.itemName ?? "Unknown Artist"
        coverPath = album.cover?.imagePath as String?
    }
}

private struct PlaylistSummary: Identifiable, Codable {
    let id: String
    let name: String
    let trackCount: Int

    init(_ playlist: SBPlaylist) {
        id = playlist.objectID.uriRepresentation().absoluteString
        name = playlist.resourceName ?? "Untitled Playlist"
        trackCount = playlist.trackURIs?.count ?? 0
    }
}

private struct HomeView: View {
    @ObservedObject var model: HomeViewModel
    let openResource: (String) -> Void

    private let albumColumns = [GridItem(.fixed(156), spacing: 18)]
    private let playlistRows = Array(repeating: GridItem(.fixed(44), spacing: 8), count: 4)

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 28) {
                albumSection(title: "Recently Played Albums", albums: model.recentlyPlayedAlbums)
                playlistSection
                albumSection(title: "Recently Added Albums", albums: model.recentlyAddedAlbums)
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func albumSection(title: String, albums: [AlbumSummary]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.weight(.semibold))
            ScrollView(.horizontal) {
                LazyHGrid(rows: albumColumns, spacing: 18) {
                    ForEach(albums) { album in
                        Button { openResource(album.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Image(nsImage: album.image)
                                    .resizable()
                                    .interpolation(.medium)
                                    .scaledToFill()
                                    .frame(width: 148, height: 148)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(radius: 2, y: 1)
                                Text(album.name).font(.headline).lineLimit(1)
                                Text(album.artistName).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(width: 148, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(album.name) by \(album.artistName)")
                    }
                }
            }
            .scrollIndicators(.visible)
        }
    }

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently Played Playlists").font(.title2.weight(.semibold))
            ScrollView(.horizontal) {
                LazyHGrid(rows: playlistRows, spacing: 12) {
                    ForEach(model.recentlyPlayedPlaylists) { playlist in
                        Button { openResource(playlist.id) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "music.note.list")
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name).lineLimit(1)
                                    Text("\(playlist.trackCount) tracks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .frame(width: 220, height: 44)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 200, alignment: .top)
            }
            .scrollIndicators(.visible)
        }
    }
}
