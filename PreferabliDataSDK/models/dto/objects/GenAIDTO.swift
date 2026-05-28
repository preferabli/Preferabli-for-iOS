//
//  GenAIDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 5/20/26.
//

import Foundation

public struct GenAIStartConversationDTO: Decodable, Sendable {
    public let sessionId: String

    private enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }
}

public struct GenAIThinkingDTO: Decodable, Sendable {
    public let thresholdInSeconds: Int?
    public let displayText: String?

    private enum CodingKeys: String, CodingKey {
        case thresholdInSeconds = "threshold_in_seconds"
        case displayText = "display_text"
    }
}

public struct GenAIVoiceOptionDTO: Decodable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let displayName: String

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

public struct GenAIFeedbackDTO: Decodable, Sendable {
    public let id: Int
}

public typealias GenAIHistoryResponseDTO = [String: GenAIMessageDTO?]

public struct GenAIHistoryConversationSummary: Identifiable, Hashable, Sendable {
    public var id: String { sessionId }

    public let sessionId: String
    public let messageId: Int?
    public let turn: Int?
    public let previewText: String
    public let createdAt: Date?

    public init(
        sessionId: String,
        messageId: Int?,
        turn: Int?,
        previewText: String,
        createdAt: Date?
    ) {
        self.sessionId = sessionId
        self.messageId = messageId
        self.turn = turn
        self.previewText = previewText
        self.createdAt = createdAt
    }
}

public struct GenAIUtteranceContentDTO: Decodable, Sendable {
    public let remoteId: Int?
    public let productId: Int?
    public let entityId: Int?
    public let order: Int?
    public let entityName: String?
    public let entityProbability: Double?
    public let name: String?
    public let recognitionType: String?
    public let displayData: String?

    enum CodingKeys: String, CodingKey {
        case remoteId = "id"
        case productId = "product_id"
        case entityId = "entity_id"
        case order
        case entityName = "entity_name"
        case entityProbability = "entity_prob"
        case name
        case recognitionType = "recog_type"
        case displayData = "display_data"
    }
}

public struct GenAIUtteranceDTO: Decodable, Sendable {
    public let type: String?
    public let subType: String?
    public let order: Int?
    public let content: [GenAIUtteranceContentDTO]

    enum CodingKeys: String, CodingKey {
        case type
        case subType = "sub_type"
        case order
        case content
    }

    fileprivate var isPrimaryDisplayText: Bool {
        let type = type ?? ""
        let subType = subType ?? ""

        return type == "error" ||
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
}

public struct GenAIMessageDTO: Decodable, Sendable {
    public let id: Int
    public let sessionId: String?
    public let transactionId: String?
    public let source: String?
    public let utterance: String?
    public let turn: Int?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let userAction: String?
    public let userOptions: String?
    public let userSelection: String?
    public let reportedIssue: String?
    public let feedbackId: Int?
    public let positiveReaction: Bool?
    public let utteranceObjects: [GenAIUtteranceDTO]

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case transactionId = "transaction_id"
        case source
        case utterance
        case turn
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case userAction = "user_action"
        case userOptions = "user_options"
        case userSelection = "user_selection"
        case reportedIssue = "reported_issue"
        case feedbackId = "feedback_id"
        case positiveReaction = "positive_reaction"
        case utteranceObjects = "utterance_objects"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        transactionId = try container.decodeIfPresent(String.self, forKey: .transactionId)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        utterance = try container.decodeIfPresent(String.self, forKey: .utterance)
        turn = try container.decodeIfPresent(Int.self, forKey: .turn)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        userAction = try container.decodeIfPresent(String.self, forKey: .userAction)
        userOptions = try container.decodeIfPresent(String.self, forKey: .userOptions)
        userSelection = try container.decodeIfPresent(String.self, forKey: .userSelection)
        reportedIssue = try container.decodeIfPresent(String.self, forKey: .reportedIssue)
        feedbackId = try container.decodeIfPresent(Int.self, forKey: .feedbackId)
        positiveReaction = try container.decodeIfPresent(Bool.self, forKey: .positiveReaction)

        utteranceObjects = try container.decodeIfPresent(
            [GenAIUtteranceDTO].self,
            forKey: .utteranceObjects
        ) ?? []
    }

    public var productEntityIds: [Int] {
        utteranceObjects.flatMap { object -> [Int] in
            guard ["products", "product_list", "wine_list"].contains(object.subType) else {
                return []
            }

            return object.content.compactMap { content in
                if let productId = content.productId {
                    return productId
                }

                if object.subType == "products" {
                    return content.entityId
                }

                return content.remoteId
            }
        }
        .uniqued()
    }

    public var variantIds: [Int] {
        utteranceObjects.flatMap { object -> [Int] in
            guard ["product_list", "wine_list"].contains(object.subType) else {
                return []
            }

            return object.content.compactMap { content in
                guard content.productId != nil else {
                    return nil
                }

                return content.remoteId
            }
        }
        .uniqued()
    }

    public var foodIds: [Int] {
        utteranceObjects
            .filter { $0.subType == "foods" }
            .flatMap(\.content)
            .compactMap(\.entityId)
    }

    public var historyPreviewText: String {
        var text = utterance ?? ""

        for utteranceObject in utteranceObjects where utteranceObject.isPrimaryDisplayText {
            for contentObject in utteranceObject.content.sorted(by: { ($0.order ?? 0) < ($1.order ?? 0) }) {
                if let display = contentObject.displayData, !display.isEmptyOrWhitespace() {
                    text = display
                }
            }
        }

        return text
    }
}

public struct GenAILambdaDTO: Decodable, Sendable {
    public let url: String
    public let isCurrent: Bool
    public let isStaging: Bool
    public let isDev: Bool

    enum CodingKeys: String, CodingKey {
        case url
        case isCurrent = "is_current"
        case isStaging = "is_staging"
        case isDev = "is_dev"
    }
}

internal struct GenAIChallengeDTO: Decodable, Sendable {
    let powHash: String
    let difficulty: Int

    enum CodingKeys: String, CodingKey {
        case powHash = "pow_hash"
        case difficulty
    }
}

internal struct GenAIHandshakeDTO: Decodable, Sendable {
    let token: String
}

public struct GenAIProductDescriptionDTO: Decodable {
    public let id: Int?
    public let productId: Int?
    public let variantId: Int?
    public let productName: String?
    public let description: String?
    public let createdAt: String?
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case productId = "product_id"
        case variantId = "variant_id"
        case productName = "product_name"
        case description
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
