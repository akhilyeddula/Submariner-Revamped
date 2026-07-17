import Foundation
import AVFoundation
import os.log

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "fr.read-write.Submariner", category: "SBResourceLoaderDelegate")

class SBResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate, @unchecked Sendable {
    private var session: URLSession!
    private var pendingRequests = [URLSessionTask: AVAssetResourceLoadingRequest]()
    private let contentType: String
    private let queue = DispatchQueue(label: "fr.read-write.Submariner.ResourceLoader")
    
    init(contentType: String) {
        self.contentType = contentType
        super.init()
        let config = URLSessionConfiguration.default
        // We use a serial queue to handle delegate callbacks cleanly
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        queue.async {
            guard let url = loadingRequest.request.url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return
            }
            
            // Restore original scheme
            var actualComponents = components
            if components.scheme == "sbhttp" {
                actualComponents.scheme = "http"
            } else if components.scheme == "sbhttps" {
                actualComponents.scheme = "https"
            } else {
                return
            }
            
            guard let actualURL = actualComponents.url else { return }
            
            var request = URLRequest(url: actualURL)
            
            // Forward range headers for seeking
            if let dataRequest = loadingRequest.dataRequest, dataRequest.requestsAllDataToEndOfResource == false {
                let rangeHeader = "bytes=\(dataRequest.requestedOffset)-\(dataRequest.requestedOffset + Int64(dataRequest.requestedLength) - 1)"
                request.setValue(rangeHeader, forHTTPHeaderField: "Range")
            } else if let dataRequest = loadingRequest.dataRequest, dataRequest.requestedOffset > 0 {
                let rangeHeader = "bytes=\(dataRequest.requestedOffset)-"
                request.setValue(rangeHeader, forHTTPHeaderField: "Range")
            }
            
            let task = self.session.dataTask(with: request)
            self.pendingRequests[task] = loadingRequest
            task.resume()
        }
        return true
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        queue.async {
            if let task = self.pendingRequests.first(where: { $0.value == loadingRequest })?.key {
                task.cancel()
                self.pendingRequests.removeValue(forKey: task)
            }
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        queue.async {
            guard let loadingRequest = self.pendingRequests[dataTask] else {
                completionHandler(.cancel)
                return
            }
            
            if let infoRequest = loadingRequest.contentInformationRequest {
                infoRequest.contentType = self.contentType
                infoRequest.isByteRangeAccessSupported = true
                
                // If it's a 206 Partial Content, expectedContentLength is just the chunk size,
                // but we need to parse Content-Range header for the real total length.
                var totalLength: Int64 = response.expectedContentLength
                if let httpResponse = response as? HTTPURLResponse,
                   let contentRange = httpResponse.allHeaderFields["Content-Range"] as? String {
                    // e.g., "bytes 21010-47021/47022"
                    if let rangeTotal = contentRange.split(separator: "/").last, let parsedTotal = Int64(rangeTotal) {
                        totalLength = parsedTotal
                    }
                }
                
                if totalLength > 0 {
                    infoRequest.contentLength = totalLength
                }
            }
            
            completionHandler(.allow)
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        queue.async {
            guard let loadingRequest = self.pendingRequests[dataTask] else { return }
            loadingRequest.dataRequest?.respond(with: data)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        queue.async {
            guard let loadingRequest = self.pendingRequests[task] else { return }
            
            if let error = error as NSError?, error.code != NSURLErrorCancelled {
                logger.error("Resource loader task failed with error: \(error.localizedDescription)")
                loadingRequest.finishLoading(with: error)
            } else {
                loadingRequest.finishLoading()
            }
            self.pendingRequests.removeValue(forKey: task)
        }
    }
}
