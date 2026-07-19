//
//  SBClientController.swift
//  Submariner
//
//  Created by Calvin Buckley on 2023-06-13.
//  Copyright © 2023 Submariner Developers. All rights reserved.
//

import Cocoa
import os

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SBSubsonicRequestOperation")

class SBSubsonicRequestOperation: SBOperation, @unchecked Sendable {
    typealias ParsingCustomization = ((SBSubsonicParsingOperation) -> Void)
    
    private let serverID: NSManagedObjectID
    private let baseURL: String?
    private let currentAlbumCount: Int
    
    var parameters: [URLQueryItem] = []
    let request: SBSubsonicRequestType
    var customization: ParsingCustomization? = nil
    var endpoint: String! // XXX: Make into let
    // Note that POST method is supported by almost all servers, even Subsonic,
    // but OpenSubsonic API says to check for the extension first.
    let usesPost: Bool
    private var dataTask: URLSessionDataTask?
    private var retryWorkItem: DispatchWorkItem?
    private let maximumRetryCount = 3
    
    init(server: SBServer, request: SBSubsonicRequestType) {
        parameters = server.getBaseQueryItems()
        self.request = request
        self.serverID = server.objectID
        self.baseURL = server.url
        self.currentAlbumCount = server.home?.albums?.count ?? 0
        
        // name is temporary, and we're on the same thread as what passed us this i hope
        let baseName = "Requesting from \(server.resourceName ?? "server")"
        self.usesPost = server.supportsFormPost.boolValue
        super.init(managedObjectContext: server.managedObjectContext!, name: baseName)
        
        buildUrl()
        
        DispatchQueue.main.async {
            self.name = "\(baseName): \(self.endpoint!)"
        }
    }
    
    // #MARK: - HTTP Requests
    
    private var progressObserver: NSKeyValueObservation?
    
    private func buildFormParams() -> String {
        SubsonicFormEncoder.encode(parameters)
    }
    
    private func request(url: URL, type: SBSubsonicRequestType, customization: ParsingCustomization? = nil, retryCount: Int = 0) {
        let session = URLSession.shared
        var request = URLRequest(url: url)
        if self.usesPost {
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = self.buildFormParams().data(using: .utf8)
        }
        // No auth header needed since we just pass them over query string
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if self.usesPost {
                logger.info("Handling POST URL \(url, privacy: .public)")
            } else {
                // sensitive because &p= contains user password
                logger.info("Handling URL \(url, privacy: .sensitive)")
                logger.info("\tAPI endpoint \(url.path, privacy: .public)")
            }
            
            if let error = error {
                if (error as NSError).code == NSURLErrorCancelled && self.isCancelled {
                    self.finish()
                    return
                }
                DispatchQueue.main.async {
                    NSApp.presentError(error)
                }
                self.finish()
                return
            } else if let response = response as? HTTPURLResponse {
                logger.info("\tStatus code is \(response.statusCode)")
                // Note that Subsonic and Navidrome return app-level error bodies in HTTP 200
                switch (response.statusCode) {
                case 404, 410, 501:
                    // For unsupported features, it may vary. 404 is used for features that
                    // seem unknown to the server in Subsonic and Navidrome. Navidrome at least
                    // uses 501 for features that may be implemented in the future, and 410 for
                    // features that will never be implemented. OwnCloud Music returns a 200 with
                    // a code 70 Subsonic error instead, so we handle that in the response parser.
                    self.threadedContext.perform {
                        if let server = try? self.threadedContext.existingObject(with: self.serverID) as? SBServer {
                            server.markNotSupported(feature: type)
                            self.saveThreadedContext()
                        }
                    }
                    self.finish()
                    return
                case 429:
                    // Newer versions of Navidrome back getCoverArt w/ third-party APIs.
                    // As such, it rate limits API requests that can invoke them.
                    // Instead of bothering the user, retry the request later.

                    // Retry-After is seconds or a specific date
                    let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                    logger.info("Retrying w/ Retry-After value \(retryAfter ?? "<nil>")")

                    let delay: TimeInterval
                    if let retryAfter = retryAfter,
                       let specificDate = retryAfter.dateTimeFromHTTP() {
                        delay = max(specificDate.timeIntervalSinceNow, 1)
                    } else {
                        // handle if Retry-After is valid, invalid, or missing
                        delay = TimeInterval(retryAfter ?? "5") ?? 5
                    }
                    // Use DispatchQueue instead of Timer because this completion handler
                    // runs on a background thread with no run loop. Timer would need a
                    // running RunLoop to fire, which doesn't exist here.
                    guard retryCount < self.maximumRetryCount, !self.isCancelled else {
                        let error = NSError(
                            domain: NSURLErrorDomain,
                            code: 429,
                            userInfo: [NSLocalizedDescriptionKey: "The server rate limit was exceeded after \(self.maximumRetryCount) retries."]
                        )
                        DispatchQueue.main.async { NSApp.presentError(error) }
                        self.finish()
                        return
                    }
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let self, !self.isCancelled else { return }
                        self.request(url: url, type: type, customization: customization, retryCount: retryCount + 1)
                    }
                    self.retryWorkItem = workItem
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: workItem)
                    return
                case 200: // OK, continue
                    break
                default:
                    let message = "HTTP \(response.statusCode) for \(url.path)"
                    let userInfo = [NSLocalizedDescriptionKey: message]
                    // XXX: Right domain?
                    let error = NSError(domain: NSURLErrorDomain, code: response.statusCode, userInfo: userInfo)
                    DispatchQueue.main.async {
                        NSApp.presentError(error)
                    }
                    self.finish()
                    return
                }
                
