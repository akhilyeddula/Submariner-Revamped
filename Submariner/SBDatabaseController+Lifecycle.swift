//
//  SBDatabaseController+Lifecycle.swift
//  Submariner
//
//  Created by Rafaël Warnault on 04/06/11.
//  Copyright (c) 2011-2014, Rafaël Warnault. All rights reserved.
//

import Cocoa
import CoreData

extension SBDatabaseController {
    // MARK: - Onboarding Check
    @objc func shouldShowOnboarding() -> Bool {
        let localMusicPredicate = NSPredicate(format: "(server == nil)")
        let localMusicFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Artist")
        localMusicFetchRequest.predicate = localMusicPredicate
        
        let serverFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Server")
        
        do {
            let localMusicCount = try self.managedObjectContext.count(for: localMusicFetchRequest)
            let serverCount = try self.managedObjectContext.count(for: serverFetchRequest)
            return localMusicCount < 1 && serverCount < 1
        } catch {
            NSLog("Error counting Artist or Server: %@", error.localizedDescription)
            return true
        }
    }

    // MARK: - Window Lifecycle
    override func windowDidLoad() {
        super.windowDidLoad()
        
        let contentLayoutGuide = self.window!.contentLayoutGuide as! NSLayoutGuide
        splitVC.view.topAnchor.constraint(equalTo: self.window!.contentView!.topAnchor, constant: 0).isActive = true
        splitVC.view.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor).isActive = true
        splitVC.view.leftAnchor.constraint(equalTo: contentLayoutGuide.leftAnchor).isActive = true
        splitVC.view.rightAnchor.constraint(equalTo: contentLayoutGuide.rightAnchor).isActive = true
        
        // populate default sections
        self.populatedDefaultSections()
        
        // edit controllers
        editServerController.managedObjectContext = self.managedObjectContext
        addServerPlaylistController.managedObjectContext = self.managedObjectContext
        
        // source list drag and drop
        sourceList.registerForDraggedTypes([
            .libraryItems,
            .libraryItem,
            .playlist
        ])
        
        // re-layout when visible
        self.window!.contentView!.addObserver(self, forKeyPath: "safeAreaInsets", options: .new, context: nil)
        
        OperationQueue.sharedServerQueue.addObserver(self, forKeyPath: "operationCount", options: .new, context: nil)
        
