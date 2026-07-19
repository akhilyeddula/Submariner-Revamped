//
//  SBDatabaseController+Notifications.swift
//  Submariner
//
//  Created by Rafaël Warnault on 04/06/11.
//  Copyright (c) 2011-2014, Rafaël Warnault. All rights reserved.
//

import Cocoa
import CoreData
import os

extension SBDatabaseController {
    @objc func trackCacheUpdated(_ notification: Notification) {
        guard let trackID = notification.object as? NSManagedObjectID,
              let track = try? managedObjectContext.existingObject(with: trackID) as? SBTrack else {
            NotificationCenter.default.post(name: .SBPlayerPlaylistUpdated, object: SBPlayer.sharedInstance())
            return
        }
        track.willChangeValue(forKey: "onlineImage")
        track.didChangeValue(forKey: "onlineImage")
        let selectedTracks = (rightVC.selectedViewController as? SBViewController)?.selectedTracks
        NotificationCenter.default.post(name: .SBTrackSelectionChanged, object: selectedTracks)
    }
    // MARK: - Subsonic Notifications
    @objc func subsonicPlaylistsUpdatedNotification(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let obj = notification.object as? NSManagedObject {
                let uris = [obj.objectID.uriRepresentation().absoluteString]
                let oldIndices = self.sourceList.selectedRowIndexes
                self.sourceList.reloadData()
                self.sourceList.reloadURIs(uris)
                let newIndices = self.sourceList.selectedRowIndexes
                if newIndices.isEmpty && !oldIndices.isEmpty {
                    self.ignoreNextSelection = true
                    self.sourceList.selectRowIndexes(oldIndices, byExtendingSelection: false)
                }
            }
        }
    }

    @objc func subsonicPlaylistUpdatedNotification(_ notification: Notification) {
        guard let oid = notification.object as? NSManagedObjectID else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let playlist = try? self.managedObjectContext.existingObject(with: oid) as? SBPlaylist {
                print("subsonicPlaylistUpdatedNotification received for playlist: \(playlist.resourceName ?? "nil")")
                if self.playlistController.playlist?.objectID == playlist.objectID {
                    print("Playlist matches active playlistController. Reloading UI.")
                    // Re-assign the playlist to force Cocoa Bindings to re-evaluate `playlist.tracks`
                    self.playlistController.playlist = playlist
                    // Optionally force a fetch and reload
                    self.playlistController.tracksController.fetch(nil)
                    self.playlistController.tracksTableView.reloadData()
                } else {
                    print("Playlist does NOT match active playlistController. Active: \(self.playlistController.playlist?.resourceName ?? "nil")")
                }
            } else if let server = try? self.managedObjectContext.existingObject(with: oid) as? SBServer {
                print("subsonicPlaylistUpdatedNotification received for server: \(server.resourceName ?? "nil")")
                server.getServerPlaylists()
            }
        }
    }

    @objc func subsonicPlaylistsCreatedNotification(_ notification: Notification) {
        if let oid = notification.object as? NSManagedObjectID,
           let server = try? self.managedObjectContext.existingObject(with: oid) as? SBServer {
            server.getServerPlaylists()
        }
    }

    @objc func subsonicConnectionFailed(_ notification: Notification) {
        if let attr = notification.object as? [String: Any] {
            let code = (attr["code"] as? Int) ?? Int(attr["code"] as? String ?? "") ?? 0
            let message = attr["message"] as? String ?? ""
            
            DispatchQueue.main.async { [weak self] in
                guard self != nil else { return }
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "Subsonic Error (code \(code))"
                alert.informativeText = message
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    @objc func subsonicConnectionSucceeded(_ notification: Notification) {
        if let oid = notification.object as? NSManagedObjectID,
           let server = try? self.managedObjectContext.existingObject(with: oid) as? SBServer {
            server.getOpenSubsonicExtensions()
            server.getServerLicense()
            server.getArtists()
            server.getServerPlaylists()
        }
    }

    // MARK: - Window Notification
    @objc func windowDidChangeOcclusionState(_ notification: Notification) {
        if let sender = notification.object as? NSWindow, sender == self.window {
            let visible = self.window!.occlusionState.contains(.visible)
            let playing = SBPlayer.sharedInstance().isPlaying
            if visible && playing {
                self.updateProgress()
                self.installProgressTimer()
            } else {
                self.uninstallProgressTimer()
            }
        }
    }

    // MARK: - First Responder/Selection Notifications
    @objc func updateMenuBindings(_ notification: Notification) {
        self.willChangeValue(forKey: "selectedMusicItems")
        self.willChangeValue(forKey: "selectedMusicItemsStarred")
        self.willChangeValue(forKey: "hasSelectedMusicItems")
        self.didChangeValue(forKey: "hasSelectedMusicItems")
        self.didChangeValue(forKey: "selectedMusicItemsStarred")
        self.didChangeValue(forKey: "selectedMusicItems")
    }

    @objc func updateTitle(_ notification: Notification) {
        self.updateTitle()
    }

    // MARK: - Player Notifications
    @objc func playerPlaylistUpdatedNotification(_ notification: Notification) {
        if let currentTrack = SBPlayer.sharedInstance().currentTrack {
            let trackInfos = SBPlayer.sharedInstance().subtitle
            self.window?.title = currentTrack.itemName ?? ""
            self.window?.subtitle = trackInfos
        } else {
            self.window?.title = rightVC.selectedViewController?.title ?? ""
            self.window?.subtitle = ""
            playPauseButton.state = .on
        }
    }

    @objc func playerPlayStateNotification(_ notification: Notification) {
        if SBPlayer.sharedInstance().currentTrack != nil {
            self.installProgressTimer()
            if SBPlayer.sharedInstance().isPaused {
                playPauseButton.state = .off
            } else {
                playPauseButton.state = .on
            }
        } else {
            self.uninstallProgressTimer()
            self.clearPlaybackProgress()
            playPauseButton.state = .on
        }
    }

    @objc func playerSeekNotification(_ notification: Notification) {
        self.updateProgress()
    }

    @objc func playerHaveMovieToPlayNotification(_ notification: Notification) {
        // [self displayViewControllerForResource:[notification object]];
    }
}
