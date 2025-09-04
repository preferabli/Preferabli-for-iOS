//
//  SessionManagerExt.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 12/13/17.
//  Copyright © 2023 RingIT, Inc. All rights reserved.
//

import Foundation
import Alamofire

extension Session {
    internal func get(_ url: URLConvertible) -> AFDataResponse<Data?> {
        return get(url, params: nil)
    }
    
    internal func get(_ url: URLConvertible, params: Parameters?) -> AFDataResponse<Data?> {
        return syncRequest(url: url, parameters: params)
    }
    
    internal func delete(_ url: URLConvertible) -> AFDataResponse<Data?> {
        return syncRequest(url: url, method: .delete)
    }
    
    internal func post(_ url: URLConvertible, params: Parameters?) throws -> AFDataResponse<Data?> {
        return try syncRequest(urlString: url.asURL().absoluteString, method: "post", jsonObject: params)
    }
    
    internal func post(_ url: URLConvertible, json: Parameters?) throws -> AFDataResponse<Data?> {
        return try syncRequest(urlString: url.asURL().absoluteString, method: "post", jsonObject: json)
    }
    
    internal func post(_ urlString: String, jsonObject: Any) throws -> AFDataResponse<Data?> {
        return try syncRequest(urlString: urlString, method: "post", jsonObject: jsonObject)
    }
    
    internal func put(_ url: URLConvertible, json: Parameters?) throws -> AFDataResponse<Data?> {
        return try syncRequest(urlString: url.asURL().absoluteString, method: "put", jsonObject: json)
    }
    
    internal func put(_ urlString: String, jsonObject: Any) throws -> AFDataResponse<Data?> {
        return try syncRequest(urlString: urlString, method: "put", jsonObject: jsonObject)
    }
    
    internal func syncRequest(url: URLConvertible) -> AFDataResponse<Data?> {
        return syncRequest(url: url, method: .get, parameters: nil, encoding: URLEncoding.default, headers: nil)
    }
    
    internal func syncRequest(url: URLConvertible, parameters: Parameters?) -> AFDataResponse<Data?> {
        return syncRequest(url: url, method: .get, parameters: parameters, encoding: URLEncoding.default, headers: nil)
    }
    
    internal func syncRequest(url: URLConvertible, method: HTTPMethod) -> AFDataResponse<Data?> {
        return syncRequest(url: url, method: method, parameters: nil, encoding: URLEncoding.default, headers: nil)
    }
    
    internal func syncRequest(url: URLConvertible, method: HTTPMethod, parameters: Parameters?) -> AFDataResponse<Data?> {
        return syncRequest(url: url, method: method, parameters: parameters, encoding: URLEncoding.default, headers: nil)
    }
    
    internal func syncRequest(url: URLConvertible, method: HTTPMethod, parameters: Parameters?, encoding: ParameterEncoding, headers: HTTPHeaders?) -> AFDataResponse<Data?> {
        if (Preferabli.loggingEnabled) {
            print(parameters)
        }
        
        var outResponse: AFDataResponse<Data?>!
        let semaphore = DispatchSemaphore(value: 0)
        
        self.request(url, method: method, parameters: parameters, encoding: encoding, headers: headers).response { response in
            outResponse = response
            semaphore.signal()
        }
        semaphore.wait(timeout: DispatchTime.distantFuture)
        
        return outResponse
    }
    
    internal func syncRequest(urlString: String, method: String, jsonObject: Any) throws -> AFDataResponse<Data?> {
        if (Preferabli.loggingEnabled) {
            print(jsonObject)
        }
        
        var outResponse: AFDataResponse<Data?>!
        let semaphore = DispatchSemaphore(value: 0)
        
        let url = URL(string: urlString)
        var request = URLRequest(url: url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if (jsonObject is Data) {
            request.httpBody = jsonObject as! Data
        } else {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonObject)
        }
        
        self.request(request).response { response in
            outResponse = response
            semaphore.signal()
        }
        semaphore.wait(timeout: DispatchTime.distantFuture)
        
        return outResponse
    }

    internal func syncUpload(url: URLConvertible, data: Data) throws -> AFDataResponse<Data?> {
        var outResponse: AFDataResponse<Data?>!
        let semaphore = DispatchSemaphore(value: 0)
        
        let url = URL(string: try url.asURL().absoluteString)
        var request = URLRequest(url: url!)
        request.httpMethod = "post"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        self.upload(multipartFormData: { multipartFormData in
            multipartFormData.append(data, withName: "file", fileName: "file.jpg", mimeType: "image/jpeg")
            multipartFormData.append(String(PreferabliTools.getPreferabliUserId()).data(using: String.Encoding.utf8, allowLossyConversion: false)!, withName: "user_id")
        }, with: request).response(completionHandler: { response in
            
            switch response.result {
            case .success:
                outResponse = response
                semaphore.signal()
            case .failure:
                print(response.error?.localizedDescription)
            }
        })
        semaphore.wait(timeout: DispatchTime.distantFuture)
        
        return outResponse
    }
    
    internal func syncUpload(url: URLConvertible, data: Data, position: String) throws -> AFDataResponse<Data?> {
        var outResponse: AFDataResponse<Data?>!
        let semaphore = DispatchSemaphore(value: 0)
        
        let url = URL(string: try url.asURL().absoluteString)
        var request = URLRequest(url: url!)
        request.httpMethod = "post"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        self.upload(multipartFormData: { multipartFormData in
            multipartFormData.append(data, withName: "file", fileName: "file.jpg", mimeType: "image/jpeg")
            multipartFormData.append(position.data(using: String.Encoding.utf8, allowLossyConversion: false)!, withName: "position")
        }, with: request).response(completionHandler: { response in
            
            switch response.result {
            case .success:
                outResponse = response
                semaphore.signal()
            case .failure:
                print(response.error?.localizedDescription)
            }
        })
        semaphore.wait(timeout: DispatchTime.distantFuture)
        
        return outResponse
    }
}
