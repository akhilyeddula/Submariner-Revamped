//
//  SBEditServerController.swift
//  Submariner
//
//  Created by Calvin Buckley on 2024-02-09.
//
//  Copyright (c) 2024 Calvin Buckley
//  SPDX-License-Identifier: BSD-3-Clause
//  

import Cocoa

@objc(SBEditServerController) class SBEditServerController: SBSheetController, NSControlTextEditingDelegate {
    @objc var server: SBServer? {
        didSet {
            oldName = server?.resourceName
            oldURL = server?.url
            oldUsername = server?.username
            oldPassword = server?.password
            oldToken = server?.useTokenAuth
        }
    }
    @objc var editMode: Bool = false
    
    @IBOutlet var descriptionTextField: NSTextField!
    @IBOutlet var urlTextField: NSTextField!
    @IBOutlet var usernameTextField: NSTextField!
    @IBOutlet var passwordTextField: NSTextField!
    
    private var oldURL, oldUsername, oldPassword, oldName: String?
    private var oldToken: NSNumber?
    
    func showErrorAlert(message: String, information: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = information
        alert.runModal()
    }
    
    override func closeSheet(_ sender: Any!) {
        // make sure things make sense so we don't deal with some bizarre sitch
        // FIXME: other validations possible; i believe SBServer does this for resourceName already
        guard let server = self.server else {
            // XXX: shouldn't be possible?
            return
        }
        guard let resourceName = server.resourceName, !resourceName.isEmpty else {
            showErrorAlert(message: "Invalid Server Name", information: "The server name can't be empty.")
            return
        }
        guard let url = server.url, !url.isEmpty else {
            showErrorAlert(message: "Invalid URL", information: "The URL can't be empty.")
            return
        }
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false else {
            showErrorAlert(message: "Invalid URL", information: "The URL isn't valid. It should be a full URL including the protocol, hostname, and if needed, port.")
            return
        }
        // username and password must be passed to subsonic, but allowed to be empty in theory
        
        let identityChanged = server.url != oldURL || server.username != oldUsername
        let passwordChanged = server.password != oldPassword
        managedObjectContext.commitEditing()
        do {
            try managedObjectContext.save()
        } catch {
            NSApp.presentError(error)
            return
        }

        if identityChanged, let oldURL, let oldURLValue = URL(string: oldURL), let oldUsername {
            server.updateKeychain(oldURL: oldURLValue, oldUsername: oldUsername)
        } else if passwordChanged || !editMode {
            server.updateKeychainPassword()
        }

        super.closeSheet(sender)
        
        // Invalidate the server's parameters since it could have changed (i.e. token)
        // ...which is held by the client controller owned by the server.
        // easiest way to do that is to force a reconnect
        server.connect()
    }
    
    override func cancelSheet(_ sender: Any!) {
        guard let server = self.server else {
            return
        }
        
        if editMode {
            // XXX: MOC undo unreliable; should be a transaction?
            server.resourceName = oldName;
            server.url = oldURL;
            server.username = oldUsername;
            server.password = oldPassword;
            server.useTokenAuth = oldToken;
            self.managedObjectContext.commitEditing()
            try? self.managedObjectContext.save()
        } else {
            self.managedObjectContext.delete(server)
            self.managedObjectContext.processPendingChanges()
        }
        
        super.cancelSheet(sender)
    }
}