        // notifications registration
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(subsonicPlaylistsUpdatedNotification(_:)), name: NSNotification.Name("SBSubsonicPlaylistsUpdatedNotification"), object: nil)
        notificationCenter.addObserver(self, selector: #selector(subsonicPlaylistUpdatedNotification(_:)), name: NSNotification.Name("SBSubsonicPlaylistUpdatedNotification"), object: nil)
        notificationCenter.addObserver(self, selector: #selector(subsonicPlaylistsCreatedNotification(_:)), name: NSNotification.Name("SBSubsonicPlaylistsCreatedNotification"), object: nil)
        notificationCenter.addObserver(self, selector: #selector(playerPlaylistUpdatedNotification(_:)), name: NSNotification.Name("SBPlayerPlaylistUpdatedNotification"), object: nil)
        notificationCenter.addObserver(self, selector: #selector(playerPlayStateNotification(_:)), name: NSNotification.Name("SBPlayerPlayStateNotification"), object: nil)
        notificationCenter.addObserver(self, selector: #selector(subsonicConnectionSucceeded(_:)), name: NSNotification.Name("SBSubsonicConnectionSucceededNotification"), object: nil)
        notificationCenter.addObserver(self, selector: #selector(subsonicConnectionFailed(_:)), name: NSNotification.Name("SBSubsonicConnectionFailedNotification"), object: nil)
        notificationCenter.addObserver(self, selector: #selector(windowDidChangeOcclusionState(_:)), name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(updateTitle(_:)), name: NSNotification.Name("SBTitleUpdated"), object: nil)
        notificationCenter.addObserver(self, selector: #selector(updateMenuBindings(_:)), name: NSNotification.Name("SBTrackSelectionChanged"), object: nil)
        notificationCenter.addObserver(self, selector: #selector(updateMenuBindings(_:)), name: NSNotification.Name("SBFirstResponderBecame"), object: nil)
        notificationCenter.addObserver(self, selector: #selector(updateMenuBindings(_:)), name: NSNotification.Name("SBFirstResponderNoLonger"), object: nil)
        notificationCenter.addObserver(self, selector: #selector(playerSeekNotification(_:)), name: NSNotification.Name("SBPlaySeekNotification"), object: nil)
        notificationCenter.addObserver(self, selector: #selector(trackCacheUpdated(_:)), name: .SBTrackCacheUpdated, object: nil)
        
        // setup main box subviews
        let navItem = SBOnboardingNavigationItem()
        self.navigate(to: navItem)
        
        if let lastRightSidebar = UserDefaults.standard.string(forKey: "RightSidebar") {
            if lastRightSidebar == "ServerUsers" {
                self.toggleServerUsers(self)
            } else if lastRightSidebar == "Tracklist" {
                self.toggleTrackList(self)
            } else if lastRightSidebar == "Inspector" {
                self.toggleInspector(self)
            }
        }
        
        resourcesController.addObserver(self, forKeyPath: "content", options: .new, context: nil)

    }

    // MARK: - Awake from NIB
    override func awakeFromNib() {
        super.awakeFromNib()
        
        splitVC = NSSplitViewController()
        splitVC.splitView.isVertical = true
        splitVC.view.translatesAutoresizingMaskIntoConstraints = false
        
        let a = NSSplitViewItem(sidebarWithViewController: leftVC)
        a.holdingPriority = NSLayoutConstraint.Priority(275)
        splitVC.addSplitViewItem(a)
        
        let b = NSSplitViewItem(viewController: rightVC)
        b.holdingPriority = NSLayoutConstraint.Priority(266)
        b.titlebarSeparatorStyle = .none
        splitVC.addSplitViewItem(b)
        
        tracklistSplit = NSSplitViewItem(viewController: tracklistVC)
        tracklistSplit.holdingPriority = NSLayoutConstraint.Priority(300)
        tracklistSplit.titlebarSeparatorStyle = .none
        tracklistSplit.maximumThickness = tracklistController.view.frame.size.width
        tracklistSplit.minimumThickness = 150 + 36
        
        splitVC.addSplitViewItem(tracklistSplit)
        tracklistSplit.canCollapse = true
        tracklistSplit.isCollapsed = true
        
        self.window!.contentView!.replaceSubview(mainSplitView, with: splitVC.view)
        
        splitVC.splitView.autosaveName = "DatabaseWindowSplitViewController"
        splitVC.splitView.identifier = NSUserInterfaceItemIdentifier("SBDatabaseWindowSplitViewController")
        
        routePickerToolbarItem.view = routePicker
        tracklistButton.databaseController = self
        volumeButton.volumePopover = volumePopover
    }

    // MARK: - KVO Observer
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let queue = object as? OperationQueue, queue === OperationQueue.sharedServerQueue {
            if keyPath == "operationCount" {
                if OperationQueue.sharedServerQueue.operationCount > 0 {
                    DispatchQueue.main.async { [weak self] in
                        self?.progressIndicator.startAnimation(self)
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.progressIndicator.stopAnimation(self)
                    }
                }
            }
        } else if let treeController = object as? NSTreeController, treeController === resourcesController {
            if keyPath == "content" {
                let predicate = NSPredicate(format: "(resourceName == %@)", "Offline")
                if let section = try? self.managedObjectContext.fetch(entityNamed: "Section", predicate: predicate) as? SBSection {
                    sourceList.expandURIs([section.objectID.uriRepresentation().absoluteString])
                }
                
                let playlistsPredicate = NSPredicate(format: "(resourceName == %@)", "Playlists")
                if let section = try? self.managedObjectContext.fetch(entityNamed: "Section", predicate: playlistsPredicate) as? SBSection {
                    sourceList.expandURIs([section.objectID.uriRepresentation().absoluteString])
                }
                
                if let savedExpanded = UserDefaults.standard.array(forKey: "NSOutlineView Items SourceList") as? [String] {
                    sourceList.expandURIs(savedExpanded)
                }
                
                resourcesController.removeObserver(self, forKeyPath: "content")
                
                let serversPredicate = NSPredicate(format: "(resourceName == %@)", "Servers")
                if let serversSection = try? self.managedObjectContext.fetch(entityNamed: "Section", predicate: serversPredicate) as? SBSection {
                    sourceList.expandURIs([serversSection.objectID.uriRepresentation().absoluteString])
                }
                
                try? self.managedObjectContext.save()
                self.loadInitialContentView()
            }
        } else if let view = object as? NSView, view === self.window?.contentView, keyPath == "safeAreaInsets" {
            let targetRect = (rightVC.selectedViewController === serverHomeController) ? rightVC.view.safeAreaRect : rightVC.view.frame
            rightVC.selectedViewController?.view.setFrameSize(targetRect.size)
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    // MARK: - Initial View Loading
    @objc func loadInitialContentView() {
        var lastViewed: Any? = nil
        if let lastViewedURLString = UserDefaults.standard.string(forKey: "LastViewedResource") {
            if let lastViewedURL = URL(string: lastViewedURLString),
               let oid = self.managedObjectContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: lastViewedURL) {
                do {
                    lastViewed = try self.managedObjectContext.existingObject(with: oid)
                } catch {
                    NSLog("existingObjectWithID failed, but not fatal: %@", error.localizedDescription)
                }
            }
        }
        
        if self.shouldShowOnboarding() {
            let navItem = SBOnboardingNavigationItem()
            self.navigate(to: navItem)
        } else if let resource = lastViewed as? SBServer {
            self.switchToResource(resource)
        } else if let playlist = lastViewed as? SBPlaylist, playlist.server != nil {
            self.switchToResource(playlist)
        } else if let server = try? managedObjectContext.fetch(SBServer.fetchRequest()).first {
            self.switchToResource(server)
        } else {
            let navItem = SBOnboardingNavigationItem()
            self.navigate(to: navItem)
        }
        
        if rightVC.arrangedObjects.count > 1 {
            rightVC.arrangedObjects = [rightVC.arrangedObjects[0]]
        }
        rightVC.selectedIndex = 0
    }

    @objc func populatedDefaultSections() {
        // Offline cache section. The former local library is intentionally hidden;
        // server downloads are files in MediaCache, not duplicate Core Data tracks.
        var predicate = NSPredicate(format: "(resourceName == %@)", "Offline")
        var section = try? self.managedObjectContext.fetch(entityNamed: "Section", predicate: predicate) as? SBSection
        if section == nil {
            predicate = NSPredicate(format: "(resourceName == %@) OR (resourceName == %@) OR (resourceName == %@)", "Library", "LIBRARY", "Offline")
            section = try? self.managedObjectContext.fetch(entityNamed: "Section", predicate: predicate) as? SBSection
            if let sect = section {
                sect.resourceName = "Offline"
            } else {
                section = SBSection.insertInManagedObjectContext(context: self.managedObjectContext)
                section?.resourceName = "Offline"
                section?.index = 0
            }
        }
        
        // library resource
        predicate = NSPredicate(format: "(resourceName == %@)", "Music")
        library = try? self.managedObjectContext.fetch(entityNamed: "Library", predicate: predicate) as? SBLibrary
        if let library {
            section?.removeFromResources(library)
            library.section = nil
        }
        
        // DOWNLOADS resource
        predicate = NSPredicate(format: "(resourceName == %@)", "Downloads")
        let resource = try? self.managedObjectContext.fetch(entityNamed: "Downloads", predicate: predicate) as? SBDownloads
        if resource == nil {
            let downloads = SBDownloads.insertInManagedObjectContext(context: self.managedObjectContext)
            downloads.resourceName = "Downloads"
            downloads.index = 1
            downloads.section = section
            if let firstStore = self.managedObjectContext.persistentStoreCoordinator?.persistentStores.first {
                self.managedObjectContext.assign(downloads, to: firstStore)
            }
        }
        
        // playlist section
        predicate = NSPredicate(format: "(resourceName == %@)", "Playlists")
        section = try? self.managedObjectContext.fetch(entityNamed: "Section", predicate: predicate) as? SBSection
        if section == nil {
            predicate = NSPredicate(format: "(resourceName == %@)", "PLAYLISTS")
            section = try? self.managedObjectContext.fetch(entityNamed: "Section", predicate: predicate) as? SBSection
            if let sect = section {
                sect.resourceName = "Playlists"
            } else {
                section = SBSection.insertInManagedObjectContext(context: self.managedObjectContext)
                section?.resourceName = "Playlists"
                section?.index = 1
            }
        }
        
        // servers section
        predicate = NSPredicate(format: "(resourceName == %@)", "Servers")
        section = try? self.managedObjectContext.fetch(entityNamed: "Section", predicate: predicate) as? SBSection
        if section == nil {
            predicate = NSPredicate(format: "(resourceName == %@)", "SERVERS")
            section = try? self.managedObjectContext.fetch(entityNamed: "Section", predicate: predicate) as? SBSection
            if let sect = section {
                sect.resourceName = "Servers"
            } else {
                section = SBSection.insertInManagedObjectContext(context: self.managedObjectContext)
                section?.resourceName = "Servers"
                section?.index = 2
            }
        }
        
        self.managedObjectContext.processPendingChanges()
        try? self.managedObjectContext.save()
    }
}
