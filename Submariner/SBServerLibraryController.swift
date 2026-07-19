//
//  SBServerLibraryController.swift
//  Submariner
//
//  Created by Rafaël Warnault on 06/06/11.
//  Copyright (c) 2011-2014, Rafaël Warnault
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  * Redistributions of source code must retain the above copyright notice, this
//  list of conditions and the following disclaimer.
//
//  * Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation
//  and/or other materials provided with the distribution.
//
//  * Neither the name of the Read-Write.fr nor the names of its
//  contributors may be used to endorse or promote products derived from
//  this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
//  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
//  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
//  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

import Cocoa
import CoreData

@objc(SBServerLibraryController)
class SBServerLibraryController: SBServerViewController, NSTableViewDelegate, NSTableViewDataSource, NSSplitViewDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate {
    
    @IBOutlet var artistsTableView: NSTableView!
    @IBOutlet var tracksTableView: SBTableView!
    @IBOutlet weak var albumsCollectionView: SBCollectionView!
    @IBOutlet var artistsController: NSArrayController!
    @IBOutlet var albumsController: NSArrayController!
    @IBOutlet var tracksController: NSArrayController!
    @IBOutlet var artistSplitView: NSSplitView!
    @IBOutlet weak var filterView: NSSearchField!
    @IBOutlet weak var rightSplitView: NSSplitView!
    
    @objc dynamic var artistSortDescriptor: [NSSortDescriptor]?
    @objc dynamic var albumSortDescriptor: [NSSortDescriptor]?
    

    
    override class func nibName() -> String? {
        return "ServerLibrary"
    }
    
    override var title: String? {
        get {
            if let resourceName = self.server?.resourceName {
                return "Artists on \(resourceName)"
            }
            return "Artists"
        }
        set {
            super.title = newValue
        }
    }
    
    override init(managedObjectContext context: NSManagedObjectContext) {
        super.init(managedObjectContext: context)
        
        let artistDescriptor = NSSortDescriptor(key: "itemName", ascending: true, selector: #selector(NSString.artistListCompare(_:)))
        artistSortDescriptor = [artistDescriptor]
        
        let albumYearDescriptor = NSSortDescriptor(key: "year", ascending: true)
        let albumNameDescriptor = NSSortDescriptor(key: "itemName", ascending: true, selector: #selector(NSString.caseInsensitiveCompare(_:)))
        albumSortDescriptor = [albumYearDescriptor, albumNameDescriptor]
        
        let trackNumberDescriptor = NSSortDescriptor(key: "trackNumber", ascending: true)
        let discNumberDescriptor = NSSortDescriptor(key: "discNumber", ascending: true)
        trackSortDescriptor = [discNumberDescriptor, trackNumberDescriptor]
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        // set initial filter, we can perhaps persist between launches by storing in the text for filter
        self.filterArtist(filterView)
        
        self.setValue(rightSplitView, forKey: "compensatedSplitView")
        // so it doesn't resize unless the user does so
        artistSplitView.delegate = self
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        NotificationCenter.default.post(name: .SBTrackSelectionChanged, object: tracksController.selectedObjects)
    }
    
    deinit {
        UserDefaults.standard.removeObserver(self, forKeyPath: "albumSortOrder")
        NotificationCenter.default.removeObserver(self, name: .SBSubsonicCoversUpdated, object: nil)
        NotificationCenter.default.removeObserver(self, name: .SBSubsonicTracksUpdated, object: nil)
        albumsController.removeObserver(self, forKeyPath: "arrangedObjects")
        albumsController.removeObserver(self, forKeyPath: "selectedObjects")
        tracksController.removeObserver(self, forKeyPath: "selectedObjects")
    }
    
    override func loadView() {
        super.loadView()
        
        albumsCollectionView.register(SBAlbumViewItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("SBAlbumViewItem"))
        
        // observe album covers
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(subsonicCoversUpdatedNotification(_:)),
                                               name: .SBSubsonicCoversUpdated,
                                               object: nil)
        
        // observe tracks
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(subsonicTracksUpdatedNotification(_:)),
                                               name: .SBSubsonicTracksUpdated,
                                               object: nil)
        
        // Observe album for saving. Artist isn't observed for saving because it triggers after for some reason.
        albumsController.addObserver(self,
                                     forKeyPath: "arrangedObjects",
                                     options: .new,
                                     context: nil)
        
        albumsController.addObserver(self,
                                     forKeyPath: "selectedObjects",
                                     options: .new,
                                     context: nil)
        
        tracksController.addObserver(self,
                                     forKeyPath: "selectedObjects",
                                     options: .new,
                                     context: nil)
        
        UserDefaults.standard.addObserver(self,
                                          forKeyPath: "albumSortOrder",
                                          options: [.new, .initial],
                                          context: nil)
    }
    
    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        
        if let controller = object as? NSArrayController, controller == albumsController, keyPath == "selectedObjects" {
            if let album = albumsController.selectedObjects.first as? SBAlbum {
                let urlString = album.objectID.uriRepresentation().absoluteString
                UserDefaults.standard.set(urlString, forKey: "LastViewedResource")
            }
        } else if let controller = object as? NSArrayController, controller == tracksController, keyPath == "selectedObjects" {
            if self.view.window != nil {
                NotificationCenter.default.post(name: .SBTrackSelectionChanged, object: tracksController.selectedObjects)
            }
        } else if let controller = object as? NSArrayController, controller == albumsController, keyPath == "arrangedObjects" {
            albumsCollectionView.reloadData()
            albumsCollectionView.selectionIndexes = albumsController.selectionIndexes
        } else if let defaults = object as? UserDefaults, defaults == UserDefaults.standard, keyPath == "albumSortOrder" {
            albumSortDescriptor = self.sortDescriptorsForPreference()
            albumsController.sortDescriptors = albumSortDescriptor ?? []
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    /// Gets the selected track, album, or artist, in that order. Used mostly for saving state.
    @objc func selectedItem() -> SBMusicItem? {
        guard self.isViewLoaded else { return nil }
        let selectedTracks = tracksTableView.selectedRow
        if selectedTracks != -1 {
            return (tracksController.arrangedObjects as? [SBMusicItem])?[selectedTracks]
        }
        let selectedAlbums = albumsController.selectionIndexes
        if !selectedAlbums.isEmpty {
            if let firstIndex = selectedAlbums.first {
                return (albumsController.arrangedObjects as? [SBMusicItem])?[firstIndex]
            }
        }
        let selectedArtists = artistsTableView.selectedRow
        if selectedArtists != -1 {
            return (artistsController.arrangedObjects as? [SBMusicItem])?[selectedArtists]
        }
        return nil
    }
    
    // MARK: - Properties
    
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
    
    override var selectedMusicItems: [any SBStarrable]! {
        if let window = self.databaseController?.window {
            let responder = window.firstResponder
            if responder == tracksTableView {
                return tracksController.selectedObjects as? [SBTrack] ?? []
            } else if responder == albumsCollectionView {
                return albumsController.selectedObjects as? [SBAlbum] ?? []
            } else if responder == artistsTableView {
                return artistsController.selectedObjects as? [SBArtist] ?? []
            }
        }
        return []
    }
    
    // MARK: - Notifications
    
    @objc private func subsonicCoversUpdatedNotification(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let albumID = notification.object as? NSManagedObjectID,
                  let albums = self.albumsController.arrangedObjects as? [SBAlbum],
                  let index = albums.firstIndex(where: { $0.objectID == albumID }) else { return }
            self.albumsCollectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
        }
    }
    
