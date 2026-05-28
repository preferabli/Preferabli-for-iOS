//
//  GenAIModels.swift
//  Tastefuli
//
//  SwiftData replacement for the old GenAI CoreData models.
//

import Foundation
import SwiftData

@Model
public final class GenAIMessage: HasIntID, HasTimestamps {

    public enum Source {
        public static let system = "dialog_system"

        public static var client: String {
            Bundle.main.object(forInfoDictionaryKey: "clientInterface") as? String ?? "ios_sdk"
        }
    }

    @Attribute(.unique) public var id: Int

    public var sessionId: String?
    public var transactionId: String?
    public var source: String?
    public var utterance: String?
    public var turn: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var userAction: String?
    public var userOptions: String?
    public var userSelection: String?

    public var reportedIssue: String?
    public var feedbackId: Int?
    public var positiveReaction: Bool

    // Product / food relationships from the CoreData version are represented as IDs here.
    // The SwiftUI layer can hydrate products with ProductsQuery(ids:) and food cards can be
    // hydrated later when the API layer is ported.
    public var productIds: [Int]
    public var variantIds: [Int]
    public var foodIds: [Int]

    public var selectedProductId: Int?
    public var selectedFoodId: Int?
    public var didRejectSelection: Bool

    @Relationship(deleteRule: .cascade, inverse: \GenAIUtterance.message)
    public var utteranceObjects: [GenAIUtterance]

    @Transient public var showTypingAnimation = false
    @Transient public var isLoadingPlaceholder = false
    @Transient public var showProductOptionsAnimation = false
    @Transient public var showPostTypingAnimation = false
    @Transient public var shouldShowPostText = false
    @Transient public var shouldShowProductOptions = true
    
    // local only
    public var isTombstoned: Bool = false

    public init(
        id: Int = GenAIMessage.makeLocalId(),
        isTombstoned: Bool = false,
        sessionId: String? = nil,
        transactionId: String? = nil,
        source: String? = nil,
        utterance: String? = nil,
        turn: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        userAction: String? = nil,
        userOptions: String? = nil,
        userSelection: String? = nil,
        reportedIssue: String? = nil,
        feedbackId: Int? = nil,
        positiveReaction: Bool = false,
        productIds: [Int] = [],
        variantIds: [Int] = [],
        foodIds: [Int] = [],
        selectedProductId: Int? = nil,
        selectedFoodId: Int? = nil,
        didRejectSelection: Bool = false,
        utteranceObjects: [GenAIUtterance] = []
    ) {
        self.id = id
        self.isTombstoned = isTombstoned
        self.sessionId = sessionId
        self.transactionId = transactionId
        self.source = source
        self.utterance = utterance
        self.turn = turn
        self.created_at = createdAt
        self.updated_at = updatedAt
        self.userAction = userAction
        self.userOptions = userOptions
        self.userSelection = userSelection
        self.reportedIssue = reportedIssue
        self.feedbackId = feedbackId
        self.positiveReaction = positiveReaction
        self.productIds = productIds
        self.variantIds = variantIds
        self.foodIds = foodIds
        self.selectedProductId = selectedProductId
        self.selectedFoodId = selectedFoodId
        self.didRejectSelection = didRejectSelection
        self.utteranceObjects = utteranceObjects
    }
    
    public static func predicate(forID id: Int) -> Predicate<GenAIMessage> {
        #Predicate<GenAIMessage> { $0.id == id }
    }

    public static func makeLocalId() -> Int {
        Int.random(in: 1_000_000_000...9_223_372_036_854_000_000)
    }

    public static func loading(sessionId: String?, turn: Int) -> GenAIMessage {
        let message = GenAIMessage(
            sessionId: sessionId,
            source: Source.system,
            utterance: nil,
            turn: turn,
            createdAt: Date(),
            updatedAt: Date()
        )
        message.isLoadingPlaceholder = true
        return message
    }

    public var isSystemMessage: Bool {
        source == Source.system
    }

    public var isUserMessage: Bool {
        !isSystemMessage
    }

    public var isUserSelection: Bool {
        userOptions != nil
    }

    public var hasProductOptions: Bool {
        !productIds.isEmpty
    }

    public var hasFoodOptions: Bool {
        !foodIds.isEmpty || !foodOptionContents.isEmpty
    }

    public var hasSelectionOptions: Bool {
        hasProductOptions || hasFoodOptions
    }

    public var awaitsSelection: Bool {
        isUserSelection &&
        hasSelectionOptions &&
        selectedProductId == nil &&
        selectedFoodId == nil &&
        !didRejectSelection
    }

    public var canReceiveFeedback: Bool {
        isSystemMessage && !(transactionId ?? "").isEmptyOrWhitespace()
    }

