//
//  APIService.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/10/16.
//

import Foundation
import Alamofire
import os

// MARK: - Logging

private enum APILog {
    static let request  = Logger(subsystem: "com.preferabli.app", category: "api.request")
    static let response = Logger(subsystem: "com.preferabli.app", category: "api.response")
}

private let debugLogIDHeader = "X-Preferabli-Debug-Log-ID"
private let authRetryHeader = "X-Preferabli-Auth-Retry"

private func safeEndpointHint(_ endpoint: String, maxLen: Int = 50) -> String {
    let raw = (URL(string: endpoint)?.path.isEmpty == false) ? (URL(string: endpoint)?.path ?? endpoint) : endpoint
    let replaced = raw
        .replacingOccurrences(of: "https://", with: "")
        .replacingOccurrences(of: "http://", with: "")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "?", with: "_")
        .replacingOccurrences(of: "&", with: "_")
        .replacingOccurrences(of: "=", with: "_")
        .replacingOccurrences(of: ":", with: "_")

    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    var out = ""
    out.reserveCapacity(min(replaced.count, maxLen))
    for s in replaced.unicodeScalars {
        out.append(allowed.contains(s) ? Character(s) : "_")
        if out.count >= maxLen { break }
    }
    return out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
}

/// Writes full JSON to /tmp and logs one compact response message that includes:
/// - correlation ID
/// - status / endpoint / sizes
/// - sandbox tmp path
private func writeJSONToTempAndLog(
    _ json: String,
    endpoint: String,
    status: Int,
    bytes: Int,
    logID: String
) {
    let hint = safeEndpointHint(endpoint)
    let ts = Int(Date().timeIntervalSince1970)
    let filename = "api-\(status)-\(hint.isEmpty ? "response" : hint)-\(logID)-\(ts).json"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

    do {
        try json.write(to: url, atomically: true, encoding: .utf8)

        var msg = "[\(logID)]\n✅ \(status) \(endpoint)\n"
        msg += "Full JSON: \(url.path)\n"

        APILog.response.debug("\(msg, privacy: .public)")
    } catch {
        APILog.response.error("[\(logID, privacy: .public)] Failed to write JSON temp file: \(error.localizedDescription, privacy: .public)")
    }
}

// MARK: - API Service

