// Copyright © 2023 Rangeproof Pty Ltd. All rights reserved.
//
// stringlint:disable

import Foundation

// MARK: - String

public extension String {    
    /// Initialize with an optional pointer and a specific length
    init?(pointer: UnsafeRawPointer?, length: Int, encoding: String.Encoding = .utf8) {
        guard
            let pointer: UnsafeRawPointer = pointer,
            let result: String = String(data: Data(bytes: pointer, count: length), encoding: encoding)
        else { return nil }
        
        self = result
    }
}

// MARK: - Array

public extension Array where Element == String {
    init?(pointer: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?, count: Int?) {
        self.init(pointee: pointer.map { $0.pointee.map { UnsafePointer($0) } }, count: count)
    }
    
    init?(pointer: UnsafeMutablePointer<UnsafePointer<CChar>?>?, count: Int?) {
        self.init(pointee: pointer.map { $0.pointee }, count: count)
    }
    
    init(
        pointer: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
        count: Int?,
        defaultValue: [String]
    ) {
        self = ([String](pointer: pointer, count: count) ?? defaultValue)
    }
    
    init(
        pointer: UnsafeMutablePointer<UnsafePointer<CChar>?>?,
        count: Int?,
        defaultValue: [String]
    ) {
        self = ([String](pointer: pointer, count: count) ?? defaultValue)
    }
    
    init?(
        pointee: UnsafePointer<CChar>?,
        count: Int?
    ) {
        guard
            let count: Int = count,
            let pointee: UnsafePointer<CChar> = pointee
        else { return nil }
        
        // If we were given a count but it's 0 then trying to access the pointer could
        // crash (as it could be bad memory) so just return an empty array
        guard count > 0 else {
            self = []
            return
        }
        
        self = (0..<count).reduce(into: []) { result, index in
            /// We need to calculate the start position of each of the hashes in memory which will
            /// be at the end of the previous hash plus one (due to the null termination character
            /// which isn't included in Swift strings so isn't included in `count`)
            let prevLength: Int = (result.isEmpty ? 0 :
                result.map { ($0.count + 1) }.reduce(0, +)
            )
            
            result.append(String(cString: pointee.advanced(by: prevLength)))
        }
    }
}


// MARK: - CAccessible

public protocol CAccessible {
    // General types
    
    func get<T>(_ keyPath: KeyPath<Self, T>) -> T
    
    // String variants
    
    func get(_ keyPath: KeyPath<Self, CChar65>) -> String
    func get(_ keyPath: KeyPath<Self, CChar67>) -> String
    func get(_ keyPath: KeyPath<Self, CChar101>) -> String
    func get(_ keyPath: KeyPath<Self, CChar224>) -> String
    func get(_ keyPath: KeyPath<Self, CChar268>) -> String
    
    func get(_ keyPath: KeyPath<Self, CChar65>, nullIfEmpty: Bool) -> String?
    func get(_ keyPath: KeyPath<Self, CChar67>, nullIfEmpty: Bool) -> String?
    func get(_ keyPath: KeyPath<Self, CChar101>, nullIfEmpty: Bool) -> String?
    func get(_ keyPath: KeyPath<Self, CChar224>, nullIfEmpty: Bool) -> String?
    func get(_ keyPath: KeyPath<Self, CChar268>, nullIfEmpty: Bool) -> String?
    
    // Data variants
    
    func get(_ keyPath: KeyPath<Self, CUChar32>) -> Data
    func get(_ keyPath: KeyPath<Self, CUChar32>) -> [UInt8]
    func getHex(_ keyPath: KeyPath<Self, CUChar32>) -> String
    func get(_ keyPath: KeyPath<Self, CUChar64>) -> Data
    func get(_ keyPath: KeyPath<Self, CUChar64>) -> [UInt8]
    func getHex(_ keyPath: KeyPath<Self, CUChar64>) -> String
    func get(_ keyPath: KeyPath<Self, CUChar100>) -> Data
    func get(_ keyPath: KeyPath<Self, CUChar100>) -> [UInt8]
    func getHex(_ keyPath: KeyPath<Self, CUChar100>) -> String
    
