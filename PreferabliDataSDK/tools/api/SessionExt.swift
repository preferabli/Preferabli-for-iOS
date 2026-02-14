//
//  SessionExt.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 12/13/17.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//

import Foundation
import Alamofire

internal typealias SParams = [String: Sendable]

extension Session {

    // MARK: - Helpers

    private func mapToOptionalData(_ resp: DataResponse<Data, AFError>) -> AFDataResponse<Data?> {
        .init(
            request: resp.request,
            response: resp.response,
            data: resp.data,
            metrics: resp.metrics,
            serializationDuration: resp.serializationDuration,
            result: resp.result.map { Optional($0) }
        )
    }

    /// Runs an Alamofire DataRequest and *cancels the underlying request* if the Swift Task is cancelled.
    private func performDataRequest(_ make: () -> DataRequest) async -> AFDataResponse<Data?> {
        // If we're already cancelled, don't even start.
        if Task.isCancelled {
            return AFDataResponse<Data?>(
                request: nil,
                response: nil,
                data: nil,
                metrics: nil,
                serializationDuration: 0,
                result: .failure(AFError.explicitlyCancelled)
            )
        }

        let req = make()

        let resp: DataResponse<Data, AFError> = await withTaskCancellationHandler {
            req.cancel()
        } operation: {
            await req.serializingData().response
        }

        return mapToOptionalData(resp)
    }

    /// Runs an Alamofire UploadRequest and *cancels the underlying request* if the Swift Task is cancelled.
    private func performUploadRequest(_ make: () -> UploadRequest) async -> AFDataResponse<Data?> {
        if Task.isCancelled {
            return AFDataResponse<Data?>(
                request: nil,
                response: nil,
                data: nil,
                metrics: nil,
                serializationDuration: 0,
                result: .failure(AFError.explicitlyCancelled)
            )
        }

        let req = make()

        let resp: DataResponse<Data, AFError> = await withTaskCancellationHandler {
            req.cancel()
        } operation: {
            await req.serializingData().response
        }

        return mapToOptionalData(resp)
    }

    // MARK: - Raw Requests

    /// Generic data request using Alamofire parameter encoding.
    @discardableResult
    internal func requestData(
        url: URLConvertible,
        method: HTTPMethod = .get,
        parameters: Parameters? = nil,
        encoding: ParameterEncoding = URLEncoding.default,
        headers: HTTPHeaders? = nil
    ) async -> AFDataResponse<Data?> {
        await performDataRequest {
            request(
                url,
                method: method,
                parameters: parameters,
                encoding: encoding,
                headers: headers
            )
        }
    }

    /// JSON body request with raw Data (already-encoded JSON).
    @discardableResult
    internal func requestJSON(
        urlString: String,
        method: HTTPMethod,
        json data: Data,
        headers: HTTPHeaders? = nil
    ) async -> AFDataResponse<Data?> {
        // Build URLRequest safely
        guard let url = URL(string: urlString) else {
            return AFDataResponse<Data?>(
                request: nil,
                response: nil,
                data: nil,
                metrics: nil,
                serializationDuration: 0,
                result: .failure(AFError.invalidURL(url: urlString))
            )
        }

        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.httpBody = data
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Apply extra headers if any
        if let headers {
            for h in headers {
                req.setValue(h.value, forHTTPHeaderField: h.name)
            }
        }

        return await performDataRequest {
            request(req)
        }
    }

    /// JSON body request with an Encodable payload (preferred).
    @discardableResult
    internal func requestJSON<T: Encodable & Sendable>(
        urlString: String,
        method: HTTPMethod,
        json body: T,
        encoder: JSONEncoder = JSONEncoder(),
        headers: HTTPHeaders? = nil
    ) async throws -> AFDataResponse<Data?> {
        if Task.isCancelled { throw CancellationError() }
        let data = try encoder.encode(body)
        return await requestJSON(urlString: urlString, method: method, json: data, headers: headers)
    }

    // MARK: - Convenience verbs (GET / DELETE / POST / PUT, legacy)

    @discardableResult
    internal func deleteActual(_ url: URLConvertible) async -> AFDataResponse<Data?> {
        await requestData(url: url, method: .delete, parameters: nil, encoding: URLEncoding.default, headers: nil)
    }

