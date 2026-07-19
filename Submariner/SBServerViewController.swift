//
//  SBServerViewController.swift
//  Submariner
//
//  Created by Rafaël Warnault on 17/05/11.
//  Copyright (c) 2011-2014, Rafaël Warnault. All rights reserved.
//

import Cocoa

@objc(SBServerViewController)
class SBServerViewController: SBViewController {
    @objc dynamic var server: SBServer!
    
    @objc init(server aServer: SBServer?, context: NSManagedObjectContext) {
        self.server = aServer
        super.init(managedObjectContext: context)
    }
    
    @objc override init(managedObjectContext context: NSManagedObjectContext) {
        super.init(managedObjectContext: context)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    @IBAction @objc func createNewPlaylistWithSelectedTracks(_ sender: Any?) {
        if let dbController = databaseController,
           let addServerPlaylistController = dbController.addServerPlaylistController {
            addServerPlaylistController.server = self.server
            addServerPlaylistController.tracks = self.selectedTracks
            addServerPlaylistController.openSheet(sender)
        }
    }
    
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let action = item.action
        
        let tracksSelected = self.selectedTracks.count
        
        if action == #selector(createNewPlaylistWithSelectedTracks(_:)) {
            return tracksSelected > 0
        }
        
        return super.validateUserInterfaceItem(item)
    }
}