    func get(_ keyPath: KeyPath<Self, CUChar32>, nullIfEmpty: Bool) -> Data?
    func get(_ keyPath: KeyPath<Self, CUChar32>, nullIfEmpty: Bool) -> [UInt8]?
    func getHex(_ keyPath: KeyPath<Self, CUChar32>, nullIfEmpty: Bool) -> String?
    func get(_ keyPath: KeyPath<Self, CUChar64>, nullIfEmpty: Bool) -> Data?
    func get(_ keyPath: KeyPath<Self, CUChar64>, nullIfEmpty: Bool) -> [UInt8]?
    func getHex(_ keyPath: KeyPath<Self, CUChar64>, nullIfEmpty: Bool) -> String?
    func get(_ keyPath: KeyPath<Self, CUChar100>, nullIfEmpty: Bool) -> Data?
    func get(_ keyPath: KeyPath<Self, CUChar100>, nullIfEmpty: Bool) -> [UInt8]?
    func getHex(_ keyPath: KeyPath<Self, CUChar100>, nullIfEmpty: Bool) -> String?
}

public extension CAccessible {
    // General types
    
    func get<T>(_ keyPath: KeyPath<Self, T>) -> T { withUnsafePointer(to: self) { $0.get(keyPath) } }
    
    // String variants
    
    func get(_ keyPath: KeyPath<Self, CChar65>) -> String { withUnsafePointer(to: self) { $0.get(keyPath) } }
    func get(_ keyPath: KeyPath<Self, CChar67>) -> String { withUnsafePointer(to: self) { $0.get(keyPath) } }
    func get(_ keyPath: KeyPath<Self, CChar101>) -> String { withUnsafePointer(to: self) { $0.get(keyPath) } }
    func get(_ keyPath: KeyPath<Self, CChar224>) -> String { withUnsafePointer(to: self) { $0.get(keyPath) } }
    func get(_ keyPath: KeyPath<Self, CChar268>) -> String { withUnsafePointer(to: self) { $0.get(keyPath) } }
    
    func get(_ keyPath: KeyPath<Self, CChar65>, nullIfEmpty: Bool = false) -> String? {
        withUnsafePointer(to: self) { $0.get(keyPath, nullIfEmpty: nullIfEmpty) }
    }
    func get(_ keyPath: KeyPath<Self, CChar67>, nullIfEmpty: Bool = false) -> String? {
        withUnsafePointer(to: self) { $0.get(keyPath, nullIfEmpty: nullIfEmpty) }
    }
    func get(_ keyPath: KeyPath<Self, CChar101>, nullIfEmpty: Bool = false) -> String? {
        withUnsafePointer(to: self) { $0.get(keyPath, nullIfEmpty: nullIfEmpty) }
    }
    func get(_ keyPath: KeyPath<Self, CChar224>, nullIfEmpty: Bool = false) -> String? {
        withUnsafePointer(to: self) { $0.get(keyPath, nullIfEmpty: nullIfEmpty) }
    }
    func get(_ keyPath: KeyPath<Self, CChar268>, nullIfEmpty: Bool = false) -> String? {
        withUnsafePointer(to: self) { $0.get(keyPath, nullIfEmpty: nullIfEmpty) }
    }
    
    // Data variants
    
