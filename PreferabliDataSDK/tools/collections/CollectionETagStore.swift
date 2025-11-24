//
//  CollectionETagStore.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/30/25.
//

import Foundation

enum CollectionETagStore {
    private static func key(for collectionId: Int) -> String { "collection_etags_\(collectionId)" }

    static func save(_ headerValue: String, for collectionId: Int) {
        let parts = headerValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return }

        var saved = Storage.getKeyStore().stringArray(forKey: key(for: collectionId)) ?? []
        var changed = false
        for p in parts where !saved.contains(p) {
            saved.append(p)
            changed = true
        }
        if changed {
            Storage.getKeyStore().set(saved, forKey: key(for: collectionId))
        }
    }
}

extension HTTPURLResponse {
    func valueInsensitive(for name: String) -> String? {
        let target = name.lowercased().replacingOccurrences(of: "_", with: "-")
        for (k, v) in allHeaderFields {
            let key = String(describing: k).lowercased().replacingOccurrences(of: "_", with: "-")
            if key == target { return String(describing: v) }
        }
        return nil
    }
}
