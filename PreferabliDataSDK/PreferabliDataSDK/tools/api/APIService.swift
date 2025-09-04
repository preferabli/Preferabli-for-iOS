//
//  APIService.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/10/16.
//  Copyright © 2023 RingIT, Inc. All rights reserved.
//

import Foundation
import CoreData
import Alamofire

/// Internal class used for interacting with our API.
internal class APIService {
    
    private var alamo : Session?
    private var urlCache : URLCache?
    
    /// Create Alamo class that interacts with our API.
    internal func createAlamo() {
        let defaults = PreferabliTools.getKeyStore()
                
        var headers: HTTPHeaders = ["client_interface" : defaults.string(forKey: "CLIENT_INTERFACE")!, "client_interface_version" : String(Preferabli.versionCode)]
                
        if let access_token = defaults.string(forKey: "access_token") {
            headers.update(name: "Authorization", value: "Bearer " + access_token)
        }
        
        if (Preferabli.loggingEnabled) {
            print("Printing default header:")
            print(headers)
        }

        let configuration = URLSessionConfiguration.default
        configuration.headers = headers
        configuration.timeoutIntervalForRequest = 30
        let halfgig = 500 * 1024 * 1024
        urlCache = URLCache.init(memoryCapacity: halfgig, diskCapacity: halfgig, diskPath: "diskPath")
        configuration.urlCache = urlCache
        configuration.requestCachePolicy = .useProtocolCachePolicy
        alamo = Alamofire.Session(configuration: configuration, interceptor: Interceptor(adapter: LoggingAdapter.init(loggingEnabled: Preferabli.loggingEnabled), retrier: RequestRetry.init()))
    }

    internal func clearUrlCache() {
        urlCache?.removeAllCachedResponses()
    }
    
    internal func getAlamo() throws -> Session {
        return try getAlamo(requiresAccessToken: true)
    }
    
    internal func getAlamo(requiresAccessToken : Bool) throws -> Session {
        objc_sync_enter(Preferabli.api)
        defer { objc_sync_exit(Preferabli.api) }
        
        if (PreferabliTools.isNullOrWhitespace(string: PreferabliTools.getKeyStore().string(forKey: "CLIENT_INTERFACE"))) {
            throw PreferabliException.init(type: .InvalidClientInterface)
        }
        
        if (requiresAccessToken && PreferabliTools.isNullOrWhitespace(string: PreferabliTools.getKeyStore().string(forKey: "access_token"))) {
            throw PreferabliException.init(type: .InvalidAccessToken)
        }
        
        if (alamo == nil) {
            createAlamo()
        }
        
        return alamo!
    }
    
    internal func refreshDefaults() {
        objc_sync_enter(Preferabli.api)
        defer { objc_sync_exit(Preferabli.api) }
        
        alamo = nil
    }
}

private final class RequestRetry : RequestRetrier {
    func retry(_ request: Alamofire.Request, for session: Alamofire.Session, dueTo error: any Error, completion: @escaping @Sendable (Alamofire.RetryResult) -> Void) {
        // nada
    }
}

private final class LoggingAdapter: RequestAdapter {
    func adapt(_ urlRequest: URLRequest, for session: Alamofire.Session, completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void) {
        if (loggingEnabled) {
            if (urlRequest.urlRequest != nil) {
                if (urlRequest.urlRequest?.httpMethod != nil) {
                    print(urlRequest.urlRequest!.httpMethod!)
                }
                if (urlRequest.urlRequest?.url != nil) {
                    print(urlRequest.urlRequest!.url!.absoluteString)
                }
                if (urlRequest.urlRequest?.httpBody != nil) {
                    print(urlRequest.urlRequest!.httpBody!)
                }
            }
        }
        completion(.success(urlRequest))
    }
    
    
    let loggingEnabled : Bool
    
    init(loggingEnabled : Bool) {
        self.loggingEnabled = loggingEnabled
    }
}

extension APIService {
    internal class func continueOrThrowPreferabliException(response : AFDataResponse<Data?>) async throws -> AFDataResponse<Data?> {
        if (response.error == nil && response.response != nil && response.response!.statusCode >= 200 && response.response!.statusCode < 300) {
            if (Preferabli.loggingEnabled) {
                if let data = response.data, let utf8Text = String(data: data, encoding: .utf8) {
                    print("Data: \(utf8Text)")
                }
            }
            return response
        } else if (response.response != nil && response.data != nil) {
            if (response.response!.statusCode == 401) {
                let parameters = ["user_id": PreferabliTools.getPreferabliUserId(), "token_refresh" : PreferabliTools.getKeyStore().string(forKey: "refresh_token") ?? ""] as [String : Any]
                do {
                    let sessionResponse = try Preferabli.api.getAlamo().post(APIEndpoints.postSession, jsonObject: parameters)
                    if (sessionResponse.error == nil && sessionResponse.response != nil && sessionResponse.response!.statusCode < 400) {
                        _ = SessionData(map: try continueOrThrowJSONException(data: sessionResponse.data!) as! [String : Any])
                        
                        if (response.request!.httpMethod!.lowercased() == "get" || response.request!.httpMethod!.lowercased() == "delete") {
                            return try Preferabli.api.getAlamo().syncRequest(url: response.request!.url!, method: HTTPMethod(rawValue: response.request!.httpMethod!), parameters: nil, encoding: URLEncoding.default, headers: response.request!.headers)
                        } else if (response.request!.httpBody != nil) {
                            return try Preferabli.api.getAlamo().syncRequest(urlString: response.request!.url!.absoluteString, method: response.request!.httpMethod!, jsonObject: response.request!.httpBody!)
                        }
                    } else {
                        throw PreferabliException.init(type: .APIError, code: response.response!.statusCode)
                    }
                } catch {
//                    await PreferabliTools.logout()
                    throw PreferabliException.init(type: .APIError, code: response.response!.statusCode)
                }
            }
            let errorDictionary = try continueOrThrowJSONException(data: response.data!) as? [String : Any]
            if (errorDictionary == nil) {
                throw PreferabliException.init(type: .APIError, code: response.response!.statusCode)
            }
            let error = APIError(map: errorDictionary!)
            if (error.message != nil) {
                throw PreferabliException.init(error: error)
            } else {
                throw PreferabliException.init(type: .APIError, code: response.response!.statusCode)
            }
        } else {
            throw PreferabliException.init(type: .NetworkError)
        }
    }
    
