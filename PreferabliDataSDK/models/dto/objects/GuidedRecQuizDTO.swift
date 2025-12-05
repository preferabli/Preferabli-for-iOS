//
//  GuidedRec.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/10/16.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//

import Foundation

/// A Guided Rec questionnaire. Returned by ``Preferabli/getGuidedRec(guided_rec_id:onCompletion:onFailure:)``.
public struct GuidedRecQuizDTO : Decodable, Sendable, Identifiable, Hashable {
    
    /// The default wine questionnaire.
    public static let WINE_DEFAULT : Int = 1
    
    public var id: Int // Added ID back
    public var name : String?
    public var default_currency : String?
    public var product_category : String?
    public var default_price_min : Int?
    public var default_price_max : Int?
    public var default_price_increment : Int?
    public var max_results_per_type : Int?
    public var questions : [GuidedRecQuestionDTO]
}

/// A question within a ``GuidedRec`` questionnaire.
public struct GuidedRecQuestionDTO : Decodable, Sendable, Identifiable, Hashable {
    public var id: Int // Added ID back
    public var number : Int?
    public var choices : [GuidedRecChoiceDTO]
    public var type : String?
    public var minimum_selected : Int?
    public var maximum_selected : Int?
    public var text : String?
    public var requires_choice_ids: [Int]? // For logic filtering
    public var mixpanel_group_slug : String?
    public var default_price_min : Int?
    public var default_price_max : Int?
    public var default_price_increment : Int?
}

/// A choice within a ``GuidedRecQuestion``. Pass an array of these to get results from ``Preferabli/getGuidedRecResults(guided_rec_id:selected_choice_ids:price_min:price_max:collection_id:include_merchant_links:onCompletion:onFailure:)``.
public struct GuidedRecChoiceDTO : Decodable, Sendable, Identifiable, Hashable {
    public var id: Int // Added ID back
    public var number : Int?
    public var requires_choice_ids : [Int]?
    public var text : String?
}
