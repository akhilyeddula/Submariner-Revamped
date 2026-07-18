//
//  SBDatabaseController+SourceList.swift
//  Submariner
//
//  Created by Rafaël Warnault on 04/06/11.
//  Copyright (c) 2011-2014, Rafaël Warnault. All rights reserved.
//

import Cocoa
import CoreData

extension SBDatabaseController {
    // MARK: - Source List Selection Helpers
    @objc func sourceListSelectedRow() -> Int {
        var selectedRow = sourceList.clickedRow
        if selectedRow == -1 {
            selectedRow = sourceList.selectedRow
        }
        return selectedRow
    }

    @objc func sourceListSelectedResource() -> SBResource? {
        let row = self.sourceListSelectedRow()
        if row != -1 {
            let item = sourceList.item(atRow: row) as? NSTreeNode
            return item?.representedObject as? SBResource
        }
        return nil
    }

    // MARK: - NSOutlineViewDataSource & Drag & Drop
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let sourcePlaylist = info.draggingPasteboard.playlist(managedObjectContext: self.managedObjectContext)
        let tracks = info.draggingPasteboard.libraryItems(managedObjectContext: self.managedObjectContext)
        guard let tracks = tracks, !tracks.isEmpty else {
            return []
        }
        
        let firstTrack = tracks[0]
        let represented = (item as? NSTreeNode)?.representedObject
        
        if let targetPlaylist = represented as? SBPlaylist {
            if targetPlaylist === sourcePlaylist {
                return []
            } else if targetPlaylist.server == nil {
                return .copy
            } else if targetPlaylist.server == firstTrack.server {
                return .copy
            }
        } else if represented is SBDownloads || represented is SBLibrary {
            if firstTrack.server != nil || (firstTrack.server != nil && firstTrack.localTrack == nil) {
                return .copy
            }
        }
        
        return []
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let sourcePlaylist = info.draggingPasteboard.playlist(managedObjectContext: self.managedObjectContext)
        let tracks = info.draggingPasteboard.libraryItems(managedObjectContext: self.managedObjectContext)
        guard let tracks = tracks, !tracks.isEmpty else {
            return false
        }
        
        let represented = (item as? NSTreeNode)?.representedObject
        
        if let playlist = represented as? SBPlaylist {
            if sourcePlaylist === playlist {
                return false
            }
            if playlist.server == nil {
                playlist.add(tracks: tracks)
            } else if let playlistID = playlist.itemId, let server = playlist.server {
                server.updatePlaylist(ID: playlistID, name: nil, comment: nil, appending: tracks, removing: nil)
            }
            return true
        } else if represented is SBDownloads || represented is SBLibrary {
            if let resource = represented as? SBResource {
                self.switchToResource(resource)
            }
            
            for track in tracks {
                if let op = SBSubsonicDownloadOperation(managedObjectContext: self.managedObjectContext, trackID: track.objectID) {
                    OperationQueue.sharedDownloadQueue.addOperation(op)
                }
            }
            return true
        }
        
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        let resource = (item as? NSTreeNode)?.representedObject as? SBResource
        if let playlist = resource as? SBPlaylist, let tracks = playlist.tracks, !tracks.isEmpty {
            return SBPlaylistPasteboardWriter(playlist: playlist)
        }
        return nil
    }

    // MARK: - NSOutlineViewDelegate
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        var view = sourceList.makeView(withIdentifier: NSUserInterfaceItemIdentifier("SBSourceListViewItem"), owner: self) as? SBSourceListViewItem
        if view == nil {
            view = SBSourceListViewItem()
            view?.identifier = NSUserInterfaceItemIdentifier("SBSourceListViewItem")
        }
        return view
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        return SBSourceListRowView()
    }

    func outlineView(_ outlineView: NSOutlineView, tintConfigurationForItem item: Any) -> NSTintConfiguration? {
        return NSTintConfiguration.default
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        let represented = (item as? NSTreeNode)?.representedObject
        return represented is SBSection
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        if ignoreNextSelection {
            ignoreNextSelection = false
            return
        }
        let selectedRow = sourceList.selectedRow
        if selectedRow != -1 {
            let item = sourceList.item(atRow: selectedRow) as? NSTreeNode
            if let resource = item?.representedObject as? SBResource {
                self.switchToResource(resource, updateSidebar: false)
            }
        }
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        let represented = (item as? NSTreeNode)?.representedObject
        if represented is SBSection {
            return false
        }
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, shouldEdit tableColumn: NSTableColumn?, item: Any) -> Bool {
        let represented = (item as? NSTreeNode)?.representedObject
        if represented is SBPlaylist || represented is SBServer {
            return true
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, persistentObjectForItem item: Any?) -> Any? {
        if let represented = (item as? NSTreeNode)?.representedObject as? NSManagedObject {
            return represented.objectID.uriRepresentation().absoluteString
        }
        return nil
    }

    // MARK: - NSMenuDelegate
    private func appendMenuItem(_ menu: NSMenu, action: Selector, title: String, symbolName: String?) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        if let name = symbolName {
            if #available(macOS 26, *) {
                item.image = NSImage(systemSymbolName: name, accessibilityDescription: title)
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        let row = sourceList.clickedRow
        if row == -1 { return }
        
        let item = sourceList.item(atRow: row) as? NSTreeNode
        let resource = item?.representedObject as? SBResource
        
        menu.removeAllItems()
        
        if let playlist = resource as? SBPlaylist {
            if let tracks = playlist.tracks, !tracks.isEmpty {
                self.appendMenuItem(menu, action: #selector(playSelected(_:)), title: "Play", symbolName: "play")
                self.appendMenuItem(menu, action: #selector(addSelectedToTracklist(_:)), title: "Add to Tracklist", symbolName: "text.append")
                menu.addItem(NSMenuItem.separator())
            }
            self.appendMenuItem(menu, action: #selector(editItem(_:)), title: "Rename", symbolName: nil)
            self.appendMenuItem(menu, action: #selector(removeItem(_:)), title: "Delete", symbolName: "trash")
        } else if resource is SBServer {
            self.appendMenuItem(menu, action: #selector(addRemotePlaylist(_:)), title: "Add Playlist to Server", symbolName: "music.note.list")
            menu.addItem(NSMenuItem.separator())
            self.appendMenuItem(menu, action: #selector(reloadServer(_:)), title: "Reload Server", symbolName: "arrow.clockwise")
            self.appendMenuItem(menu, action: #selector(scanLibrary(_:)), title: "Scan Server Library", symbolName: nil)
            menu.addItem(NSMenuItem.separator())
            self.appendMenuItem(menu, action: #selector(openHomePage(_:)), title: "Open Home Page", symbolName: "house")
            self.appendMenuItem(menu, action: #selector(editItem(_:)), title: "Configure Server", symbolName: nil)
            menu.addItem(NSMenuItem.separator())
            self.appendMenuItem(menu, action: #selector(removeItem(_:)), title: "Remove Server", symbolName: "trash")
        } else if resource is SBSection || resource == nil {
            self.appendMenuItem(menu, action: #selector(addPlaylist(_:)), title: "New Playlist", symbolName: "music.note.list")
            self.appendMenuItem(menu, action: #selector(addServer(_:)), title: "New Server", symbolName: "network")
        }
    }
}
