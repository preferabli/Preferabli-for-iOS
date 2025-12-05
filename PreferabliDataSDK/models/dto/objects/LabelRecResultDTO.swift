//
//  LabelRecResultDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 1/13/17.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//

import Foundation
import CoreData

/// The result container eturned by ``Preferabli/labelRecognition(image:include_merchant_links:onCompletion:onFailure:)``.
public struct LabelRecResultDTO: Decodable, Sendable {
    
    /// A score on a scale of 0 - 100  representing the degree of difference between the submitted image and the matching image.  Results with higher scores ore more likely a matching ``Product``.
    public var score: Double
    public var product: ProductDTO
}