/// Internal class used for interacting with our API.
internal actor APIService {

    private var alamo: Session?
    private var urlCache: URLCache?

    /// Coalesces concurrent token refreshes.
    private var refreshTask: Task<Void, Error>?

    /// Coalesces forced logout work after refresh failure.
    private var forcedLogoutTask: Task<Void, Never>?

    internal func createAlamo() async {
        let logging = await MainActor.run { Preferabli.main.loggingEnabled }
        let clientInterface = Storage.getKeyStore().string(forKey: "CLIENT_INTERFACE") ?? ""
        let version = await MainActor.run { Preferabli.versionCode }

        var headers: HTTPHeaders = [
            "client_interface": clientInterface,
            "client_interface_version": String(version)
        ]

        if let accessToken = Storage.getKeyStore().string(forKey: "access_token"),
           !accessToken.isEmptyOrWhitespace() {
            headers.update(name: "Authorization", value: "Bearer " + accessToken)
        }

        if logging {
            print("Printing default headers:")
            print(headers)
        }

        let configuration = URLSessionConfiguration.default
        configuration.headers = headers
        configuration.timeoutIntervalForRequest = 30
        let halfgig = 500 * 1024 * 1024

        urlCache = URLCache(memoryCapacity: halfgig, diskCapacity: halfgig, diskPath: "diskPath")
        configuration.urlCache = urlCache
        configuration.requestCachePolicy = .useProtocolCachePolicy

        alamo = Alamofire.Session(
            configuration: configuration,
            interceptor: Interceptor(
                adapter: LoggingAdapter(loggingEnabled: logging),
                retrier: RequestRetry()
            )
        )
    }

    internal func clearUrlCache() {
        urlCache?.removeAllCachedResponses()
    }

    /// Returns a configured Alamofire `Session`, lazily creating it.
    internal func getAlamo(requiresAccessToken: Bool = true) async throws -> Session {
        if Storage.getKeyStore().string(forKey: "CLIENT_INTERFACE").isEmptyOrWhitespace {
            throw PreferabliException(type: .InvalidClientInterface)
        }

        if requiresAccessToken && Storage.getKeyStore().string(forKey: "access_token").isEmptyOrWhitespace {
            throw PreferabliException(type: .InvalidAccessToken)
        }

        if alamo == nil {
            await createAlamo()
        }

        return alamo!
    }

    internal func refreshDefaults() {
        alamo = nil
    }

    /// Performs a single shared refresh no matter how many 401s arrive at once.
    internal func refreshSessionIfNeeded() async throws {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task<Void, Error> {
            let refreshToken = Storage.getKeyStore().string(forKey: "refresh_token") ?? ""
            if refreshToken.isEmptyOrWhitespace() {
                throw PreferabliException(
                    type: .InvalidAccessToken,
                    message: "Missing refresh token; cannot refresh session."
                )
            }

            let params: SParams = [
                "user_id": PreferabliTools.getPreferabliUserId(),
                "token_refresh": refreshToken
            ]

            let session = try await self.getAlamo(requiresAccessToken: false)
            let sessionResponse = try await session.post(APIEndpoints.sessions, json: params)

            if sessionResponse.error == nil,
               let http = sessionResponse.response,
               (200..<300).contains(http.statusCode),
               let data = sessionResponse.data {

                let obj = try APIService.continueOrThrowJSONException(data: data)
                guard let dict = obj as? [String: Any] else {
                    throw PreferabliException(
                        type: .JSONError,
                        message: "[\(APIEndpoints.sessions)] Session refresh JSON root was not a dictionary.",
                        code: http.statusCode
                    )
                }

                let sessionData = SessionData(map: dict)
                await sessionData.saveSession()
                return
            }

            let status = sessionResponse.response?.statusCode ?? 0
            var msg = "[\(APIEndpoints.sessions)] Token refresh failed with status \(status)."
            if let raw = sessionResponse.data, !raw.isEmpty {
                let snippet = String(decoding: raw.prefix(1000), as: UTF8.self)
                msg += "\n── Refresh Raw (first 1000 bytes) ──\n\(snippet)\n────────"
            }

            throw PreferabliException(type: .InvalidAccessToken, message: msg, code: status)
        }

        refreshTask = task

        do {
            try await task.value
            refreshTask = nil
        } catch {
            refreshTask = nil
            throw error
        }
    }

    /// Ensures we only run the forced-logout cleanup once even if many requests fail together.
    internal func forceLogoutAfterRefreshFailureIfNeeded() async {
        if let forcedLogoutTask {
            await forcedLogoutTask.value
            return
        }

        let task = Task<Void, Never> {
            await Preferabli.main.handleRefreshFailureLogout()
        }

        forcedLogoutTask = task
        await task.value
        forcedLogoutTask = nil
    }
}

private final class RequestRetry: RequestRetrier {
    func retry(
        _ request: Alamofire.Request,
        for session: Alamofire.Session,
        dueTo error: any Error,
        completion: @escaping @Sendable (Alamofire.RetryResult) -> Void
    ) {
        completion(.doNotRetry)
    }
}

private final class LoggingAdapter: RequestAdapter {
    let loggingEnabled: Bool
    init(loggingEnabled: Bool) { self.loggingEnabled = loggingEnabled }

    func adapt(
        _ urlRequest: URLRequest,
        for session: Alamofire.Session,
        completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void
    ) {
        var req = urlRequest

        if loggingEnabled {
            #if DEBUG
            if req.value(forHTTPHeaderField: debugLogIDHeader) == nil {
                req.setValue(UUID().uuidString, forHTTPHeaderField: debugLogIDHeader)
            }
            #endif

            let id = req.value(forHTTPHeaderField: debugLogIDHeader) ?? "-"
            let method = req.httpMethod ?? "?"
            let url    = req.url?.absoluteString ?? "?"

            var msg = "[\(id)]\n➡️ \(method) \(url)"
            if let body = req.httpBody, !body.isEmpty {
                let snippet = String(decoding: body.prefix(2000), as: UTF8.self)
                msg += "\nRequest body:\n\(snippet)"
            }

            APILog.request.debug("\(msg, privacy: .private)")
        }

        completion(.success(req))
    }
}