    @objc private func subsonicTracksUpdatedNotification(_ notification: Notification) {
        DispatchQueue.main.async {
            self.tracksTableView.reloadData()
        }
    }
    
    // MARK: - IBActions
    
    @IBAction func filterArtist(_ sender: Any?) {
        var searchString: String? = nil
        if let control = sender as? NSControl {
            searchString = control.stringValue
        }
        
        let predicate: NSPredicate
        if let searchString = searchString, !searchString.isEmpty {
            predicate = NSPredicate(format: "(itemName CONTAINS[cd] %@ && itemId != nil)", searchString)
        } else {
            predicate = NSPredicate(format: "(itemId != nil || entity.name == 'Group')")
        }
        artistsController.filterPredicate = predicate
    }
    
    @IBAction func getTopTracksForSelectedArtist(_ sender: Any?) {
        if let artist = selectedArtists.first {
            if let name = artist.itemName {
                databaseController?.getTopTracks(for: name)
            }
        }
    }
    
    @IBAction func getSimilarTracksForSelectedArtist(_ sender: Any?) {
        if let artist = selectedArtists.first {
            databaseController?.getSimilarTracks(for: artist)
        }
    }
    
    @objc func showTrackInLibrary(_ track: SBTrack) {
        if let artist = track.album?.artist {
            artistsController.setSelectedObjects([artist])
        }
        artistsTableView.scrollRowToVisible(artistsTableView.selectedRow)
        if let album = track.album {
            albumsController.setSelectedObjects([album])
        }
        albumsCollectionView.selectItems(in: albumsController.selectionIndexes, scrollPosition: .centeredVertically)
        tracksController.setSelectedObjects([track])
        tracksTableView.scrollRowToVisible(tracksTableView.selectedRow)
    }
    
    @objc func showAlbumInLibrary(_ album: SBAlbum) {
        if let artist = album.artist {
            artistsController.setSelectedObjects([artist])
        }
        albumsCollectionView.selectItems(in: albumsController.selectionIndexes, scrollPosition: .centeredVertically)
        albumsController.setSelectedObjects([album])
        artistsTableView.scrollRowToVisible(artistsTableView.selectedRow)
    }
    
