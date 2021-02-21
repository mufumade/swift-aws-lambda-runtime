//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAWSLambdaRuntime open source project
//
// Copyright (c) 2017-2020 Apple Inc. and the SwiftAWSLambdaRuntime project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@_exported import AWSLambdaRuntimeCore
import struct Foundation.Data
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
import NIO
import NIOFoundationCompat

/// Extension to the `Lambda` companion to enable execution of Lambdas that take and return `Codable` events.
extension Lambda {
    /// An asynchronous Lambda Closure that takes a `In: Decodable` and returns a `Result<Out: Encodable, Error>` via a completion handler.
    public typealias CodableClosure<In: Decodable, Out: Encodable> = (Lambda.Context, In, @escaping (Result<Out, Error>) -> Void) -> Void

    /// Run a Lambda defined by implementing the `CodableClosure` function.
    ///
    /// - parameters:
    ///     - closure: `CodableClosure` based Lambda.
    ///
    /// - note: This is a blocking operation that will run forever, as its lifecycle is managed by the AWS Lambda Runtime Engine.
    public static func run<In: Decodable, Out: Encodable>(_ closure: @escaping CodableClosure<In, Out>) {
        self.run(CodableClosureWrapper(closure))
    }

    /// An asynchronous Lambda Closure that takes a `In: Decodable` and returns a `Result<Void, Error>` via a completion handler.
    public typealias CodableVoidClosure<In: Decodable> = (Lambda.Context, In, @escaping (Result<Void, Error>) -> Void) -> Void

    /// Run a Lambda defined by implementing the `CodableVoidClosure` function.
    ///
    /// - parameters:
    ///     - closure: `CodableVoidClosure` based Lambda.
    ///
    /// - note: This is a blocking operation that will run forever, as its lifecycle is managed by the AWS Lambda Runtime Engine.
    public static func run<In: Decodable>(_ closure: @escaping CodableVoidClosure<In>) {
        self.run(CodableVoidClosureWrapper(closure))
    }
}

internal struct CodableClosureWrapper<In: Decodable, Out: Encodable>: LambdaHandler {
    typealias In = In
    typealias Out = Out

    private let closure: Lambda.CodableClosure<In, Out>

    init(_ closure: @escaping Lambda.CodableClosure<In, Out>) {
        self.closure = closure
    }

    func handle(context: Lambda.Context, event: In, callback: @escaping (Result<Out, Error>) -> Void) {
        self.closure(context, event, callback)
    }
}

internal struct CodableVoidClosureWrapper<In: Decodable>: LambdaHandler {
    typealias In = In
    typealias Out = Void

    private let closure: Lambda.CodableVoidClosure<In>

    init(_ closure: @escaping Lambda.CodableVoidClosure<In>) {
        self.closure = closure
    }

    func handle(context: Lambda.Context, event: In, callback: @escaping (Result<Out, Error>) -> Void) {
        self.closure(context, event, callback)
    }
}

// MARK: - Async

#if compiler(>=5.4) && $AsyncAwait
extension Lambda {
    
    /// An async Lambda Closure that takes a `In: Decodable` and returns an `Out: Encodable`
    public typealias CodableAsyncClosure<In: Decodable, Out: Encodable> = (Lambda.Context, In) async throws -> Out
    
    /// Run a Lambda defined by implementing the `CodableAsyncClosure` function.
    ///
    /// - parameters:
    ///     - closure: `CodableAsyncClosure` based Lambda.
    ///
    /// - note: This is a blocking operation that will run forever, as its lifecycle is managed by the AWS Lambda Runtime Engine.
    public static func run<In: Decodable, Out: Encodable>(_ closure: @escaping CodableAsyncClosure<In, Out>) {
        self.run(CodableAsyncWrapper(closure))
    }

    /// An asynchronous Lambda Closure that takes a `In: Decodable` and returns nothing.
    public typealias CodableVoidAsyncClosure<In: Decodable> = (Lambda.Context, In) async throws -> ()

