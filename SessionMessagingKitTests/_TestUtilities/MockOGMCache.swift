// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Combine
import SessionUtilitiesKit

@testable import SessionMessagingKit

class MockOGMCache: Mock<OGMCacheType>, OGMCacheType {
    var defaultRoomsPublisher: AnyPublisher<[OpenGroupManager.DefaultRoomInfo], Error>? {
        get { return mock() }
        set { mockNoReturn(args: [newValue]) }
    }
    
    var groupImagePublishers: [String: AnyPublisher<Data, Error>] {
        get { return mock() }
        set { mockNoReturn(args: [newValue]) }
    }
    
    var pollers: [String: OpenGroupAPI.Poller] {
        get { return mock() }
        set { mockNoReturn(args: [newValue]) }
    }
    
    var isPolling: Bool {
        get { return mock() }
        set { mockNoReturn(args: [newValue]) }
    }
    
    var hasPerformedInitialPoll: [String: Bool] {
        get { return mock() }
        set { mockNoReturn(args: [newValue]) }
    }
    
    var timeSinceLastPoll: [String: TimeInterval] {
        get { return mock() }
        set { mockNoReturn(args: [newValue]) }
    }
    
    var pendingChanges: [OpenGroupAPI.PendingChange] {
        get { return mock() }
        set { mockNoReturn(args: [newValue]) }
    }
    
    func getTimeSinceLastOpen(using dependencies: Dependencies) -> TimeInterval {
        return mock(args: [dependencies])
    }
}
