/// Copyright © 2024 Rangeproof Pty Ltd. All rights reserved.
///
/// The below classes are an evolution of the old `Atomic<T>` types that we had implemented. A write-up on the need for
/// the old class and it's approaches can be found at these links:
/// https://www.vadimbulavin.com/atomic-properties/
/// https://www.vadimbulavin.com/swift-atomic-properties-with-property-wrappers/
///
/// We use the `ReadWriteLock` approach because the `DispatchQueue` approach means mutating the property
/// occurs on a different thread, and `GRDB` requires it's changes to be executed on specific threads so using a lock
/// is more compatible (and the `ReadWriteLock` allows for concurrent reads which shouldn't be a huge issue but could
/// help reduce cases of blocking)

import Foundation

// MARK: - ThreadSafe

/// `ThreadSafe<Value>` is a wrapper providing a thread-safe way to get and set a value, it's limited to types which are marked
/// as `ThreadSafeType` (reference types or structs which have `mutating` functions **should not** use this mechanism
/// as it cannot ensure thread safety for those types)
@propertyWrapper
public class ThreadSafe<Value: ThreadSafeType> {
    private var value: Value
    private let lock: ReadWriteLock = ReadWriteLock()

    public var wrappedValue: Value {
        get {
            lock.readLock()
            let result: Value = value
            lock.unlock()
            
            return result
        }
        set {
            lock.writeLock()
            self.value = newValue
            lock.unlock()
        }
    }
    
    // MARK: - Initialization

    public init(wrappedValue: Value) {
        self.value = wrappedValue
    }
    
    public init(_ wrappedValue: Value) {
        self.value = wrappedValue
    }
    
    // MARK: - Functions

    public func performUpdateAndMap<T>(_ closure: (Value) -> (Value, T)) -> T {
        return try! performInternal { closure($0) }
    }
    
    public func performUpdateAndMap<T>(_ closure: (Value) throws -> (Value, T)) throws -> T {
        return try performInternal { try closure($0) }
    }
    
    // MARK: - Internal Functions
    
    @discardableResult private func performInternal<T>(_ mutation: (Value) throws -> (Value, T)) throws -> T {
        lock.writeLock()
        defer { lock.unlock() }
        
        let (updatedValue, result) = try mutation(value)
        self.value = updatedValue
        return result
    }
}

/// `ThreadSafeObject` is an implementation of `ThreadSafe` specifically for reference types, it avoids using `inout` within
/// the `mutate` function (which can only really be done safely for reference types) and also supports reentrant access (ie. if we are
/// already in a mutation on the current thread then there is no need to acquire another lock, just interact with the value directly)
///
/// **Note:** There is some potential for confusing behaviour when using this type in a reentrant way - if the object is entirely replaced
/// than previous instances provided in the closures won't be updated with the new instance (this is more problemmatic for mutating structs
/// rather than objects as their isntances get replaced, there are critical logs for these cases)
@propertyWrapper
public final class ThreadSafeObject<Value> {
    private var value: Value
    private let lock: ReadWriteLock = ReadWriteLock()
    @ThreadSafe private var mutationThreadId: UInt32? = nil

    public var wrappedValue: Value {
        guard mutationThreadId != Thread.current.threadId else { return value }
        
        lock.readLock()
        defer { lock.unlock() }
        return value
    }
    
    // MARK: - Initialization

    public init(wrappedValue: Value) {
        self.value = wrappedValue
    }
    
    public init(_ wrappedValue: Value) {
        self.value = wrappedValue
    }
    
    // MARK: - Functions
    
    /// Replace the current value with an updated one
    public func set(to value: Value) {
        guard mutationThreadId != Thread.current.threadId else {
            if Value.self is any Collection || Value.self is DictionaryType.Type {
                Log.critical("ThreadSafeObject<\(Value.self)>.set(to:) called while in mutation, this could result in buggy behaviours")
            }
            
            self.value = value
            return
        }
        
        lock.writeLock()
        self.value = value
        lock.unlock()
    }
    
    public func perform(_ closure: (Value) -> ()) {
        try? performInternal { value in
            closure(value)
            return (value, ())
        }
    }
    