    internal class func continueOrThrowJSONException(data : Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            // report malformed JSON
            Analytics.track( ["event" : "error", "type" : "JSON", "data" : data.base64EncodedString()])
            throw PreferabliException.init(type: .JSONError)
        }
    }
}

/// These are our API routes.
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

    internal static func integration(id : Int) -> String {
        return baseUrl + "integrations/\(id)"
    }
    
    internal static func lookupConversion(id : Int) -> String {
        return baseUrl + "integrations/\(id)/lookups"
    }
    
    internal static func lttt(id : Int) -> String {
        return baseUrl + "integration/\(id)/lttt"
    }
    
    internal static func customer(id : Int, customerId : Int) -> String {
        return baseUrl + "channels/\(id)/customers/\(customerId)"
    }

    internal static func guidedRec(id : Int) -> String {
        return baseUrl + "questionnaire/\(id)"
    }
    
    internal static func guidedRecResults() -> String {
        return baseUrl + "query"
    }
    
    internal static func guidedRecResults(id : Int) -> String {
        return baseUrl + "query?override_collection_ids[]=\(id)"
    }
    
    internal static func customerTags(id : Int, and customerId : Int) -> String {
        return baseUrl + "channels/\(id)/customers/\(customerId)/tags"
    }
    
    internal static func customerProfile(id : Int, and customerId : Int) -> String {
        return baseUrl + "channels/\(id)/customers/\(customerId)/profile?include_styles=false"
    }
    
    internal static func collection(id : Int) -> String {
        return baseUrl + "collections/\(id)"
    }
    
    internal static func product(id : Int) -> String {
        return baseUrl + "products/\(id)"
    }

    internal static func user(id : Int) -> String {
        return baseUrl + "users/\(id)"
    }
    
    internal static func wili() -> String {
        return baseUrl + "wili"
    }
    
    internal static func tags(id : Int) -> String {
        return baseUrl + "collections/\(id)/tags"
    }
    
    internal static func variants(product_id : Int) -> String {
        return baseUrl + "products/\(product_id)/variants"
    }
    
    internal static func style(id : Int) -> String {
        return baseUrl + "styles/\(id)"
    }
    
    internal static func channel(id : Int) -> String {
        return baseUrl + "channels/\(id)"
    }
    
    internal static func tag(collectionId : Int, tagId : Int) -> String {
        return baseUrl + "collections/\(collectionId)/tags/\(tagId)"
    }
    
    internal static func groups(collectionId : Int, versionId : Int) -> String {
        return baseUrl + "collections/\(collectionId)/versions/\(versionId)/groups"
    }
    
    internal static func orderings(collectionId : Int, versionId : Int, groupId : Int) -> String {
        return baseUrl + "collections/\(collectionId)/versions/\(versionId)/groups/\(groupId)/orderings"
    }
    
    internal static func ordering(collectionId : Int, versionId : Int, groupId : Int, orderingId : Int) -> String {
        return baseUrl + "collections/\(collectionId)/versions/\(versionId)/groups/\(groupId)/orderings/\(orderingId)"
    }
    
    internal static func variant(product_id : Int, variant_id : Int) -> String {
        return baseUrl + "products/\(product_id)/variants/\(variant_id)"
    }
    
    internal static func customerTag(id : Int, customerId : Int, tagId : Int) -> String {
        return baseUrl + "channels/\(id)/customers/\(customerId)/tags/\(tagId)"
    }
    
    internal static func customerTags(id : Int, customerId : Int) -> String {
           return baseUrl + "channels/\(id)/customers/\(customerId)/tags"
    }
    
    internal static func userCollections(id : Int) -> String {
        return baseUrl + "users/\(id)/usercollections"
    }
    
    internal static func userCollection(id : Int, userCollectionId : Int) -> String {
        return baseUrl + "users/\(id)/usercollections/\(userCollectionId)"
    }
    
    internal static func profile(id : Int) -> String {
        return baseUrl + "users/\(id)/profile?include_styles=false"
    }
    
    internal static func userTags(id : Int) -> String {
        return baseUrl + "users/\(id)/tags"
    }

    internal static func userTag(id : Int, tagId : Int) -> String {
        return baseUrl + "users/\(id)/tags/\(tagId)"
    }
}
