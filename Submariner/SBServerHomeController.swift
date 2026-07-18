//
//  SBServerHomeController.swift
//  Submariner
//
//  Created by Rafaël Warnault on 08/06/11.
//  Copyright (c) 2011-2014, Rafaël Warnault
//  All rights reserved.
//

import Cocoa

private let GROUP_LABEL = "Label"
private let GROUP_SEPARATOR = "HasSeparator"
private let GROUP_SELECTION_MODE = "SelectionMode"
private let GROUP_ITEMS = "Items"
private let ITEM_IDENTIFIER = "Identifier"
private let ITEM_NAME = "Name"

@objc(SBServerHomeController)
class SBServerHomeController: SBServerViewController, MGScopeBarDelegate, NSTableViewDataSource, NSTableViewDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate {
    
    @IBOutlet var scopeBar: MGScopeBar!
    @IBOutlet weak var albumsCollectionView: SBCollectionView!
    @IBOutlet var tracksTableView: NSTableView!
    @IBOutlet var tracksController: NSArrayController!
    @IBOutlet var albumsController: NSArrayController!
    
    private var scopeGroups = NSMutableArray()
    private var albumSortDescriptor: [NSSortDescriptor]?
    private var shouldInfiniteScroll = false
    
    override class func nibName() -> String? {
        return "ServerHome"
    }
    
    override var title: String? {
        get {
            if let serverName = server?.resourceName {
                return "Albums on \(serverName)"
            }
            return super.title
        }
        set {
            super.title = newValue
        }
    }
    
