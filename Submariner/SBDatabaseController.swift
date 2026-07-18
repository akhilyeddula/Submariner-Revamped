//
//  SBDatabaseController.swift
//  Submariner
//
//  Created by Rafaël Warnault on 04/06/11.
//  Copyright (c) 2011-2014, Rafaël Warnault. All rights reserved.
//

import Cocoa
import Quartz

@objc(SBDatabaseController)
class SBDatabaseController: SBWindowController,
    NSWindowDelegate, NSOutlineViewDelegate, NSOutlineViewDataSource,
    NSPageControllerDelegate, NSMenuDelegate {

    // MARK: - IBOutlets (names must match Database.xib exactly)
    @IBOutlet var mainSplitView: NSSplitView!
    @IBOutlet var sourceList: NSOutlineView!
    @IBOutlet var resourcesController: NSTreeController!
    @IBOutlet var editServerController: SBEditServerController!
    @IBOutlet var addServerPlaylistController: SBAddServerPlaylistController!
    @IBOutlet var progressIndicator: NSProgressIndicator!
    @IBOutlet var durationTextField: NSTextField!
    @IBOutlet var progressTextField: NSTextField!
    @IBOutlet var progressSlider: NSSlider!
    @IBOutlet var playPauseButton: NSButton!
    @IBOutlet var leftVC: NSViewController!
    @IBOutlet var rightVC: NSPageController!
    @IBOutlet var tracklistVC: NSViewController!
    @IBOutlet var tracklistContainmentBox: NSBox!
    @IBOutlet var routePicker: SBRoutePickerView!
    @IBOutlet var routePickerToolbarItem: NSToolbarItem!
    @IBOutlet weak var volumeToolbarItem: NSToolbarItem!
    @IBOutlet var volumeButton: SBVolumeButton!
    @IBOutlet var volumePopover: NSPopover!
    @IBOutlet var tracklistButton: SBTracklistButton!
    @IBOutlet var searchField: NSSearchField!
    @IBOutlet var searchToolbarItem: NSSearchToolbarItem!

    // MARK: - Child View Controllers
    var onboardingController: SBOnboardingController!
    var musicController: SBMusicController!
    var downloadsController: SBDownloadsController!
    var tracklistController: SBTracklistController!
    var playlistController: SBPlaylistController!
    var musicSearchController: SBMusicSearchController!
    var serverLibraryController: SBServerLibraryController!
    var serverHomeController: SBServerHomeController!
    var serverDirectoryController: SBServerDirectoryController!
    var serverPodcastController: SBServerPodcastController!
    var serverUserController: SBServerUserViewController!
    var serverSearchController: SBServerSearchController!
    var inspectorController: SBInspectorController!
    var tempVC: SBViewController!

    // MARK: - Sheet Controllers (not managed by IB)
    var jumpToTimestampController: SBJumpToTimestampController!
    var playRateController: SBPlayRateController!

    // MARK: - State Properties
    @objc dynamic var resourceSortDescriptors: [NSSortDescriptor] = []
    @objc dynamic var library: SBLibrary?
    @objc dynamic var server: SBServer?
    
    var splitVC: NSSplitViewController!
    var tracklistSplit: NSSplitViewItem!
    var transition: CATransition!
    var progressUpdateTimer: Timer?
    var ignoreNextSelection: Bool = false

    // MARK: - nibName
    @objc override class func nibName() -> String? { "Database" }

    // MARK: - Initializer
    @objc override init(managedObjectContext context: NSManagedObjectContext) {
        super.init(managedObjectContext: context)
        
        // Sort descriptors: index first, then alphabetical
        resourceSortDescriptors = [
            NSSortDescriptor(key: "index", ascending: true),
            NSSortDescriptor(key: "resourceName", ascending: true)
        ]
        
        // Child view controllers
        onboardingController = SBOnboardingController(managedObjectContext: context)
        musicController = SBMusicController(managedObjectContext: context)
        downloadsController = SBDownloadsController(managedObjectContext: context)
        tracklistController = SBTracklistController(managedObjectContext: context)
        playlistController = SBPlaylistController(managedObjectContext: context)
        musicSearchController = SBMusicSearchController(managedObjectContext: context)
        serverLibraryController = SBServerLibraryController(managedObjectContext: context)
        serverHomeController = SBServerHomeController(managedObjectContext: context)
        serverDirectoryController = SBServerDirectoryController(managedObjectContext: context)
        serverPodcastController = SBServerPodcastController(managedObjectContext: context)
        serverUserController = SBServerUserViewController(managedObjectContext: context)
        serverSearchController = SBServerSearchController(managedObjectContext: context)
        inspectorController = SBInspectorController()
        tempVC = SBViewController(managedObjectContext: context)
        
        // Sheet controllers
        jumpToTimestampController = SBJumpToTimestampController()
        playRateController = SBPlayRateController()
        
        // Wire back-references
        let allControllers: [SBViewController] = [
            onboardingController, musicController, musicSearchController,
            tracklistController, playlistController, serverLibraryController,
            serverHomeController, serverDirectoryController,
            serverSearchController, serverUserController
        ]
        allControllers.forEach { $0.databaseController = self }
        inspectorController.databaseController = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - deinit
    deinit {
        NotificationCenter.default.removeObserver(self)
        OperationQueue.sharedServerQueue.removeObserver(self, forKeyPath: "operationCount")
        self.window?.contentView?.removeObserver(self, forKeyPath: "safeAreaInsets")
    }

    // MARK: - Sidebar Computed Properties (KVO-bound in XIB)
    @objc dynamic var isTracklistShown: NSNumber {
        get {
            guard tracklistSplit != nil && tracklistContainmentBox != nil && tracklistController != nil else {
                return false
            }
            return NSNumber(value: !tracklistSplit.isCollapsed && (tracklistContainmentBox.contentView === tracklistController.view))
        }
        set {
            self.toggleTrackList(nil)
        }
    }

    @objc dynamic var isServerUsersShown: NSNumber {
        get {
            guard tracklistSplit != nil && tracklistContainmentBox != nil && serverUserController != nil else {
                return false
            }
            return NSNumber(value: !tracklistSplit.isCollapsed && (tracklistContainmentBox.contentView === serverUserController.view))
        }
        set {
            self.toggleServerUsers(nil)
        }
    }

    @objc dynamic var isInspectorShown: NSNumber {
        get {
            guard tracklistSplit != nil && tracklistContainmentBox != nil && inspectorController != nil else {
                return false
            }
            return NSNumber(value: !tracklistSplit.isCollapsed && (tracklistContainmentBox.contentView === inspectorController.view))
        }
        set {
            self.toggleInspector(nil)
        }
    }

    // MARK: - Selected Music Items Properties
    @objc var selectedMusicItems: [SBStarrable]? {
        let target = NSApp.target(forAction: #selector(getter: self.selectedMusicItems))
        if let targetObj = target as AnyObject?, targetObj !== self {
            if let respondingTarget = targetObj as? SBViewController {
                return respondingTarget.selectedMusicItems
            }
        }
        return nil
    }

    @objc var hasSelectedMusicItems: Bool {
        return (selectedMusicItems?.count ?? 0) > 0
    }

    @objc var selectedMusicItemsStarred: NSControl.StateValue {
        get {
            guard let selected = selectedMusicItems, !selected.isEmpty else {
                return .off
            }
            let starredCount = selected.filter { $0.starredBool }.count
            if starredCount == 0 {
                return .off
            } else if starredCount == selected.count {
                return .on
            } else {
                return .mixed
            }
        }
        set {
            if let selected = selectedMusicItems {
                for item in selected {
                    item.starredBool = (newValue == .on)
                }
            }
        }
    }
}