    /// POST with URL-encoded/JSON parameters via AF's ParameterEncoding.
    /// NOTE: if the server expects JSON, prefer `post(_:json:)` or `post(_:sjson:)`.
    @discardableResult
    internal func post(_ url: URLConvertible, params: Parameters?) async -> AFDataResponse<Data?> {
        await requestData(url: url, method: .post, parameters: params, encoding: URLEncoding.default, headers: nil)
    }

    /// POST an Encodable JSON body (preferred).
    @discardableResult
    internal func post<T: Encodable & Sendable>(_ url: URLConvertible, json body: T) async throws -> AFDataResponse<Data?> {
        if Task.isCancelled { throw CancellationError() }
        return try await requestJSON(urlString: try url.asURL().absoluteString, method: .post, json: body)
    }

    /// POST a pre-encoded JSON `Data` body.
    @discardableResult
    internal func post(_ urlString: String, json data: Data) async -> AFDataResponse<Data?> {
        await requestJSON(urlString: urlString, method: .post, json: data)
    }

    /// POST a legacy `Parameters` JSON body (kept for compatibility).
    @discardableResult
    internal func post(_ url: URLConvertible, json params: Parameters?) async throws -> AFDataResponse<Data?> {
        if Task.isCancelled { throw CancellationError() }
        let data = try JSONSerialization.data(withJSONObject: params ?? [:], options: [])
        return await requestJSON(urlString: try url.asURL().absoluteString, method: .post, json: data)
    }

    /// PUT an Encodable JSON body (preferred).
    @discardableResult
    internal func put<T: Encodable & Sendable>(_ url: URLConvertible, json body: T) async throws -> AFDataResponse<Data?> {
        if Task.isCancelled { throw CancellationError() }
        return try await requestJSON(urlString: try url.asURL().absoluteString, method: .put, json: body)
    }

    /// PUT a pre-encoded JSON `Data` body.
    @discardableResult
    internal func put(_ urlString: String, json data: Data) async -> AFDataResponse<Data?> {
        await requestJSON(urlString: urlString, method: .put, json: data)
    }

    /// PUT a legacy `Parameters` JSON body (kept for compatibility).
    @discardableResult
    internal func put(_ url: URLConvertible, json params: Parameters?) async throws -> AFDataResponse<Data?> {
        if Task.isCancelled { throw CancellationError() }
        let data = try JSONSerialization.data(withJSONObject: params ?? [:], options: [])
        return await requestJSON(urlString: try url.asURL().absoluteString, method: .put, json: data)
    }

    // MARK: - Uploads (multipart)

    /// Multipart upload: JPEG data + position.
    @discardableResult
    internal func upload(
        _ url: URLConvertible,
        data: Data,
        position: String = "front"
    ) async -> AFDataResponse<Data?> {
        await performUploadRequest {
            upload(
                multipartFormData: { form in
                    form.append(data, withName: "file", fileName: "file.jpg", mimeType: "image/jpeg")
                    form.append(Data(position.utf8), withName: "position")
                    form.append(Data(String(PreferabliTools.getPreferabliUserId()).utf8), withName: "user_id")
                },
                to: url,
                method: .post
            )
        }
    }
}

// MARK: - SParams normalization + typed convenience

extension Session {

    enum ParamError: LocalizedError {
        case unsupportedValue(String, keyPath: String)

        var errorDescription: String? {
            switch self {
            case .unsupportedValue(let type, let keyPath):
                return "Unsupported JSON value of type \(type) at keyPath '\(keyPath)'. " +
                "Allowed: String, Bool, Int/Double, NSNull, arrays/dicts of those, " +
                "plus Date/URL/UUID/Decimal/NSNumber/Data (with conversions)."
            }
        }
    }

    // Helper to unwrap Any Optional
    private func unwrapOptional(_ any: Any) -> (isOptional: Bool, value: Any?) {
        let mirror = Mirror(reflecting: any)
        guard mirror.displayStyle == .optional else { return (false, any) }
        if let child = mirror.children.first { return (true, child.value) }
        return (true, nil)
    }

