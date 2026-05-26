//
//  PreferabliTools.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/10/16.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//

import Foundation
import UIKit
import Alamofire
import SwiftData
import CoreLocation
import AVFoundation
import Contacts
import Photos
import Mixpanel

/// Contains lots of helper methods for private use within Preferabli's projects.
public class PreferabliTools {

    // Async gate (serializes logouts)
    private actor LogoutGate {
        private var inProgress = false

        func begin() -> Bool {
            guard !inProgress else { return false }
            inProgress = true
            return true
        }

        func end() { inProgress = false }
        func isRunning() -> Bool { inProgress }
    }

    private static let gate = LogoutGate()

    // Sync mirror for MainActor-only callsites (e.g., Storage.withContext)
    @MainActor private static var _logoutFlag: Bool = false

    @MainActor internal static func _setLoggingOutFlag(_ v: Bool) {
        _logoutFlag = v
    }

    /// MainActor-safe *sync* check (only call from MainActor code)
    @MainActor internal static func isLoggingOutSync() -> Bool {
        _logoutFlag
    }

    // MARK: Public logout API

    /// Begins logout if one is not already in progress.
    internal static func beginLogout() async -> Bool {
        let ok = await gate.begin()
        if ok {
            await MainActor.run { _setLoggingOutFlag(true) }
        }
        return ok
    }

    internal static func endLogout() async {
        await gate.end()
        await MainActor.run { _setLoggingOutFlag(false) }
    }

    internal static func isLoggingOut() async -> Bool {
        await gate.isRunning()
    }

