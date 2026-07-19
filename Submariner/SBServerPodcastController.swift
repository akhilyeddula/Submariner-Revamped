//
//  SBServerPodcastController.swift
//  Submariner
//
//  Created by Rafaël Warnault on 23/08/11.
//
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

@objc class SBServerPodcastController: SBServerViewController {
    @IBOutlet var podcastsController: NSArrayController!
    @IBOutlet var episodesController: NSArrayController!
    @IBOutlet var podcastsTableView: NSTableView!
    @IBOutlet var episodesTableView: NSTableView!
    
    @objc dynamic var podcastsSortDescriptors: [NSSortDescriptor] = [
        NSSortDescriptor(key: "itemId", ascending: true)
    ]
    
    @objc dynamic var episodesSortDescriptors: [NSSortDescriptor] = [
        NSSortDescriptor(key: "publishDate", ascending: false)
    ]
    
    override class func nibName() -> String? {
        "ServerPodcasts"
    }
    
    override var title: String? {
        get {
            if let serverName = server?.resourceName {
                return "Podcasts on \(serverName)"
            }
            return "Podcasts"
        }
        set {
            super.title = newValue
        }
    }
    
    override func loadView() {
        super.loadView()
        
        self.addObserver(self, forKeyPath: "server", options: [.initial, .new, .old], context: nil)
        
        podcastsTableView.target = self
        podcastsTableView.doubleAction = #selector(trackDoubleClick(_:))
    }
    
    deinit {
        self.removeObserver(self, forKeyPath: "server")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "server" {
            self.willChangeValue(forKey: "title")
            podcastsController.content = nil
            server?.getServerPodcasts()
            self.didChangeValue(forKey: "title")
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    @IBAction @objc override func trackDoubleClick(_ sender: Any?) {
        let selectedRow = episodesTableView.selectedRow
        if selectedRow != -1 {
            if let arrangedObjects = episodesController.arrangedObjects as? [SBEpisode],
               selectedRow < arrangedObjects.count {
                let clickedTrack = arrangedObjects[selectedRow]
                let status = clickedTrack.episodeStatus ?? ""
                if status == "completed" {
                    // add track to player
                    if UserDefaults.standard.integer(forKey: "playerBehavior") == 1 {
                        SBPlayer.sharedInstance().add(tracks: arrangedObjects, replace: true)
                        // play track
                        SBPlayer.sharedInstance().play(track: clickedTrack)
                    } else {
                        SBPlayer.sharedInstance().add(tracks: arrangedObjects, replace: false)
                        SBPlayer.sharedInstance().play(track: clickedTrack)
                    }
                } else {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Unavailable Episode"
                    alert.informativeText = "This podcast episode isn't available. It might still be downloading. (The current status is \"\(status)\".)"
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
}