    private func toJSONAny(_ v: Sendable, keyPath: String = "$") throws -> Any {
        // 0) Optionals
        let (isOpt, unwrapped) = unwrapOptional(v)
        if isOpt {
            guard let unwrapped else { return NSNull() } // nil -> null
            return try toJSONAny(unwrapped as! Sendable, keyPath: keyPath)
        }

        // 1) Primitives
        switch v {
        case let s as String: return s
        case let b as Bool:   return b

        case let n as Int:    return n
        case let n as Int8:   return Int(n)
        case let n as Int16:  return Int(n)
        case let n as Int32:  return Int(n)
        case let n as Int64:  return n
        case let n as UInt:   return n
        case let n as UInt8:  return Int(n)
        case let n as UInt16: return Int(n)
        case let n as UInt32: return Int(n)
        case let n as UInt64: return n
        case let n as Double: return n
        case let n as Float:  return Double(n)
        case let n as NSNumber: return n
        case let d as Decimal:  return NSDecimalNumber(decimal: d)

        case is NSNull:       return NSNull()

        // 2) Foundation “stringifiable” types
        case let date as Date:
            let f = ISO8601DateFormatter()
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.string(from: date)
        case let url as URL:
            return url.absoluteString
        case let uuid as UUID:
            return uuid.uuidString

        // 3) Data policy: base64 string
        case let data as Data:
            return data.base64EncodedString()

        // 4) Arrays
        case let arr as [Sendable]:
            return try arr.enumerated().map { idx, el in
                try toJSONAny(el, keyPath: "\(keyPath)[\(idx)]")
            }

        // 5) Dictionaries
        case let dict as [String: Sendable]:
            var out: [String: Any] = [:]
            out.reserveCapacity(dict.count)
            for (k, val) in dict {
                out[k] = try toJSONAny(val, keyPath: "\(keyPath).\(k)")
            }
            return out

        default:
            throw ParamError.unsupportedValue("\(type(of: v))", keyPath: keyPath)
        }
    }

    private func toJSONAnyDict(_ params: SParams) throws -> [String: Any] {
        try toJSONAny(params) as! [String: Any]
    }

    /// Turn SParams into URLQueryItem(s), using bracketed repeated keys for arrays:
    ///   ["variant_ids": [1,2,3]]  ->  variant_ids[]=1&variant_ids[]=2&variant_ids[]=3
    private func toQueryItems(_ params: SParams) throws -> [URLQueryItem] {
        var out: [URLQueryItem] = []
        out.reserveCapacity(params.count)

        for (k, v) in params {
            switch v {
            case let s as String:
                out.append(URLQueryItem(name: k, value: s))
            case let b as Bool:
                out.append(URLQueryItem(name: k, value: b ? "true" : "false"))

            case let n as Int:     out.append(URLQueryItem(name: k, value: String(n)))
            case let n as Int64:   out.append(URLQueryItem(name: k, value: String(n)))
            case let n as UInt:    out.append(URLQueryItem(name: k, value: String(n)))
            case let n as UInt64:  out.append(URLQueryItem(name: k, value: String(n)))
            case let n as Double:  out.append(URLQueryItem(name: k, value: String(n)))
            case let n as Float:   out.append(URLQueryItem(name: k, value: String(n)))

            case is NSNull:
                out.append(URLQueryItem(name: k, value: ""))

            case let arr as [Sendable]:
                let key = k.hasSuffix("[]") ? k : "\(k)[]"
                for elem in arr {
                    out.append(URLQueryItem(name: key, value: try toQueryLeaf(elem)))
                }

            default:
                throw ParamError.unsupportedValue("\(type(of: v))", keyPath: "$.\(k)")
            }
        }

        return out
    }

    private func toQueryLeaf(_ v: Sendable) throws -> String {
        switch v {
        case let s as String: return s
        case let b as Bool:   return b ? "true" : "false"
        case let n as Int:    return String(n)
        case let n as Int64:  return String(n)
        case let n as UInt:   return String(n)
        case let n as UInt64: return String(n)
        case let n as Double: return String(n)
        case let n as Float:  return String(n)
        default:
            throw ParamError.unsupportedValue("\(type(of: v))", keyPath: "$[]")
        }
    }

    // MARK: - SParams-based verbs

    /// GET with SParams → query string
    @discardableResult
    internal func get(_ url: URLConvertible, sparams: SParams? = nil) async throws -> AFDataResponse<Data?> {
        if Task.isCancelled { throw CancellationError() }

        let base = try url.asURL().absoluteString
        guard let sparams else {
            return await requestData(url: base, method: .get, parameters: nil, encoding: URLEncoding.default, headers: nil)
        }

        guard var comps = URLComponents(string: base) else {
            throw AFError.invalidURL(url: base)
        }

        var items = comps.queryItems ?? []
        items.append(contentsOf: try toQueryItems(sparams))
        comps.queryItems = items

        let finalURL = comps.string ?? base
        return await requestData(url: finalURL, method: .get, parameters: nil, encoding: URLEncoding.default, headers: nil)
    }