    func get(_ keyPath: KeyPath<Self, CUChar32>) -> Data { withUnsafePointer(to: self) { $0.get(keyPath) } }
    func get(_ keyPath: KeyPath<Self, CUChar32>) -> [UInt8] { withUnsafePointer(to: self) { $0.get(keyPath) } }
    func getHex(_ keyPath: KeyPath<Self, CUChar32>) -> String { withUnsafePointer(to: self) { $0.getHex(keyPath) } }
    func get(_ keyPath: KeyPath<Self, CUChar64>) -> Data { withUnsafePointer(to: self) { $0.get(keyPath) } }
    func get(_ keyPath: KeyPath<Self, CUChar64>) -> [UInt8] { withUnsafePointer(to: self) { $0.get(keyPath) } }
    func getHex(_ keyPath: KeyPath<Self, CUChar64>) -> String { withUnsafePointer(to: self) { $0.getHex(keyPath) } }
    func get(_ keyPath: KeyPath<Self, CUChar100>) -> Data { withUnsafePointer(to: self) { $0.get(keyPath) } }
    func get(_ keyPath: KeyPath<Self, CUChar100>) -> [UInt8] { withUnsafePointer(to: self) { $0.get(keyPath) } }
    func getHex(_ keyPath: KeyPath<Self, CUChar100>) -> String { withUnsafePointer(to: self) { $0.getHex(keyPath) } }
    
    func get(_ keyPath: KeyPath<Self, CUChar32>, nullIfEmpty: Bool = false) -> Data? {
        withUnsafePointer(to: self) { $0.get(keyPath, nullIfEmpty: nullIfEmpty) }
    }
    func get(_ keyPath: KeyPath<Self, CUChar32>, nullIfEmpty: Bool = false) -> [UInt8]? {
        withUnsafePointer(to: self) { $0.get(keyPath, nullIfEmpty: nullIfEmpty) }
    }
    func getHex(_ keyPath: KeyPath<Self, CUChar32>, nullIfEmpty: Bool = false) -> String? {
        withUnsafePointer(to: self) { $0.getHex(keyPath, nullIfEmpty: nullIfEmpty) }
    }
    func get(_ keyPath: KeyPath<Self, CUChar64>, nullIfEmpty: Bool = false) -> Data? {
        withUnsafePointer(to: self) { $0.get(keyPath, nullIfEmpty: nullIfEmpty) }
    }
    func get(_ keyPath: KeyPath<Self, CUChar64>, nullIfEmpty: Bool = false) -> [UInt8]? {
        withUnsafePointer(to: self) { $0.get(keyPath, nullIfEmpty: nullIfEmpty) }
    }
    func getHex(_ keyPath: KeyPath<Self, CUChar64>, nullIfEmpty: Bool = false) -> String? {
        withUnsafePointer(to: self) { $0.getHex(keyPath, nullIfEmpty: nullIfEmpty) }
    }
    func get(_ keyPath: KeyPath<Self, CUChar100>, nullIfEmpty: Bool = false) -> Data? {
        withUnsafePointer(to: self) { $0.get(keyPath, nullIfEmpty: nullIfEmpty) }
    }
    func get(_ keyPath: KeyPath<Self, CUChar100>, nullIfEmpty: Bool = false) -> [UInt8]? {
        withUnsafePointer(to: self) { $0.get(keyPath, nullIfEmpty: nullIfEmpty) }
    }
    func getHex(_ keyPath: KeyPath<Self, CUChar100>, nullIfEmpty: Bool = false) -> String? {
        withUnsafePointer(to: self) { $0.getHex(keyPath, nullIfEmpty: nullIfEmpty) }
    }
}

// MARK: - CMutable

public protocol CMutable {
    // General types
    
    mutating func set<T>(_ keyPath: WritableKeyPath<Self, T>, to value: T)
    
    // String variants
    
    mutating func set(_ keyPath: WritableKeyPath<Self, CChar65>, to value: String?)
    mutating func set(_ keyPath: WritableKeyPath<Self, CChar67>, to value: String?)
    mutating func set(_ keyPath: WritableKeyPath<Self, CChar101>, to value: String?)
    mutating func set(_ keyPath: WritableKeyPath<Self, CChar224>, to value: String?)
    mutating func set(_ keyPath: WritableKeyPath<Self, CChar268>, to value: String?)
    
    // Data variants
    
