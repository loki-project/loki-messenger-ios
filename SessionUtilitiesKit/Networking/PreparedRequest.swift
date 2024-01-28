// Copyright © 2023 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Combine
import GRDB

// MARK: - HTTP.PreparedRequest<R>

public extension HTTP {
    struct PreparedRequest<R> {
        public struct CachedResponse {
            fileprivate let info: ResponseInfoType
            fileprivate let originalData: Any
            fileprivate let convertedData: R
        }
        
        public let request: URLRequest
        public let target: any RequestTarget
        public let originalType: Decodable.Type
        public let responseType: R.Type
        public let retryCount: Int
        public let timeout: TimeInterval
        public let cachedResponse: CachedResponse?
        fileprivate let responseConverter: ((ResponseInfoType, Any) throws -> R)
        public let subscriptionHandler: (() -> Void)?
        public let outputEventHandler: (((CachedResponse)) -> Void)?
        public let completionEventHandler: ((Subscribers.Completion<Error>) -> Void)?
        public let cancelEventHandler: (() -> Void)?
        
        // The following types are needed for `BatchRequest` handling
        public let method: HTTPMethod
        private let path: String
        public let endpoint: (any EndpointType)
        public let endpointName: String
        public let batchEndpoints: [any EndpointType]
        public let batchRequestVariant: HTTP.BatchRequest.Child.Variant
        public let batchResponseTypes: [Decodable.Type]
        public let requireAllBatchResponses: Bool
        public let excludedSubRequestHeaders: [String]
        
        private let jsonKeyedBodyEncoder: ((inout KeyedEncodingContainer<HTTP.BatchRequest.Child.CodingKeys>, HTTP.BatchRequest.Child.CodingKeys) throws -> ())?
        private let jsonBodyEncoder: ((inout SingleValueEncodingContainer) throws -> ())?
        private let b64: String?
        private let bytes: [UInt8]?
        
