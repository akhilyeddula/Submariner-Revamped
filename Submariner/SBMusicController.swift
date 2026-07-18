//
//  SBMusicController.swift
//  Submariner
//
//  Created by Antigravity on 2026-07-17.
//  Copyright © 2011-2026 Submariner Developers. All rights reserved.
//

import Cocoa
import CoreData

@objc(SBMusicController)
class SBMusicController: SBViewController, NSTableViewDelegate, NSTableViewDataSource, NSSplitViewDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate {
    
    @IBOutlet var mergeArtistsController: SBMergeArtistsController!
    @IBOutlet var artistsTableView: NSTableView!
    @IBOutlet weak var albumsCollectionView: SBCollectionView!
    @IBOutlet var tracksTableView: NSTableView!
    @IBOutlet var artistsController: NSArrayController!
    @IBOutlet var albumsController: NSArrayController!
    @IBOutlet var tracksController: NSArrayController!
    @IBOutlet var artistSplitView: NSSplitView!
    @IBOutlet weak var rightSplitView: NSSplitView!
    
    @objc var artistSortDescriptor: [NSSortDescriptor] = []
    @objc var albumSortDescriptor: [NSSortDescriptor] = []
    
    private var observersRegistered = false
    private static var showAlbumTries = 10
    
    override class func nibName() -> String? {
        return "Music"
    }
    
    override var title: String? {
        get {
            return "Local Library"
        }
        set {
            super.title = newValue
        }
    }
    