    /// Helper wrapper to serialize logouts.
    internal static func withLogout<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        guard await beginLogout() else { throw CancellationError() }
        defer { Task { await endLogout() } }
        return try await body()
    }

    // MARK: Inflight cancellation registry

    private actor CancelRegistry {
        private var cancellers: [UUID: @Sendable () -> Void] = [:]

        func register(_ cancel: @escaping @Sendable () -> Void) -> UUID {
            let id = UUID()
            cancellers[id] = cancel
            return id
        }

        func unregister(_ id: UUID) {
            cancellers[id] = nil
        }

        func cancelAll() {
            let all = cancellers.values
            cancellers.removeAll(keepingCapacity: true)
            for c in all { c() }
        }
    }

    private static let registry = CancelRegistry()

    internal static func cancelAllInflight() async {
        await registry.cancelAll()
    }

    internal static func registerForLogoutCancellation(
        _ cancel: @escaping @Sendable () -> Void
    ) async -> UUID {
        await registry.register(cancel)
    }

    internal static func unregisterLogoutCancellation(_ token: UUID) async {
        await registry.unregister(token)
    }

    /// Convenience: spawn a cancellable task (Task<Void, Never>) that gets cancelled on logout.
    @discardableResult
    public static func detachedCancellableTask(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {

        let task = Task.detached(priority: priority) {
            await operation()
        }

        Task {
            let token = await registry.register { task.cancel() }
            _ = await task.result
            await registry.unregister(token)
        }

        return task
    }
    
    // PreferabliTools.swift

    @discardableResult
    public static func detachedCancellableTask(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> Void,
        onError: (@Sendable (Error) -> Void)? = nil
    ) -> Task<Void, Never> {

        let task = Task.detached(priority: priority) {
            do {
                try await operation()
            } catch is CancellationError {
                // ignore
            } catch {
                onError?(error)
            }
        }

        Task {
            let token = await registry.register { task.cancel() }
            _ = await task.result
            await registry.unregister(token)
        }

        return task
    }
    
    internal class func saveCollectionEtag(response : AFDataResponse<Data?>, collectionId : Int) {
        if (response.response != nil) {
            let headers = response.response!.allHeaderFields
            if (!(headers["collection_etag"] as? String).isEmptyOrWhitespace) {
                var collectionEtags = Storage.getKeyStore().stringArray(forKey: "collection_etags_" + NSNumber(value: collectionId).stringValue) ?? Array<String>()
                if (!collectionEtags.contains(headers["collection_etag"] as! String)) {
                    collectionEtags.append(headers["collection_etag"] as! String)
                    Storage.getKeyStore().set(collectionEtags, forKey: "collection_etags_" + NSNumber(value: collectionId).stringValue)
                }
            }
        }
    }
    
    internal class func hasBeenLoaded(response : AFDataResponse<Data?>, collectionId : NSNumber) -> Bool {
        if (response.response != nil && Storage.getKeyStore().bool(forKey: "hasLoaded" + collectionId.stringValue)) {
            let headers = response.response!.allHeaderFields
            if (!(headers["collection_etag"] as? String).isEmptyOrWhitespace) {
                let collectionEtags = Storage.getKeyStore().stringArray(forKey: "collection_etags_" + collectionId.stringValue) ?? Array<String>()
                if (collectionEtags.contains(headers["collection_etag"] as! String)) {
                    return true
                }
            }
        }
        
        return false
    }
    
    internal class func getTimezoneWithOffset(identifier : String) -> String {
        let timezone = TimeZone.init(identifier: identifier)!
        let seconds = timezone.secondsFromGMT()
        let hours = seconds/3600
        let minutes = abs(seconds/60) % 60
        return "(GMT" + String(format: "%+.2d:%.2d", hours, minutes) + ") " + timezone.localizedName(for: NSTimeZone.NameStyle.standard, locale: Locale.current)!
    }
    
    internal class func sortTimezonesByOffset(timezones: [TimeZone]) -> Array<TimeZone> {
        return timezones.sorted {
            if ($0.secondsFromGMT() == $1.secondsFromGMT()) {
                return $0.localizedName(for: NSTimeZone.NameStyle.standard, locale: Locale.current)!.caseInsensitiveCompare($1.localizedName(for: NSTimeZone.NameStyle.standard, locale: Locale.current)!) == ComparisonResult.orderedAscending
            }
            return $0.secondsFromGMT() < $1.secondsFromGMT()
        }
    }
    
    internal class func addSDKProperties() {
        let id = Preferabli.isPreferabliUserLoggedIn() ? PreferabliTools.getPreferabliUserId() : PreferabliTools.getCustomerId()
        let email = Storage.getKeyStore().object(forKey: "email") as? String
        let zip = Storage.getKeyStore().object(forKey: "zipCode") as? String
        let display_name = Storage.getKeyStore().object(forKey: "displayName") as? String
        let isTeamPreferabli = Storage.getKeyStore().bool(forKey: "isTeamPreferabli")
        
        if (id != 0) {
            Mixpanel.getInstance(name: "PreferabliDataSDK")?.identify(distinctId: String(id))
            Mixpanel.getInstance(name: "PreferabliDataSDK")?.people.set(properties: [(Preferabli.isPreferabliUserLoggedIn() ? "user_id" : "customer_id") : id, "is_team_preferabli" : isTeamPreferabli])
            
            if (!email.isEmptyOrWhitespace) {
                Mixpanel.getInstance(name: "PreferabliDataSDK")?.people.set(properties: ["$email": email!])
            }
            
            if (!zip.isEmptyOrWhitespace) {
                Mixpanel.getInstance(name: "PreferabliDataSDK")?.people.set(properties: ["zip_code": zip!])
            }
            
            if (!display_name.isEmptyOrWhitespace) {
                Mixpanel.getInstance(name: "PreferabliDataSDK")?.people.set(properties: ["display_name": display_name!])
            }
        }
    }
    
    internal class func calculateDistanceInMiles(lat1 : NSNumber?, lon1 : NSNumber?, lat2 : NSNumber?, lon2 : NSNumber?) -> Int? {
        if (lat1 == nil || lat1 == 0 || lat2 == nil || lat2 == 0 || lon1 == nil || lon1 == 0 || lon2 == nil || lon2 == 0) {
            return nil
        }
        let coordinate1 = CLLocation(latitude: lat1 as! CLLocationDegrees, longitude: lon1 as! CLLocationDegrees)
        let coordinate2 = CLLocation(latitude: lat2 as! CLLocationDegrees, longitude: lon2 as! CLLocationDegrees)
        
        let distanceInMeters = coordinate1.distance(from: coordinate2)
        let distanceInMiles = distanceInMeters / 1609.344
        return Int(distanceInMiles)
    }
    
    internal class func getPreferabliUserId() -> Int {
        return Storage.getKeyStore().integer(forKey: "user_id")
    }
    
    internal class func getCustomerId() -> Int {
        return Storage.getKeyStore().integer(forKey: "customer_id")
    }
    
    internal class func getAPIDateFormatter() -> DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return dateFormatter
    }
    
    internal class func setUserProperties(user : PreferabliUser) {
        // set user properties to defaults
        Storage.getKeyStore().set(user.id, forKey: "user_id")
        Storage.getKeyStore().set(user.fname, forKey: "firstName")
        Storage.getKeyStore().set(user.lname, forKey: "lastName")
        Storage.getKeyStore().set(user.display_name, forKey: "displayName")
        Storage.getKeyStore().set(user.country, forKey: "country")
        Storage.getKeyStore().set(user.avatar?.path, forKey: "avatar")
        Storage.getKeyStore().set(user.zip_code, forKey: "zipCode")
        Storage.getKeyStore().set(user.email, forKey: "email")
        Storage.getKeyStore().set(user.is_team_preferabli, forKey: "isTeamPreferabli")
        Storage.getKeyStore().set(user.rating_collection_id, forKey: "ratings_id")
        Storage.getKeyStore().set(user.wishlist_collection_id, forKey: "wishlist_id")
        Storage.getKeyStore().set(user.claim_code, forKey: "claim_code")
        Storage.getKeyStore().set(user.provided_feedback_at, forKey: "feedbackDate")
        Storage.getKeyStore().set(user.intercom_hmac, forKey: "intercom_hmac")
        
        NotificationCenter.default.post(
            name: .preferabliIdentityDidChange,
            object: nil,
            userInfo: [
                "userId": user.id,
                "email": user.email as Any
            ]
        )
    }
    
    internal class func getSymbolForCurrencyCode(currencyCode: String?) -> String {
        if (currencyCode.isEmptyOrWhitespace) {
            return "$"
        }
        
        let code = currencyCode!
        var candidates: [String] = []
        let locales: [String] = NSLocale.availableLocaleIdentifiers
        for localeID in locales {
            guard let symbol = findMatchingSymbol(localeID: localeID, currencyCode: code) else {
                continue
            }
            if symbol.count == 1 {
                return symbol
            }
            candidates.append(symbol)
        }
        let sorted = String.sortStringsByLength(list: candidates)
        if sorted.count < 1 {
            return ""
        }
        return sorted[0]
    }
    
    internal class func getLocaleForCurrencyCode(currencyCode: String?) -> Locale {
        if (currencyCode.isEmptyOrWhitespace) {
            return Locale.current
        }
        
        let code = currencyCode!
        var candidates: [String] = []
        let locales: [String] = NSLocale.availableLocaleIdentifiers
        for localeID in locales {
            guard let symbol = findMatchingSymbol(localeID: localeID, currencyCode: code) else {
                continue
            }
            if symbol.count == 1 {
                return  Locale(identifier: localeID as String)
            }
            candidates.append(localeID)
        }
        let sorted = String.sortStringsByLength(list: candidates)
        if sorted.count < 1 {
            return Locale.current
        }
        return Locale(identifier: sorted[0] as String)
    }
    
    internal class func findMatchingSymbol(localeID: String, currencyCode: String) -> String? {
        let locale = Locale(identifier: localeID as String)
        guard let code = locale.currency?.identifier else {
            return nil
        }
        if code != currencyCode {
            return nil
        }
        guard let symbol = locale.currencySymbol else {
            return nil
        }
        return symbol
    }

    internal class func hasDaysPassed(days: Int, startDate: Date?) -> Bool {
        if let startDate = startDate {
            let calendar = NSCalendar.current
            let components = calendar.dateComponents([Calendar.Component.day], from: startDate, to: Date.init())
            return components.day! > (days - 1)
        } else {
            // never called API before!
            return true
        }
    }
    
    internal class func hasMinutesPassed(minutes: Int, startDate: Date?) -> Bool {
        if let startDate = startDate {
            let calendar = NSCalendar.current
            let components = calendar.dateComponents([Calendar.Component.minute], from: startDate, to: Date.init())
            return components.minute! > (minutes - 1)
        } else {
            // never called API before!
            return true
        }
    }
    
    internal class func splitCombinedScriptsToDictionary(from fullScript: String) -> [String: String] {
        let pattern = #"(?=if\s*\(!window\.__([A-Z0-9_]+)_LOADED__\)\s*\{)"#

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsrange = NSRange(fullScript.startIndex..<fullScript.endIndex, in: fullScript)

            let matches = regex.matches(in: fullScript, options: [], range: nsrange)

            guard !matches.isEmpty else { return ["UNKNOWN": fullScript] }

            var scriptDict: [String: String] = [:]

            for (i, match) in matches.enumerated() {
                guard let nameRange = Range(match.range(at: 1), in: fullScript) else { continue }
                let scriptName = String(fullScript[nameRange])

                let start = match.range.lowerBound
                let end = (i + 1 < matches.count) ? matches[i + 1].range.lowerBound : nsrange.upperBound

                if let range = Range(NSRange(location: start, length: end - start), in: fullScript) {
                    let scriptBody = String(fullScript[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    scriptDict[scriptName] = scriptBody
                }
            }

            return scriptDict
        } catch {
            print("Regex error: \(error)")
            return ["ERROR": fullScript]
        }
    }
    
    nonisolated public static func getImageUrl(media: Media?, width: Int, height: Int, quality: Int, scale: Float = Storage.getKeyStore().float(forKey: "mainScale")) -> URL? {
        return getImageUrl(image: media?.path, width: width, height: height, quality: quality, scale: scale, png: media?.type == "image/png")
    }
    
    // Core, nonisolated builder (no main-actor APIs)
    nonisolated public static func getImageUrl(image: String?, width: Int, height: Int, quality: Int, scale: Float = Storage.getKeyStore().float(forKey: "mainScale"), png : Bool = false) -> URL? {
        guard let raw = image, !raw.isEmptyOrWhitespace() else { return nil }
        if raw.contains("placeholder") { return nil }
        if raw.contains("winering.com") || raw.contains("preferabli.com") { return URL(string: raw) }
        if !raw.contains("s3.amazonaws.com/winering-production") { return URL(string: raw) }

        var key = raw
        let index = raw.range(of: "winering-production/", options: .backwards, range: nil, locale: nil)!.upperBound
        let start = raw.index(index, offsetBy: 0)
        let end = raw.endIndex
        let range = start..<end
        key = String(raw[range])

        let cloudfrontAppId = "ios_psdk/fit-in/"
        let sizeString = "\(Int(Float(width) * scale * 1.4))x\(Int(Float(height) * scale * 1.4))/"
        let qualityString = "filters:quality(\(quality))/"
        let pngString = key.containsIgnoreCase("png") || png ? "filters:format(png)/" : ""
        let urlString = "https://dxlu3le4zp2pd.cloudfront.net/wineringlabel/" + cloudfrontAppId + sizeString + qualityString + pngString + key
        return URL(string: urlString)
    }
}
