//
//  SBDatabaseController+Validations.swift
//  Submariner
//
//  Created by Rafaël Warnault on 04/06/11.
//  Copyright (c) 2011-2014, Rafaël Warnault. All rights reserved.
//

import Cocoa

extension SBDatabaseController {
    // MARK: - NSUserInterfaceValidations
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let action = item.action
        
        let isPlaying = SBPlayer.sharedInstance().isPlaying
        let tracklistHasItems = SBPlayer.sharedInstance().playlist.count > 0
        
        if action == #selector(playPause(_:)) {
            return isPlaying || tracklistHasItems
        }
        
        if action == #selector(stop(_:))
            || action == #selector(rewind(_:)) || action == #selector(fastForward(_:))
            || action == #selector(jumpToTimestamp(_:))
            || action == #selector(goToCurrentTrack(_:)) {
            return isPlaying
        }
        
        if action == #selector(cleanTracklist(_:)) {
            return tracklistHasItems
        }
        
        if action == #selector(previousTrack(_:)) || action == #selector(nextTrack(_:)) {
            return isPlaying
        }
        
        if action == #selector(showIndices(_:))
            || action == #selector(showAlbums(_:))
            || action == #selector(showDirectories(_:))
            || action == #selector(showSongs(_:))
            || action == #selector(reloadCurrentServer(_:))
            || action == #selector(openCurrentServerHomePage(_:))
            || action == #selector(addPlaylistToCurrentServer(_:))
            || action == #selector(configureCurrentServer(_:))
            || action == #selector(scanCurrentLibrary(_:)) {
            return self.server != nil
        }
        
        if action == #selector(showPodcasts(_:)) {
            return self.server != nil && self.server?.supportsPodcasts.boolValue == true
        }
        
        if action == #selector(toggleServerUsers(_:)) {
            return self.server != nil && self.server?.supportsNowPlaying.boolValue == true
        }
        
        if action == #selector(search(_:)) {
            let canBeVisible = self.window?.toolbar?.visibleItems?.contains(searchToolbarItem) == true || self.window?.toolbar?.isVisible == false
            return searchToolbarItem.isEnabled && canBeVisible
        }
        
        if action == #selector(renameItem(_:))
            || action == #selector(delete(_:))
            || action == #selector(playSelected(_:))
            || action == #selector(addSelectedToTracklist(_:)) {
            if self.window?.firstResponder !== sourceList {
                return false
            }
            let selectedRow = sourceList.selectedRow
            if selectedRow != -1 {
                let node = sourceList.item(atRow: selectedRow) as? NSTreeNode
                let resource = node?.representedObject as? SBResource
                return (resource is SBPlaylist || resource is SBServer)
            } else {
                return false
            }
        }
        
        if action == #selector(navigateBack(_:)) {
            return rightVC.selectedIndex > 0
        } else if action == #selector(navigateForward(_:)) {
            return rightVC.selectedIndex < rightVC.arrangedObjects.count - 1
        }
        
        if action == #selector(addPlaylistFromTracklist(_:)) {
            return SBPlayer.sharedInstance().playlist.count > 0
        }
        
        return true
    }
}