    mutating func set<T: DataProtocol>(_ keyPath: WritableKeyPath<Self, CUChar32>, to value: T?)
    mutating func set<T: DataProtocol>(_ keyPath: WritableKeyPath<Self, CUChar64>, to value: T?)
    mutating func set<T: DataProtocol>(_ keyPath: WritableKeyPath<Self, CUChar100>, to value: T?)
}

public extension CMutable {
    // General types
    
    mutating func set<T>(_ keyPath: WritableKeyPath<Self, T>, to value: T) {
        withUnsafeMutablePointer(to: &self) { $0.set(keyPath, to: value) }
    }
    
    // Data variants
    
    mutating func set<T: DataProtocol>(_ keyPath: WritableKeyPath<Self, CUChar32>, to value: T?) {
        withUnsafeMutablePointer(to: &self) { $0.set(keyPath, to: value) }
    }
    
    mutating func set<T: DataProtocol>(_ keyPath: WritableKeyPath<Self, CUChar64>, to value: T?) {
        withUnsafeMutablePointer(to: &self) { $0.set(keyPath, to: value) }
    }
    
    mutating func set<T: DataProtocol>(_ keyPath: WritableKeyPath<Self, CUChar100>, to value: T?) {
        withUnsafeMutablePointer(to: &self) { $0.set(keyPath, to: value) }
    }
    
    // String variants
    
    mutating func set(_ keyPath: WritableKeyPath<Self, CChar65>, to value: String?) {
        withUnsafeMutablePointer(to: &self) { $0.set(keyPath, to: value) }
    }
    
    mutating func set(_ keyPath: WritableKeyPath<Self, CChar67>, to value: String?) {
        withUnsafeMutablePointer(to: &self) { $0.set(keyPath, to: value) }
    }
    
    mutating func set(_ keyPath: WritableKeyPath<Self, CChar101>, to value: String?) {
        withUnsafeMutablePointer(to: &self) { $0.set(keyPath, to: value) }
    }
    
    mutating func set(_ keyPath: WritableKeyPath<Self, CChar224>, to value: String?) {
        withUnsafeMutablePointer(to: &self) { $0.set(keyPath, to: value) }
    }
    
    mutating func set(_ keyPath: WritableKeyPath<Self, CChar268>, to value: String?) {
        withUnsafeMutablePointer(to: &self) { $0.set(keyPath, to: value) }
    }
}

// MARK: - Pointer Convenience

public extension UnsafeMutablePointer {
    // General types
    
    func get<T>(_ keyPath: KeyPath<Pointee, T>) -> T { UnsafePointer(self).get(keyPath) }
    
    // String variants
    
    func get(_ keyPath: KeyPath<Pointee, CChar65>) -> String { UnsafePointer(self).get(keyPath) }
    func get(_ keyPath: KeyPath<Pointee, CChar67>) -> String { UnsafePointer(self).get(keyPath) }
    func get(_ keyPath: KeyPath<Pointee, CChar101>) -> String { UnsafePointer(self).get(keyPath) }
    func get(_ keyPath: KeyPath<Pointee, CChar224>) -> String { UnsafePointer(self).get(keyPath) }
    func get(_ keyPath: KeyPath<Pointee, CChar268>) -> String { UnsafePointer(self).get(keyPath) }
    
    func get(_ keyPath: KeyPath<Pointee, CChar65>, nullIfEmpty: Bool = false) -> String? {
        UnsafePointer(self).get(keyPath, nullIfEmpty: nullIfEmpty)
    }
    func get(_ keyPath: KeyPath<Pointee, CChar67>, nullIfEmpty: Bool = false) -> String? {
        UnsafePointer(self).get(keyPath, nullIfEmpty: nullIfEmpty)
    }
    func get(_ keyPath: KeyPath<Pointee, CChar101>, nullIfEmpty: Bool = false) -> String? {
        UnsafePointer(self).get(keyPath, nullIfEmpty: nullIfEmpty)
    }
    func get(_ keyPath: KeyPath<Pointee, CChar224>, nullIfEmpty: Bool = false) -> String? {
        UnsafePointer(self).get(keyPath, nullIfEmpty: nullIfEmpty)
    }
    func get(_ keyPath: KeyPath<Pointee, CChar268>, nullIfEmpty: Bool = false) -> String? {
        UnsafePointer(self).get(keyPath, nullIfEmpty: nullIfEmpty)
    }
    
