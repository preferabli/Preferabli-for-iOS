//
//  LabelRecResult.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 1/13/17.
//  Copyright © 2023 RingIT, Inc. All rights reserved.
//

import Foundation
import CoreData

/// The result container eturned by ``Preferabli/labelRecognition(image:include_merchant_links:onCompletion:onFailure:)``.
public class LabelRecResult {
    
    /// A score on a scale of 0 - 100  representing the degree of difference between the submitted image and the matching image.  Results with higher scores ore more likely a matching ``Product``.
    public var score: NSNumber
    public var product: Product
    
    internal init(score : NSNumber, product : Product) {
        self.score = score
        self.product = product
    }
}