        public init<T: Encodable, E: EndpointType>(
            request: Request<T, E>,
            urlRequest: URLRequest,
            responseType: R.Type,
            requireAllBatchResponses: Bool = true,
            retryCount: Int = 0,
            timeout: TimeInterval
        ) where R: Decodable {
            let batchRequests: [HTTP.BatchRequest.Child]? = (request.body as? BatchRequestChildRetrievable)?.requests
            let batchEndpoints: [E] = (batchRequests?
                .compactMap { $0.request.batchRequestEndpoint(of: E.self) })
                .defaulting(to: [])
            let batchResponseTypes: [Decodable.Type]? = (batchRequests?
                .compactMap { batchRequest -> [Decodable.Type]? in
                    guard batchRequest.request.batchRequestEndpoint(of: E.self) != nil else { return nil }
                    
                    return batchRequest.request.batchResponseTypes
                }
                .flatMap { $0 })
            
            self.request = urlRequest
            self.target = request.target
            self.originalType = R.self
            self.responseType = responseType
            self.retryCount = retryCount
            self.timeout = timeout
            self.cachedResponse = nil
            
            // When we are making a batch request we also want to call though any sub request event
            // handlers (this allows a lot more reusability for individual requests to manage their
            // own results or custom handling just when triggered via a batch request)
            self.responseConverter = {
                guard
                    let subRequestResponseConverters: [(Int, ((ResponseInfoType, Any) throws -> Any))] = batchRequests?
                        .enumerated()
                        .compactMap({ ($0.0, $0.1.request.erasedResponseConverter) }),
                    !subRequestResponseConverters.isEmpty
                else {
                    return { info, response in
                        guard let validResponse: R = response as? R else { throw HTTPError.invalidResponse }
                        
                        return validResponse
                    }
                }
                
                // Results are returned in the same order they were made in so we can use the matching
                // indexes to get the correct response
                return { info, response in
                    let convertedResponse: Any = try {
                        switch response {
                            case let batchResponse as HTTP.BatchResponse:
                                return HTTP.BatchResponse(
                                    data: try subRequestResponseConverters
                                        .map { index, responseConverter in
                                            guard batchResponse.count > index else {
                                                throw HTTPError.invalidResponse
                                            }
                                            
                                            return try responseConverter(info, batchResponse[index])
                                        }
                                )
                                
                            case let batchResponseMap as HTTP.BatchResponseMap<E>:
                                return HTTP.BatchResponseMap(
                                    data: try subRequestResponseConverters
                                        .reduce(into: [E: Any]()) { result, subResponse in
                                            let index: Int = subResponse.0
                                            let responseConverter: ((ResponseInfoType, Any) throws -> Any) = subResponse.1
                                            
                                            guard
                                                batchEndpoints.count > index,
                                                let targetResponse: Any = batchResponseMap[batchEndpoints[index]]
                                            else { throw HTTPError.invalidResponse }
                                            
                                            let endpoint: E = batchEndpoints[index]
                                            result[endpoint] = try responseConverter(info, targetResponse)
                                        }
                                )
                                
                            default: throw HTTPError.invalidResponse
                        }
                    }()
                    
                    guard let validResponse: R = convertedResponse as? R else {
                        SNLog("[PreparedRequest] Unable to convert responses for missing response")
                        throw HTTPError.invalidResponse
                    }
                    
                    return validResponse
                }
            }()
            self.outputEventHandler = {
                guard
                    let subRequestEventHandlers: [(Int, ((ResponseInfoType, Any, Any) -> Void))] = batchRequests?
                        .enumerated()
                        .compactMap({ index, batchRequest in
                            batchRequest.request.erasedOutputEventHandler.map { (index, $0) }
                        }),
                    !subRequestEventHandlers.isEmpty
                else { return nil }
                
                // Results are returned in the same order they were made in so we can use the matching
                // indexes to get the correct response
                return { data in
                    switch data.originalData {
                        case let batchResponse as HTTP.BatchResponse:
                            subRequestEventHandlers.forEach { index, eventHandler in
                                guard batchResponse.count > index else {
                                    SNLog("[PreparedRequest] Unable to handle output events for missing response")
                                    return
                                }
                                
                                eventHandler(data.info, batchResponse[index], batchResponse[index])
                            }
                            
                        case let batchResponseMap as HTTP.BatchResponseMap<E>:
                            subRequestEventHandlers.forEach { index, eventHandler in
                                guard
                                    batchEndpoints.count > index,
                                    let targetResponse: Any = batchResponseMap[batchEndpoints[index]]
                                else {
                                    SNLog("[PreparedRequest] Unable to handle output events for missing response")
                                    return
                                }
                                
                                eventHandler(data.info, targetResponse, targetResponse)
                            }
                            
                        default: SNLog("[PreparedRequest] Unable to handle output events for unknown batch response type")
                    }
                }
            }()
            self.subscriptionHandler = nil
            self.completionEventHandler = {
                guard
                    let subRequestEventHandlers: [((Subscribers.Completion<Error>) -> Void)] = batchRequests?
                        .compactMap({ $0.request.completionEventHandler }),
                    !subRequestEventHandlers.isEmpty
                else { return nil }
                
                // Since the completion event doesn't provide us with any data we can't return the
                // individual subRequest results here
                return { result in subRequestEventHandlers.forEach { $0(result) } }
            }()
            self.cancelEventHandler = {
                guard
                    let subRequestEventHandlers: [(() -> Void)] = batchRequests?
                        .compactMap({ $0.request.cancelEventHandler }),
                    !subRequestEventHandlers.isEmpty
                else { return nil }
                
                return { subRequestEventHandlers.forEach { $0() } }
            }()
            
            // The following data is needed in this type for handling batch requests
            self.method = request.method
            self.endpoint = request.endpoint
            self.endpointName = E.name
            self.path = request.target.urlPathAndParamsString
            
            self.batchEndpoints = batchEndpoints
            self.batchRequestVariant = E.batchRequestVariant
            self.batchResponseTypes = batchResponseTypes.defaulting(to: [HTTP.BatchSubResponse<R>.self])
            self.requireAllBatchResponses = requireAllBatchResponses
            self.excludedSubRequestHeaders = E.excludedSubRequestHeaders
            
            if batchRequests != nil && self.batchEndpoints.count != self.batchResponseTypes.count {
                SNLog("[PreparedRequest] Created with invalid sub requests")
            }
            
            // Note: Need to differentiate between JSON, b64 string and bytes body values to ensure
            // they are encoded correctly so the server knows how to handle them
            switch request.body {
                case let bodyString as String:
                    self.jsonKeyedBodyEncoder = nil
                    self.jsonBodyEncoder = nil
                    self.b64 = bodyString
                    self.bytes = nil
                    
                case let bodyBytes as [UInt8]:
                    self.jsonKeyedBodyEncoder = nil
                    self.jsonBodyEncoder = nil
                    self.b64 = nil
                    self.bytes = bodyBytes
                    
                default:
                    self.jsonKeyedBodyEncoder = { [body = request.body] container, key in
                        try container.encodeIfPresent(body, forKey: key)
                    }
                    self.jsonBodyEncoder = { [body = request.body] container in
                        try container.encode(body)
                    }
                    self.b64 = nil
                    self.bytes = nil
            }
        }
        
