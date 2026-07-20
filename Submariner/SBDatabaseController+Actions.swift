//
//  SBDatabaseController+Actions.swift
//  Submariner
//
//  Created by Rafaël Warnault on 04/06/11.
//  Copyright (c) 2011-2014, Rafaël Warnault. All rights reserved.
//

import Cocoa
import CoreData

extension SBDatabaseController {
    // MARK: - Demo Server Action
    @IBAction func createDemoServer(_ sender: Any?) {
        guard (try? managedObjectContext.count(for: SBServer.fetchRequest())) == 0 else { return }
            let s = SBServer.insertInManagedObjectContext(context: self.managedObjectContext)
            s.resourceName = "Subsonic Demo"
            s.url = "http://demo.subsonic.org/"
            s.username = "guest1"
            s.password = "guest"
            s.updateKeychainPassword()
            try? self.managedObjectContext.save()
            
            self.switchToResource(s)
    }

    // MARK: - Right Sidebar Toggles
    private func toggleRightSidebar(_ type: String) {
        var newVC: NSViewController? = nil
        if type == "Tracklist" {
            newVC = tracklistController
        } else if type == "ServerUsers" {
            newVC = serverUserController
        } else if type == "Inspector" {
            newVC = inspectorController
        } else {
            NSLog("Oops. Unknown right sidebar type %@", type)
            return
        }
        
        self.willChangeValue(forKey: "isServerUsersShown")
        self.willChangeValue(forKey: "isTracklistShown")
        self.willChangeValue(forKey: "isInspectorShown")
        
        let maybeAnimated: NSSplitViewItem = self.window!.isVisible ? tracklistSplit.animator() : tracklistSplit
        if tracklistContainmentBox.contentView !== newVC?.view {
            tracklistContainmentBox.contentView = newVC?.view
            maybeAnimated.isCollapsed = false
        } else {
            maybeAnimated.isCollapsed = !tracklistSplit.isCollapsed
        }
        
        UserDefaults.standard.set(tracklistSplit.isCollapsed ? "" : type, forKey: "RightSidebar")
        
        self.didChangeValue(forKey: "isInspectorShown")
        self.didChangeValue(forKey: "isServerUsersShown")
        self.didChangeValue(forKey: "isTracklistShown")
    }

    @IBAction func toggleTrackList(_ sender: Any?) {
        self.toggleRightSidebar("Tracklist")
    }

    @IBAction func toggleServerUsers(_ sender: Any?) {
        guard self.server != nil else { return }
        self.toggleRightSidebar("ServerUsers")
    }

    @IBAction func toggleInspector(_ sender: Any?) {
        self.toggleRightSidebar("Inspector")
    }

    @IBAction func toggleVolume(_ sender: Any?) {
        // volume toggle wiring
        // Cocoa handles volume toggle via volumeButton popup or menu
    }

    // MARK: - Playlist Actions
    @IBAction func addPlaylist(_ sender: Any?) {
        guard let server = try? managedObjectContext.fetch(SBServer.fetchRequest()).first else { return }
        addServerPlaylistController.server = server
        addServerPlaylistController.openSheet(sender)
    }

    @IBAction func addRemotePlaylist(_ sender: Any?) {
        addPlaylist(sender)
    }

    @IBAction func addPlaylistToCurrentServer(_ sender: Any?) {
        if let server = self.server ?? (try? managedObjectContext.fetch(SBServer.fetchRequest()).first) {
            addServerPlaylistController.server = server
            addServerPlaylistController.openSheet(sender)
        }
    }

    @IBAction func addPlaylistFromTracklist(_ sender: Any?) {
        guard let server = try? managedObjectContext.fetch(SBServer.fetchRequest()).first else { return }
        addServerPlaylistController.server = server
        addServerPlaylistController.tracks = SBPlayer.sharedInstance().playlist
        addServerPlaylistController.openSheet(sender)
    }

    @IBAction func removeItem(_ sender: Any?) {
        if let resource = self.sourceListSelectedResource() {
            if resource is SBPlaylist || resource is SBServer {
                let alert = NSAlert()
                let removeButton = alert.addButton(withTitle: "Remove")
                removeButton.hasDestructiveAction = true
                alert.addButton(withTitle: "Cancel")
                alert.messageText = "Delete \(resource.resourceName ?? "")?"
                alert.informativeText = "Deleted items cannot be restored."
                alert.alertStyle = .warning
                
                alert.beginSheetModal(for: self.window!) { [weak self] returnCode in
                    self?.removeItemAlertDidEnd(alert, returnCode: returnCode.rawValue, resource: resource)
                }
            }
        }
    }

    private func removeItemAlertDidEnd(_ alert: NSAlert, returnCode: Int, resource: SBResource) {
        if returnCode == NSApplication.ModalResponse.alertFirstButtonReturn.rawValue {
            if self.server === resource {
                self.server = nil
                if tracklistContainmentBox.contentView === serverUserController.view {
                    self.toggleTrackList(nil)
                }
                self.navigate(to: SBOnboardingNavigationItem())
            }
            if let playlist = resource as? SBPlaylist {
                if let server = playlist.server, let playlistID = playlist.itemId {
                    server.deletePlaylist(ID: playlistID)
                }
            }
            if resource is SBPlaylist || resource is SBServer {
                (resource as? SBServer)?.deleteKeychainPassword()
                self.managedObjectContext.delete(resource)
                try? self.managedObjectContext.save()
            }
        }
    }

