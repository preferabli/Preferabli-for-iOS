//
//  PreferabliException.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/11/16.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//

import Foundation

/// Some kind of error has occurred. See ``getMessage()`` for more information on what happened.
public struct PreferabliException : Error {
    
    private var type : PreferabliExceptionType
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
        var mesageToReturn = message
        if (message.isEmptyOrWhitespace) {
            mesageToReturn = type.getMessage()
        }
        
        if (code != 0) {
            mesageToReturn = String(code) + " " + mesageToReturn!
        }
        
        return mesageToReturn!
    }
    
    var localizedDescription: String {
        return getMessage()
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
            return "JSON error. Contact support."
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
        }
    }
}
