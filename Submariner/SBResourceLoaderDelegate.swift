import Foundation
import AVFoundation
import os.log

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "fr.read-write.Submariner", category: "SBResourceLoaderDelegate")

/// Intercepts AVPlayer's HTTP requests for remote Subsonic streams using a custom URL scheme
/// (sbhttp/sbhttps → http/https) and re-fetches them via URLSession.
///
/// This bypasses AVFoundation's strict network probing pipeline (which fails against
/// Subsonic's stream.view endpoint due to missing Content-Length/Accept-Ranges headers),
/// eliminating the nw_connection abort errors and dramatically reducing playback latency.
class SBResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate,
                                 URLSessionDataDelegate, URLSessionTaskDelegate,
                                 @unchecked Sendable {

    private let contentType: String

    /// Protects `pendingRequests`. Using an NSLock (not DispatchQueue) to allow synchronous
    /// access from multiple URLSession delegate callbacks without deadlock risk.
    private let lock = NSLock()
    private var pendingRequests: [URLSessionTask: AVAssetResourceLoadingRequest] = [:]

    /// A dedicated URLSession whose delegate is self. Created lazily so the URLSession
    /// doesn't exist until the first request arrives.
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600 // Allow up to 1 hour for long tracks/streams
        // delegateQueue nil → URLSession creates its own serial OperationQueue
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    init(contentType: String) {
        self.contentType = contentType
        super.init()
    }

    deinit {
        // Cancel all outstanding tasks and invalidate the session when we're released.
        // This is critical: without this, the URLSession retains a strong reference to
        // self via its delegate, creating a retain cycle that prevents deallocation.
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

        if let infoRequest = loadingRequest.contentInformationRequest {
            infoRequest.contentType = contentType
            
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
        loadingRequest?.dataRequest?.respond(with: data)
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