    /// Run a Lambda defined by implementing the `CodableVoidAsyncClosure` function.
    ///
    /// - parameters:
    ///     - closure: `CodableVoidAsyncClosure` based Lambda.
    ///
    /// - note: This is a blocking operation that will run forever, as its lifecycle is managed by the AWS Lambda Runtime Engine.
    public static func run<In: Decodable>(_ closure: @escaping CodableVoidAsyncClosure<In>) {
        self.run(CodableVoidAsyncWrapper(closure))
    }
}

internal struct CodableAsyncWrapper<In: Decodable, Out: Encodable>: AsyncLambdaHandler {
    typealias In = In
    typealias Out = Out

    private let closure: Lambda.CodableAsyncClosure<In, Out>

    init(_ closure: @escaping Lambda.CodableAsyncClosure<In, Out>) {
        self.closure = closure
    }

    func handle(context: Lambda.Context, event: In) async throws -> Out {
        try await self.closure(context, event)
    }
}

internal struct CodableVoidAsyncWrapper<In: Decodable>: AsyncLambdaHandler {
    typealias In = In
    typealias Out = Void

    private let closure: Lambda.CodableVoidAsyncClosure<In>

    init(_ closure: @escaping Lambda.CodableVoidAsyncClosure<In>) {
        self.closure = closure
    }

    func handle(context: Lambda.Context, event: In) async throws -> Void {
        try await self.closure(context, event)
    }
}
#endif

// MARK: - Codable support

/// Implementation of  a`ByteBuffer` to `In` decoding
public extension EventLoopLambdaHandler where In: Decodable {
    func decode(buffer: ByteBuffer) throws -> In {
        try self.decoder.decode(In.self, from: buffer)
    }
}

/// Implementation of  `Out` to `ByteBuffer` encoding
public extension EventLoopLambdaHandler where Out: Encodable {
    func encode(allocator: ByteBufferAllocator, value: Out) throws -> ByteBuffer? {
        try self.encoder.encode(value, using: allocator)
    }
}

/// Default `ByteBuffer` to `In` decoder using Foundation's JSONDecoder
/// Advanced users that want to inject their own codec can do it by overriding these functions.
public extension EventLoopLambdaHandler where In: Decodable {
    var decoder: LambdaCodableDecoder {
        Lambda.defaultJSONDecoder
    }
}

/// Default `Out` to `ByteBuffer` encoder using Foundation's JSONEncoder
/// Advanced users that want to inject their own codec can do it by overriding these functions.
public extension EventLoopLambdaHandler where Out: Encodable {
    var encoder: LambdaCodableEncoder {
        Lambda.defaultJSONEncoder
    }
}

public protocol LambdaCodableDecoder {
    func decode<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T
}

public protocol LambdaCodableEncoder {
    func encode<T: Encodable>(_ value: T, using allocator: ByteBufferAllocator) throws -> ByteBuffer
}

private extension Lambda {
    static let defaultJSONDecoder = JSONDecoder()
    static let defaultJSONEncoder = JSONEncoder()
}

extension JSONDecoder: LambdaCodableDecoder {}

extension JSONEncoder: LambdaCodableEncoder {
    public func encode<T>(_ value: T, using allocator: ByteBufferAllocator) throws -> ByteBuffer where T: Encodable {
        // nio will resize the buffer if necessary
        var buffer = allocator.buffer(capacity: 1024)
        try self.encode(value, into: &buffer)
        return buffer
    }
}

extension JSONEncoder {
    /// Convenience method to allow encoding json directly into a `String`. It can be used to encode a payload into an `APIGateway.V2.Response`'s body.
    public func encodeAsString<T: Encodable>(_ value: T) throws -> String {
        try String(decoding: self.encode(value), as: Unicode.UTF8.self)
    }
}

extension JSONDecoder {
    /// Convenience method to allow decoding json directly from a `String`. It can be used to decode a payload from an `APIGateway.V2.Request`'s body.
    public func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        try self.decode(type, from: Data(string.utf8))
    }
}