    @objc override init(managedObjectContext context: NSManagedObjectContext) {
        super.init(managedObjectContext: context)
        
        let artistDescriptor = NSSortDescriptor(key: "itemName", ascending: true, selector: #selector(NSString.artistListCompare(_:)))
        self.artistSortDescriptor = [artistDescriptor]
        
        let albumYearDescriptor = NSSortDescriptor(key: "year", ascending: true)
        let albumNameDescriptor = NSSortDescriptor(key: "itemName", ascending: true, selector: #selector(NSString.caseInsensitiveCompare(_:)))
        self.albumSortDescriptor = [albumYearDescriptor, albumNameDescriptor]
        
        let trackNumberDescriptor = NSSortDescriptor(key: "trackNumber", ascending: true)
        let discNumberDescriptor = NSSortDescriptor(key: "discNumber", ascending: true)
        self.trackSortDescriptor = [discNumberDescriptor, trackNumberDescriptor]
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.setValue(rightSplitView, forKey: "compensatedSplitView")
        artistSplitView.delegate = self
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        NotificationCenter.default.post(name: .SBTrackSelectionChanged, object: tracksController.selectedObjects)
    }
    
    deinit {
        if observersRegistered {
            UserDefaults.standard.removeObserver(self, forKeyPath: "albumSortOrder")
            if artistsController != nil {
                artistsController.removeObserver(self, forKeyPath: "selectedObjects")
            }
            if albumsController != nil {
                albumsController.removeObserver(self, forKeyPath: "selectedObjects")
            }
            if tracksController != nil {
                tracksController.removeObserver(self, forKeyPath: "selectedObjects")
            }
        }
    }
    
    override func loadView() {
        super.loadView()
        
        albumsCollectionView.register(SBAlbumViewItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("SBAlbumViewItem"))
        
        mergeArtistsController.parentWindow = databaseController?.window
        
        artistsController.addObserver(self, forKeyPath: "selectedObjects", options: .new, context: nil)
        albumsController.addObserver(self, forKeyPath: "selectedObjects", options: .new, context: nil)
        tracksController.addObserver(self, forKeyPath: "selectedObjects", options: .new, context: nil)
        
        UserDefaults.standard.addObserver(self, forKeyPath: "albumSortOrder", options: [.new, .initial], context: nil)
        observersRegistered = true
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let keyPath = keyPath else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        
        if let arrayController = object as? NSArrayController {
            if arrayController == albumsController && keyPath == "selectedObjects" {
                if let album = albumsController.selectedObjects.first as? SBAlbum {
                    let urlString = album.objectID.uriRepresentation().absoluteString
                    UserDefaults.standard.set(urlString, forKey: "LastViewedResource")
                }
                albumsCollectionView.selectionIndexes = albumsController.selectionIndexes
            } else if arrayController == artistsController && keyPath == "selectedObjects" {
                albumsCollectionView.reloadData()
                albumsCollectionView.selectionIndexes = albumsController.selectionIndexes
            } else if arrayController == tracksController && keyPath == "selectedObjects" && self.view.window != nil {
                NotificationCenter.default.post(name: .SBTrackSelectionChanged, object: tracksController.selectedObjects)
            } else {
                super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            }
        } else if let userDefaults = object as? UserDefaults, userDefaults == UserDefaults.standard && keyPath == "albumSortOrder" {
            let descriptors = self.sortDescriptorsForPreference()
            albumSortDescriptor = descriptors
            albumsController.sortDescriptors = descriptors
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    @objc func selectedItem() -> SBMusicItem? {
        guard self.isViewLoaded else { return nil }
        let selectedTrackRow = tracksTableView.selectedRow
        if selectedTrackRow != -1, let arranged = tracksController.arrangedObjects as? [AnyObject], selectedTrackRow < arranged.count {
            return arranged[selectedTrackRow] as? SBMusicItem
        }
        let selectedAlbums = albumsCollectionView.selectionIndexes
        if !selectedAlbums.isEmpty, let arranged = albumsController.arrangedObjects as? [AnyObject], let firstIndex = selectedAlbums.first, firstIndex < arranged.count {
            return arranged[firstIndex] as? SBMusicItem
        }
        let selectedArtistRow = artistsTableView.selectedRow
        if selectedArtistRow != -1, let arranged = artistsController.arrangedObjects as? [AnyObject], selectedArtistRow < arranged.count {
            return arranged[selectedArtistRow] as? SBMusicItem
        }
        return nil
    }
    
    // #MARK: - Properties
    
    override var tracks: [SBTrack]! {
        return tracksController.arrangedObjects as? [SBTrack] ?? []
    }
    
    override var selectedTrackRow: Int {
        return tracksTableView.selectedRow
    }
    
    override var selectedTracks: [SBTrack]! {
        return tracksController.selectedObjects as? [SBTrack] ?? []
    }
    
    override var selectedAlbums: [SBAlbum]! {
        return albumsController.selectedObjects as? [SBAlbum] ?? []
    }
    
    override var selectedArtists: [SBArtist]! {
        return artistsController.selectedObjects as? [SBArtist] ?? []
    }
    
    override var selectedMusicItems: [SBStarrable]! {
        if let responder = self.databaseController?.window?.firstResponder {
            if responder == tracksTableView {
                return tracksController.selectedObjects as? [SBStarrable] ?? []
            } else if responder == albumsCollectionView {
                return albumsController.selectedObjects as? [SBStarrable] ?? []
            } else if responder == artistsTableView {
                return artistsController.selectedObjects as? [SBStarrable] ?? []
            }
        }
        return []
    }
    
    // #MARK: - IBActions
    
    @IBAction func filterArtist(_ sender: Any) {
        let searchString: String?
        if let control = sender as? NSControl {
            searchString = control.stringValue
        } else if let string = sender as? String {
            searchString = string
        } else {
            searchString = nil
        }
        
        let predicate: NSPredicate
        if let searchString = searchString, !searchString.isEmpty {
            predicate = NSPredicate(format: "(itemName CONTAINS[cd] %@) && (server == nil)", searchString)
        } else {
            predicate = NSPredicate(format: "server == nil")
        }
        artistsController.filterPredicate = predicate
    }
    
    @IBAction func removeArtist(_ sender: Any) {
        let selectedRow = artistsTableView.selectedRow
        if selectedRow != -1, let arranged = artistsController.arrangedObjects as? [SBArtist], selectedRow < arranged.count {
            let selectedArtist = arranged[selectedRow]
            if selectedArtist.isLinked?.boolValue == false {
                let alert = NSAlert()
                let removeButton = alert.addButton(withTitle: "Remove from Database")
                removeButton.hasDestructiveAction = true
                alert.addButton(withTitle: "Cancel")
                let deleteButton = alert.addButton(withTitle: "Delete Files")
                deleteButton.hasDestructiveAction = true
                alert.messageText = "Delete the selected artist?"
                alert.informativeText = "This artist has been copied into the Submariner database. If you choose Delete, the artist will be removed from the database and deleted from the file system. If you choose Remove, the copied files will be preserved."
                alert.alertStyle = .warning
                
                if let window = self.view.window {
                    alert.beginSheetModal(for: window) { returnCode in
                        self.removeArtistAlertDidEnd(alert, returnCode: returnCode.rawValue, contextInfo: nil)
                    }
                }
            } else {
                let alert = NSAlert()
                let removeButton = alert.addButton(withTitle: "Remove")
                removeButton.hasDestructiveAction = true
                alert.addButton(withTitle: "Cancel")
                alert.messageText = "Remove the selected artist?"
                alert.informativeText = "This can't be undone."
                alert.alertStyle = .warning
                
                if let window = self.view.window {
                    alert.beginSheetModal(for: window) { returnCode in
                        self.removeArtistAlertDidEnd(alert, returnCode: returnCode.rawValue, contextInfo: nil)
                    }
                }
            }
        }
    }
    
    @IBAction func removeAlbum(_ sender: Any) {
        let indexSet = albumsCollectionView.selectionIndexes
        if let selectedRow = indexSet.first {
            if let arranged = albumsController.arrangedObjects as? [SBAlbum], selectedRow < arranged.count {
                let selectedAlbum = arranged[selectedRow]
                if selectedAlbum.isLinked?.boolValue == false {
                    let alert = NSAlert()
                    let removeButton = alert.addButton(withTitle: "Remove from Database")
                    removeButton.hasDestructiveAction = true
                    alert.addButton(withTitle: "Cancel")
                    let deleteButton = alert.addButton(withTitle: "Delete Files")
                    deleteButton.hasDestructiveAction = true
                    alert.messageText = "Delete the selected album?"
                    alert.informativeText = "This album has been copied into the Submariner database. If you choose Delete, the album will be removed from the database and deleted from the file system. If you choose Remove, the copied files will be preserved."
                    alert.alertStyle = .warning
                    
                    if let window = self.view.window {
                        alert.beginSheetModal(for: window) { returnCode in
                            self.removeAlbumAlertDidEnd(alert, returnCode: returnCode.rawValue, contextInfo: nil)
                        }
                    }
                } else {
                    let alert = NSAlert()
                    let removeButton = alert.addButton(withTitle: "Remove")
                    removeButton.hasDestructiveAction = true
                    alert.addButton(withTitle: "Cancel")
                    alert.messageText = "Remove the selected album?"
                    alert.informativeText = "This can't be undone."
                    alert.alertStyle = .warning
                    
                    if let window = self.view.window {
                        alert.beginSheetModal(for: window) { returnCode in
                            self.removeAlbumAlertDidEnd(alert, returnCode: returnCode.rawValue, contextInfo: nil)
                        }
                    }
                }
            }
        }
    }
    
    @IBAction func removeTrack(_ sender: Any) {
        let selectedRow = tracksTableView.selectedRow
        if selectedRow != -1, let arranged = tracksController.arrangedObjects as? [SBTrack], selectedRow < arranged.count {
            let selectedTrack = arranged[selectedRow]
            if selectedTrack.isLinked?.boolValue == false {
                let alert = NSAlert()
                let removeButton = alert.addButton(withTitle: "Remove from Database")
                removeButton.hasDestructiveAction = true
                alert.addButton(withTitle: "Cancel")
                let deleteButton = alert.addButton(withTitle: "Delete Files")
                deleteButton.hasDestructiveAction = true
                alert.messageText = "Delete the selected track?"
                alert.informativeText = "This track has been copied into the Submariner database. If you choose Delete, the track will be removed from the database and deleted from the file system. If you choose Remove, the copied files will be preserved."
                alert.alertStyle = .warning
                
                if let window = self.view.window {
                    alert.beginSheetModal(for: window) { returnCode in
                        self.removeTrackAlertDidEnd(alert, returnCode: returnCode.rawValue, contextInfo: nil)
                    }
                }
            } else {
                let alert = NSAlert()
                let removeButton = alert.addButton(withTitle: "Remove")
                removeButton.hasDestructiveAction = true
                alert.addButton(withTitle: "Cancel")
                alert.messageText = "Remove the selected track?"
                alert.informativeText = "Removed tracks cannot be restored."
                alert.alertStyle = .warning
                
                if let window = self.view.window {
                    alert.beginSheetModal(for: window) { returnCode in
                        self.removeTrackAlertDidEnd(alert, returnCode: returnCode.rawValue, contextInfo: nil)
                    }
                }
            }
        }
    }
    
    @IBAction func delete(_ sender: Any) {
        if let responder = self.databaseController?.window?.firstResponder {
            if responder == tracksTableView {
                self.removeTrack(self)
            } else if responder == albumsCollectionView {
                self.removeAlbum(self)
            } else if responder == artistsTableView {
                self.removeArtist(self)
            }
        }
    }
    
    @IBAction func showArtistInFinder(_ sender: Any) {
        var urls: [URL] = []
        let selectedIndexes = artistsTableView.selectedRowIndexes
        if let arranged = artistsController.arrangedObjects as? [SBArtist] {
            selectedIndexes.forEach { idx in
                if idx < arranged.count, let artistPath = arranged[idx].path {
                    let trackURL = URL(fileURLWithPath: artistPath)
                    urls.append(trackURL)
                }
            }
        }
        if !urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }
    
    @IBAction func showAlbumInFinder(_ sender: Any) {
        let indexSet = albumsCollectionView.selectionIndexes
        if let selectedRow = indexSet.first {
            if let arranged = albumsController.arrangedObjects as? [SBAlbum], selectedRow < arranged.count {
                let album = arranged[selectedRow]
                if let albumPath = album.path, !albumPath.isEmpty {
                    NSWorkspace.shared.selectFile(albumPath, inFileViewerRootedAtPath: "")
                }
            }
        }
    }
    
    @IBAction override func showSelectedInFinder(_ sender: Any?) {
        if let responder = self.databaseController?.window?.firstResponder {
            if responder == tracksTableView {
                self.showTrackInFinder(self)
            } else if responder == albumsCollectionView {
                self.showAlbumInFinder(self)
            } else if responder == artistsTableView {
                self.showArtistInFinder(self)
            }
        }
    }
    
    @IBAction func mergeArtists(_ sender: Any) {
        let indexSet = artistsTableView.selectedRowIndexes
        if !indexSet.isEmpty, let arranged = artistsController.arrangedObjects as? [SBArtist] {
            var artists: [SBArtist] = []
            indexSet.forEach { idx in
                if idx < arranged.count {
                    artists.append(arranged[idx])
                }
            }
            mergeArtistsController.artists = artists
            mergeArtistsController.openSheet(sender)
        }
    }
    
    @objc func showTrackInLibrary(_ track: SBTrack) {
        if let artist = track.album?.artist {
            artistsController.setSelectedObjects([artist])
            artistsTableView.scrollRowToVisible(artistsTableView.selectedRow)
        }
        if let album = track.album {
            albumsController.setSelectedObjects([album])
            albumsCollectionView.selectItems(in: albumsController.selectionIndexes, scrollPosition: .centeredVertically)
        }
        tracksController.setSelectedObjects([track])
        tracksTableView.scrollRowToVisible(tracksTableView.selectedRow)
    }
    
    @objc func showAlbumInLibrary(_ album: SBAlbum) {
        if let content = artistsController.content as? [AnyObject], content.count >= 1 {
            // ready
        } else if SBMusicController.showAlbumTries > 0 {
            SBMusicController.showAlbumTries -= 1
            self.perform(#selector(showAlbumInLibrary(_:)), with: album, afterDelay: 0.1)
            return
        }
        
        if let artist = album.artist {
            artistsController.setSelectedObjects([artist])
            artistsTableView.scrollRowToVisible(artistsTableView.selectedRow)
        }
        albumsController.setSelectedObjects([album])
        albumsCollectionView.selectItems(in: albumsController.selectionIndexes, scrollPosition: .centeredVertically)
    }
    
    @objc func showArtistInLibrary(_ artist: SBArtist) {
        artistsController.setSelectedObjects([artist])
        artistsTableView.scrollRowToVisible(artistsTableView.selectedRow)
    }
    
    @IBAction override func createNewLocalPlaylistWithSelectedTracks(_ sender: Any?) {
        let selectedRow = tracksTableView.selectedRow
        if selectedRow == -1 {
            return
        }
        if let arranged = tracksController.arrangedObjects as? [SBTrack] {
            self.createLocalPlaylist(withSelected: arranged, selectedIndices: tracksTableView.selectedRowIndexes, databaseController: self.databaseController)
        }
    }
    
    // #MARK: - NSAlert Sheet Support
    
    @objc func removeTrackAlertDidEnd(_ alert: NSAlert, returnCode: Int, contextInfo: UnsafeMutableRawPointer?) {
        if returnCode == NSApplication.ModalResponse.alertSecondButtonReturn.rawValue {
            return
        }
        let selectedRows = tracksTableView.selectedRowIndexes
        var tracksToDelete: [SBTrack] = []
        if let arranged = tracksController.arrangedObjects as? [SBTrack] {
            selectedRows.forEach { idx in
                if idx < arranged.count {
                    tracksToDelete.append(arranged[idx])
                }
            }
        }
        let deleteFile = returnCode == NSApplication.ModalResponse.alertThirdButtonReturn.rawValue
        for selectedTrack in tracksToDelete {
            if deleteFile, let trackPath = selectedTrack.path {
                do {
                    try FileManager.default.removeItem(atPath: trackPath)
                } catch {
                    NSApp.presentError(error)
                }
            }
            if let moc = self.managedObjectContext {
                moc.delete(selectedTrack)
            }
        }
        if let moc = self.managedObjectContext {
            moc.processPendingChanges()
            try? moc.save()
        }
        UserDefaults.standard.removeObject(forKey: "LastViewedResource")
    }
    
    @objc func removeAlbumAlertDidEnd(_ alert: NSAlert, returnCode: Int, contextInfo: UnsafeMutableRawPointer?) {
        if returnCode == NSApplication.ModalResponse.alertSecondButtonReturn.rawValue {
            return
        }
        let selectedRows = albumsCollectionView.selectionIndexes
        var albumsToDelete: [SBAlbum] = []
        if let arranged = albumsController.arrangedObjects as? [SBAlbum] {
            selectedRows.forEach { idx in
                if idx < arranged.count {
                    albumsToDelete.append(arranged[idx])
                }
            }
        }
        let deleteFile = returnCode == NSApplication.ModalResponse.alertThirdButtonReturn.rawValue
        for selectedAlbum in albumsToDelete {
            if deleteFile, let albumPath = selectedAlbum.path {
                do {
                    try FileManager.default.removeItem(atPath: albumPath)
                } catch {
                    NSApp.presentError(error)
                }
            }
            if let moc = self.managedObjectContext {
                moc.delete(selectedAlbum)
            }
        }
        if let moc = self.managedObjectContext {
            moc.processPendingChanges()
            try? moc.save()
        }
        UserDefaults.standard.removeObject(forKey: "LastViewedResource")
    }
    
    @objc func removeArtistAlertDidEnd(_ alert: NSAlert, returnCode: Int, contextInfo: UnsafeMutableRawPointer?) {
        if returnCode == NSApplication.ModalResponse.alertSecondButtonReturn.rawValue {
            return
        }
        let selectedRows = artistsTableView.selectedRowIndexes
        var artistsToDelete: [SBArtist] = []
        if let arranged = artistsController.arrangedObjects as? [SBArtist] {
            selectedRows.forEach { idx in
                if idx < arranged.count {
                    artistsToDelete.append(arranged[idx])
                }
            }
        }
        let deleteFile = returnCode == NSApplication.ModalResponse.alertThirdButtonReturn.rawValue
        for selectedArtist in artistsToDelete {
            if deleteFile, let artistPath = selectedArtist.path {
                do {
                    try FileManager.default.removeItem(atPath: artistPath)
                } catch {
                    NSApp.presentError(error)
                }
            }
            if let moc = self.managedObjectContext {
                moc.delete(selectedArtist)
            }
        }
        if let moc = self.managedObjectContext {
            moc.processPendingChanges()
            try? moc.save()
        }
        UserDefaults.standard.removeObject(forKey: "LastViewedResource")
    }
    
    // #MARK: - NSTableViewDelegate / NSTableViewDataSource
    
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if tableView == artistsTableView {
            if row > -1, let arranged = artistsController.arrangedObjects as? [AnyObject], row < arranged.count {
                let group = arranged[row]
                if group is SBGroup {
                    return true
                }
            }
        }
        return false
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if tableView == artistsTableView {
            if row > -1, let arranged = artistsController.arrangedObjects as? [AnyObject], row < arranged.count {
                let group = arranged[row]
                if group is SBGroup {
                    return false
                }
            }
        }
        return true
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView == artistsTableView {
            if row != -1, let arranged = artistsController.arrangedObjects as? [AnyObject], row < arranged.count {
                let index = arranged[row]
                if index is SBIndex && !(index is SBGroup) {
                    return 22.0
                }
                if index is SBGroup {
                    return 20.0
                }
            }
        }
        return 17.0
    }
    
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        if tableView == tracksTableView {
            if let arranged = tracksController.arrangedObjects as? [SBTrack], row < arranged.count {
                let track = arranged[row]
                return SBLibraryItemPasteboardWriter(item: track, index: row)
            }
        }
        return nil
    }
    
    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        if tableView == tracksTableView && !tableView.tableColumns.isEmpty && tableColumn == tableView.tableColumns[0] {
            let asc = tracksController.sortDescriptors.first?.ascending ?? true
            let trackNumberDescriptor = NSSortDescriptor(key: "trackNumber", ascending: !asc)
            let discNumberDescriptor = NSSortDescriptor(key: "discNumber", ascending: !asc)
            tracksController.sortDescriptors = [discNumberDescriptor, trackNumberDescriptor]
        }
    }
    
    // #MARK: - NSCollectionViewDataSource
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        if let arranged = albumsController.arrangedObjects as? [AnyObject] {
            return arranged.count
        }
        return 0
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        if let arranged = albumsController.arrangedObjects as? [SBAlbum], indexPath.item < arranged.count {
            let album = arranged[indexPath.item]
            let item = albumsCollectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("SBAlbumViewItem"), for: indexPath)
            item.representedObject = album
            return item
        }
        return NSCollectionViewItem()
    }
    