    // Data variants
    
    func get(_ keyPath: KeyPath<Pointee, CUChar32>) -> Data { UnsafePointer(self).get(keyPath) }
    func get(_ keyPath: KeyPath<Pointee, CUChar32>) -> [UInt8] { UnsafePointer(self).get(keyPath) }
    func getHex(_ keyPath: KeyPath<Pointee, CUChar32>) -> String { UnsafePointer(self).getHex(keyPath) }
    func get(_ keyPath: KeyPath<Pointee, CUChar64>) -> Data { UnsafePointer(self).get(keyPath) }
    func get(_ keyPath: KeyPath<Pointee, CUChar64>) -> [UInt8] { UnsafePointer(self).get(keyPath) }
    func getHex(_ keyPath: KeyPath<Pointee, CUChar64>) -> String { UnsafePointer(self).getHex(keyPath) }
    func get(_ keyPath: KeyPath<Pointee, CUChar100>) -> Data { UnsafePointer(self).get(keyPath) }
    func get(_ keyPath: KeyPath<Pointee, CUChar100>) -> [UInt8] { UnsafePointer(self).get(keyPath) }
    func getHex(_ keyPath: KeyPath<Pointee, CUChar100>) -> String { UnsafePointer(self).getHex(keyPath) }
    
    func get(_ keyPath: KeyPath<Pointee, CUChar32>, nullIfEmpty: Bool = false) -> Data? {
        UnsafePointer(self).get(keyPath, nullIfEmpty: nullIfEmpty)
    }
    func get(_ keyPath: KeyPath<Pointee, CUChar32>, nullIfEmpty: Bool = false) -> [UInt8]? {
        UnsafePointer(self).get(keyPath, nullIfEmpty: nullIfEmpty)
    }
    func getHex(_ keyPath: KeyPath<Pointee, CUChar32>, nullIfEmpty: Bool = false) -> String? {
        UnsafePointer(self).getHex(keyPath, nullIfEmpty: nullIfEmpty)
    }
    func get(_ keyPath: KeyPath<Pointee, CUChar64>, nullIfEmpty: Bool = false) -> Data? {
        UnsafePointer(self).get(keyPath, nullIfEmpty: nullIfEmpty)
    }
    func get(_ keyPath: KeyPath<Pointee, CUChar64>, nullIfEmpty: Bool = false) -> [UInt8]? {
        UnsafePointer(self).get(keyPath, nullIfEmpty: nullIfEmpty)
    }
    func getHex(_ keyPath: KeyPath<Pointee, CUChar64>, nullIfEmpty: Bool = false) -> String? {
        UnsafePointer(self).getHex(keyPath, nullIfEmpty: nullIfEmpty)
    }
    func get(_ keyPath: KeyPath<Pointee, CUChar100>, nullIfEmpty: Bool = false) -> Data? {
        UnsafePointer(self).get(keyPath, nullIfEmpty: nullIfEmpty)
    }
    func get(_ keyPath: KeyPath<Pointee, CUChar100>, nullIfEmpty: Bool = false) -> [UInt8]? {
        UnsafePointer(self).get(keyPath, nullIfEmpty: nullIfEmpty)
    }
    func getHex(_ keyPath: KeyPath<Pointee, CUChar100>, nullIfEmpty: Bool = false) -> String? {
        UnsafePointer(self).getHex(keyPath, nullIfEmpty: nullIfEmpty)
    }
}

public extension UnsafeMutablePointer {
    // General types
    
    func set<T>(_ keyPath: WritableKeyPath<Pointee, T>, to value: T) { pointee[keyPath: keyPath] = value }
    
    // String variants
    
