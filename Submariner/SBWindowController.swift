//
//  SBWindowController.swift
//  Submariner
//
//  Created by Rafaël Warnault on 14/05/11.
//  Copyright (c) 2011-2014, Rafaël Warnault. All rights reserved.
//

import Cocoa

@objc(SBWindowController)
class SBWindowController: NSWindowController {
    @objc dynamic var managedObjectContext: NSManagedObjectContext!

    @objc class func nibName() -> String? {
        return nil
    }

    override var windowNibName: NSNib.Name? {
        return type(of: self).nibName()
    }

    @objc init(managedObjectContext context: NSManagedObjectContext) {
        self.managedObjectContext = context
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
