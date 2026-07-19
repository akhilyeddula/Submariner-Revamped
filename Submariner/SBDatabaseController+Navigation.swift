//
//  SBDatabaseController+Navigation.swift
//  Submariner
//
//  Created by Rafaël Warnault on 04/06/11.
//  Copyright (c) 2011-2014, Rafaël Warnault. All rights reserved.
//

import Cocoa
import CoreData

extension SBDatabaseController {
    // MARK: - Navigation Routing
    @objc(goToTrack:) func go(to track: SBTrack?) {
        guard let track = track else { return }
        if let server = track.server {
            self.switchToResource(server)
            serverLibraryController.server = server
            let navItem = SBServerLibraryNavigationItem(server: server)
            navItem.selectedMusicItem = track
            self.navigate(to: navItem)
        }
    }

    @objc(navigateForwardToNavItem:) func navigate(to navItem: SBNavigationItem) {
        self.saveNavItemState()
        rightVC.navigateForward(to: navItem)
    }

    // MARK: - Resource Switching
    @objc func switchToResource(_ resource: NSManagedObject?) {
        self.switchToResource(resource, updateSidebar: true)
    }

    @objc func switchToResource(_ resource: NSManagedObject?, updateSidebar: Bool) {
        if let server = resource as? SBServer {
            server.connect()
        } else if let playlist = resource as? SBPlaylist, let server = playlist.server {
            server.connect()
        }
        
        if let resource = resource {
            self.displayViewControllerForResource(resource)
        }
        
        if updateSidebar, let resource = resource {
            self.updateSourceListSelection(resource)
        }
    }

    @objc func displayViewControllerForResource(_ resource: NSManagedObject) {
        if resource is SBSection { return }
        
        let urlString = resource.objectID.uriRepresentation().absoluteString
        UserDefaults.standard.set(urlString, forKey: "LastViewedResource")
        
        var navItem: SBNavigationItem? = nil
        if resource is SBLibrary {
            return
        } else if resource is SBDownloads {
            navItem = SBDownloadsNavigationItem()
        } else if let playlist = resource as? SBPlaylist {
            navItem = SBPlaylistNavigationItem(playlist: playlist)
        } else if let server = resource as? SBServer {
            switch server.selectedTabIndex {
            case 0:
                navItem = SBServerLibraryNavigationItem(server: server)
            case 1:
                navItem = SBServerHomeNavigationItem(server: server)
            case 2:
                navItem = SBServerPodcastsNavigationItem(server: server)
            case 3:
                navItem = SBServerDirectoriesNavigationItem(server: server)
            case 4:
                navItem = SBServerSearchNavigationItem(server: server, query: "")
            default:
                navItem = SBServerLibraryNavigationItem(server: server)
            }
        } else if let album = resource as? SBAlbum {
            if let server = album.artist?.server {
                self.switchToResource(server)
                serverLibraryController.showAlbumInLibrary(album)
            }
        } else if let artist = resource as? SBArtist {
            if let server = artist.server {
                self.switchToResource(server)
                serverLibraryController.showArtistInLibrary(artist)
            }
        }
        
        if let navItem = navItem {
            self.navigate(to: navItem)
        }
    }

    @objc func updateSourceListSelection(_ resource: NSManagedObject) {
        var sidebarResource: NSManagedObject = resource
        if let artist = sidebarResource as? SBArtist, let server = artist.server {
            sidebarResource = server
        } else if let album = sidebarResource as? SBAlbum, let server = album.artist?.server {
            sidebarResource = server
        } else if let track = sidebarResource as? SBTrack, let server = track.server {
            sidebarResource = server
        }
        
        let newPath = resourcesController.indexPath(for: sidebarResource) as IndexPath?
        if let path = newPath, path != resourcesController.selectionIndexPath {
            ignoreNextSelection = true
            resourcesController.setSelectionIndexPath(path)
        }
    }

    @objc func getTopTracks(for artistName: String) {
        if let server = self.server {
            let navItem = SBServerSearchNavigationItem(server: server, topTracksFor: artistName)
            self.navigate(to: navItem)
        }
    }

    @objc func getSimilarTracks(for artist: SBArtist) {
        if let server = self.server {
            let navItem = SBServerSearchNavigationItem(server: server, similarTo: artist)
            self.navigate(to: navItem)
        }
    }

    // MARK: - Title Utility
    @objc func updateTitle() {
        if SBPlayer.sharedInstance().isPlaying {
            return
        }
        self.window?.title = rightVC.selectedViewController?.title ?? ""
        self.window?.subtitle = ""
    }

    // MARK: - State Management
    @objc func saveNavItemState() {
        guard rightVC.selectedIndex != -1, !rightVC.arrangedObjects.isEmpty else { return }
        
        let navItem = rightVC.arrangedObjects[rightVC.selectedIndex] as? SBNavigationItem
        if let musicNavItem = navItem as? SBServerLibraryNavigationItem {
            musicNavItem.selectedMusicItem = serverLibraryController.selectedItem()
        }
    }

    @objc func resetViewAfterTransition() {
        self.updateTitle()
        let targetRect = (rightVC.selectedViewController === serverHomeController) ? rightVC.view.safeAreaRect : rightVC.view.frame
        rightVC.selectedViewController?.view.setFrameSize(targetRect.size)
    }

