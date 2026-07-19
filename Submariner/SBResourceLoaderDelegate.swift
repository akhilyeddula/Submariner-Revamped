//
//  SBResourceLoaderDelegate.swift
//  Submariner
//
//  Created by Akhil Yeddula on 2026-07-17.
//  Copyright © 2026 Submariner Developers. All rights reserved.
//

import Foundation
import AVFoundation
import UniformTypeIdentifiers
import os.log

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "fr.read-write.Submariner", category: "SBResourceLoaderDelegate")

class SBResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {

    private let contentType: String

    /// Protects `pendingRequests`. Using an NSLock (not DispatchQueue) to allow synchronous
    /// access from multiple URLSession delegate callbacks without deadlock risk.
    private let lock = NSLock()
    private var pendingRequests: [URLSessionTask: AVAssetResourceLoadingRequest] = [:]

    /// A dedicated URLSession whose delegate is self. Created lazily so the URLSession
    /// doesn't exist until the first request arrives.
    private lazy var session: URLSession = makeSession()

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600 // Allow up to 1 hour for long tracks/streams
        // delegateQueue nil → URLSession creates its own serial OperationQueue
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    init(contentType: String) {
        self.contentType = contentType
        super.init()
    }

    func invalidateAndCancel() {
        let requests = lock.withLock { () -> [AVAssetResourceLoadingRequest] in
            let requests = Array(pendingRequests.values)
            pendingRequests.removeAll()
            return requests
        }
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        requests.forEach { $0.finishLoading(with: error) }
        session.invalidateAndCancel()
    }

    // MARK: - Helpers

    /// Translate our synthetic sbhttp/sbhttps scheme back to the real http/https scheme.
    private func actualURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch components.scheme {
        case "sbhttp":  components.scheme = "http"
        case "sbhttps": components.scheme = "https"
        default: return nil
        }
        return components.url
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let requestURL = loadingRequest.request.url,
              let actualURL = actualURL(from: requestURL) else {
            logger.error("Resource loader got unexpected URL scheme: \(loadingRequest.request.url?.scheme ?? "nil", privacy: .public)")
            return false
        }

        var urlRequest = URLRequest(url: actualURL)

        // DO NOT use HEAD requests. Subsonic API (stream.view) often returns XML or errors
        // for HEAD requests, or fails to include media headers. Always use GET.
        let dataRequest = loadingRequest.dataRequest
        if loadingRequest.contentInformationRequest != nil && dataRequest == nil {
            // If AVPlayer only wants info, ask for the first 2 bytes to force a 206 Partial Content
            // response with the full Content-Range, without downloading the whole file.
            urlRequest.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        } else if let dr = dataRequest {
            if dr.requestedOffset > 0 || !dr.requestsAllDataToEndOfResource {
                let start = dr.requestedOffset
                let end = dr.requestsAllDataToEndOfResource
                    ? ""
                    : "\(dr.requestedOffset + Int64(dr.requestedLength) - 1)"
                urlRequest.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
            }
        }

        let task = session.dataTask(with: urlRequest)
        lock.withLock { pendingRequests[task] = loadingRequest }
        task.resume()

        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        var taskToCancel: URLSessionTask?
        lock.withLock {
            // Use === (identity) not == because AVAssetResourceLoadingRequest is a reference type.
            if let entry = pendingRequests.first(where: { $0.value === loadingRequest }) {
                taskToCancel = entry.key
                pendingRequests.removeValue(forKey: entry.key)
            }
        }
        taskToCancel?.cancel()
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // IMPORTANT: completionHandler MUST be called on this callback's thread before returning.
        // Dispatching it to another queue and returning would leave URLSession in an undefined state.
        let loadingRequest = lock.withLock { pendingRequests[dataTask] }