    func set(_ keyPath: WritableKeyPath<Pointee, CChar65>, to value: String?) { setCString(keyPath, value, maxLength: 65) }
    func set(_ keyPath: WritableKeyPath<Pointee, CChar67>, to value: String?) { setCString(keyPath, value, maxLength: 67) }
    func set(_ keyPath: WritableKeyPath<Pointee, CChar101>, to value: String?) { setCString(keyPath, value, maxLength: 101) }
    func set(_ keyPath: WritableKeyPath<Pointee, CChar224>, to value: String?) { setCString(keyPath, value, maxLength: 224) }
    func set(_ keyPath: WritableKeyPath<Pointee, CChar268>, to value: String?) { setCString(keyPath, value, maxLength: 268) }
    
    // Data variants
    
    func set<T: DataProtocol>(_ keyPath: WritableKeyPath<Pointee, CUChar32>, to value: T?) {
        setData(keyPath, value.map { Data($0) }, length: 32)
    }
    
    func set<T: DataProtocol>(_ keyPath: WritableKeyPath<Pointee, CUChar64>, to value: T?) {
        setData(keyPath, value.map { Data($0) }, length: 64)
    }
    
    func set<T: DataProtocol>(_ keyPath: WritableKeyPath<Pointee, CUChar100>, to value: T?) {
        setData(keyPath, value.map { Data($0) }, length: 100)
    }
}

public extension UnsafePointer {
    // General types
    
    func get<T>(_ keyPath: KeyPath<Pointee, T>) -> T { pointee[keyPath: keyPath] }
    
    // String variants
    
    func get(_ keyPath: KeyPath<Pointee, CChar65>) -> String { getCString(keyPath, maxLength: 65) }
    func get(_ keyPath: KeyPath<Pointee, CChar67>) -> String { getCString(keyPath, maxLength: 67) }
    func get(_ keyPath: KeyPath<Pointee, CChar101>) -> String { getCString(keyPath, maxLength: 101) }
    func get(_ keyPath: KeyPath<Pointee, CChar224>) -> String { getCString(keyPath, maxLength: 224) }
    func get(_ keyPath: KeyPath<Pointee, CChar268>) -> String { getCString(keyPath, maxLength: 268) }
    
    func get(_ keyPath: KeyPath<Pointee, CChar65>, nullIfEmpty: Bool = false) -> String? {
        getCString(keyPath, maxLength: 65, nullIfEmpty: nullIfEmpty)
    }
    func get(_ keyPath: KeyPath<Pointee, CChar67>, nullIfEmpty: Bool = false) -> String? {
        getCString(keyPath, maxLength: 67, nullIfEmpty: nullIfEmpty)
    }
    func get(_ keyPath: KeyPath<Pointee, CChar101>, nullIfEmpty: Bool = false) -> String? {
        getCString(keyPath, maxLength: 101, nullIfEmpty: nullIfEmpty)
    }
    func get(_ keyPath: KeyPath<Pointee, CChar224>, nullIfEmpty: Bool = false) -> String? {
        getCString(keyPath, maxLength: 224, nullIfEmpty: nullIfEmpty)
    }
    func get(_ keyPath: KeyPath<Pointee, CChar268>, nullIfEmpty: Bool = false) -> String? {
        getCString(keyPath, maxLength: 268, nullIfEmpty: nullIfEmpty)
    }
    
    // Data variants
    
    func get(_ keyPath: KeyPath<Pointee, CUChar32>) -> Data { getData(keyPath, length: 32) }
    func get(_ keyPath: KeyPath<Pointee, CUChar32>) -> [UInt8] { Array(getData(keyPath, length: 32)) }
    func getHex(_ keyPath: KeyPath<Pointee, CUChar32>) -> String { getData(keyPath, length: 32).toHexString() }
    func get(_ keyPath: KeyPath<Pointee, CUChar64>) -> Data { getData(keyPath, length: 64) }
    func get(_ keyPath: KeyPath<Pointee, CUChar64>) -> [UInt8] { Array(getData(keyPath, length: 64)) }
    func getHex(_ keyPath: KeyPath<Pointee, CUChar64>) -> String { getData(keyPath, length: 64).toHexString() }
    func get(_ keyPath: KeyPath<Pointee, CUChar100>) -> Data { getData(keyPath, length: 100) }
    func get(_ keyPath: KeyPath<Pointee, CUChar100>) -> [UInt8] { Array(getData(keyPath, length: 100)) }
    func getHex(_ keyPath: KeyPath<Pointee, CUChar100>) -> String { getData(keyPath, length: 100).toHexString() }
    