        fileprivate init<U: Decodable>(
            request: URLRequest,
            target: any RequestTarget,
            originalType: U.Type,
            responseType: R.Type,
            retryCount: Int,
            timeout: TimeInterval,
            cachedResponse: CachedResponse?,
            responseConverter: @escaping (ResponseInfoType, Any) throws -> R,
            subscriptionHandler: (() -> Void)?,
            outputEventHandler: ((CachedResponse) -> Void)?,
            completionEventHandler: ((Subscribers.Completion<Error>) -> Void)?,
            cancelEventHandler: (() -> Void)?,
            method: HTTPMethod,
            endpoint: (any EndpointType),
            endpointName: String,
            path: String,
            batchEndpoints: [any EndpointType],
            batchRequestVariant: HTTP.BatchRequest.Child.Variant,
            batchResponseTypes: [Decodable.Type],
            requireAllBatchResponses: Bool,
            excludedSubRequestHeaders: [String],
            jsonKeyedBodyEncoder: ((inout KeyedEncodingContainer<HTTP.BatchRequest.Child.CodingKeys>, HTTP.BatchRequest.Child.CodingKeys) throws -> ())?,
            jsonBodyEncoder: ((inout SingleValueEncodingContainer) throws -> ())?,
            b64: String?,
            bytes: [UInt8]?
        ) {
            self.request = request
            self.target = target
            self.originalType = originalType
            self.responseType = responseType
            self.retryCount = retryCount
            self.timeout = timeout
            self.cachedResponse = cachedResponse
            self.responseConverter = responseConverter
            self.subscriptionHandler = subscriptionHandler
            self.outputEventHandler = outputEventHandler
            self.completionEventHandler = completionEventHandler
            self.cancelEventHandler = cancelEventHandler
            
            // The following data is needed in this type for handling batch requests
            self.method = method
            self.endpoint = endpoint
            self.endpointName = endpointName
            self.path = path
            self.batchEndpoints = batchEndpoints
            self.batchRequestVariant = batchRequestVariant
            self.batchResponseTypes = batchResponseTypes
            self.requireAllBatchResponses = requireAllBatchResponses
            self.excludedSubRequestHeaders = excludedSubRequestHeaders
            self.jsonKeyedBodyEncoder = jsonKeyedBodyEncoder
            self.jsonBodyEncoder = jsonBodyEncoder
            self.b64 = b64
            self.bytes = bytes
        }
    }
}

// MARK: - ErasedPreparedRequest

public protocol ErasedPreparedRequest {
    var endpointName: String { get }
    var batchRequestVariant: HTTP.BatchRequest.Child.Variant { get }
    var batchResponseTypes: [Decodable.Type] { get }
    var excludedSubRequestHeaders: [String] { get }
    
