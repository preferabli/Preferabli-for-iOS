//
//  APIService.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/10/16.
//  Copyright © 2025 RingIT.
//  Swift 6–safe rewrite: actor isolation + explicit main-actor hops
//

import Foundation
import Alamofire

/// Internal class used for interacting with our API.
internal actor APIService {

    private var alamo: Session?
    private var urlCache: URLCache?

    internal func createAlamo() async {
        let logging = await MainActor.run { Preferabli.main.loggingEnabled }
        let clientInterface = Storage.getKeyStore().string(forKey: "CLIENT_INTERFACE") ?? ""
        let version = await MainActor.run { Preferabli.versionCode }

        var headers: HTTPHeaders = [
            "client_interface": clientInterface,
            "client_interface_version": String(version)
        ]

        if let accessToken = Storage.getKeyStore().string(forKey: "access_token") {
            headers.update(name: "Authorization", value: "Bearer " + accessToken)
        }

        if logging {
            print("Printing default header:")
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
        // Force unwrap is safe after create
        return alamo!
    }

    internal func refreshDefaults() {
        alamo = nil
    }
}

private final class RequestRetry: RequestRetrier {
    func retry(
        _ request: Alamofire.Request,
        for session: Alamofire.Session,
        dueTo error: any Error,
        completion: @escaping @Sendable (Alamofire.RetryResult) -> Void
    ) {
        // no automatic retry behavior today
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
        if loggingEnabled, let req = urlRequest as URLRequest? {
            if let method = req.httpMethod { print(method) }
            if let url = req.url { print(url.absoluteString) }
            if let body = req.httpBody { print(body) }
        }
        completion(.success(urlRequest))
    }
}

extension APIService {
    /// Returns `response` on 2xx, else throws `PreferabliException`.
    /// Handles 401 by attempting a token refresh and retrying the original request.
    internal static func continueOrThrowPreferabliException(
        response: AFDataResponse<Data?>
    ) async throws -> AFDataResponse<Data?> {

        // Happy path: 2xx + no AF error
        if response.error == nil,
           let http = response.response,
           (200..<300).contains(http.statusCode) {

            let logging = await MainActor.run { Preferabli.main.loggingEnabled }
            if logging, let data = response.data, let utf8 = String(data: data, encoding: .utf8) {
                print("Data: \(utf8)")
            }
            return response
        }

        // Error path with HTTP + data
        if let http = response.response, let data = response.data {

            // 401: try refresh, then replay the original request
            if http.statusCode == 401 {
                let params: SParams = [
                    "user_id": PreferabliTools.getPreferabliUserId(),
                    "token_refresh": Storage.getKeyStore().string(forKey: "refresh_token") ?? ""
                ]

                do {
                    // Hop to main actor to get the service handle, then hop to the service actor
                    let api = await Preferabli.main.api
                    let session = try await api.getAlamo()

                    let sessionResponse = try await session.post(APIEndpoints.postSession, json: params)

                    if sessionResponse.error == nil,
                       let http2 = sessionResponse.response,
                       http2.statusCode < 400 {

                        let sessionData = SessionData(map: try continueOrThrowJSONException(data: sessionResponse.data!) as! [String: Any])
                        await sessionData.saveSession()

                        guard let req = response.request,
                              let method = req.httpMethod?.lowercased()
                        else {
                            throw PreferabliException(type: .APIError, code: http.statusCode)
                        }

                        let s = try await api.getAlamo()
                        if method == "get" || method == "delete" {
                            return await s.requestData(
                                url: req.url!,
                                method: HTTPMethod(rawValue: req.httpMethod!),
                                parameters: nil,
                                encoding: URLEncoding.default,
                                headers: nil
                            )
                        } else if let body = req.httpBody {
                            return await s.requestJSON(
                                urlString: req.url!.absoluteString,
                                method: HTTPMethod(rawValue: req.httpMethod!),
                                json: body
                            )
                        } else {
                            return await s.requestData(
                                url: req.url!,
                                method: HTTPMethod(rawValue: req.httpMethod!),
                                parameters: nil,
                                encoding: URLEncoding.default,
                                headers: nil
                            )
                        }
                    }

                    // Refresh failed
                    throw PreferabliException(type: .APIError, code: http.statusCode)

                } catch {
                    // If refresh or replay fails, surface as API error with original code
                    throw PreferabliException(type: .APIError, code: http.statusCode)
                }
            }

            // Non-401: try to parse API error body
            let errorObject = try continueOrThrowJSONException(data: data) as? [String: Any]
            guard let dict = errorObject else {
                throw PreferabliException(type: .APIError, code: http.statusCode)
            }

            let apiError = APIError(map: dict)
            if apiError.message != nil {
                throw PreferabliException(error: apiError)
            } else {
                throw PreferabliException(type: .APIError, code: http.statusCode)
            }
        }

        // No HTTP response or data
        throw PreferabliException(type: .NetworkError)
    }

    internal static func continueOrThrowJSONException(data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            // report malformed JSON
            Analytics.track(["event": "error", "type": "JSON", "data": data.base64EncodedString()])
            throw PreferabliException(type: .JSONError)
        }
    }
}

// MARK: - API Endpoints

internal struct APIEndpoints {
    internal static let baseUrl = "https://api.preferabli.com/api/6.2/"
    internal static let postSession = baseUrl + "sessions"
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
    internal static let wheretobuy = baseUrl + "wheretobuy"

    internal static func integration(id: Int) -> String { baseUrl + "integrations/\(id)" }
    internal static func lookupConversion(id: Int) -> String { baseUrl + "integrations/\(id)/lookups" }
    internal static func lttt(id: Int) -> String { baseUrl + "integration/\(id)/lttt" }
    internal static func customer(id: Int, customerId: Int) -> String { baseUrl + "channels/\(id)/customers/\(customerId)" }
    internal static func guidedRec(id: Int) -> String { baseUrl + "questionnaire/\(id)" }
    internal static func guidedRecResults() -> String { baseUrl + "query" }
    internal static func guidedRecResults(id: Int) -> String { baseUrl + "query?override_collection_ids[]=\(id)" }
    internal static func customerTags(id: Int, and customerId: Int) -> String { baseUrl + "channels/\(id)/customers/\(customerId)/tags" }
    internal static func customerProfile(id: Int, and customerId: Int) -> String { baseUrl + "channels/\(id)/customers/\(customerId)/profile?include_styles=false" }
    internal static func collection(id: Int) -> String { baseUrl + "collections/\(id)" }
    internal static func product(id: Int) -> String { baseUrl + "products/\(id)" }
    internal static func user(id: Int) -> String { baseUrl + "users/\(id)" }
    internal static func wili() -> String { baseUrl + "wili" }
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
}