    @objc func showArtistInLibrary(_ artist: SBArtist) {
        artistsController.setSelectedObjects([artist])
        artistsTableView.scrollRowToVisible(artistsTableView.selectedRow)
    }
    
    // MARK: - NSTableViewDelegate & DataSource
    
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        var ret = false
        if tableView == artistsTableView {
            if row > -1 {
                if let arranged = artistsController.arrangedObjects as? [AnyObject], row < arranged.count {
                    let group = arranged[row]
                    if group is SBGroup {
                        ret = true
                    }
                }
            }
        }
        return ret
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        var ret = true
        if tableView == artistsTableView {
            if row > -1 {
                if let arranged = artistsController.arrangedObjects as? [AnyObject], row < arranged.count {
                    let group = arranged[row]
                    if group is SBGroup {
                        ret = false
                    }
                }
            }
        }
        return ret
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView == artistsTableView {
            if row != -1 {
                if let arranged = artistsController.arrangedObjects as? [AnyObject], row < arranged.count {
                    let index = arranged[row]
                    if index is SBArtist {
                        return 22.0
                    } else if index is SBGroup {
                        return 20.0
                    }
                }
            }
        }
        return 17.0
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        if let tableView = notification.object as? NSTableView, tableView == artistsTableView {
            let selectedRow = tableView.selectedRow
            if selectedRow != -1 {
                if let arranged = artistsController.arrangedObjects as? [AnyObject], selectedRow < arranged.count {
                    if let selectedArtist = arranged[selectedRow] as? SBArtist {
                        server?.get(artist: selectedArtist)
                        albumsCollectionView.deselectAll(self)
                    }
                }
            }
        }
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
    
    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        if tableView == tracksTableView {
            if let identifier = tableColumn?.identifier.rawValue, identifier == "rating" {
                let selectedRow = tracksTableView.selectedRow
                if selectedRow != -1 {
                    if let arranged = tracksController.arrangedObjects as? [SBTrack], selectedRow < arranged.count {
                        let clickedTrack = arranged[selectedRow]
                        if let trackID = clickedTrack.itemId, let ratingVal = object as? NSNumber {
                            let rating = ratingVal.intValue
                            server?.setRating(Int(rating), id: trackID)
                        }
                    }
                }
            }
        }
    }
    
    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        if tableView == tracksTableView && tableColumn == tableView.tableColumns.first {
            let asc = tracksController.sortDescriptors.first?.ascending ?? true
            let trackNumberDescriptor = NSSortDescriptor(key: "trackNumber", ascending: !asc)
            let discNumberDescriptor = NSSortDescriptor(key: "discNumber", ascending: !asc)
            tracksController.sortDescriptors = [discNumberDescriptor, trackNumberDescriptor]
        }
    }
    
    // MARK: - NSCollectionViewDataSource & Delegate
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        if let arranged = albumsController.arrangedObjects as? [AnyObject] {
            return arranged.count
        }
        return 0
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let arranged = albumsController.arrangedObjects as? [SBAlbum] ?? []
        let album = arranged[indexPath.item]
        let item = albumsCollectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("SBAlbumViewItem"), for: indexPath) as! SBAlbumViewItem
        item.representedObject = album
        return item
    }
    
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        albumsController.setSelectionIndexes(IndexSet())
    }
    
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let index = indexPaths.first?.item else {
            return
        }
        albumsController.setSelectionIndex(index)
        
        let selectedRow = albumsController.selectionIndexes.first ?? -1
        if selectedRow != -1, let arranged = albumsController.arrangedObjects as? [SBAlbum], selectedRow < arranged.count {
            tracksController.content = nil
            let album = arranged[selectedRow]
            server?.get(album: album)
            
            if let tracks = album.tracks, tracks.count > 0 {
                tracksController.content = tracks
            } else {
                tracksController.content = nil
            }
        } else {
            tracksController.content = nil
        }
    }
    
    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        return true
    }
    
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard let arranged = albumsController.arrangedObjects as? [SBAlbum], indexPath.item < arranged.count else {
            return nil
        }
        let album = arranged[indexPath.item]
        if let tracksSet = album.tracks {
            let sortDescriptors = tracksController.sortDescriptors
            let tracks = tracksSet.sortedArray(using: sortDescriptors) as? [SBTrack] ?? []
            return SBLibraryPasteboardWriter(items: tracks)
        }
        return nil
    }
    
    // MARK: - NSSplitViewDelegate
    
    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        if splitView == artistSplitView {
            return view != splitView.subviews.first
        }
        return true
    }
    
    // MARK: - UI Validator
    
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let action = item.action
        if action == #selector(showSelectedInLibrary(_:)) {
            return false
        }
        return super.validateUserInterfaceItem(item)
    }
}