    /// POST with SParams → JSON body
    @discardableResult
    internal func post(_ url: URLConvertible, sjson: SParams) async throws -> AFDataResponse<Data?> {
        if Task.isCancelled { throw CancellationError() }
        let obj = try toJSONAnyDict(sjson)
        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        return await requestJSON(urlString: try url.asURL().absoluteString, method: .post, json: data)
    }

    /// PUT with SParams → JSON body
    @discardableResult
    internal func put(_ url: URLConvertible, sjson: SParams) async throws -> AFDataResponse<Data?> {
        if Task.isCancelled { throw CancellationError() }
        let obj = try toJSONAnyDict(sjson)
        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        return await requestJSON(urlString: try url.asURL().absoluteString, method: .put, json: data)
    }
}

// MARK: - Typed convenience (unchanged semantics, now cancellation-cooperative via the raw helpers)

extension Session {
    private struct _EmptyEncodable: Encodable, Sendable {}

    internal func get<T: Decodable>(
        _ url: URLConvertible,
        sparams: SParams? = nil,
        decoder: JSONDecoder = .preferabli()
    ) async throws -> T {
        if Task.isCancelled { throw CancellationError() }

        let requestCollectionId = collectionIdFromURL(url)
        let raw = try await get(url, sparams: sparams)
        let validated = try await APIService.continueOrThrowPreferabliException(response: raw)

        guard let data = validated.data else { throw PreferabliException(type: .JSONError) }

        do {
            let decoded = try decoder.decode(T.self, from: data)

            if let http = validated.response,
               let cid = requestCollectionId,
               let etag = http.valueInsensitive(for: "Collection-ETag")
                ?? http.valueInsensitive(for: "collection_etag") {
                CollectionETagStore.save(etag, for: cid)
            }

            return decoded
        } catch let decErr as DecodingError {
            let endpoint = (try? url.asURL().absoluteString)
            let status = validated.response?.statusCode
            throw PreferabliException.fromDecodingError(
                decErr,
                endpoint: endpoint,
                method: "GET",
                status: status,
                raw: data,
                expecting: T.self
            )
        }
    }

    internal func getText(
        _ url: URLConvertible,
        sparams: SParams? = nil
    ) async throws -> String {
        if Task.isCancelled { throw CancellationError() }

        let raw = try await get(url, sparams: sparams)
        let validated = try await APIService.continueOrThrowPreferabliException(response: raw)

        guard let data = validated.data else {
            throw PreferabliException(type: .JSONError, message: "Empty response body while expecting text.")
        }

        guard let text = String(data: data, encoding: .utf8) else {
            let snippet = String(decoding: data.prefix(300), as: UTF8.self)
            throw PreferabliException(
                type: .JSONError,
                message: "Unable to decode response as UTF-8 text.\n── Raw (first 300 bytes as UTF8 lossy) ──\n\(snippet)\n────────",
                code: validated.response?.statusCode ?? 0
            )
        }

        return text
    }

    @discardableResult
    internal func delete(_ url: URLConvertible) async throws {
        if Task.isCancelled { throw CancellationError() }
        let raw = await deleteActual(url)
        _ = try await APIService.continueOrThrowPreferabliException(response: raw)
    }

    @discardableResult
    internal func delete<T: Decodable>(
        _ url: URLConvertible,
        decoder: JSONDecoder = .preferabli()
    ) async throws -> T {
        if Task.isCancelled { throw CancellationError() }

        let requestCollectionId = collectionIdFromURL(url)
        let raw = await deleteActual(url)
        let validated = try await APIService.continueOrThrowPreferabliException(response: raw)

        guard let data = validated.data else {
            if T.self == EmptyResponse.self { return EmptyResponse() as! T }
            throw PreferabliException(type: .JSONError)
        }

        do {
            let decoded = try decoder.decode(T.self, from: data)

            if let http = validated.response,
               let cid = requestCollectionId,
               let etag = http.valueInsensitive(for: "Collection-ETag")
                ?? http.valueInsensitive(for: "collection_etag") {
                CollectionETagStore.save(etag, for: cid)
            }

            return decoded
        } catch let decErr as DecodingError {
            let endpoint = (try? url.asURL().absoluteString)
            let status = validated.response?.statusCode
            throw PreferabliException.fromDecodingError(
                decErr,
                endpoint: endpoint,
                method: "DELETE",
                status: status,
                raw: data,
                expecting: T.self
            )
        }
    }