    var erasedResponseConverter: ((ResponseInfoType, Any) throws -> Any) { get }
    var erasedOutputEventHandler: ((ResponseInfoType, Any, Any) -> Void)? { get }
    var completionEventHandler: ((Subscribers.Completion<Error>) -> Void)? { get }
    var cancelEventHandler: (() -> Void)? { get }
    
    func batchRequestEndpoint<E: EndpointType>(of type: E.Type) -> E?
    func encodeForBatchRequest(to encoder: Encoder) throws
}

extension HTTP.PreparedRequest: ErasedPreparedRequest {
    public var erasedResponseConverter: ((ResponseInfoType, Any) throws -> Any) {
        let originalType: Decodable.Type = self.originalType
        let converter: ((ResponseInfoType, Any) throws -> R) = self.responseConverter
        
        return { info, data in
            switch data {
                case let subResponse as ErasedBatchSubResponse:
                    return HTTP.BatchSubResponse(
                        code: subResponse.code,
                        headers: subResponse.headers,
                        body: try originalType.from(subResponse.erasedBody).map { try converter(info, $0) }
                    )
                    
                default: return try originalType.from(data).map { try converter(info, $0) } as Any
            }
        }
    }
    
    public var erasedOutputEventHandler: ((ResponseInfoType, Any, Any) -> Void)? {
        guard let outputEventHandler: ((CachedResponse) -> Void) = self.outputEventHandler else {
            return nil
        }
        
        let originalType: Decodable.Type = self.originalType
        let originalConverter: ((ResponseInfoType, Any) throws -> R) = self.responseConverter
        
        return { info, _, data in
            switch data {
                case let subResponse as ErasedBatchSubResponse:
                    guard
                        let erasedBody: Any = originalType.from(subResponse.erasedBody),
                        let validResponse: R = try? originalConverter(info, erasedBody)
                    else { return }
                    
                    outputEventHandler(CachedResponse(
                        info: info,
                        originalData: subResponse.erasedBody as Any,
                        convertedData: validResponse
                    ))
                    
                default:
                    guard
                        let erasedBody: Any = originalType.from(data),
                        let validResponse: R = try? originalConverter(info, erasedBody)
                    else { return }
                    
                    outputEventHandler(CachedResponse(
                        info: info,
                        originalData: erasedBody,
                        convertedData: validResponse
                    ))
            }
        }
    }
    
    public func batchRequestEndpoint<E: EndpointType>(of type: E.Type) -> E? {
        return (endpoint as? E)
    }
    
    public func encodeForBatchRequest(to encoder: Encoder) throws {
        switch batchRequestVariant {
            case .unsupported:
                SNLog("Attempted to encode unsupported request type \(endpointName) as a batch subrequest")
                
            case .sogs:
                var container: KeyedEncodingContainer<HTTP.BatchRequest.Child.CodingKeys> = encoder.container(keyedBy: HTTP.BatchRequest.Child.CodingKeys.self)
                
                // Exclude request signature headers (not used for sub-requests)
                let excludedSubRequestHeaders: [String] = excludedSubRequestHeaders.map { $0.lowercased() }
                let batchRequestHeaders: [String: String] = (request.allHTTPHeaderFields ?? [:])
                    .filter { key, _ in !excludedSubRequestHeaders.contains(key.lowercased()) }
                
                if !batchRequestHeaders.isEmpty {
                    try container.encode(batchRequestHeaders, forKey: .headers)
                }
                
                try container.encode(method, forKey: .method)
                try container.encode(path, forKey: .path)
                try jsonKeyedBodyEncoder?(&container, .json)
                try container.encodeIfPresent(b64, forKey: .b64)
                try container.encodeIfPresent(bytes, forKey: .bytes)
                
            case .storageServer:
                var container: SingleValueEncodingContainer = encoder.singleValueContainer()
                
                try jsonBodyEncoder?(&container)
        }
    }
}