    // MARK: - NSPageControllerDelegate
    func pageController(_ pageController: NSPageController, frameFor object: Any?) -> NSRect {
        if object is SBServerHomeNavigationItem {
            return rightVC.view.safeAreaRect
        }
        return rightVC.view.frame
    }

    func pageController(_ pageController: NSPageController, prepare viewController: NSViewController, with object: Any?) {
        if let navItem = object as? SBServerLibraryNavigationItem {
            serverLibraryController.server = navItem.server
        }
        viewController.viewDidAppear()
    }

    func pageController(_ pageController: NSPageController, didTransitionTo object: Any) {
        guard let navItem = object as? SBNavigationItem else { return }
        
        if let serverNavItem = navItem as? SBServerNavigationItem {
            self.server = serverNavItem.server
            self.updateSourceListSelection(serverNavItem.server)
        } else if let playlistNavItem = navItem as? SBPlaylistNavigationItem {
            let playlist = playlistNavItem.playlist
            self.server = playlist.server
            self.updateSourceListSelection(playlist)
        } else {
            self.server = nil
        }
        
        if let searchNavItem = navItem as? SBServerSearchNavigationItem {
            if let q = searchNavItem.searchQuery, q.isEmpty {
                self.server?.search(query: "")
                searchField.stringValue = ""
                searchToolbarItem.endSearchInteraction()
            } else if let q = searchNavItem.searchQuery {
                self.server?.search(query: q)
                searchField.stringValue = q
            } else if let artistName = searchNavItem.topTracksForArtist {
                self.server?.getTopTracks(artistName: artistName)
                searchField.stringValue = ""
            } else if let artistID = searchNavItem.similarToArtistID,
                      let artistName = searchNavItem.similarToArtistName,
                      let server = self.server {
                let request = SBSubsonicRequestOperation(
                    server: server,
                    request: .getSimilarTracks(artistID: artistID, artistName: artistName)
                )
                OperationQueue.sharedServerQueue.addOperation(request)
                searchField.stringValue = ""
            } else if searchNavItem.starred {
                self.server?.getStarred()
                searchField.stringValue = ""
            }
        } else {
            searchField.stringValue = ""
            searchToolbarItem.endSearchInteraction()
        }
        
        if let playlistNavItem = navItem as? SBPlaylistNavigationItem {
            let playlist = playlistNavItem.playlist
            playlistController.playlist = playlist
            if let server = playlist.server {
                server.getPlaylistTracks(playlist)
            }
            self.updateSourceListSelection(playlist)
            NotificationCenter.default.post(name: NSNotification.Name("SBPlaylistSelectionChanged"), object: playlist)
        } else {
            NotificationCenter.default.post(name: NSNotification.Name("SBPlaylistSelectionChanged"), object: nil)
        }
        
        if let musicNavItem = navItem as? SBServerLibraryNavigationItem {
            if let track = musicNavItem.selectedMusicItem as? SBTrack {
                serverLibraryController.showTrackInLibrary(track)
            } else if let album = musicNavItem.selectedMusicItem as? SBAlbum {
                serverLibraryController.showAlbumInLibrary(album)
            } else if let artist = musicNavItem.selectedMusicItem as? SBArtist {
                serverLibraryController.showArtistInLibrary(artist)
            }
        }
        
        if navItem is SBServerNavigationItem {
            searchToolbarItem.isEnabled = true
            searchField.placeholderString = "Server Search"
        } else if let playlistNavItem = navItem as? SBPlaylistNavigationItem {
            searchToolbarItem.isEnabled = true
            searchField.placeholderString = (playlistNavItem.playlist.server != nil) ? "Server Search" : ""
        } else {
            searchToolbarItem.isEnabled = false
            searchField.placeholderString = ""
        }
        
        if navItem is SBDownloadsNavigationItem {
            if let downloads = try? self.managedObjectContext.fetch(entityNamed: "Downloads") as? SBDownloads {
                self.updateSourceListSelection(downloads)
            }
        }
        
        self.resetViewAfterTransition()
    }

    func pageControllerWillStartLiveTransition(_ pageController: NSPageController) {
        self.saveNavItemState()
    }

    func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
        rightVC.completeTransition()
        self.resetViewAfterTransition()
    }

    func pageController(_ pageController: NSPageController, identifierFor object: Any) -> String {
        guard let navItem = object as? SBNavigationItem else { return "" }
        return navItem.identifier
    }

    func pageController(_ pageController: NSPageController, viewControllerForIdentifier identifier: String) -> NSViewController {
        switch identifier {
        case "Onboarding":
            return onboardingController
        case "Downloads":
            return downloadsController
        case "ServerLibrary":
            return serverLibraryController
        case "ServerHome":
            return serverHomeController
        case "ServerDirectories":
            return serverDirectoryController
        case "ServerPodcasts":
            return serverPodcastController
        case "ServerSearch":
            return serverSearchController
        case "Playlist":
            return playlistController
        default:
            tempVC.view.frame = rightVC.view.frame
            return tempVC
        }
    }
}
