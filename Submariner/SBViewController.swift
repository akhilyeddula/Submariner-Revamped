//
//  SBViewController.swift
//  Submariner
//
//  Created by Rafaël Warnault on 06/06/11.
//
//  Copyright (c) 2011-2014, Rafaël Warnault
//  All rights reserved.
//

import Cocoa
import CoreData

struct SBSelectedRowStatus: OptionSet {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let none = SBSelectedRowStatus([])
    static let downloadable = SBSelectedRowStatus(rawValue: 1 << 0)
    static let showableInFinder = SBSelectedRowStatus(rawValue: 1 << 1)
    static let favourited = SBSelectedRowStatus(rawValue: 1 << 2)
}

@objc(SBSelectedItemType)
enum SBSelectedItemType: Int {
    case none = 0
    case artist = 1
    case album = 2
    case track = 4
    case directory = 8
}

@objc(SBViewController)
class SBViewController: NSViewController, NSUserInterfaceValidations {

    @objc dynamic var managedObjectContext: NSManagedObjectContext!
    
    private var compensatedSplitViewToken: Int = 0
    @IBOutlet weak var compensatedSplitView: NSSplitView?
    @objc weak var databaseController: SBDatabaseController?
    @objc dynamic var trackSortDescriptor: [NSSortDescriptor] = []
    
    @objc class func nibName() -> String? {
        return nil
    }
    
