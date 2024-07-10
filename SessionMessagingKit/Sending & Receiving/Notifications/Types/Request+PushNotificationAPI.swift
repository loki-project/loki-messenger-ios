// Copyright © 2023 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionSnodeKit
import SessionUtilitiesKit

// MARK: Request - PushNotificationAPI

public extension Request where Endpoint == PushNotificationAPI.Endpoint {
    init(
        method: HTTPMethod = .get,
        endpoint: Endpoint,
        queryParameters: [HTTPQueryParam: String] = [:],
        headers: [HTTPHeader: String] = [:],
        body: T? = nil,
        using dependencies: Dependencies
    ) throws {
        self = Request(
            method: method,
            endpoint: endpoint,
            destination: try .server(
                method: method,
                server: endpoint.server(using: dependencies),
                endpoint: endpoint,
                queryParameters: queryParameters,
                headers: headers,
                x25519PublicKey: endpoint.serverPublicKey
            ),
            headers: headers,
            body: body
        )
    }
}