extension APIService {

    private static func buildReplayRequest(from original: URLRequest) async -> URLRequest {
        var replay = original

        replay.setValue("1", forHTTPHeaderField: authRetryHeader)

        if let accessToken = Storage.getKeyStore().string(forKey: "access_token"),
           !accessToken.isEmptyOrWhitespace() {
            replay.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            replay.setValue(nil, forHTTPHeaderField: "Authorization")
        }

        let clientInterface = Storage.getKeyStore().string(forKey: "CLIENT_INTERFACE") ?? ""
        let version = await MainActor.run { Preferabli.versionCode }

        replay.setValue(clientInterface, forHTTPHeaderField: "client_interface")
        replay.setValue(String(version), forHTTPHeaderField: "client_interface_version")

        return replay
    }

    /// Returns `response` on 2xx, else throws `PreferabliException`.
    /// Handles 401 by attempting a token refresh and retrying the original request once.
    internal static func continueOrThrowPreferabliException(
        response: AFDataResponse<Data?>
    ) async throws -> AFDataResponse<Data?> {

        let endpoint = response.request?.url?.absoluteString ?? "<unknown-url>"
        let status   = response.response?.statusCode
        let raw      = response.data

        func makeErr(
            _ type: PreferabliExceptionType,
            code: Int = (status ?? 0),
            message: String? = nil,
            attachRaw: Bool = true
        ) -> PreferabliException {
            var msg = "[\(endpoint)] \(message ?? type.getMessage())"
            if attachRaw, let raw, !raw.isEmpty {
                let snippet = String(decoding: raw.prefix(1000), as: UTF8.self)
                msg += "\n── Raw (first 1000 bytes) ──\n\(snippet)\n────────"
            }
            return PreferabliException(type: type, message: msg, code: code)
        }

        // Happy path: 2xx + no AF error
        if response.error == nil,
           let http = response.response,
           (200..<300).contains(http.statusCode) {

            let logging = await MainActor.run { Preferabli.main.loggingEnabled }
            if logging, let data = response.data {
                let s = prettyJSONString(from: data)
                let logID = response.request?.value(forHTTPHeaderField: debugLogIDHeader) ?? "-"

                writeJSONToTempAndLog(
                    s,
                    endpoint: endpoint,
                    status: http.statusCode,
                    bytes: data.count,
                    logID: logID
                )
            }

            return response
        }

        // HTTP error path
        if let http = response.response, let data = response.data {

            if http.statusCode == 401 {
                let api = await Preferabli.main.api

                // Already retried once after refresh -> session is dead.
                if response.request?.value(forHTTPHeaderField: authRetryHeader) == "1" {
                    await api.forceLogoutAfterRefreshFailureIfNeeded()
                    throw makeErr(
                        .InvalidAccessToken,
                        code: http.statusCode,
                        message: "Request remained unauthorized after token refresh and retry."
                    )
                }

                do {
                    try await api.refreshSessionIfNeeded()

                    guard let originalRequest = response.request else {
                        throw makeErr(
                            .APIError,
                            code: http.statusCode,
                            message: "Unable to replay original request (missing URLRequest)."
                        )
                    }

                    let replayRequest = await buildReplayRequest(from: originalRequest)
                    let session = try await api.getAlamo()
                    let replayResponse = await session.requestRaw(replayRequest)

                    return try await continueOrThrowPreferabliException(response: replayResponse)
                } catch let e as PreferabliException {
                    await api.forceLogoutAfterRefreshFailureIfNeeded()

                    var msg = "[\(endpoint)] \(e.getMessage())"
                    if let raw, !raw.isEmpty {
                        let snippet = String(decoding: raw.prefix(1000), as: UTF8.self)
                        msg += "\n── Original Raw (first 1000 bytes) ──\n\(snippet)\n────────"
                    }

                    throw PreferabliException(type: e.type, message: msg, code: e.getCode())
                } catch {
                    await api.forceLogoutAfterRefreshFailureIfNeeded()
                    throw makeErr(
                        .APIError,
                        code: http.statusCode,
                        message: "Token refresh/replay failed: \(error.localizedDescription)"
                    )
                }
            }

            do {
                let obj = try continueOrThrowJSONException(data: data)
                guard let dict = obj as? [String: Any] else {
                    throw makeErr(.APIError, code: http.statusCode, message: "API error body was not a dictionary.")
                }

                let apiError = APIError(map: dict)
                if apiError.message != nil {
                    var msg = "[\(endpoint)] \(PreferabliException(error: apiError).getMessage())"
                    let snippet = String(decoding: data.prefix(1000), as: UTF8.self)
                    msg += "\n── Raw (first 1000 bytes) ──\n\(snippet)\n────────"
                    throw PreferabliException(type: .APIError, message: msg, code: http.statusCode)
                } else {
                    throw makeErr(.APIError, code: http.statusCode, message: "HTTP \(http.statusCode) without API error message.")
                }
            } catch let e as PreferabliException {
                let msg = "[\(endpoint)] \(e.getMessage())"
                throw PreferabliException(type: e.type, message: msg, code: http.statusCode)
            }
        }

        // Non-HTTP AF error path
        if let af = response.error {
            if af.isExplicitlyCancelledError {
                throw PreferabliException(
                    type: .Cancelled,
                    message: "[\(endpoint)] Request cancelled.",
                    code: 0
                )
            }

            if let urlErr = af.underlyingError as? URLError, urlErr.code == .cancelled {
                throw PreferabliException(
                    type: .Cancelled,
                    message: "[\(endpoint)] Request cancelled.",
                    code: 0
                )
            }

            throw PreferabliException(
                type: .APIError,
                message: "[\(endpoint)] Alamofire error: \(af.localizedDescription)",
                code: 0
            )
        }

        throw makeErr(.APIError, code: status ?? 0, message: "Unknown API error.", attachRaw: true)
    }