    func get(_ keyPath: KeyPath<Pointee, CUChar32>, nullIfEmpty: Bool = false) -> Data? {
        getData(keyPath, length: 32, nullIfEmpty: nullIfEmpty)
    }
    func get(_ keyPath: KeyPath<Pointee, CUChar32>, nullIfEmpty: Bool = false) -> [UInt8]? {
        getData(keyPath, length: 32, nullIfEmpty: nullIfEmpty).map { Array($0) }
    }
    func getHex(_ keyPath: KeyPath<Pointee, CUChar32>, nullIfEmpty: Bool = false) -> String? {
        getData(keyPath, length: 32, nullIfEmpty: nullIfEmpty).map { $0.toHexString() }
    }
    func get(_ keyPath: KeyPath<Pointee, CUChar64>, nullIfEmpty: Bool = false) -> Data? {
        getData(keyPath, length: 64, nullIfEmpty: nullIfEmpty)
    }
    func get(_ keyPath: KeyPath<Pointee, CUChar64>, nullIfEmpty: Bool = false) -> [UInt8]? {
        getData(keyPath, length: 64, nullIfEmpty: nullIfEmpty).map { Array($0) }
    }
    func getHex(_ keyPath: KeyPath<Pointee, CUChar64>, nullIfEmpty: Bool = false) -> String? {
        getData(keyPath, length: 64, nullIfEmpty: nullIfEmpty).map { $0.toHexString() }
    }
    func get(_ keyPath: KeyPath<Pointee, CUChar100>, nullIfEmpty: Bool = false) -> Data? {
        getData(keyPath, length: 100, nullIfEmpty: nullIfEmpty)
    }
    func get(_ keyPath: KeyPath<Pointee, CUChar100>, nullIfEmpty: Bool = false) -> [UInt8]? {
        getData(keyPath, length: 100, nullIfEmpty: nullIfEmpty).map { Array($0) }
    }
    func getHex(_ keyPath: KeyPath<Pointee, CUChar100>, nullIfEmpty: Bool = false) -> String? {
        getData(keyPath, length: 100, nullIfEmpty: nullIfEmpty).map { $0.toHexString() }
    }
}

// MARK: - Internal Logic

private extension UnsafeMutablePointer {
    private func getData<T>(_ keyPath: KeyPath<Pointee, T>, length: Int) -> Data {
        return UnsafePointer(self).getData(keyPath, length: length)
    }
    
    private func getData<T>(_ keyPath: KeyPath<Pointee, T>, length: Int, nullIfEmpty: Bool) -> Data? {
        return UnsafePointer(self).getData(keyPath, length: length, nullIfEmpty: nullIfEmpty)
    }
    
    private func setData<T>(_ keyPath: WritableKeyPath<Pointee, T>, _ value: Data?, length: Int) {
        if let value: Data = value, value.count > length {
            Log.warn("Setting \(keyPath) to data with \(value.count) length, expected: \(length), value will be truncated.")
        }
        
        var mutableSelf = pointee
        withUnsafeMutableBytes(of: &mutableSelf[keyPath: keyPath]) { rawBufferPointer in
            guard let baseAddress = rawBufferPointer.baseAddress else { return }
            
            let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
            guard let value: Data = value else {
                // Zero-fill the data
                memset(buffer, 0, length)
                return
            }
            
            value.copyBytes(to: buffer, count: min(length, value.count))
            
            if value.count < length {
                // Zero-fill any remaining bytes
                memset(buffer.advanced(by: value.count), 0, length - value.count)
            }
        }
        pointee = mutableSelf
    }
    
