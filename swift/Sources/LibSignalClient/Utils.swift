//
// Copyright 2020-2022 Signal Messenger, LLC.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalFfi

#if canImport(Security)
import Security
#endif

internal func invokeFnReturningString(fn: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> SignalFfiErrorRef?) throws -> String {
    try invokeFnReturningOptionalString(fn: fn)!
}

internal func invokeFnReturningOptionalString(fn: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> SignalFfiErrorRef?) throws -> String? {
    var output: UnsafePointer<Int8>?
    try checkError(fn(&output))
    if output == nil {
        return nil
    }
    let result = String(cString: output!)
    signal_free_string(output)
    return result
}

internal func invokeFnReturningStringArray(fn: (UnsafeMutablePointer<SignalStringArray>?) -> SignalFfiErrorRef?) throws -> [String] {
    var array = SignalFfi.SignalStringArray()
    try checkError(fn(&array))

    var bytes = UnsafeBufferPointer(start: array.bytes.base, count: array.bytes.length)
    let lengths = UnsafeBufferPointer(start: array.lengths.base, count: array.lengths.length)

    let result = lengths.map { length in
        let view = bytes.prefix(length)
        bytes = UnsafeBufferPointer(rebasing: bytes.suffix(from: length))
        return String(decoding: view, as: Unicode.UTF8.self)
    }

    signal_free_bytestring_array(array)
    return result
}

internal func invokeFnReturningArray(fn: (UnsafeMutablePointer<SignalOwnedBuffer>?) -> SignalFfiErrorRef?) throws -> [UInt8] {
    var output = SignalOwnedBuffer()
    try checkError(fn(&output))
    let result = Array(UnsafeBufferPointer(start: output.base, count: output.length))
    signal_free_buffer(output.base, output.length)
    return result
}

internal func invokeFnReturningData(fn: (UnsafeMutablePointer<SignalOwnedBuffer>?) -> SignalFfiErrorRef?) throws -> Data {
    var output = SignalOwnedBuffer()
    try checkError(fn(&output))
    let result = Data(UnsafeBufferPointer(start: output.base, count: output.length))
    signal_free_buffer(output.base, output.length)
    return result
}

internal func invokeFnReturningDataNoCopy(fn: (UnsafeMutablePointer<SignalOwnedBuffer>?) -> SignalFfiErrorRef?) throws -> Data {
    var output = SignalOwnedBuffer()
    try checkError(fn(&output))
    guard let base = output.base else { return Data() }
    return Data(bytesNoCopy: base, count: output.length, deallocator: .custom { base, length in
        signal_free_buffer(base, length)
    })
}

internal func invokeFnReturningFixedLengthArray<ResultAsTuple>(fn: (UnsafeMutablePointer<ResultAsTuple>) -> SignalFfiErrorRef?) throws -> [UInt8] {
    precondition(MemoryLayout<ResultAsTuple>.alignment == 1, "not a fixed-sized array (tuple) of UInt8")
    var output = Array(repeating: 0 as UInt8, count: MemoryLayout<ResultAsTuple>.size)
    try output.withUnsafeMutableBytes { buffer in
        let typedPointer = buffer.baseAddress!.assumingMemoryBound(to: ResultAsTuple.self)
        return try checkError(fn(typedPointer))
    }
    return output
}

internal func invokeFnReturningSerialized<Result: ByteArray, SerializedResult>(fn: (UnsafeMutablePointer<SerializedResult>) -> SignalFfiErrorRef?) throws -> Result {
    let output = try invokeFnReturningFixedLengthArray(fn: fn)
    return try Result(contents: output)
}

internal func invokeFnReturningVariableLengthSerialized<Result: ByteArray>(fn: (UnsafeMutablePointer<SignalOwnedBuffer>?) -> SignalFfiErrorRef?) throws -> Result {
    let output = try invokeFnReturningArray(fn: fn)
    return try Result(contents: output)
}