    // MARK: - Server Actions
    @IBAction func addServer(_ sender: Any?) {
        (NSApp.delegate as? SBAppDelegate)?.preferencesController.showServerSettings(sender)
    }

    @IBAction func configureCurrentServer(_ sender: Any?) {
        (NSApp.delegate as? SBAppDelegate)?.preferencesController.showServerSettings(sender)
    }

    @IBAction func renameItem(_ sender: Any?) {
        if let resource = self.sourceListSelectedResource() {
            if resource is SBPlaylist || resource is SBServer {
                sourceList.editColumn(0, row: self.sourceListSelectedRow(), with: nil, select: true)
            }
        }
    }

    @IBAction func editItem(_ sender: Any?) {
        if let resource = self.sourceListSelectedResource() {
            if resource is SBPlaylist {
                sourceList.editColumn(0, row: self.sourceListSelectedRow(), with: nil, select: true)
            } else if let server = resource as? SBServer {
                editServerController.editMode = true
                editServerController.server = server
                editServerController.openSheet(sender)
            }
        }
    }

    @IBAction func playSelected(_ sender: Any?) {
        if let playlist = self.sourceListSelectedResource() as? SBPlaylist, let tracks = playlist.tracks {
            SBPlayer.sharedInstance().play(tracks: Array(tracks) as [SBTrack], startingAt: 0)
        }
    }

    @IBAction func addSelectedToTracklist(_ sender: Any?) {
        if let playlist = self.sourceListSelectedResource() as? SBPlaylist, let tracks = playlist.tracks {
            SBPlayer.sharedInstance().add(tracks: Array(tracks) as [SBTrack], replace: false)
        }
    }

    @objc func reloadServerInternal(_ server: SBServer?) {
        guard let server = server else { return }
        server.getOpenSubsonicExtensions()
        server.getServerLicense()
        server.getArtists()
        server.getServerDirectories()
        server.getServerPlaylists()
        
        if serverHomeController.server === server {
            serverHomeController.reloadSelected(nil)
        }
        serverUserController.refreshNowPlaying()
    }

    @IBAction func reloadServer(_ sender: Any?) {
        if let server = self.sourceListSelectedResource() as? SBServer {
            self.reloadServerInternal(server)
        }
    }

    @IBAction func reloadCurrentServer(_ sender: Any?) {
        self.reloadServerInternal(self.server)
    }

    @objc func scanLibraryInternal(_ server: SBServer?) {
        guard let server = server else { return }
        server.scanLibrary()
    }

    @IBAction func scanLibrary(_ sender: Any?) {
        if let server = self.sourceListSelectedResource() as? SBServer {
            self.scanLibraryInternal(server)
        }
    }

    @IBAction func scanCurrentLibrary(_ sender: Any?) {
        self.scanLibraryInternal(self.server)
    }

    // MARK: - Playback Control Actions
    @IBAction func playPause(_ sender: Any?) {
        let player = SBPlayer.sharedInstance()
        if player.isPlaying || player.isPaused {
            player.playPause()
        } else {
            player.playTracklistAtBeginning()
        }
    }

    @IBAction func stop(_ sender: Any?) {
        SBPlayer.sharedInstance().stop()
    }

    @IBAction func nextTrack(_ sender: Any?) {
        SBPlayer.sharedInstance().next()
    }

    @IBAction func previousTrack(_ sender: Any?) {
        SBPlayer.sharedInstance().previous()
    }

    @IBAction func seekTime(_ sender: Any?) {
        let player = SBPlayer.sharedInstance()
        if player.isPlaying, let slider = sender as? NSSlider {
            player.seek(percentage: slider.doubleValue)
        }
    }

    @IBAction func rewind(_ sender: Any?) {
        let player = SBPlayer.sharedInstance()
        if player.isPlaying {
            player.rewind()
        }
    }

    @IBAction func fastForward(_ sender: Any?) {
        let player = SBPlayer.sharedInstance()
        if player.isPlaying {
            player.fastForward()
        }
    }

    @IBAction func setVolume(_ sender: Any?) {
        if let slider = sender as? NSSlider {
            SBPlayer.sharedInstance().volume = slider.floatValue
        }
    }

    @IBAction func setMuteOn(_ sender: Any?) {
        SBPlayer.sharedInstance().volume = 0.0
    }

    @IBAction func setMuteOff(_ sender: Any?) {
        SBPlayer.sharedInstance().volume = 1.0
    }

    @IBAction func volumeUp(_ sender: Any?) {
        let player = SBPlayer.sharedInstance()
        let newVolume = min(1.0, player.volume + 0.1)
        player.volume = newVolume
    }

