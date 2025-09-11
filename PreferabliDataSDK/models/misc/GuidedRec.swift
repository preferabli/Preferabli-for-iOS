//
//  GuidedRec.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/10/16.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//

import Foundation

/// A Guided Rec questionnaire. Returned by ``Preferabli/getGuidedRec(guided_rec_id:onCompletion:onFailure:)``.
public class GuidedRec : BaseObject {
    
    /// The default wine questionnaire.
    public static let WINE_DEFAULT : Int = 1
    
    public var name : String?
    public var default_currency : String?
    public var default_price_min : Int?
    public var default_price_max : Int?
    public var max_results_per_type : Int?
    public var questions : [GuidedRecQuestion]

    internal init(map : [String : Any]) {
        name = map["name"] as? String
        default_currency = map["default_currency"] as? String
        default_price_min = map["default_price_min"] as? Int
        default_price_max = map["default_price_max"] as? Int
        questions = Array<GuidedRecQuestion>()
        for question in (map["questions"] as! NSArray) {
            questions.append(GuidedRecQuestion.init(map: question as! [String : Any]))
        }
        max_results_per_type = map["maximum_selected"] as? Int
        super.init(id: map["id"] as? Int ?? 0)
    }
}

/// A question within a ``GuidedRec`` questionnaire.
public class GuidedRecQuestion : BaseObject {
    
    public var number : Int?
    public var choices : [GuidedRecChoice]
    public var type : String?
    public var minimum_selected : Int?
    public var maximum_selected : Int?
    public var text : String?

    internal init(map : [String : Any]) {
        number = map["number"] as? Int
        choices = Array<GuidedRecChoice>()
        for choice in (map["choices"] as! NSArray) {
            choices.append(GuidedRecChoice.init(map: choice as! [String : Any]))
        }
        type = map["type"] as? String
        minimum_selected = map["minimum_selected"] as? Int
        maximum_selected = map["maximum_selected"] as? Int
        text = map["text"] as? String
        super.init(id: map["id"] as? Int ?? 0)
    }
}

/// A choice within a ``GuidedRecQuestion``. Pass an array of these to get results from ``Preferabli/getGuidedRecResults(guided_rec_id:selected_choice_ids:price_min:price_max:collection_id:include_merchant_links:onCompletion:onFailure:)``.
public class GuidedRecChoice : BaseObject {

    public var number : Int?
    public var requires_choice_ids : [Int]?
    public var text : String?
    
    internal init(map : [String : Any]) {
        number = map["number"] as? Int
        requires_choice_ids = map["requires_choice_ids"] as? [Int]
        text = map["text"] as? String
        super.init(id: map["id"] as? Int ?? 0)
    }
}
