//
//  PushNotificationReceipt.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 2/26/26.
//


import Foundation
import SwiftData

@Model
public final class PushNotificationReceipt {
    /// Prefer OneSignal's notification id when available; otherwise we fallback to a locally generated id.
    /// Marked unique to support true upsert behavior.
    @Attribute(.unique)
    public var notification_id: String

    public var title: String
    public var message: String
    public var received_at: Date
    public var updated_at: Date

    public init(
        notification_id: String,
        title: String,
        message: String,
        received_at: Date = .now,
        updated_at: Date = .now
    ) {
        self.notification_id = notification_id
        self.title = title
        self.message = message
        self.received_at = received_at
        self.updated_at = updated_at
    }

    public static func predicate(forNotificationId id: String) -> Predicate<PushNotificationReceipt> {
        #Predicate { $0.notification_id == id }
    }
}
