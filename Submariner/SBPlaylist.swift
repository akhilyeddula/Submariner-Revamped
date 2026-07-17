//
//  SBPlaylist+CoreDataClass.swift
//  Submariner
//
//  Created by Calvin Buckley on 2023-04-23.
//  Copyright © 2023 Submariner Developers. All rights reserved.
//
//

import Foundation
import CoreData
import os

@objc(SBPlaylist)
public class SBPlaylist: SBResource {
    @objc var resources = NSSet()
    
    // #MARK: - Core Data NSSet backwards compatibility
    
    override public class func keyPathsForValuesAffectingValue(forKey key: String) -> Set<String> {
        if key == "tracks" {
            return Set(["trackIDs"])
        } else if key == "trackIDs" {
            return Set(["tracks"])
        }
        return super.keyPathsForValuesAffectingValue(forKey: key)
    }
    
    @objc dynamic var tracks: [SBTrack]? {
        get {
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SBPlaylist")
            logger.info("Getting tracks for playlist \(self.resourceName ?? "<nil>"), trackIDs count: \(self.trackIDs?.count ?? 0)")
            // If tracks get deleted, compactMap means we can skip over them if they turn out to not exist anymore, without complicated schemes
            return trackIDs?.compactMap { uri in
                if let moc = self.managedObjectContext {
                    if let oid = moc.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri) {
                        let track = moc.object(with: oid) as? SBTrack
                        if track == nil {
                            logger.warning("Failed to cast resolved object for URI: \(uri) to SBTrack")
                        } else {
                            logger.info("Successfully resolved URI: \(uri) to track: \(track?.itemName ?? "<nil>")")
                        }
                        return track
                    } else {
                        logger.warning("Failed to resolve URI to managedObjectID: \(uri)")
                    }
                } else {
                    logger.warning("No managedObjectContext for playlist when resolving URI: \(uri)")
                }
                return nil
            }
        }
        set {
            if let tracks = newValue {
                self.trackIDs = tracks.map { $0.objectID.uriRepresentation() }
            }
        }
    }
    
    func add(track: SBTrack) {
        ensureTrackIDsNotNil()
        var ids = trackIDs ?? []
        ids.append(track.objectID.uriRepresentation())
        trackIDs = ids
    }
    
    @objc(addTracks:) func add(tracks: [SBTrack]) {
        ensureTrackIDsNotNil()
        var ids = trackIDs ?? []
        let additionalIDs = tracks.map { $0.objectID.uriRepresentation() }
        ids.append(contentsOf: additionalIDs)
        trackIDs = ids
    }
    
    func add(tracks: [SBTrack], at row: Int) {
        ensureTrackIDsNotNil()
        var ids = trackIDs ?? []
        let additionalIDs = tracks.map { $0.objectID.uriRepresentation() }
        ids.insert(contentsOf: additionalIDs, at: row)
        trackIDs = ids
    }
    
    func remove(indices: IndexSet) {
        trackIDs?.remove(atOffsets: indices)
    }
    
    @objc(moveIndices:toRow:) func moveTracks(fromOffsets indices: IndexSet, toOffset row: Int) -> IndexSet? {
        return trackIDs?.moveReturningNewIndices(fromOffsets: indices, toOffset: row)
    }
    
    // #MARK: - Core Data insert compatibility shim
    
    @objc(insertInManagedObjectContext:) class func insertInManagedObjectContext(context: NSManagedObjectContext) -> SBPlaylist {
        let entity = NSEntityDescription.entity(forEntityName: "Playlist", in: context)
        return NSEntityDescription.insertNewObject(forEntityName: entity!.name!, into: context) as! SBPlaylist
    }
    
    private func ensureTrackIDsNotNil() {
        if trackIDs == nil {
            trackIDs = []
        }
    }
    
    public override func awakeFromInsert() {
        ensureTrackIDsNotNil()
    }
}