    @objc init(managedObjectContext context: NSManagedObjectContext) {
        self.managedObjectContext = context
        super.init(nibName: type(of: self).nibName(), bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc var tracks: [SBTrack]! {
        return []
    }
    
    @objc var selectedTrackRow: Int {
        return -1
    }
    
    @objc var selectedTracks: [SBTrack]! {
        return []
    }
    
    @objc var selectedAlbums: [SBAlbum]! {
        return []
    }
    
    @objc var selectedArtists: [SBArtist]! {
        return []
    }
    
    @objc var selectedDirectories: [SBDirectory]! {
        return []
    }
    
    @objc var selectedMusicItems: [SBStarrable]! {
        return selectedTracks.compactMap { $0 as SBStarrable }
    }
    
    override var title: String? {
        didSet {
            NotificationCenter.default.post(name: Notification.Name("SBTitleUpdated"), object: self)
        }
    }
    
    // MARK: - IBActions
    
    // MARK: Playing
    
    @IBAction @objc func trackDoubleClick(_ sender: Any?) {
        if selectedTrackRow < 0 {
            return
        }
        
        SBPlayer.sharedInstance().play(tracks: (tracks as NSArray).sortedArray(using: trackSortDescriptor) as! [SBTrack], startingAt: selectedTrackRow)
    }
    
    @IBAction @objc func albumDoubleClick(_ sender: Any?) {
        guard let album = selectedAlbums.first else { return }
        
        if let albumTracks = album.tracks?.allObjects as? [SBTrack] {
            SBPlayer.sharedInstance().play(tracks: (albumTracks as NSArray).sortedArray(using: trackSortDescriptor) as! [SBTrack], startingAt: 0)
        }
    }
    
    @IBAction @objc func playDirectory(_ sender: Any?) {
        guard let directory = selectedDirectories.first else { return }
        
        let directoryTracks = recursiveTracks(from: directory)
        SBPlayer.sharedInstance().play(tracks: (directoryTracks as NSArray).sortedArray(using: trackSortDescriptor) as! [SBTrack], startingAt: 0)
    }
    
    @IBAction @objc func playSelected(_ sender: Any?) {
        let itemType = selectedItemType()
        if itemType == .album {
            albumDoubleClick(sender)
        } else if itemType == .track {
            trackDoubleClick(sender)
        } else if itemType == .directory {
            playDirectory(sender)
        }
    }
    
    @IBAction @objc func playFirstDiscFromAlbum(_ sender: Any?) {
        guard let album = selectedAlbums.first else { return }
        let albumTracks = firstDiscTracks(for: album)
        SBPlayer.sharedInstance().play(tracks: albumTracks, startingAt: 0)
    }
    
    // MARK: Add to Tracklist
    
    @IBAction @objc func addDirectoryToTracklist(_ sender: Any?) {
        guard let directory = selectedDirectories.first else { return }
        
        let directoryTracks = recursiveTracks(from: directory)
        SBPlayer.sharedInstance().add(tracks: directoryTracks, replace: false)
    }
    
    @IBAction @objc func addArtistToTracklist(_ sender: Any?) {
        var trackList: [SBTrack] = []
        for artist in selectedArtists {
            if let albums = artist.albums?.allObjects as? [SBAlbum] {
                for album in albums {
                    if let albumTracks = album.tracks?.allObjects as? [SBTrack] {
                        trackList.append(contentsOf: (albumTracks as NSArray).sortedArray(using: trackSortDescriptor) as! [SBTrack])
                    }
                }
            }
        }
        
        SBPlayer.sharedInstance().add(tracks: trackList, replace: false)
    }
    
    @IBAction @objc func addAlbumToTracklist(_ sender: Any?) {
        guard let album = selectedAlbums.first else { return }
        
        if let albumTracks = album.tracks?.allObjects as? [SBTrack] {
            SBPlayer.sharedInstance().add(tracks: (albumTracks as NSArray).sortedArray(using: trackSortDescriptor) as! [SBTrack], replace: false)
        }
    }
    
    @IBAction @objc func addSelectedToTracklist(_ sender: Any?) {
        let itemType = selectedItemType()
        if itemType == .artist {
            addArtistToTracklist(sender)
        } else if itemType == .album {
            addAlbumToTracklist(sender)
        } else if itemType == .track {
            addTrackToTracklist(sender)
        } else if itemType == .directory {
            addDirectoryToTracklist(sender)
        }
    }
    
    @IBAction @objc func queueFirstDiscFromAlbum(_ sender: Any?) {
        guard let album = selectedAlbums.first else { return }
        let albumTracks = firstDiscTracks(for: album)
        SBPlayer.sharedInstance().add(tracks: albumTracks, replace: false)
    }
    
    @IBAction @objc func addTrackToTracklist(_ sender: Any?) {
        SBPlayer.sharedInstance().add(tracks: selectedTracks, replace: false)
    }
    
    // MARK: Playlist
    
    @IBAction @objc func createNewLocalPlaylistWithSelectedTracks(_ sender: Any?) {
        createLocalPlaylist(withSelected: selectedTracks, databaseController: databaseController)
    }
    
    // MARK: Downloading
    
    @IBAction @objc func downloadDirectory(_ sender: Any?) {
        guard let directory = selectedDirectories.first else { return }
        
        let directoryTracks = recursiveTracks(from: directory)
        for track in directoryTracks {
            let op = SBSubsonicDownloadOperation(managedObjectContext: managedObjectContext, trackID: track.objectID)
            OperationQueue.sharedDownloadQueue.addOperation(op!)
        }
    }
    
    @IBAction @objc func downloadTrack(_ sender: Any?) {
        downloadTracks(selectedTracks, databaseController: databaseController)
    }
    
    @IBAction @objc func downloadAlbum(_ sender: Any?) {
        guard let doubleClickedAlbum = selectedAlbums.first else { return }
        
        databaseController?.showDownloadView(self)
        
        if let albumTracks = doubleClickedAlbum.tracks?.allObjects as? [SBTrack] {
            let sortedTracks = (albumTracks as NSArray).sortedArray(using: trackSortDescriptor) as! [SBTrack]
            for track in sortedTracks {
                let op = SBSubsonicDownloadOperation(managedObjectContext: managedObjectContext, trackID: track.objectID)
                OperationQueue.sharedDownloadQueue.addOperation(op!)
            }
        }
    }
    
    @IBAction @objc func downloadSelected(_ sender: Any?) {
        let itemType = selectedItemType()
        if itemType == .album {
            downloadAlbum(sender)
        } else if itemType == .track {
            downloadTrack(sender)
        } else if itemType == .directory {
            downloadDirectory(sender)
        }
    }
    
    // MARK: Show in
    
    @IBAction @objc func showSelectedInLibrary(_ sender: Any?) {
        if let firstTrack = selectedTracks.first {
            databaseController?.go(to: firstTrack)
        }
    }
    
    @IBAction @objc func showTrackInFinder(_ sender: Any?) {
        showTracksInFinder(selectedTracks)
    }
    
    @IBAction @objc func showSelectedInFinder(_ sender: Any?) {
        showTracksInFinder(selectedTracks)
    }
    
    // MARK: - Workaround for split view and safe area
    
    override func viewDidAppear() {
        super.viewDidAppear()
        guard let splitView = compensatedSplitView else { return }
        
        if compensatedSplitViewToken == 0 {
            compensatedSplitViewToken = 1
            
            if splitView.isVertical && splitView.subviews.count != 2 {
                return
            }
            
            let oldPriority = splitView.holdingPriorityForSubview(at: 0)
            let otherPriority = splitView.holdingPriorityForSubview(at: 1)
            splitView.setHoldingPriority(otherPriority, forSubviewAt: 0)
            
            let topItem = splitView.subviews[0]
            let oldSize = topItem.frame.size.height
            splitView.setPosition(oldSize, ofDividerAt: 0)
            
            splitView.setHoldingPriority(oldPriority, forSubviewAt: 0)
        }
    }
    
    // MARK: - Library View Helper Functions
    
    @objc func sortDescriptors(forPreference preference: String?) -> [NSSortDescriptor] {
        let albumNameDescriptor = NSSortDescriptor(key: "itemName", ascending: true, selector: #selector(NSString.caseInsensitiveCompare(_:)))
        if preference == "OldestFirst" {
            let albumYearDescriptor = NSSortDescriptor(key: "year", ascending: true)
            return [albumYearDescriptor, albumNameDescriptor]
        } else {
            return [albumNameDescriptor]
        }
    }
    
    @objc func sortDescriptorsForPreference() -> [NSSortDescriptor] {
        let newOrderType = UserDefaults.standard.string(forKey: "albumSortOrder")
        return sortDescriptors(forPreference: newOrderType)
    }
    
    @objc(showTracksInFinder:selectedIndices:)
    func showTracksInFinder(_ trackList: [SBTrack], selectedIndices indexSet: IndexSet) {
        let selectedTracks = (trackList as NSArray).objects(at: indexSet) as! [SBTrack]
        showTracksInFinder(selectedTracks)
    }
    
    @objc(showTracksInFinder:)
    func showTracksInFinder(_ trackList: [SBTrack]) {
        var tracks: [URL] = []
        var remoteOnly = 0
        
        for track in trackList {
            var trackToUse = track
            if let localTrack = track.localTrack {
                trackToUse = localTrack
            } else if trackToUse.isLocal?.boolValue == false {
                remoteOnly += 1
                continue
            }
            if let path = trackToUse.path {
                let trackURL = URL(fileURLWithPath: path)
                tracks.append(trackURL)
            }
        }
        
        if tracks.count > 0 {
            NSWorkspace.shared.activateFileViewerSelecting(tracks)
        }
        if remoteOnly > 0 {
            let oops = NSAlert()
            oops.messageText = "Some tracks couldn't be shown in Finder"
            oops.informativeText = "If the remote track isn't cached, it only exists on the server, and not the filesystem."
            oops.alertStyle = .informational
            oops.addButton(withTitle: "OK")
            oops.beginSheetModal(for: self.view.window!) { response in }
        }
    }
    
    @objc func downloadTracks(_ trackList: [SBTrack], selectedIndices indexSet: IndexSet, databaseController: SBDatabaseController?) {
        let selectedTracks = (trackList as NSArray).objects(at: indexSet) as! [SBTrack]
        downloadTracks(selectedTracks, databaseController: databaseController)
    }
    
    @objc func downloadTracks(_ trackList: [SBTrack], databaseController: SBDatabaseController?) {
        var downloaded = 0
        for track in trackList {
            if track.localTrack != nil || track.isLocal?.boolValue == true {
                return
            }
            
            if let op = SBSubsonicDownloadOperation(managedObjectContext: self.managedObjectContext, trackID: track.objectID) {
                OperationQueue.sharedDownloadQueue.addOperation(op)
                downloaded += 1
            }
        }
        if databaseController != nil && downloaded > 0 {
            databaseController?.showDownloadView(self)
        }
    }
    
    func selectedRowStatus(_ trackList: [SBTrack], selectedIndices indexSet: IndexSet) -> SBSelectedRowStatus {
        let selectedTracks = (trackList as NSArray).objects(at: indexSet) as! [SBTrack]
        return selectedRowStatus(selectedTracks)
    }
    
    func selectedRowStatus(_ trackList: [SBTrack]) -> SBSelectedRowStatus {
        var downloadable = 0
        var showable = 0
        var favourited = 0
        
        for track in trackList {
            if track.isLocal?.boolValue == true || track.localTrack != nil {
                showable += 1
            }
            if track.isLocal?.boolValue == false && track.localTrack == nil {
                downloadable += 1
            }
            if track.starredBool {
                favourited += 1
            }
        }
        
        var status = SBSelectedRowStatus.none
        if downloadable > 0 { status.insert(.downloadable) }
        if showable > 0 { status.insert(.showableInFinder) }
        if favourited > 0 { status.insert(.favourited) }
        return status
    }
    
    @objc func createLocalPlaylist(withSelected trackList: [SBTrack], selectedIndices indexSet: IndexSet, databaseController: SBDatabaseController?) {
        let selectedTracks = (trackList as NSArray).objects(at: indexSet) as! [SBTrack]
        createLocalPlaylist(withSelected: selectedTracks, databaseController: databaseController)
    }
    
    @objc func createLocalPlaylist(withSelected trackList: [SBTrack], databaseController: SBDatabaseController?) {
        let predicate = NSPredicate(format: "(resourceName == %@)", "Playlists")
        
        if let playlistsSection = try? managedObjectContext.fetch(entityNamed: "Section", predicate: predicate) as? SBSection {
            let newPlaylist = SBPlaylist(context: managedObjectContext)
            newPlaylist.resourceName = "New Playlist"
            newPlaylist.section = playlistsSection
            newPlaylist.setValue(NSOrderedSet(array: trackList), forKey: "tracks")
            
            playlistsSection.addToResources(newPlaylist)
        }
    }
    
    @objc func firstDiscTracks(for album: SBAlbum) -> [SBTrack] {
        guard let albumTracks = album.tracks?.allObjects as? [SBTrack] else { return [] }
        let sortedTracks = (albumTracks as NSArray).sortedArray(using: trackSortDescriptor) as! [SBTrack]
        
        var filteredTracks = sortedTracks.filter { $0.discNumber?.int32Value == 1 }
        if filteredTracks.isEmpty {
            filteredTracks = sortedTracks.filter { $0.discNumber?.int32Value == 0 }
        }
        return filteredTracks
    }
    
    @objc func recursiveTracks(from directory: SBDirectory) -> [SBTrack] {
        var tracks: [SBTrack] = []
        for item in directory.children {
            if let track = item as? SBTrack {
                tracks.append(track)
            } else if let childDir = item as? SBDirectory {
                let childTracks = recursiveTracks(from: childDir)
                tracks.append(contentsOf: childTracks)
            }
        }
        return tracks
    }
    
    func selectedItemType() -> SBSelectedItemType {
        guard let first = selectedMusicItems.first as? NSObject else {
            return .none
        }
        if first.isKind(of: SBArtist.self) {
            return .artist
        } else if first.isKind(of: SBAlbum.self) {
            return .album
        } else if first.isKind(of: SBTrack.self) {
            return .track
        } else if first.isKind(of: SBDirectory.self) {
            return .directory
        }
        return .none
    }
    
    // MARK: - UI Validator
    
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard let action = item.action else { return false }
        
        let artistsSelected = selectedArtists.count
        let albumSelected = selectedAlbums.count
        let tracksSelected = selectedTracks.count
        let directoriesSelected = selectedDirectories.count
        
        let type = selectedItemType()
        let tracksActive = (type == .track)
        let albumsActive = (type == .album)
        let artistsActive = (type == .artist)
        let directoriesActive = (type == .directory)
        
        var selectedTrackRowStatus: SBSelectedRowStatus = .none
        if tracksActive {
            selectedTrackRowStatus = selectedRowStatus(selectedTracks)
        }
        
        if action == #selector(playSelected(_:)) {
            return (albumSelected > 0 && albumsActive) ||
                   (tracksSelected > 0 && tracksActive) ||
                   (directoriesSelected > 0 && directoriesActive)
        }
        
        if action == #selector(addSelectedToTracklist(_:)) {
            return (albumSelected > 0 && albumsActive) ||
                   (tracksSelected > 0 && tracksActive) ||
                   (artistsSelected > 0 && artistsActive) ||
                   (directoriesSelected > 0 && directoriesActive)
        }
        
        if action == #selector(trackDoubleClick(_:)) ||
           action == #selector(addTrackToTracklist(_:)) ||
           action == #selector(createNewLocalPlaylistWithSelectedTracks(_:)) {
            return tracksSelected > 0
        }
        
        if action == #selector(showSelectedInLibrary(_:)) {
            return tracksSelected == 1
        }
        
        if action == #selector(showSelectedInFinder(_:)) {
            return selectedTrackRowStatus.contains(.showableInFinder)
        }
        
        if action == #selector(downloadTrack(_:)) {
            return selectedTrackRowStatus.contains(.downloadable)
        }
        
        if action == #selector(downloadSelected(_:)) {
            return selectedTrackRowStatus.contains(.downloadable) ||
                   (albumSelected > 0 && albumsActive) ||
                   (directoriesSelected > 0 && directoriesActive)
        }
        
        if action == #selector(albumDoubleClick(_:)) ||
           action == #selector(downloadAlbum(_:)) ||
           action == #selector(addAlbumToTracklist(_:)) ||
           action == #selector(playFirstDiscFromAlbum(_:)) ||
           action == #selector(queueFirstDiscFromAlbum(_:)) {
            return albumSelected > 0 && albumsActive
        }
        
        if action == #selector(addArtistToTracklist(_:)) {
            return artistsSelected > 0
        }
        
        return true
    }
}