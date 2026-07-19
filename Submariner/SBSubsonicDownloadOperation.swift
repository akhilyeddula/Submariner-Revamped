//
//  SBSubsonicDownloadOperation.swift
//  Submariner
//

import Cocoa
import os

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SBSubsonicDownloadOperation")

@objc final class SBSubsonicDownloadOperation: SBOperation, URLSessionTaskDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    private let trackID: NSManagedObjectID
    private var destinationURL: URL?
    private var username: String?
    private var password: String?
    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private let byteCountFormatter = MeasurementFormatter()

    @objc init!(managedObjectContext mainContext: NSManagedObjectContext!, trackID: NSManagedObjectID) {
        self.trackID = trackID
        super.init(managedObjectContext: mainContext, name: "Downloading Track")
        operationInfo = "Pending Request..."
        progress = .none
    }

    override func main() {
        guard !isCancelled,
              let track = try? threadedContext.existingObject(with: trackID) as? SBTrack,
              let url = track.downloadURL(),
              let destinationURL = track.cachedFileURL else {
            finish()
            return
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            finish()
            return
        }

        self.destinationURL = destinationURL
        username = track.server?.username
        password = track.server?.password
        let trackName = track.itemName ?? "Track"
        DispatchQueue.main.async {
            self.name = "Downloading \(trackName)"
        }

        logger.info("Downloading track from \(url.host ?? "server", privacy: .public) via \(url.path, privacy: .public)")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let task = session.downloadTask(with: request)
        downloadTask = task
        task.resume()
    }

    override func cancel() {
        super.cancel()
        downloadTask?.cancel()
        session?.invalidateAndCancel()
        finish()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.previousFailureCount == 0 else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        if let username, let password {
            completionHandler(.useCredential, URLCredential(user: username, password: password, persistence: .none))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        if (error as NSError).code != NSURLErrorCancelled || !isCancelled {
            logger.error("Failure downloading track: \(error, privacy: .public)")
            DispatchQueue.main.async { NSApp.presentError(error) }
        }
        finish()
        session.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200...299).contains(response.statusCode),
              let destinationURL else {
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? NSURLErrorBadServerResponse
            let error = NSError(domain: NSURLErrorDomain, code: status,
                                userInfo: [NSLocalizedDescriptionKey: "The audio download failed with HTTP \(status)."])
            DispatchQueue.main.async { NSApp.presentError(error) }
            finish()
            session.invalidateAndCancel()
            return
        }

        if let mimeType = response.mimeType,
           mimeType.contains("xml") || mimeType.contains("json") || mimeType.contains("html") {
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotDecodeContentData,
                                userInfo: [NSLocalizedDescriptionKey: "The server returned \(mimeType) instead of audio."])
            DispatchQueue.main.async { NSApp.presentError(error) }
            finish()
            session.invalidateAndCancel()
            return
        }

        do {
            try FileManager.default.createDirectory(at: MediaCache.directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: location)
            } else {
                try FileManager.default.moveItem(at: location, to: destinationURL)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .SBTrackCacheUpdated, object: self.trackID)
            }
        } catch {
            logger.error("Unable to store downloaded track: \(error, privacy: .public)")
            DispatchQueue.main.async { NSApp.presentError(error) }
        }

        finish()
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let written = Measurement<UnitInformationStorage>(value: Double(totalBytesWritten), unit: .bytes).converted(to: .megabytes)
        DispatchQueue.main.async {
            if totalBytesExpectedToWrite != NSURLSessionTransferSizeUnknown {
                let expected = Measurement<UnitInformationStorage>(value: Double(totalBytesExpectedToWrite), unit: .bytes).converted(to: .megabytes)
                self.progress = .determinate(n: Float(totalBytesWritten), outOf: Float(totalBytesExpectedToWrite))
                self.operationInfo = "Downloaded \(self.byteCountFormatter.string(from: written))/\(self.byteCountFormatter.string(from: expected))"
            } else {
                self.progress = .indeterminate(n: Float(totalBytesWritten))
                self.operationInfo = "Downloaded \(self.byteCountFormatter.string(from: written))"
            }
        }
    }
}

extension Notification.Name {
    static let SBTrackCacheUpdated = Notification.Name("SBTrackCacheUpdatedNotification")
}