    @IBAction func volumeDown(_ sender: Any?) {
        let player = SBPlayer.sharedInstance()
        let newVolume = max(0.0, player.volume - 0.1)
        player.volume = newVolume
    }

    @IBAction func shuffle(_ sender: Any?) {
        let player = SBPlayer.sharedInstance()
        let isShuffle = player.isShuffle
        player.isShuffle = !isShuffle
    }

    @IBAction func repeatNone(_ sender: Any?) {
        SBPlayer.sharedInstance().repeatMode = SBPlayer.RepeatMode.no
    }

    @IBAction func repeatOne(_ sender: Any?) {
        SBPlayer.sharedInstance().repeatMode = SBPlayer.RepeatMode.one
    }

    @IBAction func repeatAll(_ sender: Any?) {
        SBPlayer.sharedInstance().repeatMode = SBPlayer.RepeatMode.all
    }

    @objc(repeat:) @IBAction func `repeat`(_ sender: Any?) {
        let player = SBPlayer.sharedInstance()
        let currentMode = player.repeatMode
        if currentMode == .no {
            player.repeatMode = .one
        } else if currentMode == .one {
            player.repeatMode = .all
        } else if currentMode == .all {
            player.repeatMode = .no
        }
    }

    // MARK: - Home Page Actions
    @IBAction func openHomePage(_ sender: Any?) {
        if let server = self.sourceListSelectedResource() as? SBServer, let urlStr = server.url, let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    @IBAction func openCurrentServerHomePage(_ sender: Any?) {
        if let server = self.server, let urlStr = server.url, let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - View Routing Actions
    @IBAction func showDownloadView(_ sender: Any?) {
        if let downloads = try? self.managedObjectContext.fetch(entityNamed: "Downloads") as? SBDownloads {
            self.switchToResource(downloads)
        }
    }

    @IBAction func showIndices(_ sender: Any?) {
        guard let server = self.server else { return }
        server.selectedTabIndex = 0
        let navItem = SBServerLibraryNavigationItem(server: server)
        self.navigate(to: navItem)
    }

    @IBAction func showAlbums(_ sender: Any?) {
        guard let server = self.server else { return }
        server.selectedTabIndex = 1
        let navItem = SBServerHomeNavigationItem(server: server)
        self.navigate(to: navItem)
    }

    @IBAction func showDirectories(_ sender: Any?) {
        guard let server = self.server else { return }
        server.selectedTabIndex = 3
        let navItem = SBServerDirectoriesNavigationItem(server: server)
        self.navigate(to: navItem)
    }

    @IBAction func showSongs(_ sender: Any?) {
        guard let server = self.server else { return }
        server.selectedTabIndex = 4
        let navItem = SBServerSearchNavigationItem(server: server, query: "")
        self.navigate(to: navItem)
    }

    @IBAction func showPodcasts(_ sender: Any?) {
        guard let server = self.server else { return }
        server.selectedTabIndex = 2
        let navItem = SBServerPodcastsNavigationItem(server: server)
        self.navigate(to: navItem)
    }

    @IBAction func search(_ sender: Any?) {
        if !self.window!.toolbar!.isVisible {
            self.window!.toggleToolbarShown(sender)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                self?.search(sender)
            }
            return
        }
        
        let visible = self.window?.toolbar?.visibleItems?.contains(searchToolbarItem) == true
        if !visible {
            return
        }
        
        var query: String? = nil
        if let searchFieldSender = sender as? NSSearchField {
            query = searchFieldSender.stringValue
        } else {
            searchToolbarItem.beginSearchInteraction()
            return
        }
        
        searchToolbarItem.endSearchInteraction()
        if let query = query, !query.isEmpty {
            var navItem: SBNavigationItem? = nil
            let topItem = rightVC.arrangedObjects[rightVC.selectedIndex] as? SBNavigationItem
            if let server = self.server {
                if let searchItem = topItem as? SBServerSearchNavigationItem, searchItem.searchQuery == query {
                    return
                }
                navItem = SBServerSearchNavigationItem(server: server, query: query)
            }
            if let item = navItem {
                self.navigate(to: item)
            }
        } else {
            if rightVC.selectedViewController is SBServerSearchController {
                rightVC.navigateBack(sender)
            }
        }
    }

    @IBAction func cleanTracklist(_ sender: Any?) {
        self.stop(sender)
        tracklistController.cleanTracklist(sender)
    }

    @IBAction func goToCurrentTrack(_ sender: Any?) {
        if let track = SBPlayer.sharedInstance().currentTrack {
            self.go(to: track)
        }
    }

    @IBAction func navigateBack(_ sender: Any?) {
        rightVC.navigateBack(sender)
    }

    @IBAction func navigateForward(_ sender: Any?) {
        rightVC.navigateForward(sender)
    }

    @IBAction func jumpToTimestamp(_ sender: Any?) {
        jumpToTimestampController.openSheet(sender)
    }

    @IBAction func showPlayRate(_ sender: Any?) {
        playRateController.openSheet(sender)
    }

    @IBAction func delete(_ sender: Any?) {
        self.removeItem(sender)
    }
}