    // #MARK: - NSCollectionViewDelegate
    
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        albumsController.setSelectionIndexes(IndexSet())
    }
    
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        if let firstItem = indexPaths.first?.item {
            albumsController.setSelectionIndex(firstItem)
        }
    }
    
    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        return true
    }
    
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        if let arranged = albumsController.arrangedObjects as? [SBAlbum], indexPath.item < arranged.count {
            let album = arranged[indexPath.item]
            if let tracksArray = album.tracks?.allObjects as? [SBTrack] {
                let sortedTracks: [SBTrack]
                let sortDescriptors = tracksController.sortDescriptors
                if !sortDescriptors.isEmpty {
                    sortedTracks = (tracksArray as NSArray).sortedArray(using: sortDescriptors) as? [SBTrack] ?? tracksArray
                } else {
                    sortedTracks = tracksArray
                }
                return SBLibraryPasteboardWriter(items: sortedTracks)
            }
        }
        return nil
    }
    
    // #MARK: - NSSplitViewDelegate
    
    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        if splitView == artistSplitView {
            return view != splitView.subviews.first
        }
        return true
    }
    
    // #MARK: - UI Validator
    
    @objc override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let action = item.action
        
        let artistsSelected = artistsTableView.selectedRowIndexes.count
        let albumSelected = albumsCollectionView.selectionIndexes.count
        let tracksSelected = tracksTableView.selectedRowIndexes.count
        
        let responder = self.databaseController?.window?.firstResponder
        let artistsActive = responder == artistsTableView
        
        if action == #selector(mergeArtists(_:)) {
            return artistsSelected > 1 && artistsActive
        }
        
        if action == #selector(delete(_:)) {
            return artistsSelected > 0 || albumSelected > 0 || tracksSelected > 0
        }
        
        if action == #selector(removeArtist(_:)) {
            return artistsSelected > 0
        }
        
        if action == #selector(removeAlbum(_:)) {
            return albumSelected > 0
        }
        
        if action == #selector(removeTrack(_:)) {
            return tracksSelected > 0
        }
        
        if action == #selector(SBViewController.showSelectedInLibrary(_:)) {
            return false
        }
        
        return super.validateUserInterfaceItem(item)
    }
}