// MARK: - Transformations

public extension HTTP.PreparedRequest {
    func signed(
        _ db: Database,
        with requestSigner: (Database, HTTP.PreparedRequest<R>, Dependencies) throws -> URLRequest,
        using dependencies: Dependencies
    ) throws -> HTTP.PreparedRequest<R> {
        return HTTP.PreparedRequest(
            request: try requestSigner(db, self, dependencies),
            target: target,
            originalType: originalType,
            responseType: responseType,
            retryCount: retryCount,
            timeout: timeout,
            cachedResponse: cachedResponse,
            responseConverter: responseConverter,
            subscriptionHandler: subscriptionHandler,
            outputEventHandler: outputEventHandler,
            completionEventHandler: completionEventHandler,
            cancelEventHandler: cancelEventHandler,
            method: method,
            endpoint: endpoint,
            endpointName: endpointName,
            path: path,
            batchEndpoints: batchEndpoints,
            batchRequestVariant: batchRequestVariant,
            batchResponseTypes: batchResponseTypes,
            requireAllBatchResponses: requireAllBatchResponses,
            excludedSubRequestHeaders: excludedSubRequestHeaders,
            jsonKeyedBodyEncoder: jsonKeyedBodyEncoder,
            jsonBodyEncoder: jsonBodyEncoder,
            b64: b64,
            bytes: bytes
        )
    }
    
    /// Due to the way prepared requests work we need to cast between different types and as a result can't avoid potentially
    /// throwing when mapping so the `map` function just calls through to the `tryMap` function, but we have both to make
    /// the interface more consistent for dev use
    func map<O>(transform: @escaping (ResponseInfoType, R) throws -> O) -> HTTP.PreparedRequest<O> {
        return tryMap(transform: transform)
    }
    
    func tryMap<O>(transform: @escaping (ResponseInfoType, R) throws -> O) -> HTTP.PreparedRequest<O> {
        let originalConverter: ((ResponseInfoType, Any) throws -> R) = self.responseConverter
        let responseConverter: ((ResponseInfoType, Any) throws -> O) = { info, response in
            let validResponse: R = try originalConverter(info, response)
            
            return try transform(info, validResponse)
        }
        
        return HTTP.PreparedRequest<O>(
            request: request,
            target: target,
            originalType: originalType,
            responseType: O.self,
            retryCount: retryCount,
            timeout: timeout,
            cachedResponse: cachedResponse.map { data in
                (try? responseConverter(data.info, data.convertedData))
                    .map { convertedData in
                        HTTP.PreparedRequest<O>.CachedResponse(
                            info: data.info,
                            originalData: data.originalData,
                            convertedData: convertedData
                        )
                    }
            },
            responseConverter: responseConverter,
            subscriptionHandler: subscriptionHandler,
            outputEventHandler: self.outputEventHandler.map { eventHandler in
                { data in
                    guard let validResponse: R = try? originalConverter(data.info, data.originalData) else {
                        return
                    }
                    
                    eventHandler(CachedResponse(
                        info: data.info,
                        originalData: data.originalData,
                        convertedData: validResponse
                    ))
                }
            },
            completionEventHandler: completionEventHandler,
            cancelEventHandler: cancelEventHandler,
            method: method,
            endpoint: endpoint,
            endpointName: endpointName,
            path: path,
            batchEndpoints: batchEndpoints,
            batchRequestVariant: batchRequestVariant,
            batchResponseTypes: batchResponseTypes,
            requireAllBatchResponses: requireAllBatchResponses,
            excludedSubRequestHeaders: excludedSubRequestHeaders,
            jsonKeyedBodyEncoder: jsonKeyedBodyEncoder,
            jsonBodyEncoder: jsonBodyEncoder,
            b64: b64,
            bytes: bytes
        )
    }
    