    public var sortedUtteranceObjects: [GenAIUtterance] {
        utteranceObjects.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    public var messageText: String {
        var text = utterance ?? ""

        for utteranceObject in sortedUtteranceObjects where utteranceObject.isPrimaryDisplayText {
            for contentObject in utteranceObject.sortedContent {
                if let display = contentObject.displayData, !display.isEmptyOrWhitespace() {
                    text = display
                }
            }
        }

        return text
    }

    public var postText: String {
        var text = ""

        for utteranceObject in sortedUtteranceObjects where utteranceObject.isPostDisplayText {
            for contentObject in utteranceObject.sortedContent {
                if let display = contentObject.displayData, !display.isEmptyOrWhitespace() {
                    text = display
                }
            }
        }

        return text
    }

    public var productOptionContents: [GenAIUtteranceContent] {
        sortedUtteranceObjects
            .filter { ["products", "product_list", "wine_list"].contains($0.subType) }
            .flatMap(\.sortedContent)
    }

    public var foodOptionContents: [GenAIUtteranceContent] {
        sortedUtteranceObjects
            .filter { $0.subType == "foods" }
            .flatMap(\.sortedContent)
    }

    public var selectedFoodName: String? {
        guard let selectedFoodId else { return nil }
        return foodOptionContents.first(where: { $0.entityId == selectedFoodId })?.displayName
    }

    public func productDescription(variantIds: [Int]) -> String? {
        guard !variantIds.isEmpty else { return nil }

        for utteranceObject in sortedUtteranceObjects where utteranceObject.subType == "product_desc" {
            for contentObject in utteranceObject.sortedContent {
                guard let contentId = contentObject.remoteId else { continue }

                if variantIds.contains(contentId),
                   let display = contentObject.displayData,
                   !display.isEmptyOrWhitespace() {
                    return display
                }
            }
        }

        return nil
    }
}

@Model
public final class GenAIUtterance {

    public var type: String
    public var subType: String
    public var order: Int?

    public var message: GenAIMessage?

    @Relationship(deleteRule: .cascade, inverse: \GenAIUtteranceContent.utterance)
    public var content: [GenAIUtteranceContent]

    public init(
        type: String = "",
        subType: String = "",
        order: Int? = nil,
        content: [GenAIUtteranceContent] = []
    ) {
        self.type = type
        self.subType = subType
        self.order = order
        self.content = content
    }

    public var sortedContent: [GenAIUtteranceContent] {
        content.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    public var isPrimaryDisplayText: Bool {
        type == "error" ||
        type == "selection_intro" ||
        (type == "text" && subType.isEmptyOrWhitespace()) ||
        [
            "lttt_intro",
            "wff_intro",
            "product_info",
            "wine_info",
            "stock_query",
            "guided_rec_intro",
            "generic_rec_intro",
            "stock_lttt",
            "product_card_info",
            "wine_card_info",
            "llm_response"
        ].contains(subType)
    }

    public var isPostDisplayText: Bool {
        [
            "lttt_outro",
            "wff_outro",
            "guided_rec_end",
            "generic_rec_end"
        ].contains(subType)
    }
}

@Model
public final class GenAIUtteranceContent {

    // Old CoreData property was named `id`. In practice this is often a product variant ID,
    // so keep it distinct from SwiftData identity.
    public var remoteId: Int?
    public var productId: Int?
    public var entityId: Int?
    public var order: Int?

    public var entityName: String?
    public var entityProbability: Double?
    public var name: String?
    public var recognitionType: String?
    public var displayData: String?

    public var utterance: GenAIUtterance?

    public init(
        remoteId: Int? = nil,
        productId: Int? = nil,
        entityId: Int? = nil,
        order: Int? = nil,
        entityName: String? = nil,
        entityProbability: Double? = nil,
        name: String? = nil,
        recognitionType: String? = nil,
        displayData: String? = nil
    ) {
        self.remoteId = remoteId
        self.productId = productId
        self.entityId = entityId
        self.order = order
        self.entityName = entityName
        self.entityProbability = entityProbability
        self.name = name
        self.recognitionType = recognitionType
        self.displayData = displayData
    }

    public var stableID: String {
        [remoteId, entityId, order]
            .compactMap { $0 }
            .map(String.init)
            .joined(separator: "-")
    }

    public var displayName: String {
        if let name, !name.isEmptyOrWhitespace() {
            return name
        }

        if let entityName, !entityName.isEmptyOrWhitespace() {
            return entityName
        }

        if let displayData, !displayData.isEmptyOrWhitespace() {
            return displayData
        }

        return ""
    }
}
