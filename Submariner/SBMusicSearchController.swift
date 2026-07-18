//
//  SBMusicSearchController.swift
//  Submariner
//
//  Created by Rafaël Warnault on 22/08/11.
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

@objc(SBMusicSearchController)
class SBMusicSearchController: SBViewController, NSTableViewDataSource {
    
    @IBOutlet var tracksTableView: NSTableView!
    @IBOutlet var tracksController: NSArrayController!
    
    private var selectionObserver: NSKeyValueObservation?
    
    override class func nibName() -> String? {
        return "MusicSearch"
    }
    
    override var title: String? {
        get {
            return "Search Results"
        }
        set {
            super.title = newValue
        }
    }
    
    override init(managedObjectContext context: NSManagedObjectContext) {
        super.init(managedObjectContext: context)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func loadView() {
        super.loadView()
        
        selectionObserver = tracksController.observe(\.selectedObjects, options: [.new]) { [weak self] ac, change in
            guard let self = self else { return }
            if self.view.window != nil {
                NotificationCenter.default.post(name: .SBTrackSelectionChanged, object: self.tracksController.selectedObjects)
            }
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        NotificationCenter.default.post(name: .SBTrackSelectionChanged, object: tracksController.selectedObjects)
    }
    
    @objc func searchString(_ query: String) {
        var searchText = query
        
        // Remove extraneous whitespace
        while searchText.contains("Â  ") {
            searchText = searchText.replacingOccurrences(of: "Â  ", with: " ")
        }
        
        // Remove leading space
        if searchText.hasPrefix(" ") {
            searchText.removeFirst()
        }
        
        // Remove trailing space
        if searchText.hasSuffix(" ") {
            searchText.removeLast()
        }
        
        if searchText.isEmpty {
            tracksController.filterPredicate = NSPredicate(format: "(isLocal == YES)")
            return
        }
        
        let searchTerms = searchText.components(separatedBy: " ")
        
        if searchTerms.count == 1 {
            let p = NSPredicate(format: "(isLocal == YES) AND ((itemName contains[cd] %@) OR (albumString contains[cd] %@) OR (artistString contains[cd] %@) OR (genre contains[cd] %@))", searchText, searchText, searchText, searchText)
            tracksController.filterPredicate = p
        } else {
            var subPredicates = [NSPredicate]()
            for term in searchTerms {
                let p = NSPredicate(format: "(isLocal == YES) AND ((itemName contains[cd] %@) OR (albumString contains[cd] %@) OR (artistString contains[cd] %@) OR (genre contains[cd] %@))", term, term, term, term)
                subPredicates.append(p)
            }
            let cp = NSCompoundPredicate(andPredicateWithSubpredicates: subPredicates)
            tracksController.filterPredicate = cp
        }
    }
    
    // MARK: - Properties
    
    override var tracks: [SBTrack] {
        tracksController.arrangedObjects as? [SBTrack] ?? []
    }
    
    override var selectedTrackRow: Int {
        tracksTableView.selectedRow
    }
    
    override var selectedTracks: [SBTrack] {
        tracksController.selectedObjects as? [SBTrack] ?? []
    }
    
    // MARK: - NSTableViewDataSource
    
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        if tableView == tracksTableView {
            if row < tracks.count {
                let track = tracks[row]
                return SBLibraryItemPasteboardWriter(item: track, index: row)
            }
        }
        return nil
    }
}
