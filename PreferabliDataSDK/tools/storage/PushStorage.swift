//
//  PushStorage.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 2/26/26.
//

import SwiftData
import Foundation

public enum PushStorage {

    public static func storeURL(appGroupID: String) -> URL {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            fatalError("Missing App Group container for \(appGroupID)")
        }
        return dir.appendingPathComponent("PreferabliPush.sqlite")
    }

    public static func makeContainer(appGroupID: String) throws -> ModelContainer {
        let schema = makeSchema()
        let url = storeURL(appGroupID: appGroupID)
        let config = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [config])
    }
    
    public static func makeSchema() -> Schema {
        Schema([PushNotificationReceipt.self])
    }
}

extension Storage {

    /// Shared location readable/writable by both the app + NotificationServiceExtension.
    public static func appGroupStoreURL(appGroupID: String) -> URL {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            fatalError("Missing App Group container for \(appGroupID). Check Signing & Capabilities.")
        }
        return dir.appendingPathComponent("PreferabliSDK.sqlite")
    }

    /// Create a container pointing at the App Group sqlite.
    @MainActor
    public static func makeAppGroupContainer(appGroupID: String) -> ModelContainer {
        let schema = makeSchema()
        let url = appGroupStoreURL(appGroupID: appGroupID)
        let config = ModelConfiguration(schema: schema, url: url)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            NSLog("[PreferabliDataSDK] Failed to create App Group container: \(error)")
            fatalError("Unable to create App Group ModelContainer: \(error)")
        }
    }
    
    @discardableResult
    nonisolated static public func upsertPushNotificationReceipt(
        notificationID: String,
        title: String,
        message: String,
        receivedAt: Date = .now,
        in ctx: ModelContext
    ) throws -> PushNotificationReceipt {

        try checkCancelled()

        var fd = FetchDescriptor<PushNotificationReceipt>(
            predicate: PushNotificationReceipt.predicate(forNotificationId: notificationID)
        )
        fd.fetchLimit = 1

        if let existing = try ctx.fetch(fd).first {
            existing.title = title
            existing.message = message
            existing.updated_at = .now
            // Keep earliest received_at (optional; you can also overwrite if you prefer)
            existing.received_at = min(existing.received_at, receivedAt)
            return existing
        }

        let created = PushNotificationReceipt(
            notification_id: notificationID,
            title: title,
            message: message,
            received_at: receivedAt,
            updated_at: .now
        )
        ctx.insert(created)
        return created
    }
}