    internal static func continueOrThrowJSONException(data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            let snippet = String(decoding: data.prefix(1000), as: UTF8.self)
            throw PreferabliException(
                type: .JSONError,
                message: "JSON parse failed: \(error.localizedDescription)\n── Raw (first 1000 bytes) ──\n\(snippet)\n────────"
            )
        }
    }

    private static func prettyJSONString(from data: Data) -> String {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data, options: []),
            let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
            let s = String(data: pretty, encoding: .utf8)
        else {
            return String(decoding: data, as: UTF8.self)
        }
        return s
    }
}

// MARK: - API Endpoints

internal struct APIEndpoints {
    internal static let baseUrl = "https://api.preferabli.com/api/en/7.0/"

    internal static let sessions = baseUrl + "sessions"
    internal static let getRec = baseUrl + "recs"
    internal static let styles = baseUrl + "styles"
    internal static let postMedia = baseUrl + "media"
    internal static let resetPassword = baseUrl + "resetpassword"
    internal static let users = baseUrl + "users"
    internal static let products = baseUrl + "products"
    internal static let search = baseUrl + "search"
    internal static let imageRec = baseUrl + "imagerec"
    internal static let lttt = baseUrl + "lttt"
    internal static let flttt = baseUrl + "flttt"
    internal static let foods = baseUrl + "foods"
    internal static let config = baseUrl + "config"
    internal static let collections = baseUrl + "collections"
    internal static let foodCategories = baseUrl + "food-categories"
    internal static let whereToBuy = baseUrl + "wheretobuy"
    internal static let magicLink = baseUrl + "sessions/magic-link"
    internal static let preferenceData = baseUrl + "wili"
    internal static let qrCode = "https://api.qr-code-generator.com/v1/create?access-token=" + SDKConfig.qrKey
    internal static let jumpstartCollection = baseUrl + "jumpstart-collection"
    internal static let stylesToTry = baseUrl + "styles-to-try-styles"
    internal static let stylesToTryRecs = baseUrl + "styles-to-try"
    internal static let styleSuggestions = baseUrl + "suggest"
    internal static let avatars = baseUrl + "avatar-options"
    internal static let channels = baseUrl + "channels"
    internal static let markets = baseUrl + "markets"
    internal static let scripts = baseUrl + "front-end-scripts"
    internal static let ctaBuckets = baseUrl + "cta-buckets"
    internal static let recipes = baseUrl + "integrations/1/recipes?limit=9999"
    internal static let recipeGroups = baseUrl + "integrations/1/recipe-groups?limit=9999"
    internal static let recipesForProducts = baseUrl + "integrations/1/recipes-for-products?limit=20"
    internal static let hubspotDeal = baseUrl + "tastefuli/hubspot/deals"
    internal static let stripePaymentIntent = baseUrl + "tastefuli/stripe/payment-intent"
    internal static let reservations = baseUrl + "tastefuli/reservations?offset=0&limit=9999"
    internal static let balloonBooking = baseUrl + "tastefuli/balloon-booking"
    internal static let completeSafetyBrief = baseUrl + "tastefuli/balloon-booking/safety-brief"

