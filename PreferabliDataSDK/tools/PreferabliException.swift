//
//  PreferabliException.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/11/16.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//

import Foundation

/// Some kind of error has occurred. See ``getMessage()`` for more information on what happened.
public struct PreferabliException: Error, LocalizedError {

    public var type : PreferabliExceptionType
    private var message : String?
    private var code : Int
    
    public init(type : PreferabliExceptionType, message : String? = nil, code : Int = 0) {
        self.type = type
        self.message = message
        self.code = code
    }
    
    internal init(error : APIError) {
        self.type = .APIError
        self.message = error.message ?? "Unknown issue. Contact support."
        self.code = error.code ?? 0
    }
    
    internal init(error : Error) {
        self.type = .OtherError
        self.message = error.localizedDescription
        self.code = 0
    }
    
    
    /// A detailed description of what went wrong.
    /// - Returns: a string description.
    public func getMessage() -> String {
        if let message,
           !message.isEmptyOrWhitespace() {
            return message
        }

        return type.getMessage()
    }

    public var errorDescription: String? {
        getMessage()
    }
    
    /// Gets an error code if available. Useful especially in case of  ``PreferabliExceptionType/APIError``.
    /// - Returns: a code if available. Returns 0 if not.
    public func getCode() -> Int {
        return code
    }
}

/// Type of error that occurred.
public enum PreferabliExceptionType : Sendable {
    /// An error from the API.
    case APIError
    /// A network error.
    case NetworkError
    /// An unknown / other error.
    case OtherError
    /// An error decoding JSON.
    case JSONError
    /// The data you requested is already loaded.
    case AlreadyLoaded
    /// An error in the data that came back from the API.
    case BadData
    /// User / customer not logged in.
    case InvalidAccessToken
    /// SDK not initialized properly.
    case InvalidClientInterface
    /// SDK not initialized properly.
    case InvalidIntegrationId
    /// A database error.
    case DatabaseError
    /// A mapping error.
    case MappingNotFound
    /// An error in the SwiftData database.
    case BadSwiftData
    /// User or system cancelled the request
    case Cancelled

    
    /// A general description of this type of exception.
    /// - Returns: a string description of the type.
    public func getMessage() -> String {
        switch self {
        case .APIError:
            return "API error."
        case .NetworkError:
            return "Network issue."
        case .OtherError:
            return "Other / unknown issue. Contact support."
        case .JSONError:
            return "JSON error. Decoding failed. Contact support."
        case .AlreadyLoaded:
            return "Already loaded this."
        case .BadData:
            return "API returned bad data. Contact support."
        case .InvalidAccessToken:
            return "You need to login a customer / user first."
        case .InvalidClientInterface:
            return "Invalid CLIENT_INTERFACE used to initialize the SDK."
        case .InvalidIntegrationId:
            return "Invalid INTEGRATION_ID used to initialize the SDK."
        case .DatabaseError:
            return "Database error. Try clearing the SDK database cache."
        case .MappingNotFound:
            return "Could not match your supplied ids to a Preferabli product. Are you sure this product is mapped?"
        case .BadSwiftData:
            return "SwiftData returned bad data. Contact support."
        case .Cancelled:
            return "Request cancelled."
        }
    }
}

extension PreferabliException {
    /// Produce a rich JSONError from a DecodingError, including codingPath + endpoint + raw snippet.
    static func fromDecodingError(
        _ err: DecodingError,
        endpoint: String? = nil,
        method: String? = nil,
        status: Int? = nil,
        raw: Data? = nil,
        expecting: Any.Type? = nil
    ) -> PreferabliException {

        func pathString(_ path: [CodingKey]) -> String {
            guard !path.isEmpty else { return "«root»" }
            return path.map { key in
                if let i = key.intValue { return "[\(i)]" }
                return key.stringValue
            }.joined(separator: ".")
        }

        let (title, details, path): (String, String, String) = {
            switch err {
            case .typeMismatch(let expected, let ctx):
                return ("Type mismatch",
                        "Expected \(expected), \(ctx.debugDescription)",
                        pathString(ctx.codingPath))
            case .valueNotFound(let expected, let ctx):
                return ("Value not found",
                        "Missing value for \(expected): \(ctx.debugDescription)",
                        pathString(ctx.codingPath))
            case .keyNotFound(let key, let ctx):
                return ("Key not found",
                        "Missing key '\(key.stringValue)': \(ctx.debugDescription)",
                        pathString(ctx.codingPath))
            case .dataCorrupted(let ctx):
                var det = ctx.debugDescription
                // If Foundation says “not valid JSON” but we *did* have bytes,
                // this is often a numeric-conversion issue (e.g., Double -> Int).
                if det.localizedCaseInsensitiveContains("not valid json"),
                   let raw, !raw.isEmpty {
                    det += " (Hint: this often happens when a non-integral JSON number is decoded into Int. " +
                           "Check numeric fields like lat/lon/prices for Int vs Double mismatches.)"
                }
                return ("Data corrupted", det, pathString(ctx.codingPath))
            @unknown default:
                return ("Decoding error",
                        String(describing: err),
                        "«unknown»")
            }
        }()

        var lines: [String] = []
        if let endpoint { lines.append("[\(endpoint)]") }
        if let method, let status { lines.append("\(method) \(status)") }
        lines.append("\(title) at \(path) — \(details)")
        if let expecting { lines.append("While decoding: \(expecting)") }

        if let raw, !raw.isEmpty {
            let snippet = String(decoding: raw.prefix(1000), as: UTF8.self)
            lines.append("── Raw (first 1000 bytes) ──")
            lines.append(snippet)
            lines.append("────────")
        }

        return PreferabliException(type: .JSONError,
                                   message: lines.joined(separator: "\n"),
                                   code: 0)
    }

    /// Wrap arbitrary Error, preferring decoding details.
    static func smartWrap(_ error: Error, endpoint: String? = nil, raw: Data? = nil) -> PreferabliException {
        if let e = error as? PreferabliException { return e }
        if let d = error as? DecodingError      { return .fromDecodingError(d, endpoint: endpoint, raw: raw) }
        return PreferabliException(error: error)
    }

    /// Make a new exception with endpoint/raw context appended to the message.
    func withContext(endpoint: String?, raw: Data?) -> PreferabliException {
        var txt = self.getMessage()
        if let endpoint { txt = "[\(endpoint)] " + txt }
        if let raw, !raw.isEmpty {
            let snippet = String(decoding: raw.prefix(1000), as: UTF8.self)
            txt += "\n── Raw (first 1000 bytes) ──\n\(snippet)\n────────"
        }
        return PreferabliException(type: type, message: txt, code: self.getCode())
    }
}
