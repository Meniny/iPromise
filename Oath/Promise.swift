//
//  Promise.swift
//  Oath
//
//  Created by Elias Abel on 06/02/16.
//  Copyright © 2016 Bushtit Lab. All rights reserved.
//

import Foundation
import Dispatch

public class Promise<T> {
    
    internal var numberOfRetries: UInt = 0

    private let lockQueue = DispatchQueue(label: "cn.meniny.oath.lockQueue", qos: .userInitiated)
    
    private var threadUnsafeState: PromiseState<T>
    internal var state: PromiseState<T> {
        get {
            return lockQueue.sync { return threadUnsafeState }
        }
        set {
            lockQueue.sync { threadUnsafeState = newValue }
        }
    }
    
    private var threadUnsafeBlocks: PromiseBlocks<T> = PromiseBlocks<T>()
    internal var blocks: PromiseBlocks<T> {
        get {
            return lockQueue.sync { return threadUnsafeBlocks }
        }
        set {
            lockQueue.sync { threadUnsafeBlocks = newValue }
        }
    }

    private var initialPromiseStart:(() -> Void)?
    private var initialPromiseStarted = false
    internal var promiseProgressCallBack: ((_ resolve: @escaping ((T) -> Void),
    _ reject: @escaping ((Error) -> Void),
    _ progress: @escaping ((Float) -> Void)) -> Void)?
    
    public init() {
        threadUnsafeState = .dormant
    }
    
    public init(value: T) {
        threadUnsafeState = .fulfilled(value: value)
    }
    
    public init(error: Error) {
        threadUnsafeState = PromiseState.rejected(error: error)
    }
    
    public typealias GenericClosure = (T) -> Void
    public typealias ErrorClosure = (Error) -> Void
    public typealias ProgressClosure = (Float) -> Void
    public typealias CallbackClosure = (_ resolve: @escaping GenericClosure, _ reject: @escaping ErrorClosure) -> Void
    public typealias ProgressCallbackClosure = (_ resolve: @escaping GenericClosure, _ reject: @escaping ErrorClosure, _ progress: @escaping ProgressClosure) -> Void

    public convenience init(callback: @escaping CallbackClosure) {
        self.init()
        promiseProgressCallBack = { resolve, reject, progress in
            callback({ [weak self] t in
                self?.fulfill(t)
            }, { [weak self ] e in
                self?.reject(e)
            })
        }
    }
    
    public convenience init(callback: @escaping ProgressCallbackClosure) {
        self.init()
        promiseProgressCallBack = { resolve, reject, progress in
            callback(self.fulfill, self.reject, self.setProgress)
        }
    }
    
    internal func resetState() {
        state = .dormant
    }
    
    public func start() {
        if state.isDormant {
            updateState(PromiseState<T>.pending(progress: 0))
            if let p = promiseProgressCallBack {
                p(fulfill, reject, setProgress)
            }
//            promiseProgressCallBack = nil //Remove callba
        }
    }
    
    internal func passAlongFirstPromiseStartFunctionAndStateTo<X>(_ promise: Promise<X>) {
        // Pass along First promise start block
        if let startBlock = self.initialPromiseStart {
            promise.initialPromiseStart = startBlock
        } else {
            promise.initialPromiseStart = self.start
        }
        // Pass along initil promise start state.
        promise.initialPromiseStarted = self.initialPromiseStarted
    }

    internal func tryStartInitialPromiseAndStartIfneeded() {
        if !initialPromiseStarted {
            initialPromiseStart?()
            initialPromiseStarted = true
        }
        if !isStarted {
            start()
        }
    }
    
    public func fulfill(_ value: T) {
        updateState(PromiseState<T>.fulfilled(value: value))
        blocks = PromiseBlocks<T>()
        promiseProgressCallBack = nil
    }
    
    public func reject(_ anError: Error) {
        updateState(PromiseState<T>.rejected(error: anError))
        // Only release callbacks if no retries a registered.
        if numberOfRetries == 0 {
            blocks = PromiseBlocks<T>()
            promiseProgressCallBack = nil
        }
    }
    
    internal func updateState(_ newState: PromiseState<T>) {
        if state.isPendingOrDormant {
            state = newState
        }
        launchCallbacksIfNeeded()
    }
    
    private func launchCallbacksIfNeeded() {
        switch state {
        case .dormant:
            break
        case .pending(let progress):
            if progress != 0 {
                for pb in blocks.progress {
                    pb(progress)
                }
            }
        case .fulfilled(let value):
            for sb in blocks.success {
                sb(value)
            }
            for fb in blocks.finally {
                fb()
            }
            initialPromiseStart = nil
        case .rejected(let anError):
            for fb in blocks.fail {
                fb(anError)
            }
            for fb in blocks.finally {
                fb()
            }
            initialPromiseStart = nil
        }
    }
    
    internal func newLinkedPromise() -> Promise<T> {
        let p = Promise<T>()
        passAlongFirstPromiseStartFunctionAndStateTo(p)
        return p
    }
    
    internal func syncStateWithCallBacks(success: @escaping ((T) -> Void),
                                         failure: @escaping ((Error) -> Void),
                                         progress: @escaping ((Float) -> Void)) {
        switch state {
        case let .fulfilled(value):
            success(value)
        case let .rejected(error):
            failure(error)
        case .dormant, .pending:
            blocks.success.append(success)
            blocks.fail.append(failure)
            blocks.progress.append(progress)
        }
    }
}

// Helpers
extension Promise {
    
    var isStarted: Bool {
        switch state {
        case .dormant:
            return false
        default:
            return true
        }
    }
}
