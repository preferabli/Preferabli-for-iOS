//
//  SessionDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/22/25.
//

import Foundation

/// Represents a session returned from the API.
public struct SessionDTO: Decodable, Sendable {
    public let id: Int?
    public let user_id: Int?
    public let customer_id: Int?
    public let token_access: String?
    public let token_refresh: String?
    public let intercom_hmac: String?

    /// Optionally provide a helper method for persistence.
    public func saveSession() async {
        let defaults = Storage.getKeyStore()
        defaults.set(token_access, forKey: "access_token")
        defaults.set(token_refresh, forKey: "refresh_token")
        defaults.set(intercom_hmac, forKey: "intercom_hmac")
        await Preferabli.main.api.refreshDefaults()
    }
}
