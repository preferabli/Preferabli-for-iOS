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
    
    private func mapToOptionalData(_ resp: DataResponse<Data, AFError>) -> DataResponse<Data?, AFError> {
      .init(
        request: resp.request,
        response: resp.response, data: resp.data,
        metrics: resp.metrics,
        serializationDuration: resp.serializationDuration,
        result: resp.result.map { Optional($0) }
      )
    }

  /// Generic data request using Alamofire parameter encoding.
  @discardableResult
  internal func requestData(url: URLConvertible, method: HTTPMethod = .get, parameters: Parameters? = nil, encoding: ParameterEncoding = URLEncoding.default, headers: HTTPHeaders? = nil) async -> AFDataResponse<Data?> {
    let logging = await MainActor.run { Preferabli.main.loggingEnabled }
    if logging {
        print(method.rawValue, (try? url.asURL().absoluteString) ?? "<invalid url>")
      if let parameters { print(parameters) }
    }

    let resp: DataResponse<Data, AFError> = await request(
      url,
      method: method,
      parameters: parameters,
      encoding: encoding,
      headers: headers
    )
    .serializingData()
    .response

    return mapToOptionalData(resp)
  }

  /// JSON body request with raw Data (already-encoded JSON).
  @discardableResult
  internal func requestJSON(urlString: String, method: HTTPMethod, json data: Data, headers: HTTPHeaders? = nil) async -> AFDataResponse<Data?> {
    var req = URLRequest(url: URL(string: urlString)!)
    req.httpMethod = method.rawValue
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = data

    let logging = await MainActor.run { Preferabli.main.loggingEnabled }
    if logging {
      print(method.rawValue, urlString)
      print(String(data: data, encoding: .utf8) ?? "<binary>")
    }

    let resp: DataResponse<Data, AFError> = await request(req)
      .serializingData()
      .response

    return mapToOptionalData(resp)
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
    let data = try encoder.encode(body)
    return await requestJSON(urlString: urlString, method: method, json: data, headers: headers)
  }

  // MARK: - Convenience verbs (GET / DELETE)

  @discardableResult
  internal func delete(_ url: URLConvertible) async -> AFDataResponse<Data?> {
    await requestData(url: url, method: .delete, parameters: nil, encoding: URLEncoding.default, headers: nil)
  }

  // MARK: - Convenience verbs (POST)

  /// POST with URL-encoded/JSON parameters via AF's ParameterEncoding.
  @discardableResult
  internal func post(_ url: URLConvertible, params: Parameters?) async -> AFDataResponse<Data?> {
    // If you intend true JSON here, consider using JSONEncoding.default
    await requestData(url: url, method: .post, parameters: params, encoding: URLEncoding.default, headers: nil)
  }

  /// POST an Encodable JSON body (preferred).
  @discardableResult
  internal func post<T: Encodable & Sendable>(_ url: URLConvertible, json body: T) async throws -> AFDataResponse<Data?> {
    try await requestJSON(urlString: try url.asURL().absoluteString, method: .post, json: body)
  }

  /// POST a pre-encoded JSON `Data` body.
  @discardableResult
  internal func post(_ urlString: String, json data: Data) async -> AFDataResponse<Data?> {
    await requestJSON(urlString: urlString, method: .post, json: data)
  }

  /// POST a legacy `Parameters` JSON body (kept for compatibility).
  @discardableResult
  internal func post(_ url: URLConvertible, json params: Parameters?) async throws -> AFDataResponse<Data?> {
    let data = try JSONSerialization.data(withJSONObject: params ?? [:], options: [])
    return await requestJSON(urlString: try url.asURL().absoluteString, method: .post, json: data)
  }

  // MARK: - Convenience verbs (PUT)

  /// PUT an Encodable JSON body (preferred).
  @discardableResult
  internal func put<T: Encodable & Sendable>(_ url: URLConvertible, json body: T) async throws -> AFDataResponse<Data?> {
    try await requestJSON(urlString: try url.asURL().absoluteString, method: .put, json: body)
  }

  /// PUT a pre-encoded JSON `Data` body.
  @discardableResult
  internal func put(_ urlString: String, json data: Data) async -> AFDataResponse<Data?> {
    await requestJSON(urlString: urlString, method: .put, json: data)
  }

  /// PUT a legacy `Parameters` JSON body (kept for compatibility).
  @discardableResult
  internal func put(_ url: URLConvertible, json params: Parameters?) async throws -> AFDataResponse<Data?> {
    let data = try JSONSerialization.data(withJSONObject: params ?? [:], options: [])
    return await requestJSON(urlString: try url.asURL().absoluteString, method: .put, json: data)
  }

  // MARK: - Uploads (multipart)

  /// Multipart upload: JPEG data + user_id.
  @discardableResult
  internal func uploadJPEG(_ url: URLConvertible, data: Data) async -> AFDataResponse<Data?> {
    let logging = await MainActor.run { Preferabli.main.loggingEnabled }
    let absolute = (try? url.asURL().absoluteString) ?? "<invalid url>"

    if logging { print("POST (multipart)", absolute, "size:", data.count) }

    let resp: DataResponse<Data, AFError> = await upload(
      multipartFormData: { form in
        form.append(data, withName: "file", fileName: "file.jpg", mimeType: "image/jpeg")
        let uid = String(PreferabliTools.getPreferabliUserId())
        form.append(uid.data(using: .utf8)!, withName: "user_id")
      },
      to: url,
      method: .post
    )
    .serializingData()
    .response

    return mapToOptionalData(resp)
  }

  /// Multipart upload: JPEG data + position.
  @discardableResult
  internal func uploadJPEG(_ url: URLConvertible, data: Data, position: String) async -> AFDataResponse<Data?> {
    let logging = await MainActor.run { Preferabli.main.loggingEnabled }
    let absolute = (try? url.asURL().absoluteString) ?? "<invalid url>"

    if logging { print("POST (multipart)", absolute, "size:", data.count, "position:", position) }

    let resp: DataResponse<Data, AFError> = await upload(
      multipartFormData: { form in
        form.append(data, withName: "file", fileName: "file.jpg", mimeType: "image/jpeg")
        form.append(position.data(using: .utf8)!, withName: "position")
      },
      to: url,
      method: .post
    )
    .serializingData()
    .response

    return mapToOptionalData(resp)
  }
}

