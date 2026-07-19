//
//  SBMusicItem+CoreDataClass.swift
//  Submariner
//
//  Created by Calvin Buckley on 2023-04-23.
//  Copyright © 2023 Submariner Developers. All rights reserved.
//
//

import Foundation
import CoreData

@objc(SBMusicItem)
public class SBMusicItem: NSManagedObject {
    // Cover overrides imagePath, but this applies to Track/Episode/Artist/Album,
    // which exist when they're a local item. Make relative, but unlike Cover, don't
    // move, since we might not be the owners of it. (It does make the "user moved
    // the path" case more annoying though, but local items can always be destroyed
    // and recreated easily.
    @objc var path: String? {
        get {
            self.willAccessValue(forKey: "path")
            let ret = self.primitiveValue(forKey: "path") as? String
            self.didAccessValue(forKey: "path")
            return ret
        }
        set {
            self.willChangeValue(forKey: "path")
            self.setPrimitiveValue(newValue, forKey: "path")
            self.didChangeValue(forKey: "path")
        }
    }
}
