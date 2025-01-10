// Copyright © 2024 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public extension NSCache {
    @objc func settingObject(_ object: ObjectType, forKey key: KeyType) -> NSCache<KeyType, ObjectType> {
        setObject(object, forKey: key)
        return self
    }
}