    internal static func venues(id: Int) -> String { baseUrl + "markets/\(id)/venues" }
    internal static func experiences(marketId: Int) -> String { baseUrl + "tastefuli/markets/\(marketId)/experiences" }
    internal static func integration(id: Int) -> String { baseUrl + "integrations/\(id)" }
    internal static func lookupConversion(id: Int) -> String { baseUrl + "integrations/\(id)/lookups" }
    internal static func lttt(id: Int) -> String { baseUrl + "integration/\(id)/lttt" }
    internal static func customer(id: Int, customerId: Int) -> String { baseUrl + "channels/\(id)/customers/\(customerId)" }
    internal static func stripePaymentMethod(id: String) -> String { baseUrl + "tastefuli/stripe/payment-intent/\(id)" }
    internal static func guidedRec(id: Int) -> String { baseUrl + "questionnaire/\(id)" }
    internal static func guidedRecResults() -> String { baseUrl + "query" }
    internal static func guidedRecResults(id: Int) -> String { baseUrl + "query?override_collection_ids[]=\(id)" }
    internal static func customerTags(id: Int, and customerId: Int) -> String { baseUrl + "channels/\(id)/customers/\(customerId)/tags" }
    internal static func customerProfile(id: Int, and customerId: Int) -> String { baseUrl + "channels/\(id)/customers/\(customerId)/profile?include_styles=false" }
    internal static func collection(id: Int) -> String { baseUrl + "collections/\(id)" }
    internal static func product(id: Int) -> String { baseUrl + "products/\(id)" }
    internal static func venue(id: Int) -> String { baseUrl + "venues/\(id)" }
    internal static func experiences(id: Int) -> String { baseUrl + "tastefuli/venues/\(id)/experiences" }
    internal static func externalReservations(id: Int) -> String { baseUrl + "tastefuli/experiences/\(id)/external-reservation" }
    internal static func reservation(id: Int) -> String { baseUrl + "tastefuli/reservations/\(id)" }
    internal static func alternativeTimes(id: Int) -> String { baseUrl + "tastefuli/reservations/\(id)/alternative-times" }
    internal static func internalReservations(id: Int) -> String { baseUrl + "tastefuli/experiences/\(id)/internal-reservation" }
    internal static func searchExperiences(query : String) -> String { baseUrl + "tastefuli/experiences?search=\(query)&offset=0&limit=20" }
    internal static func experience(id: Int, experienceId : Int) -> String { baseUrl + "venues/\(id)/experiences/\(experienceId)" }
    internal static func user(id: Int) -> String { baseUrl + "users/\(id)" }
    internal static func favoriteVenue(id: Int, venueId : Int) -> String { baseUrl + "users/\(id)/favorite-venues/\(venueId)" }
    internal static func tags(id: Int) -> String { baseUrl + "collections/\(id)/tags" }
    internal static func variants(product_id: Int) -> String { baseUrl + "products/\(product_id)/variants" }
    internal static func style(id: Int) -> String { baseUrl + "styles/\(id)" }
    internal static func channel(id: Int) -> String { baseUrl + "channels/\(id)" }
    internal static func tag(collectionId: Int, tagId: Int) -> String { baseUrl + "collections/\(collectionId)/tags/\(tagId)" }
    internal static func groups(collectionId: Int, versionId: Int) -> String { baseUrl + "collections/\(collectionId)/versions/\(versionId)/groups" }
    internal static func orderings(collectionId: Int, versionId: Int, groupId: Int) -> String { baseUrl + "collections/\(collectionId)/versions/\(versionId)/groups/\(groupId)/orderings" }
    internal static func ordering(collectionId: Int, versionId: Int, groupId: Int, orderingId: Int) -> String { baseUrl + "collections/\(collectionId)/versions/\(versionId)/groups/\(groupId)/orderings/\(orderingId)" }
    internal static func variant(product_id: Int, variant_id: Int) -> String { baseUrl + "products/\(product_id)/variants/\(variant_id)" }
    internal static func customerTag(id: Int, customerId: Int, tagId: Int) -> String { baseUrl + "channels/\(id)/customers/\(customerId)/tags/\(tagId)" }
    internal static func customerTags(id: Int, customerId: Int) -> String { baseUrl + "channels/\(id)/customers/\(customerId)/tags" }
    internal static func userCollections(id: Int) -> String { baseUrl + "users/\(id)/usercollections" }
    internal static func userCollection(id: Int, userCollectionId: Int) -> String { baseUrl + "users/\(id)/usercollections/\(userCollectionId)" }
    internal static func profile(id: Int) -> String { baseUrl + "users/\(id)/profile?include_styles=false" }
    internal static func userTags(id: Int) -> String { baseUrl + "users/\(id)/tags" }
    internal static func userTag(id: Int, tagId: Int) -> String { baseUrl + "users/\(id)/tags/\(tagId)" }