        guard let loadingRequest = loadingRequest else {
            completionHandler(.cancel)
            return
        }

        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 || http.statusCode == 206 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? NSURLErrorBadServerResponse
            let error = NSError(domain: NSURLErrorDomain, code: statusCode,
                                userInfo: [NSLocalizedDescriptionKey: "The audio server returned HTTP \(statusCode)."])
            lock.withLock { pendingRequests.removeValue(forKey: dataTask) }
            loadingRequest.finishLoading(with: error)
            completionHandler(.cancel)
            return
        }

        if let requestedOffset = loadingRequest.dataRequest?.requestedOffset,
           requestedOffset > 0, http.statusCode != 206 {
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse,
                                userInfo: [NSLocalizedDescriptionKey: "The audio server did not honor a byte-range request."])
            lock.withLock { pendingRequests.removeValue(forKey: dataTask) }
            loadingRequest.finishLoading(with: error)
            completionHandler(.cancel)
            return
        }

        if let infoRequest = loadingRequest.contentInformationRequest {
            let mimeType = response.mimeType ?? contentType
            infoRequest.contentType = UTType(mimeType: mimeType)?.identifier ?? mimeType
            
            var contentLength: Int64 = -1
            var supportsRanges = false

            if let http = response as? HTTPURLResponse {
                // If it's a 206 Partial Content, we know it supports ranges.
                // Parse Content-Range to get the real total file size.
                if http.statusCode == 206, let range = http.value(forHTTPHeaderField: "Content-Range"),
                   let totalStr = range.split(separator: "/").last,
                   let total = Int64(totalStr), total > 0 {
                    contentLength = total
                    supportsRanges = true
                } else {
                    if let acceptRanges = http.value(forHTTPHeaderField: "Accept-Ranges"), acceptRanges == "bytes" {
                        supportsRanges = true
                    }
                    if response.expectedContentLength > 0 {
                        contentLength = response.expectedContentLength
                    }
                }
            }


            // Some reverse proxies ignore Range. Do not download the entire track merely
            // to answer AVFoundation's metadata-only request.
            if loadingRequest.dataRequest == nil && http.statusCode == 200 {
                lock.withLock { pendingRequests.removeValue(forKey: dataTask) }
                loadingRequest.finishLoading()
                completionHandler(.cancel)
                return
            }

            // If a stream is being transcoded by Navidrome/Subsonic (e.g. maxBitRate is set), 
            // it will be sent with Transfer-Encoding: chunked, and we won't know the content length.
            // If we don't know the content length, we MUST NOT claim byte range support, otherwise
            // AVPlayer will abort with err=-12864 (kFigFileError_NotOpen).
            if contentLength > 0 {
                infoRequest.contentLength = contentLength
                infoRequest.isByteRangeAccessSupported = supportsRanges
            } else {
                infoRequest.isByteRangeAccessSupported = false
            }
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let loadingRequest = lock.withLock { pendingRequests[dataTask] }
        guard let loadingRequest, let request = loadingRequest.dataRequest else { return }

        if !request.requestsAllDataToEndOfResource {
            let requestedEnd = request.requestedOffset + Int64(request.requestedLength)
            let remaining = max(requestedEnd - request.currentOffset, 0)
            if Int64(data.count) >= remaining {
                if remaining > 0 {
                    request.respond(with: data.prefix(Int(remaining)))
                }
                lock.withLock { pendingRequests.removeValue(forKey: dataTask) }
                loadingRequest.finishLoading()
                dataTask.cancel()
                return
            }
        }
        request.respond(with: data)
    }

    // MARK: - URLSessionTaskDelegate

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let loadingRequest = lock.withLock { () -> AVAssetResourceLoadingRequest? in
            let req = pendingRequests[task]
            pendingRequests.removeValue(forKey: task)
            return req
        }

        guard let loadingRequest = loadingRequest else { return }

        if let error = error as NSError?, error.code != NSURLErrorCancelled {
            logger.error("Resource loader task failed: \(error.localizedDescription, privacy: .public)")
            loadingRequest.finishLoading(with: error)
        } else {
            loadingRequest.finishLoading()
        }
    }
}

// MARK: - NSLock convenience
private extension NSLock {
    /// Execute `body` while holding this lock.
    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