extension Session {

    enum ParamError: Error, CustomStringConvertible {
        case unsupportedValue(String, keyPath: String)
        var description: String {
            switch self {
            case .unsupportedValue(let type, let keyPath):
                return "Unsupported JSON value of type \(type) at \(keyPath)"
            }
        }
    }

    // JSON-normalization (recursive)
    private func toJSONAny(_ v: Sendable, keyPath: String = "$") throws -> Any {
        switch v {
        case let s as String: return s
        case let b as Bool:   return b

        // Numbers
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

        // Null
        case is NSNull:       return NSNull()

        // Arrays
        case let arr as [Sendable]:
            return try arr.enumerated().map { idx, el in
                try toJSONAny(el, keyPath: "\(keyPath)[\(idx)]")
            }

        // Dictionaries
        case let dict as [String: Sendable]:
            var out: [String: Any] = [:]
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

    // Query normalization (flat keys only; arrays joined by comma)
    private func toQueryDict(_ params: SParams) throws -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in params {
            switch v {
            case let s as String: out[k] = s
            case let b as Bool: out[k] = b ? "true" : "false"
            case let n as Int: out[k] = String(n)
            case let n as Int64: out[k] = String(n)
            case let n as UInt: out[k] = String(n)
            case let n as UInt64: out[k] = String(n)
            case let n as Double: out[k] = String(n)
            case let n as Float: out[k] = String(n)
            case is NSNull: out[k] = ""
            case let arr as [Sendable]:
                // simple convention: join as comma list (adjust to your API’s expectations)
                out[k] = try arr.map { try toQueryLeaf($0) }.joined(separator: ",")
            default:
                throw ParamError.unsupportedValue("\(type(of: v))", keyPath: "$.\(k)")
            }
        }
        return out
    }

    private func toQueryLeaf(_ v: Sendable) throws -> String {
        switch v {
        case let s as String: return s
        case let b as Bool: return b ? "true" : "false"
        case let n as Int: return String(n)
        case let n as Int64: return String(n)
        case let n as UInt: return String(n)
        case let n as UInt64: return String(n)
        case let n as Double: return String(n)
        case let n as Float: return String(n)
        default:
            throw ParamError.unsupportedValue("\(type(of: v))", keyPath: "$[]")
        }
    }
    
    // GET with SParams → query string
    @discardableResult
    internal func get(_ url: URLConvertible, sparams: SParams? = nil) async throws -> AFDataResponse<Data?> {
        let base = try url.asURL().absoluteString
        guard let sparams else {
            return await requestData(url: base, method: .get, parameters: nil, encoding: URLEncoding.default, headers: nil)
        }

        // Convert your [String: Sendable] once → [String:String] (Sendable)
        let query = try toQueryDict(sparams)

        var comps = URLComponents(string: base)!
        var items = comps.queryItems ?? []
        items.append(contentsOf: query.map { URLQueryItem(name: $0.key, value: $0.value) })
        comps.queryItems = items

        let finalURL = comps.string!
        return await requestData(url: finalURL, method: .get, parameters: nil, encoding: URLEncoding.default, headers: nil)
    }


    // POST with SParams → JSON body
    @discardableResult
    internal func post(_ url: URLConvertible, sjson: SParams) async throws -> AFDataResponse<Data?> {
        let obj = try toJSONAnyDict(sjson)
        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        return await requestJSON(urlString: try url.asURL().absoluteString, method: .post, json: data)
    }

    // PUT with SParams → JSON body
    @discardableResult
    internal func put(_ url: URLConvertible, sjson: SParams) async throws -> AFDataResponse<Data?> {
        let obj = try toJSONAnyDict(sjson)
        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        return await requestJSON(urlString: try url.asURL().absoluteString, method: .put, json: data)
    }
}