    public func perform(_ closure: (Value) throws -> ()) throws {
        try performInternal { value in
            try closure(value)
            return (value, ())
        }
    }
    
    public func performUpdate(_ closure: (Value) -> Value) {
        try? performInternal { (closure($0), ()) }
    }
    
    public func performUpdate(_ closure: (Value) throws -> Value) throws {
        try performInternal { (try closure($0), ()) }
    }

    public func performMap<T>(_ closure: (Value) -> T) -> T {
        return try! performInternal { ($0, closure($0)) }
    }
    
    public func performMap<T>(_ closure: (Value) throws -> T) throws -> T {
        return try performInternal { ($0, try closure($0)) }
    }
    
    public func performUpdateAndMap<T>(_ closure: (Value) -> (Value, T)) -> T {
        return try! performInternal { closure($0) }
    }
    
    public func performUpdateAndMap<T>(_ closure: (Value) throws -> (Value, T)) throws -> T {
        return try performInternal { try closure($0) }
    }
    
    // MARK: - Internal Functions
    
    @discardableResult private func performInternal<T>(_ mutation: (Value) throws -> (Value, T)) throws -> T {
        guard mutationThreadId != Thread.current.threadId else {
            if Value.self is any Collection || Value.self is DictionaryType.Type {
                Log.critical("ThreadSafeObject<\(Value.self)> called in a reentrant way while in mutation, this could result in buggy behaviours")
            }
            
            let (updatedValue, result) = try mutation(value)
            self.value = updatedValue
            return result
        }
        
        lock.writeLock()
        mutationThreadId = Thread.current.threadId
        defer {
            mutationThreadId = nil
            lock.unlock()
        }
        
        let (updatedValue, result) = try mutation(value)
        self.value = updatedValue
        return result
    }
}

// MARK: - ReadWriteLock

class ReadWriteLock {
    private var rwlock: pthread_rwlock_t
    
    // Need to do this in a proper init function instead of a lazy variable or it can indefinitely
    // hang on XCode 15 when trying to retrieve a lock (potentially due to optimisations?)
    init() {
        rwlock = pthread_rwlock_t()
        pthread_rwlock_init(&rwlock, nil)
    }
    
    func writeLock() {
        pthread_rwlock_wrlock(&rwlock)
    }
    
    func readLock() {
        pthread_rwlock_rdlock(&rwlock)
    }
    
    func unlock() {
        pthread_rwlock_unlock(&rwlock)
    }
}

// MARK: - ThreadSafeType

/// The `ThreadSafe` type doesn't work with mutating function so we want to constrain it to "safe" types
public protocol ThreadSafeType {}
extension Int: ThreadSafeType {}
extension Int8: ThreadSafeType {}
extension Int16: ThreadSafeType {}
extension Int32: ThreadSafeType {}
extension Int64: ThreadSafeType {}
extension UInt8: ThreadSafeType {}
extension UInt16: ThreadSafeType {}
extension UInt32: ThreadSafeType {}
extension UInt64: ThreadSafeType {}
extension Bool: ThreadSafeType {}
extension Double: ThreadSafeType {}
extension Date: ThreadSafeType {}
extension UUID: ThreadSafeType {}
extension Optional: ThreadSafeType where Wrapped: ThreadSafeType {}

@available(*, unavailable, message: "Use ThreadSafeObject instead")
extension Array: ThreadSafeType {}
@available(*, unavailable, message: "Use ThreadSafeObject instead")
extension Set: ThreadSafeType {}
@available(*, unavailable, message: "Use ThreadSafeObject instead")
extension Dictionary: ThreadSafeType {}

// MARK: - CustomDebugStringConvertible

extension ThreadSafe: CustomDebugStringConvertible where Value: CustomDebugStringConvertible {
    public var debugDescription: String {
        return wrappedValue.debugDescription
    }
}

extension ThreadSafeObject: CustomDebugStringConvertible where Value: CustomDebugStringConvertible {
    public var debugDescription: String {
        return wrappedValue.debugDescription
    }
}

// MARK: - Convenience

private extension Thread {
    var threadId: UInt32 {
        pthread_mach_thread_np(pthread_self())
    }
}
