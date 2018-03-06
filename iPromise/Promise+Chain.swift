//
//  Promise+Chain.swift
//  iPromise
//
//  Created by Elias Abel on 13/03/2017.
//  Copyright © 2017 Meniny Lab. All rights reserved.
//

import Foundation

public extension Promise {
    
    public func chain(_ block:@escaping (T) -> Void) -> Promise<T> {
        let p = newLinkedPromise()
        syncStateWithCallBacks(success: { t in
            block(t)
            p.fulfill(t)
        }, failure: p.reject, progress: p.setProgress)
        return p
    }
}