    func handleEvents(
        receiveSubscription: (() -> Void)? = nil,
        receiveOutput: (((ResponseInfoType, R)) -> Void)? = nil,
        receiveCompletion: ((Subscribers.Completion<Error>) -> Void)? = nil,
        receiveCancel: (() -> Void)? = nil
    ) -> HTTP.PreparedRequest<R> {
        let subscriptionHandler: (() -> Void)? = {
            switch (self.subscriptionHandler, receiveSubscription) {
                case (.none, .none): return nil
                case (.some(let eventHandler), .none): return eventHandler
                case (.none, .some(let eventHandler)): return eventHandler
                case (.some(let originalEventHandler), .some(let eventHandler)):
                    return {
                        originalEventHandler()
                        eventHandler()
                    }
            }
        }()
        let outputEventHandler: ((CachedResponse) -> Void)? = {
            switch (self.outputEventHandler, receiveOutput) {
                case (.none, .none): return nil
                case (.some(let eventHandler), .none): return eventHandler
                case (.none, .some(let eventHandler)):
                    return { data in
                        eventHandler((data.info, data.convertedData))
                    }
                    
                case (.some(let originalEventHandler), .some(let eventHandler)):
                    return { data in
                        originalEventHandler(data)
                        eventHandler((data.info, data.convertedData))
                    }
            }
        }()
        let completionEventHandler: ((Subscribers.Completion<Error>) -> Void)? = {
            switch (self.completionEventHandler, receiveCompletion) {
                case (.none, .none): return nil
                case (.some(let eventHandler), .none): return eventHandler
                case (.none, .some(let eventHandler)): return eventHandler
                case (.some(let originalEventHandler), .some(let eventHandler)):
                    return { result in
                        originalEventHandler(result)
                        eventHandler(result)
                    }
            }
        }()
        let cancelEventHandler: (() -> Void)? = {
            switch (self.cancelEventHandler, receiveCancel) {
                case (.none, .none): return nil
                case (.some(let eventHandler), .none): return eventHandler
                case (.none, .some(let eventHandler)): return eventHandler
                case (.some(let originalEventHandler), .some(let eventHandler)):
                    return {
                        originalEventHandler()
                        eventHandler()
                    }
            }
        }()
        
        return HTTP.PreparedRequest(
            request: request,
            target: target,
            originalType: originalType,
            responseType: responseType,
            retryCount: retryCount,
            timeout: timeout,
            cachedResponse: cachedResponse,
            responseConverter: responseConverter,
            subscriptionHandler: subscriptionHandler,
            outputEventHandler: outputEventHandler,
            completionEventHandler: completionEventHandler,
            cancelEventHandler: cancelEventHandler,
            method: method,
            endpoint: endpoint,
            endpointName: endpointName,
            path: path,
            batchEndpoints: batchEndpoints,
            batchRequestVariant: batchRequestVariant,
            batchResponseTypes: batchResponseTypes,
            requireAllBatchResponses: requireAllBatchResponses,
            excludedSubRequestHeaders: excludedSubRequestHeaders,
            jsonKeyedBodyEncoder: jsonKeyedBodyEncoder,
            jsonBodyEncoder: jsonBodyEncoder,
            b64: b64,
            bytes: bytes
        )
    }
}

// MARK: - Response

public extension HTTP.PreparedRequest {
    static func cached<E: EndpointType>(
        _ cachedResponse: R,
        endpoint: E
    ) -> HTTP.PreparedRequest<R> where R: Decodable {
        return HTTP.PreparedRequest(
            request: URLRequest(url: URL(fileURLWithPath: "")),
            target: HTTP.ServerTarget(
                server: "",
                path: "",
                queryParameters: [:],
                encType: .xchacha20,
                x25519PublicKey: ""
            ),
            originalType: R.self,
            responseType: R.self,
            retryCount: 0,
            timeout: 0,
            cachedResponse: HTTP.PreparedRequest<R>.CachedResponse(
                info: HTTP.ResponseInfo(code: 0, headers: [:]),
                originalData: cachedResponse,
                convertedData: cachedResponse
            ),
            responseConverter: { _, _ in cachedResponse },
            subscriptionHandler: nil,
            outputEventHandler: nil,
            completionEventHandler: nil,
            cancelEventHandler: nil,
            method: .get,
            endpoint: endpoint,
            endpointName: E.name,
            path: "",
            batchEndpoints: [],
            batchRequestVariant: .unsupported,
            batchResponseTypes: [],
            requireAllBatchResponses: false,
            excludedSubRequestHeaders: [],
            jsonKeyedBodyEncoder: nil,
            jsonBodyEncoder: nil,
            b64: nil,
            bytes: nil
        )
    }
}