    internal static func productProfileData(id: Int, year: Int = -1) -> String {
        return baseUrl + "variant-details?keys[]=acidity_percent&keys[]=sweetness_percent&keys[]=oak_percent&keys[]=body_percent&keys[]=peat_percent&keys[]=agave_percent&keys[]=smoke_percent&keys[]=hop_percent&keys[]=malt_percent&keys[]=flavor_percent&keys[]=carbonation_percent&keys[]=alcohol_percent&keys[]=firmness_percent&keys[]=savouriness_percent&keys[]=aromatic_percent&keys[]=flavor_profile_1_name&keys[]=flavor_profile_2_name&keys[]=flavor_profile_3_name&keys[]=flavor_profile_4_name&keys[]=flavor_profile_1_icon_png_4x_url&keys[]=flavor_profile_2_icon_png_4x_url&keys[]=flavor_profile_3_icon_png_4x_url&keys[]=flavor_profile_4_icon_png_4x_url&keys[]=food_category_1_name&keys[]=food_category_2_name&keys[]=food_category_3_name&keys[]=food_category_4_name&keys[]=food_category_1_icon_png_url&keys[]=food_category_2_icon_png_url&keys[]=food_category_3_icon_png_url&keys[]=food_category_4_icon_png_url&product_id=\(id)&year=\(year)"
    }

    internal static func productFoodData(id: Int, year: Int = -1) -> String {
        return baseUrl + "variant-details?keys[]=food_category_1_name&keys[]=food_category_2_name&keys[]=food_category_3_name&keys[]=food_category_4_name&keys[]=food_category_1_icon_png_url&keys[]=food_category_2_icon_png_url&keys[]=food_category_3_icon_png_url&keys[]=food_category_4_icon_png_url&product_id=\(id)&year=\(year)"
    }
}