    internal func post<T: Decodable>(
        _ url: URLConvertible,
        sjson: SParams,
        decoder: JSONDecoder = .preferabli()
    ) async throws -> T {
        if Task.isCancelled { throw CancellationError() }

        let requestCollectionId = collectionIdFromURL(url)
        let raw = try await post(url, sjson: sjson)
        let validated = try await APIService.continueOrThrowPreferabliException(response: raw)

        guard let data = validated.data else { throw PreferabliException(type: .JSONError) }

        do {
            let decoded = try decoder.decode(T.self, from: data)

            if let http = validated.response,
               let cid = requestCollectionId,
               let etag = http.valueInsensitive(for: "Collection-ETag")
                ?? http.valueInsensitive(for: "collection_etag") {
                CollectionETagStore.save(etag, for: cid)
            }

            return decoded
        } catch let decErr as DecodingError {
            let endpoint = (try? url.asURL().absoluteString)
            let status = validated.response?.statusCode
            throw PreferabliException.fromDecodingError(
                decErr,
                endpoint: endpoint,
                method: "POST",
                status: status,
                raw: data,
                expecting: T.self
            )
        }
    }

    internal func put<T: Decodable>(
        _ url: URLConvertible,
        sjson: SParams,
        decoder: JSONDecoder = .preferabli()
    ) async throws -> T {
        if Task.isCancelled { throw CancellationError() }

        let requestCollectionId = collectionIdFromURL(url)
        let raw = try await put(url, sjson: sjson)
        let validated = try await APIService.continueOrThrowPreferabliException(response: raw)

        guard let data = validated.data else { throw PreferabliException(type: .JSONError) }

        do {
            let decoded = try decoder.decode(T.self, from: data)

            if let http = validated.response,
               let cid = requestCollectionId,
               let etag = http.valueInsensitive(for: "Collection-ETag")
                ?? http.valueInsensitive(for: "collection_etag") {
                CollectionETagStore.save(etag, for: cid)
            }

            return decoded
        } catch let decErr as DecodingError {
            let endpoint = (try? url.asURL().absoluteString)
            let status = validated.response?.statusCode
            throw PreferabliException.fromDecodingError(
                decErr,
                endpoint: endpoint,
                method: "PUT",
                status: status,
                raw: data,
                expecting: T.self
            )
        }
    }

    internal func upload<T: Decodable>(
        _ url: URLConvertible,
        data: Data,
        position: String = "front",
        decoder: JSONDecoder = .preferabli()
    ) async throws -> T {
        if Task.isCancelled { throw CancellationError() }

        let requestCollectionId = collectionIdFromURL(url)
        let raw = await upload(url, data: data, position: position)
        let validated = try await APIService.continueOrThrowPreferabliException(response: raw)

        guard let data = validated.data else {
            if T.self == EmptyResponse.self { return EmptyResponse() as! T }
            throw PreferabliException(type: .JSONError)
        }

        do {
            let decoded = try decoder.decode(T.self, from: data)

            if let http = validated.response,
               let cid = requestCollectionId,
               let etag = http.valueInsensitive(for: "Collection-ETag")
                ?? http.valueInsensitive(for: "collection_etag") {
                CollectionETagStore.save(etag, for: cid)
            }

            return decoded
        } catch let decErr as DecodingError {
            let endpoint = (try? url.asURL().absoluteString)
            let status = validated.response?.statusCode
            throw PreferabliException.fromDecodingError(
                decErr,
                endpoint: endpoint,
                method: "POST",
                status: status,
                raw: data,
                expecting: T.self
            )
        }
    }

    // MARK: - URL helpers

    private func collectionIdFromURL(_ urlConvertible: URLConvertible) -> Int? {
        guard let url = try? urlConvertible.asURL() else { return nil }

        let partsLower = url.path
            .split(separator: "/")
            .map { String($0).lowercased() }

        guard let idx = partsLower.firstIndex(of: "collections"),
              partsLower.indices.contains(partsLower.index(after: idx)) else {
            return nil
        }

        let rawParts = url.path.split(separator: "/").map(String.init)
        let idCandidate = rawParts[rawParts.index(rawParts.startIndex, offsetBy: idx + 1)]
        let digits = idCandidate.filter { $0.isNumber }
        return Int(digits)
    }

    internal struct EmptyResponse: Codable, Sendable {
        init() {}
    }
}