// MARK: - HTTP.PreparedRequest<R>.CachedResponse

public extension Publisher where Failure == Error {
    func eraseToAnyPublisher<R>() -> AnyPublisher<(ResponseInfoType, R), Error> where Output == HTTP.PreparedRequest<R>.CachedResponse {
        return self
            .map { ($0.info, $0.convertedData) }
            .eraseToAnyPublisher()
    }
}

// MARK: - Decoding

public extension Decodable {
    fileprivate static func from(_ value: Any?) -> Self? {
        return (value as? Self)
    }
    
    static func decoded(from data: Data, using dependencies: Dependencies = Dependencies()) throws -> Self {
        return try data.decoded(as: Self.self, using: dependencies)
    }
}

public extension Publisher where Output == (ResponseInfoType, Data?), Failure == Error {
    func decoded<R>(
        with preparedRequest: HTTP.PreparedRequest<R>,
        using dependencies: Dependencies
    ) -> AnyPublisher<HTTP.PreparedRequest<R>.CachedResponse, Error> {
        self
            .tryMap { responseInfo, maybeData -> HTTP.PreparedRequest<R>.CachedResponse in
                // Depending on the 'originalType' we need to process the response differently
                let targetData: Any = try {
                    switch preparedRequest.originalType {
                        case let erasedBatchResponse as ErasedBatchResponseMap.Type:
                            let response: HTTP.BatchResponse = try HTTP.BatchResponse.decodingResponses(
                                from: maybeData,
                                as: preparedRequest.batchResponseTypes,
                                requireAllResults: preparedRequest.requireAllBatchResponses,
                                using: dependencies
                            )
                            
                            return try erasedBatchResponse.from(
                                batchEndpoints: preparedRequest.batchEndpoints,
                                response: response
                            )
                            
                        case is HTTP.BatchResponse.Type:
                            return try HTTP.BatchResponse.decodingResponses(
                                from: maybeData,
                                as: preparedRequest.batchResponseTypes,
                                requireAllResults: preparedRequest.requireAllBatchResponses,
                                using: dependencies
                            )
                            
                        case is NoResponse.Type: return NoResponse()
                        case is Optional<Data>.Type: return maybeData as Any
                        case is Data.Type: return try maybeData ?? { throw HTTPError.parsingFailed }()
                        
                        case is _OptionalProtocol.Type:
                            guard let data: Data = maybeData else { return maybeData as Any }
                            
                            return try preparedRequest.originalType.decoded(from: data, using: dependencies)
                        
                        default:
                            guard let data: Data = maybeData else { throw HTTPError.parsingFailed }
                            
                            return try preparedRequest.originalType.decoded(from: data, using: dependencies)
                    }
                }()
                
                // Generate and return the converted data
                return HTTP.PreparedRequest<R>.CachedResponse(
                    info: responseInfo,
                    originalData: targetData,
                    convertedData: try preparedRequest.responseConverter(responseInfo, targetData)
                )
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - _OptionalProtocol

/// This protocol should only be used within this file and is used to distinguish between `Any.Type` and `Optional<Any>.Type` as
/// it seems that `is Optional<Any>.Type` doesn't work nicely but this protocol works nicely as long as the case is under any explicit
/// `Optional<T>` handling that we need
private protocol _OptionalProtocol {}

extension Optional: _OptionalProtocol {}