internal func invokeFnReturningOptionalVariableLengthSerialized<Result: ByteArray>(fn: (UnsafeMutablePointer<SignalOwnedBuffer>?) -> SignalFfiErrorRef?) throws -> Result? {
    let output = try invokeFnReturningArray(fn: fn)
    if output.isEmpty {
        return nil
    }
    return try Result(contents: output)
}

internal func invokeFnReturningUuid(fn: (UnsafeMutablePointer<uuid_t>?) -> SignalFfiErrorRef?) throws -> UUID {
    var output: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    try checkError(fn(&output))
    return UUID(uuid: output)
}

internal func invokeFnReturningServiceId<Id: ServiceId>(fn: (UnsafeMutablePointer<ServiceIdStorage>?) -> SignalFfiErrorRef?) throws -> Id {
    var output: ServiceIdStorage = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    try checkError(fn(&output))
    return try Id.parseFrom(fixedWidthBinary: output)
}

internal func invokeFnReturningInteger<Result: FixedWidthInteger>(fn: (UnsafeMutablePointer<Result>?) -> SignalFfiErrorRef?) throws -> Result {
    var output: Result = 0
    try checkError(fn(&output))
    return output
}

internal func invokeFnReturningBool(fn: (UnsafeMutablePointer<Bool>?) -> SignalFfiErrorRef?) throws -> Bool {
    var output = false
    try checkError(fn(&output))
    return output
}

internal func invokeFnReturningNativeHandle<Owner: NativeHandleOwner>(fn: (UnsafeMutablePointer<OpaquePointer?>?) -> SignalFfiErrorRef?) throws -> Owner {
    var handle: OpaquePointer?
    try checkError(fn(&handle))
    return Owner(owned: handle!)
}

internal func invokeFnReturningOptionalNativeHandle<Owner: NativeHandleOwner>(fn: (UnsafeMutablePointer<OpaquePointer?>?) -> SignalFfiErrorRef?) throws -> Owner? {
    var handle: OpaquePointer?
    try checkError(fn(&handle))
    return handle.map { Owner(owned: $0) }
}

extension ContiguousBytes {
    func withUnsafeBorrowedBuffer<Result>(_ body: (SignalBorrowedBuffer) throws -> Result) rethrows -> Result {
        try withUnsafeBytes {
            try body(SignalBorrowedBuffer($0))
        }
    }
}

extension SignalBorrowedBuffer {
    internal init(_ buffer: UnsafeRawBufferPointer) {
        self.init(base: buffer.baseAddress?.assumingMemoryBound(to: UInt8.self), length: buffer.count)
    }
}

extension SignalBorrowedMutableBuffer {
    internal init(_ buffer: UnsafeMutableRawBufferPointer) {
        self.init(base: buffer.baseAddress?.assumingMemoryBound(to: UInt8.self), length: buffer.count)
    }
}

internal func fillRandom(_ buffer: UnsafeMutableRawBufferPointer) throws {
    guard let baseAddress = buffer.baseAddress else {
        // Zero-length buffers are permitted to have nil baseAddresses.
        assert(buffer.count == 0)
        return
    }

#if canImport(Security)
    let result = SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
    guard result == errSecSuccess else {
        throw SignalError.internalError("SecRandomCopyBytes failed (error code \(result))")
    }
#else
    for i in buffer.indices {
        buffer[i] = UInt8.random(in: .min ... .max)
    }
#endif
}

/// Wraps a store while providing a place to hang on to any user-thrown errors.
internal struct ErrorHandlingContext<Store> {
    var store: Store
    var error: Error? = nil

    init(_ store: Store) {
        self.store = store
    }

    mutating func catchCallbackErrors(_ body: (Store) throws -> Int32) -> Int32 {
        do {
            return try body(self.store)
        } catch {
            self.error = error
            return -1
        }
    }
}

internal func rethrowCallbackErrors<Store, Result>(_ store: Store, _ body: (UnsafeMutablePointer<ErrorHandlingContext<Store>>) throws -> Result) rethrows -> Result {
    var context = ErrorHandlingContext(store)
    do {
        return try withUnsafeMutablePointer(to: &context) {
            try body($0)
        }
    } catch SignalError.callbackError(_) where context.error != nil {
        throw context.error!
    }
}
