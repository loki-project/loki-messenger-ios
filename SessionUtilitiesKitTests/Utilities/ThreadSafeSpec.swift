// Copyright © 2024 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble

@testable import SessionUtilitiesKit

class ThreadSafeSpec: QuickSpec {
    override class func spec() {
        // MARK: - a ThreadSafeObject
        describe("a ThreadSafeObject") {
            // MARK: -- updates the stored value correctly
            it("updates the stored value correctly") {
                @ThreadSafeObject var value: Int = 0
                expect(value).to(equal(0))
                
                _value.performUpdate { _ in 1 }
                expect(value).to(equal(1))
            }
            
            // MARK: -- does not crash when doing a reentrant mutation
            it("does not crash when doing a reentrant mutation") {
                @ThreadSafeObject var value: Int = 0
                expect(value).to(equal(0))
                
                _value.performUpdate { _ in
                    _value.performUpdate { _ in 1 }
                    expect(value).to(equal(1))
                    
                    return 2
                }
                expect(value).to(equal(2))
            }
        }
    }
}