    override init(managedObjectContext context: NSManagedObjectContext) {
        super.init(managedObjectContext: context)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        scopeGroups = NSMutableArray()
        shouldInfiniteScroll = false
        
        let albumYearDescriptor = NSSortDescriptor(key: "year", ascending: true)
        let albumNameDescriptor = NSSortDescriptor(key: "itemName", ascending: true, selector: #selector(NSString.caseInsensitiveCompare(_:)))
        albumSortDescriptor = [albumYearDescriptor, albumNameDescriptor]
        
        let trackNumberDescriptor = NSSortDescriptor(key: "trackNumber", ascending: true)
        let discNumberDescriptor = NSSortDescriptor(key: "discNumber", ascending: true)
        trackSortDescriptor = [discNumberDescriptor, trackNumberDescriptor]
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        UserDefaults.standard.removeObserver(self, forKeyPath: "albumSortOrder")
        albumsController?.removeObserver(self, forKeyPath: "arrangedObjects")
        tracksController?.removeObserver(self, forKeyPath: "selectedObjects")
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        NotificationCenter.default.post(name: .SBTrackSelectionChanged, object: tracksController.selectedObjects)
    }
    
    override func loadView() {
        super.loadView()
        
        albumsCollectionView.register(SBAlbumViewItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("SBAlbumViewItem"))
        
        let items: [[String: Any]] = [
            [ITEM_IDENTIFIER: "RandomItem", ITEM_NAME: "Random"],
            [ITEM_IDENTIFIER: "NewestItem", ITEM_NAME: "Newest"],
            [ITEM_IDENTIFIER: "StarredItem", ITEM_NAME: "Favourited"],
            [ITEM_IDENTIFIER: "FrequentItem", ITEM_NAME: "Frequent"],
            [ITEM_IDENTIFIER: "RecentItem", ITEM_NAME: "Recent"],
            [ITEM_IDENTIFIER: "AlphaNameItem", ITEM_NAME: "All"]
        ]
        
        let group: [String: Any] = [
            GROUP_LABEL: "Browse By:",
            GROUP_SEPARATOR: false,
            GROUP_SELECTION_MODE: MGScopeBarGroupSelectionModeRadio,
            GROUP_ITEMS: items
        ]
        
        scopeGroups.add(group)
        
        scopeBar.setSelected(true, forItem: "RandomItem", inGroup: 0)
        scopeBar.sizeToFit()
        scopeBar.reloadData()
        
        NotificationCenter.default.addObserver(self, selector: #selector(subsonicCoversUpdatedNotification(_:)), name: .SBSubsonicCoversUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(subsonicAlbumsUpdatedNotification(_:)), name: .SBSubsonicAlbumsUpdated, object: nil)
        
        albumsController.addObserver(self, forKeyPath: "arrangedObjects", options: .new, context: nil)
        tracksController.addObserver(self, forKeyPath: "selectedObjects", options: .new, context: nil)
        
        UserDefaults.standard.addObserver(self, forKeyPath: "albumSortOrder", options: [.new, .initial], context: nil)
        
        if let albumClipView = albumsCollectionView.enclosingScrollView?.contentView {
            NotificationCenter.default.addObserver(self, selector: #selector(albumClipViewBoundsChanged(_:)), name: NSView.boundsDidChangeNotification, object: albumClipView)
        }
    }
    
    @objc func albumListType(forIdentifier identifier: String) -> SBAlbumListType {
        switch identifier {
        case "RandomItem":
            return .random
        case "NewestItem":
            return .newest
        case "HighestItem":
            return .highest
        case "FrequentItem":
            return .frequent
        case "StarredItem":
            return .starred
        case "RecentItem":
            return .recent
        case "AlphaNameItem":
            return .alphabetical
        case "AlphaArtistItem":
            return .alphabeticalByArtist
        default:
            return .random
        }
    }
    
    @objc func currentAlbumListType() -> SBAlbumListType {
        if let selectedItems = scopeBar.selectedItems as? [NSArray],
           let firstGroup = selectedItems.first as? [String],
           let identifier = firstGroup.first {
            return albumListType(forIdentifier: identifier)
        }
        return .random
    }
    
    @objc func reloadServers(with albumListType: SBAlbumListType) {
        self.server?.getAlbumListFor(type: albumListType)
    }
    
    // MARK: - Properties
    
    override var tracks: [SBTrack]! {
        return tracksController.arrangedObjects as? [SBTrack]
    }
    
    override var selectedTracks: [SBTrack]! {
        return tracksController.selectedObjects as? [SBTrack]
    }
    
    override var selectedTrackRow: Int {
        return tracksTableView.selectedRow
    }
    
    override var selectedAlbums: [SBAlbum]! {
        return albumsController.selectedObjects as? [SBAlbum]
    }
    
    override var selectedMusicItems: [SBStarrable]! {
        let responder = self.databaseController?.window?.firstResponder
        if responder == tracksTableView {
            return tracksController.selectedObjects as? [SBStarrable]
        } else if responder == albumsCollectionView {
            return albumsController.selectedObjects as? [SBStarrable]
        }
        return []
    }
    
    // MARK: - IBActions
    
    @IBAction func reloadSelected(_ sender: Any?) {
        self.reloadServers(with: self.currentAlbumListType())
    }
    
    // MARK: - Observers
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let keyPath = keyPath {
            if let album = object as? SBAlbum, keyPath == "tracks" {
                if let set = album.tracks, set.count > 0 {
                    tracksController.content = set
                    tracksTableView.reloadData()
                    album.removeObserver(self, forKeyPath: "tracks")
                }
            } else if let controller = object as? NSArrayController, controller == tracksController, keyPath == "selectedObjects" {
                if self.view.window != nil {
                    NotificationCenter.default.post(name: .SBTrackSelectionChanged, object: tracksController.selectedObjects)
                }
            } else if let controller = object as? NSArrayController, controller == albumsController, keyPath == "arrangedObjects" {
                albumsCollectionView.reloadData()
                albumsCollectionView.selectionIndexes = albumsController.selectionIndexes
            } else if let defaults = object as? UserDefaults, defaults == UserDefaults.standard, keyPath == "albumSortOrder" {
                albumSortDescriptor = sortDescriptorsForPreference()
                albumsController.sortDescriptors = albumSortDescriptor ?? []
            } else {
                super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    // MARK: - Notification / Infinite Scroll
    
    func loadWhenAtBottom() {
        guard shouldInfiniteScroll else {
            return
        }
        
        guard let scrollView = albumsCollectionView.enclosingScrollView,
              let documentView = scrollView.documentView else {
            return
        }
        let clipView = scrollView.contentView
        
        let verticalPosition = clipView.bounds.origin.y + clipView.bounds.size.height
        if verticalPosition == documentView.bounds.size.height {
            shouldInfiniteScroll = false
            self.server?.updateAlbumListFor(type: self.currentAlbumListType())
        }
    }
    
    @objc func albumClipViewBoundsChanged(_ notification: Notification) {
        loadWhenAtBottom()
    }
    
    @objc func subsonicAlbumsUpdatedNotification(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let count = userInfo["count"] as? NSNumber {
            shouldInfiniteScroll = count.intValue > 0
        }
        DispatchQueue.main.async {
            self.loadWhenAtBottom()
        }
    }
    
    @objc func subsonicCoversUpdatedNotification(_ notification: Notification) {
        DispatchQueue.main.async {
            self.albumsCollectionView.reloadData()
        }
    }
    
    // MARK: - NSCollectionViewDataSource
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return albumsController.arrangedObjects as? [Any] != nil ? (albumsController.arrangedObjects as! [Any]).count : 0
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        guard let arrangedObjects = albumsController.arrangedObjects as? [SBAlbum] else {
            return NSCollectionViewItem()
        }
        let album = arrangedObjects[indexPath.item]
        let item = albumsCollectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("SBAlbumViewItem"), for: indexPath)
        item.representedObject = album
        return item
    }
    
    // MARK: - NSCollectionViewDelegate
    
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        _ = albumsController.setSelectionIndexes(IndexSet())
    }
    
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let index = indexPaths.first?.item else { return }
        albumsController.setSelectionIndex(index)
        
        let selectedRow = albumsController.selectionIndexes.first ?? -1
        if let arrangedObjects = albumsController.arrangedObjects as? [SBAlbum],
           selectedRow != -1 && selectedRow < arrangedObjects.count {
            let album = arrangedObjects[selectedRow]
            tracksController.content = nil
            self.server?.get(album: album)
            
            if album.tracks == nil || album.tracks?.count == 0 {
                album.addObserver(self, forKeyPath: "tracks", options: [.initial, .prior, .new, .old], context: nil)
            } else {
                tracksController.content = album.tracks
            }
        }
    }
    
    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        return true
    }
    
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard let arrangedObjects = albumsController.arrangedObjects as? [SBAlbum] else {
            return nil
        }
        let album = arrangedObjects[indexPath.item]
        if let tracksSet = album.tracks {
            let sortDescriptors = tracksController.sortDescriptors
            let tracks = tracksSet.sortedArray(using: sortDescriptors) as? [SBTrack] ?? []
            return SBLibraryPasteboardWriter(items: tracks)
        }
        return nil
    }
    
    // MARK: - NSTableViewDataSource (Drag & Drop / Rating)
    
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        if tableView == tracksTableView {
            if let arrangedObjects = tracksController.arrangedObjects as? [SBTrack] {
                let track = arrangedObjects[row]
                return SBLibraryItemPasteboardWriter(item: track, index: row)
            }
        }
        return nil
    }
    
    // MARK: - NSTableViewDelegate Sort Descriptor Override
    
    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        if tableView == tracksTableView && tableColumn == tableView.tableColumns.first {
            let asc = (tracksController.sortDescriptors.first)?.ascending ?? true
            let trackNumberDescriptor = NSSortDescriptor(key: "trackNumber", ascending: !asc)
            let discNumberDescriptor = NSSortDescriptor(key: "discNumber", ascending: !asc)
            tracksController.sortDescriptors = [discNumberDescriptor, trackNumberDescriptor]
        }
    }
    
    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        if tableView == tracksTableView {
            if tableColumn?.identifier.rawValue == "rating" {
                let selectedRow = tracksTableView.selectedRow
                if selectedRow != -1,
                   let arrangedObjects = tracksController.arrangedObjects as? [SBTrack],
                   selectedRow < arrangedObjects.count {
                    let clickedTrack = arrangedObjects[selectedRow]
                    if let ratingNumber = object as? NSNumber,
                       let trackID = clickedTrack.itemId {
                        let rating = ratingNumber.intValue
                        self.server?.setRating(rating, id: trackID)
                    }
                }
            }
        }
    }
    
    // MARK: - MGScopeBarDelegate
    
    func numberOfGroups(in scopeBar: MGScopeBar!) -> Int {
        return scopeGroups.count
    }
    
    func scopeBar(_ scopeBar: MGScopeBar!, itemIdentifiersForGroup groupNumber: Int) -> [Any]! {
        if let group = scopeGroups[groupNumber] as? [String: Any],
           let items = group[GROUP_ITEMS] as? [[String: Any]] {
            return items.compactMap { $0[ITEM_IDENTIFIER] }
        }
        return []
    }
    
    func scopeBar(_ scopeBar: MGScopeBar!, labelForGroup groupNumber: Int) -> String! {
        if let group = scopeGroups[groupNumber] as? [String: Any] {
            return group[GROUP_LABEL] as? String
        }
        return nil
    }
    
    func scopeBar(_ scopeBar: MGScopeBar!, titleOfItem identifier: String!, inGroup groupNumber: Int) -> String! {
        if let group = scopeGroups[groupNumber] as? [String: Any],
           let items = group[GROUP_ITEMS] as? [[String: Any]] {
            for item in items {
                if let itemId = item[ITEM_IDENTIFIER] as? String, itemId == identifier {
                    return item[ITEM_NAME] as? String
                }
            }
        }
        return nil
    }
    
    func scopeBar(_ scopeBar: MGScopeBar!, selectionModeForGroup groupNumber: Int) -> MGScopeBarGroupSelectionMode {
        if let group = scopeGroups[groupNumber] as? [String: Any],
           let modeNum = group[GROUP_SELECTION_MODE] as? NSNumber {
            return MGScopeBarGroupSelectionMode(rawValue: UInt32(modeNum.intValue))
        }
        return MGScopeBarGroupSelectionModeRadio
    }
    
    func scopeBar(_ scopeBar: MGScopeBar!, imageForItem identifier: String!, inGroup groupNumber: Int) -> NSImage! {
        switch identifier {
        case "RandomItem":
            return NSImage(systemSymbolName: "shuffle", accessibilityDescription: "Random")
        case "NewestItem":
            return NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Newest")
        case "HighestItem":
            return NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Highest")
        case "StarredItem":
            return NSImage(systemSymbolName: "heart.fill", accessibilityDescription: "Favourited")
        case "FrequentItem":
            return NSImage(systemSymbolName: "arrowshape.up", accessibilityDescription: "Frequent")
        case "RecentItem":
            return NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Recent")
        case "AlphaNameItem":
            return NSImage(systemSymbolName: "square.stack", accessibilityDescription: "All sorted by name")
        case "AlphaArtistItem":
            return NSImage(systemSymbolName: "music.microphone", accessibilityDescription: "All sorted by artist")
        default:
            return nil
        }
    }
    
    func scopeBar(_ scopeBar: MGScopeBar!, selectedStateChanged selected: Bool, forItem identifier: String!, inGroup groupNumber: Int) {
        _ = albumsController.setSelectionIndexes(IndexSet())
        self.reloadServers(with: self.currentAlbumListType())
    }
}
