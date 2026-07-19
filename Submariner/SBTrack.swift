//
//  SBTrack+CoreDataClass.swift
//  Submariner
//
//  Created by Calvin Buckley on 2023-04-23.
//  Copyright © 2023 Submariner Developers. All rights reserved.
//
//

import Foundation
import CoreData
import UniformTypeIdentifiers
import CryptoKit

@objc(SBTrack)
public class SBTrack: SBMusicItem, SBStarrable {
    public override class func keyPathsForValuesAffectingValue(forKey key: String) -> Set<String> {
        if key == "durationString" {
            return Set(["duration"])
        } else if key == "playingImage" {
            return Set(["isPlaying"])
        } else if key == "onlineImage" {
            return Set(["isLocal"])
        } else if key == "starredImage" || key == "starredBool" {
            return Set(["starred"])
        }
        return Set()
    }
    
    @objc var durationString: String? {
        self.willAccessValue(forKey: "duration")
        let ret = String(timeInterval: TimeInterval(duration?.intValue ?? 0))
        self.didAccessValue(forKey: "duration")
        return ret
    }
    
    @objc func streamURL() -> URL? {
        if let cachedURL = cachedFileURL, FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        } else if let isLocal = self.isLocal, isLocal.boolValue,
           let path = self.path,
           FileManager.default.fileExists(atPath: path) {
            return URL.init(fileURLWithPath: path)
        } else if let server = self.server, let url = server.url {
            var parameters = server.getBaseParameters()
            parameters["maxBitRate"] = UserDefaults.standard.string(forKey: "maxBitRate")
            parameters["id"] = self.itemId
            // Instruct the server to estimate and include a Content-Length header.
            // AVFoundation requires this for its HTTP pipeline to work correctly.
            parameters["estimateContentLength"] = "true"
            
            return URL.URLWith(string: url, command: "rest/stream.view", parameters: parameters)
        }
        return nil
    }
    
    @objc func downloadURL() -> URL? {
        if let server = self.server, let url = server.url {
            var parameters = server.getBaseParameters()
            parameters["maxBitRate"] = UserDefaults.standard.string(forKey: "maxBitRate")
            parameters["id"] = self.itemId
            
            return URL.URLWith(string: url, command: "rest/download.view", parameters: parameters)
        }
        return nil
    }
    
    @objc var playingImage: NSImage? {
        if let playing = self.isPlaying, playing.boolValue {
            return NSImage(systemSymbolName: "speaker.fill", accessibilityDescription: "Playing")
        }
        return nil
    }
    
    @objc var coverImage: NSImage {
        // change this if imageRepresentation is optimized
        if let album = self.album {
            return album.imageRepresentation() as! NSImage
        }
        return SBAlbum.nullCover!
    }
    
    @objc var artistString: String? {
        if let album = self.album,
           let albumArtist = album.artist,
           let albumArtistName = albumArtist.itemName {
            return albumArtistName
        }
        return artistName
    }
    
    @objc var albumString: String? {
        return self.album?.itemName
    }
    
    @objc var onlineImage: NSImage {
        if isCached || self.isLocal?.boolValue == true {
            return NSImage(systemSymbolName: "bolt.horizontal.fill", accessibilityDescription: "Cached")!
        }
        return NSImage(systemSymbolName: "bolt.horizontal", accessibilityDescription: "Online")!
    }

    @objc var isCached: Bool {
        guard let cachedFileURL else { return false }
        return FileManager.default.fileExists(atPath: cachedFileURL.path)
    }

    @objc var cachedFileURL: URL? {
        guard server != nil, itemId != nil else { return nil }
        return MediaCache.fileURL(for: self)
    }
    
    @objc var starredImage: NSImage? {
        if self.starred != nil {
            return NSImage(systemSymbolName: "heart.fill", accessibilityDescription: "Favourited")!
        }
        //return NSImage(systemSymbolName: "heart", accessibilityDescription: "Not Favourited")!
        return nil
    }
    
    @objc var starredBool: Bool {
        get {
            return starred != nil
        } set {
            // setting it locally is mostly for the sake of instant update - we should refresh the track later
            if starred != nil {
                starred = nil
                server?.unstar(tracks: [self], albums: [], artists: [])
            } else {
                starred = Date.now
                server?.star(tracks: [self], albums: [], artists: [])
            }
        }
    }
    
    @objc func isVideo() -> Bool {
        if let contentType = self.contentType,
           let utType = UTType(mimeType: contentType) {
            return utType.conforms(to: .video)
        }
        return false
    }
    
    @objc func macOSCompatibleContentType() -> String? {
        let type = self.contentType ?? "audio/mpeg"
        if type == "audio/x-flac" {
            return "audio/flac"
        }
        return type
    }
    
    // #MARK: - AppleScript wrappers
    
    @objc var objectIDString: String {
        return objectID.uriRepresentation().absoluteString
    }
    
    @objc var coverImageURL: NSString? {
        return album?.cover?.imagePath
    }
    
    // #MARK: - Core Data insert compatibility shim
    
    @objc(insertInManagedObjectContext:) class func insertInManagedObjectContext(context: NSManagedObjectContext) -> SBTrack {
        let entity = NSEntityDescription.entity(forEntityName: "Track", in: context)
        return NSEntityDescription.insertNewObject(forEntityName: entity!.name!, into: context) as! SBTrack
    }
}

enum MediaCache {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Submariner/Audio", isDirectory: true)
    }()

    static func fileURL(for track: SBTrack) -> URL? {
        guard let server = track.server,
              let serverURL = server.url,
              let trackID = track.itemId else { return nil }
        let profile = UserDefaults.standard.string(forKey: "maxBitRate") ?? "0"
        let digest = cacheKey(serverURL: serverURL, username: server.username ?? "", trackID: trackID, profile: profile)
        let rawExtension = track.transcodeSuffix ?? track.contentSuffix ?? "audio"
        let safeExtension = rawExtension.filter { $0.isLetter || $0.isNumber }.lowercased()
        return directory.appendingPathComponent(digest).appendingPathExtension(safeExtension.isEmpty ? "audio" : safeExtension)
    }

    static func cacheKey(serverURL: String, username: String, trackID: String, profile: String) -> String {
        let identity = [serverURL, username, trackID, profile].joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
