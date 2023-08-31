// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public enum SessionUtilError: Error {
    case unableToCreateConfigObject
    case invalidConfigObject
    case userDoesNotExist
    case getOrConstructFailedUnexpectedly
    case processingLoopLimitReached
}