    private func getCString<T>(_ keyPath: KeyPath<Pointee, T>, maxLength: Int) -> String {
        return UnsafePointer(self).getCString(keyPath, maxLength: maxLength)
    }
    
    private func getCString<T>(_ keyPath: KeyPath<Pointee, T>, maxLength: Int, nullIfEmpty: Bool) -> String? {
        return UnsafePointer(self).getCString(keyPath, maxLength: maxLength, nullIfEmpty: nullIfEmpty)
    }
    
    private func setCString<T>(_ keyPath: WritableKeyPath<Pointee, T>, _ value: String?, maxLength: Int) {
        var mutableSelf = pointee
        withUnsafeMutableBytes(of: &mutableSelf[keyPath: keyPath]) { rawBufferPointer in
            guard let baseAddress = rawBufferPointer.baseAddress else { return }
            
            let buffer: UnsafeMutablePointer<CChar> = baseAddress.assumingMemoryBound(to: CChar.self)
            guard let value: String = value else {
                // Zero-fill the data
                memset(buffer, 0, maxLength)
                return
            }
            guard let nullTerminatedString: [CChar] = value.cString(using: .utf8) else { return }
            
            let copyLength: Int = min(maxLength - 1, nullTerminatedString.count - 1)
            strncpy(buffer, nullTerminatedString, copyLength)
            buffer[copyLength] = 0  // Ensure null termination
        }
        pointee = mutableSelf
    }
}

private extension UnsafePointer {
    func getData<T>(_ keyPath: KeyPath<Pointee, T>, length: Int) -> Data {
        let byteArray = pointee[keyPath: keyPath]
        return withUnsafeBytes(of: byteArray) { rawBufferPointer in
            guard let baseAddress = rawBufferPointer.baseAddress else { return Data() }
            
            return Data(bytes: baseAddress, count: length)
        }
    }
    
    func getData<T>(_ keyPath: KeyPath<Pointee, T>, length: Int, nullIfEmpty: Bool) -> Data? {
        let byteArray = pointee[keyPath: keyPath]
        return withUnsafeBytes(of: byteArray) { rawBufferPointer in
            guard let baseAddress = rawBufferPointer.baseAddress else { return nil }
            
            let result: Data = Data(bytes: baseAddress, count: length)
            
            // If all of the values are 0 then return the data as null
            guard !nullIfEmpty || result.contains(where: { $0 != 0 }) else { return nil }
            
            return result
        }
    }
    
    func getCString<T>(_ keyPath: KeyPath<Pointee, T>, maxLength: Int) -> String {
        let charArray = pointee[keyPath: keyPath]
        return withUnsafeBytes(of: charArray) { rawBufferPointer in
            guard let baseAddress = rawBufferPointer.baseAddress else { return "" }
            
            let buffer = baseAddress.assumingMemoryBound(to: CChar.self)
            return String(cString: buffer)
        }
    }
    
    func getCString<T>(_ keyPath: KeyPath<Pointee, T>, maxLength: Int, nullIfEmpty: Bool) -> String? {
        let charArray = pointee[keyPath: keyPath]
        return withUnsafeBytes(of: charArray) { rawBufferPointer in
            guard let baseAddress = rawBufferPointer.baseAddress else { return nil }
            
            let buffer = baseAddress.assumingMemoryBound(to: CChar.self)
            let result: String = String(cString: buffer)
            
            guard !nullIfEmpty || !result.isEmpty else { return nil }
            
            return result
        }
    }
}

// MARK: - Fixed Length Types

public typealias CUChar32 = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8
)

public typealias CUChar64 = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8
)

public typealias CUChar100 = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

public typealias CChar65 = (
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar
)

public typealias CChar67 = (
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar
)

public typealias CChar101 = (
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar
)

public typealias CChar224 = (
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar
)

public typealias CChar268 = (
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar
)
