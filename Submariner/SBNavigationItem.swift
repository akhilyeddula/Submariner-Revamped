//
//  SBNavigationItem.swift
//  Submariner
//
//  Created by Calvin Buckley on 2022-11-02.
//  Copyright © 2022 Calvin Buckley. All rights reserved.
//

import Cocoa

@objc class SBServerPodcastsNavigationItem: SBServerNavigationItem {
    override var identifier: String { "ServerPodcasts" }
}

@objc class SBServerDirectoriesNavigationItem: SBServerNavigationItem {
    override var identifier: String { "ServerDirectories" }
}

@objc class SBServerHomeNavigationItem: SBServerNavigationItem {
    override var identifier: String { "ServerHome" }
}

@objc class SBServerLibraryNavigationItem: SBServerNavigationItem {
    override var identifier: String { "ServerLibrary" }
    
    @objc var selectedMusicItem: SBMusicItem?
}

@objc class ArtistsNavigationItem: SBServerLibraryNavigationItem {}

@objc class SBServerSearchNavigationItem: SBServerNavigationItem {
    override var identifier: String { "ServerSearch" }
    
    var query: SBSearchResult.QueryType
    
    // HACK: Workaround for ObjC not having sum types (remove when we can just expose query to DatabaseController)
    @objc var searchQuery: String? {
        if case let .search(query) = self.query {
            return query
        }
        return nil
    }
    
    @objc var topTracksForArtist: String? {
        if case let .topTracksFor(artistName) = self.query {
            return artistName
        }
        return nil
    }
    
    @objc var similarToArtistID: String? {
        if case let .similarTo(artistID, _) = self.query {
            return artistID
        }
        return nil
    }

    @objc var similarToArtistName: String? {
        if case let .similarTo(_, artistName) = self.query {
            return artistName
        }
        return nil
    }
    
    @objc var starred: Bool {
        if case .starred = self.query {
            return true
        }
        return false
    }
    
    init(server: SBServer, queryType: SBSearchResult.QueryType) {
        self.query = queryType
        super.init(server: server)
    }
    
    @objc init(server: SBServer, query: String) {
        self.query = .search(query: query)
        super.init(server: server)
    }
    
    @objc init(server: SBServer, topTracksFor artistName: String) {
        self.query = .topTracksFor(artistName: artistName)
        super.init(server: server)
    }
    
    @objc init(server: SBServer, similarTo artist: SBArtist) {
        self.query = .similarTo(artistID: artist.itemId ?? "", artistName: artist.itemName ?? "Unknown Artist")
        super.init(server: server)
    }
}

@objc class SBPlaylistNavigationItem: SBNavigationItem {
    override var identifier: String { "Playlist" }
    
    @objc var playlist: SBPlaylist
    
    @objc init(playlist: SBPlaylist) {
        self.playlist = playlist
    }
}

@objc class SBDownloadsNavigationItem: SBNavigationItem {
    override var identifier: String { "Downloads" }
}

@objc class HomeNavigationItem: SBNavigationItem {
    override var identifier: String { "Home" }
}

@objc class SBOnboardingNavigationItem: SBNavigationItem {
    override var identifier: String { "Onboarding" }
}

@objc class SBServerNavigationItem: SBNavigationItem {
    @objc var server: SBServer
    
    @objc init(server: SBServer) {
        self.server = server
    }
}

@objc class SBNavigationItem: NSObject {
    @objc var identifier: String { "" }
}