                DispatchQueue.main.async {
                    if let operation = SBSubsonicParsingOperation(managedObjectContext: self.mainContext,
                                                                  requestType: type,
                                                                  server: self.serverID,
                                                                  xml: data,
                                                                  mimeType: response.mimeType) {
                        customization?(operation)
                        OperationQueue.sharedServerQueue.addOperation(operation)
                    }
                }
                self.finish()
            } else {
                let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse,
                                    userInfo: [NSLocalizedDescriptionKey: "The server returned an invalid response."])
                DispatchQueue.main.async { NSApp.presentError(error) }
                self.finish()
            }
        }
        progressObserver = task.progress.observe(\.fractionCompleted, changeHandler: { progress, change in
            DispatchQueue.main.async {
                self.progress = .determinate(n: Float(progress.completedUnitCount), outOf: Float(progress.totalUnitCount))
            }
        })
        dataTask = task
        task.resume()
    }
    
    override func main() {
        let queryParameters = self.usesPost ? [] : self.parameters
        guard let baseUrl = baseURL else {
            logger.error("Base server URL was nil for request \(String(describing: self.request)), the server URL likely needs to be reset")
            self.finish()
            return
        }
        guard let url = URL.URLWith(string: baseUrl, command: "rest/\(endpoint!).view", parameters: queryParameters) else {
            logger.error("URL was nil for request \(String(describing: self.request)), the server URL likely needs to be reset")
            self.finish()
            return
        }
        
        request(url: url, type: self.request, customization: self.customization)
    }

    override func cancel() {
        super.cancel()
        retryWorkItem?.cancel()
        dataTask?.cancel()
        finish()
    }
    
    private func buildUrl() {
        switch request {
        case .ping:
            endpoint = "ping"
        case .getOpenSubsonicExtensions:
            endpoint = "getOpenSubsonicExtensions"
        case .getLicense:
            endpoint = "getLicense"
        case .getCoverArt(id: let id, forAlbumId: let albumId):
            parameters["id"] = id
            let maxCoverSize = UserDefaults.standard.integer(forKey: "MaxCoverSize")
            if maxCoverSize > 0 {
                parameters["size"] = String(maxCoverSize)
            }
            endpoint = "getCoverArt"
            customization = { operation in
                operation.currentCoverID = id
                operation.currentAlbumID = albumId
            }
        case .getPlaylists:
            endpoint = "getPlaylists"
        case .getAlbumList(type: let type):
            parameters["type"] = type.subsonicParameter()
            parameters["count"] = String(10)
            endpoint = "getAlbumList2"
        case .updateAlbumList(type: let type):
            parameters["type"] = type.subsonicParameter()
            parameters["count"] = String(10)
            parameters["offset"] = String(currentAlbumCount)
            endpoint = "getAlbumList2"
        case .getPlaylist(id: let id):
            parameters["id"] = id
            endpoint = "getPlaylist"
            customization = { operation in
                operation.currentPlaylistID = id
            }
        case .deletePlaylist(id: let id):
            parameters["id"] = id
            endpoint = "deletePlaylist"
            customization = { operation in
                operation.currentPlaylistID = id
            }
        case .createPlaylist(name: let name, trackIDs: let trackIDs):
            parameters["name"] = name
            
            // XXX: DRY this with update
            parameters += trackIDs.map { URLQueryItem(name: "songId", value: $0) }
            
            endpoint = "createPlaylist"
        case .getNowPlaying:
            endpoint = "getNowPlaying"
        case .search(query: let query):
            parameters["query"] = query
            parameters["songCount"] = "100" // XXX: Configurable?
            // We don't yet surface albums/artists, so this is just merely noise
            parameters["albumCount"] = "0"
            parameters["artistCount"] = "0"
            endpoint = "search3"
            customization = { operation in
                operation.currentSearch = SBSearchResult(query: .search(query: query), serverID: self.serverID)
            }
        case .updateSearch(existingResult: let existingResult):
            switch existingResult.query {
            case .search(let query):
                parameters["query"] = query
                parameters["songCount"] = "100"
                parameters["songOffset"] = String(existingResult.tracks.count)
                parameters["albumCount"] = "0"
                parameters["artistCount"] = "0"
                endpoint = "search3"
            default: // shouldn't happen
                break
            }
            existingResult.returnedTracks = 0
            customization = { operation in
                operation.currentSearch = existingResult
            }
        case .setRating(id: let id, rating: let rating):
            parameters["rating"] = String(rating)
            parameters["id"] = id
            endpoint = "setRating"
        case .getPodcasts:
            endpoint = "getPodcasts"
        case .scrobble(id: let id):
            parameters["id"] = id
            let currentTimeMS = Int64(Date().timeIntervalSince1970 * 1000)
            parameters["time"] = String(currentTimeMS)
            endpoint = "scrobble"
        case .scanLibrary:
            endpoint = "startScan"
        case .getScanStatus:
            endpoint = "getScanStatus"
        case .replacePlaylist(id: let id, trackIDs: let trackIDs):
            parameters["playlistId"] = id
            
            parameters += trackIDs.map { URLQueryItem(name: "songId", value: $0) }
            
            endpoint = "createPlaylist"
            customization = { operation in
                operation.currentPlaylistID = id
            }
        case .updatePlaylist(id: let id, name: let name, comment: let comment, isPublic: let isPublic, appendingIDs: let appendingIDs, removing: let removing):
            parameters["playlistId"] = id
            if let name = name {
                parameters["name"] = name
            }
            if let comment = comment {
                parameters["comment"] = comment
            }
            if let isPublic = isPublic {
                parameters["public"] = "\(isPublic)"
            }
            
            parameters += appendingIDs?.map { URLQueryItem(name: "songIdToAdd", value: $0) } ?? []
            parameters += removing?.map { index in URLQueryItem(name: "songIndexToRemove", value: "\(index)") } ?? []
            
            endpoint = "updatePlaylist"
            customization = { operation in
                operation.currentPlaylistID = id
            }
        case .getArtists:
            endpoint = "getArtists"
        case .getArtist(id: let id):
            parameters["id"] = id
            endpoint = "getArtist"
            customization = { operation in
                operation.currentArtistID = id
            }
        case .getAlbum(id: let id):
            parameters["id"] = id
            endpoint = "getAlbum"
            customization = { operation in
                operation.currentAlbumID = id
            }
        case .getTrack(id: let id):
            parameters["id"] = id
            endpoint = "getSong"
        case .getDirectories:
            // XXX: there is a lastIndexDate param but since the changeover to ID3 tag primary, that's not relevant anymore
            endpoint = "getIndexes"
        case .getDirectory(id: let id):
            parameters["id"] = id
            endpoint = "getMusicDirectory"
        case .star(trackIDs: let trackIDs, albumIDs: let albumIDs, artistIDs: let artistIDs, directoryIDs: let directoryIDs):
            parameters += (trackIDs + directoryIDs).map { URLQueryItem(name: "id", value: $0) }
            parameters += albumIDs.map { URLQueryItem(name: "albumId", value: $0) }
            parameters += artistIDs.map { URLQueryItem(name: "artistId", value: $0) }
            endpoint = "star"
        case .unstar(trackIDs: let trackIDs, albumIDs: let albumIDs, artistIDs: let artistIDs, directoryIDs: let directoryIDs):
            parameters += (trackIDs + directoryIDs).map { URLQueryItem(name: "id", value: $0) }
            parameters += albumIDs.map { URLQueryItem(name: "albumId", value: $0) }
            parameters += artistIDs.map { URLQueryItem(name: "artistId", value: $0) }
            endpoint = "unstar"
        case .getTopTracks(let artistName):
            parameters["artist"] = artistName
            endpoint = "getTopSongs"
            customization = { operation in
                operation.currentSearch = SBSearchResult(query: .topTracksFor(artistName: artistName), serverID: self.serverID)
            }
        case .getSimilarTracks(let artistID, let artistName):
            parameters["id"] = artistID
            endpoint = "getSimilarSongs2"
            customization = { operation in
                operation.currentSearch = SBSearchResult(query: .similarTo(artistID: artistID, artistName: artistName), serverID: self.serverID)
            }
        case .getStarred:
            endpoint = "getStarred2"
            customization = { operation in
                operation.currentSearch = SBSearchResult(query: .starred, serverID: self.serverID)
            }
        }
    }
}

enum SubsonicFormEncoder {
    static func encode(_ parameters: [URLQueryItem]) -> String {
        parameters.map { item in
            "\(item.name.formURLEncoded)=\((item.value ?? "").formURLEncoded)"
        }.joined(separator: "&")
    }
}

private extension String {
    static let formURLAllowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    var formURLEncoded: String {
        addingPercentEncoding(withAllowedCharacters: Self.formURLAllowedCharacters) ?? ""
    }
}
