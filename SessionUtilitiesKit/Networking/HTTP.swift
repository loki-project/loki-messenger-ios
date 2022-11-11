// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Combine
import PromiseKit

public enum HTTP {
    private static let seedNodeURLSession = URLSession(configuration: .ephemeral, delegate: seedNodeURLSessionDelegate, delegateQueue: nil)
    private static let seedNodeURLSessionDelegate = SeedNodeURLSessionDelegateImplementation()
    private static let snodeURLSession = URLSession(configuration: .ephemeral, delegate: snodeURLSessionDelegate, delegateQueue: nil)
    private static let snodeURLSessionDelegate = SnodeURLSessionDelegateImplementation()

    // MARK: - Certificates
    
    private static let storageSeed1Cert: SecCertificate = {
        let path = Bundle.main.path(forResource: "storage-seed-1", ofType: "der")!
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        return SecCertificateCreateWithData(nil, data as CFData)!
    }()
    
    private static let storageSeed3Cert: SecCertificate = {
        let path = Bundle.main.path(forResource: "storage-seed-3", ofType: "der")!
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        return SecCertificateCreateWithData(nil, data as CFData)!
    }()
    
    private static let publicLokiFoundationCert: SecCertificate = {
        let path = Bundle.main.path(forResource: "public-loki-foundation", ofType: "der")!
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        return SecCertificateCreateWithData(nil, data as CFData)!
    }()
    
    // MARK: - Settings
    
    public static let defaultTimeout: TimeInterval = 10

    // MARK: - Seed Node URL Session Delegate Implementation
    
    private final class SeedNodeURLSessionDelegateImplementation: NSObject, URLSessionDelegate {
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard let trust = challenge.protectionSpace.serverTrust else {
                return completionHandler(.cancelAuthenticationChallenge, nil)
            }
            
            // Mark the seed node certificates as trusted
            let certificates = [ storageSeed1Cert, storageSeed3Cert, publicLokiFoundationCert ]
            guard SecTrustSetAnchorCertificates(trust, certificates as CFArray) == errSecSuccess else {
                return completionHandler(.cancelAuthenticationChallenge, nil)
            }
            
            // Check that the presented certificate is one of the seed node certificates
            var result: SecTrustResultType = .invalid
            guard SecTrustEvaluate(trust, &result) == errSecSuccess else {
                return completionHandler(.cancelAuthenticationChallenge, nil)
            }
            
            switch result {
                case .proceed, .unspecified:
                    // Unspecified indicates that evaluation reached an (implicitly trusted)
                    // anchor certificate without any evaluation failures, but never encountered
                    // any explicitly stated user-trust preference. This is the most common return
                    // value. The Keychain Access utility refers to this value as the "Use System
                    // Policy," which is the default user setting.
                    return completionHandler(.useCredential, URLCredential(trust: trust))
                    
                default: return completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
    
    // MARK: - Snode URL Session Delegate Implementation
    
    private final class SnodeURLSessionDelegateImplementation: NSObject, URLSessionDelegate {
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            // Snode to snode communication uses self-signed certificates but clients can safely
            // ignore this
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        }
    }

    // MARK: - Main
    
    public static func execute(
        _ method: HTTPMethod,
        _ url: String,
        timeout: TimeInterval = HTTP.defaultTimeout,
        useSeedNodeURLSession: Bool = false
    ) -> Promise<Data> {
        return execute(method, url, body: nil, timeout: timeout, useSeedNodeURLSession: useSeedNodeURLSession)
    }

    public static func execute(
        _ method: HTTPMethod,
        _ url: String,
        parameters: JSON?,
        timeout: TimeInterval = HTTP.defaultTimeout,
        useSeedNodeURLSession: Bool = false
    ) -> Promise<Data> {
        if let parameters = parameters {
            do {
                guard JSONSerialization.isValidJSONObject(parameters) else {
                    return Promise(error: HTTPError.invalidJSON)
                }
                let body = try JSONSerialization.data(withJSONObject: parameters, options: [ .fragmentsAllowed ])
                return execute(method, url, body: body, timeout: timeout, useSeedNodeURLSession: useSeedNodeURLSession)
            }
            catch (let error) {
                return Promise(error: error)
            }
        }
        else {
            return execute(method, url, body: nil, timeout: timeout, useSeedNodeURLSession: useSeedNodeURLSession)
        }
    }

    public static func execute(
        _ method: HTTPMethod,
        _ url: String,
        body: Data?,
        timeout: TimeInterval = HTTP.defaultTimeout,
        useSeedNodeURLSession: Bool = false
    ) -> Promise<Data> {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.timeoutInterval = timeout
        request.allHTTPHeaderFields?.removeValue(forKey: "User-Agent")
        request.setValue("WhatsApp", forHTTPHeaderField: "User-Agent") // Set a fake value
        request.setValue("en-us", forHTTPHeaderField: "Accept-Language") // Set a fake value
        
        let (promise, seal) = Promise<Data>.pending()
        let urlSession: URLSession = (useSeedNodeURLSession ? seedNodeURLSession : snodeURLSession)
        let task = urlSession.dataTask(with: request) { data, response, error in
            guard let data = data, let response = response as? HTTPURLResponse else {
                if let error = error {
                    SNLog("\(method.rawValue) request to \(url) failed due to error: \(error).")
                } else {
                    SNLog("\(method.rawValue) request to \(url) failed.")
                }
                
                // Override the actual error so that we can correctly catch failed requests in sendOnionRequest(invoking:on:with:)
                switch (error as? NSError)?.code {
                    case NSURLErrorTimedOut: return seal.reject(HTTPError.timeout)
                    default: return seal.reject(HTTPError.httpRequestFailed(statusCode: 0, data: nil))
                }
                
            }
            if let error = error {
                SNLog("\(method.rawValue) request to \(url) failed due to error: \(error).")
                // Override the actual error so that we can correctly catch failed requests in sendOnionRequest(invoking:on:with:)
                return seal.reject(HTTPError.httpRequestFailed(statusCode: 0, data: data))
            }
            let statusCode = UInt(response.statusCode)

            guard 200...299 ~= statusCode else {
                var json: JSON? = nil
                if let processedJson: JSON = try? JSONSerialization.jsonObject(with: data, options: [ .fragmentsAllowed ]) as? JSON {
                    json = processedJson
                }
                else if let result: String = String(data: data, encoding: .utf8) {
                    json = [ "result": result ]
                }
                
                let jsonDescription: String = (json?.prettifiedDescription ?? "no debugging info provided")
                SNLog("\(method.rawValue) request to \(url) failed with status code: \(statusCode) (\(jsonDescription)).")
                return seal.reject(HTTPError.httpRequestFailed(statusCode: statusCode, data: data))
            }
            
            seal.fulfill(data)
        }
        task.resume()
        return promise
    }
}
