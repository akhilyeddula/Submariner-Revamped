//
//  SBOperation.swift
//  Submariner
//
//  Created by Calvin Buckley on 2023-07-02.
//  Copyright © 2023 Submariner Developers. All rights reserved.
//

import Cocoa
import os

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SBOperation")

extension NSNotification.Name {
    static let SBSubsonicOperationStarted = NSNotification.Name("SBSubsonicOperationStarted")
    static let SBSubsonicOperationFinished = NSNotification.Name("SBSubsonicOperationFinished")
}

class SBOperation: Operation, ObservableObject, Identifiable, @unchecked Sendable {
    public let mainContext: NSManagedObjectContext
    public let threadedContext: NSManagedObjectContext
    
    init(managedObjectContext: NSManagedObjectContext, name: String, author: String? = nil) {
        self.mainContext = managedObjectContext
        self.threadedContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        // For automatic merging to work, seems we need to associate with the parent MOC,
        // rather than attaching to the persistent store coordinator.
        self.threadedContext.parent = managedObjectContext
        self.threadedContext.automaticallyMergesChangesFromParent = true
        self.threadedContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        self.threadedContext.retainsRegisteredObjects = true
        self.threadedContext.transactionAuthor = author
        
        super.init()
        
        self.name = name
        
        // We have to publish these ourselves to anyone interested, because OperationCenter.operations is deprecated and racy.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .SBSubsonicOperationStarted, object: self)
        }
    }
    
    // #MARK: - Metadata
    
    @Published var operationInfo: String = ""
    @Published var progress: Progress = .none
    
    enum Progress {
        case none
        case indeterminate(n: Float)
        case determinate(n: Float, outOf: Float)
    }
    
    // #MARK: - Concurrency
    
    private let stateLock = NSRecursiveLock()
    private var _isExecuting = false
    @objc dynamic override var isExecuting: Bool {
        stateLock.withLock { _isExecuting }
    }
    
    private var _isFinished = false
    private var isFinishing = false
    @objc dynamic override var isFinished: Bool {
        stateLock.withLock { _isFinished }
    }
    
    override var isAsynchronous: Bool { true }
    
    public override func start() {
        if isCancelled {
            finish()
            return
        }

        transitionToExecuting()
        threadedContext.perform { [weak self] in
            guard let self else { return }
            guard !self.isCancelled else {
                self.finish()
                return
            }
            self.main()
        }
    }
    
    public func finish() {
        let shouldFinish = stateLock.withLock { () -> Bool in
            guard !_isFinished, !isFinishing else { return false }
            isFinishing = true
            return true
        }
        guard shouldFinish else { return }

        let wasExecuting = isExecuting
        willChangeValue(forKey: "isFinished")
        if wasExecuting {
            willChangeValue(forKey: "isExecuting")
        }
        stateLock.withLock {
            _isExecuting = false
            _isFinished = true
            isFinishing = false
        }
        if wasExecuting {
            didChangeValue(forKey: "isExecuting")
        }
        didChangeValue(forKey: "isFinished")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .SBSubsonicOperationFinished, object: self)
        }
    }

    private func transitionToExecuting() {
        willChangeValue(forKey: "isExecuting")
        stateLock.withLock { _isExecuting = true }
        didChangeValue(forKey: "isExecuting")
    }

    // #MARK: - Core Data
    
    public func saveThreadedContext() {
        threadedContext.performAndWait {
            guard threadedContext.hasChanges else { return }
            logger.info("Changes to Core Data will be saved...")
            do {
                try threadedContext.save()
                try mainContext.performAndWait {
                    try mainContext.save()
                }
            } catch {
                logger.error("Failed to save: \(error, privacy: .public)")
            }
        }
    }
}

private extension NSRecursiveLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
