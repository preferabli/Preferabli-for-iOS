import Foundation
import SwiftData

/// Only the beta host opts in through its Info.plist; other SDK clients are unchanged.
public enum AppDeepLinkScheme {
    public static let isTastefuliBeta =
        Bundle.main.object(forInfoDictionaryKey: "TastefuliAppURLScheme") as? String == "tastefulibetaapp"

    public static var preferred: String {
        isTastefuliBeta ? "tastefulibetaapp" : "tastefuliapp"
    }

    public static var supported: Set<String> {
        var schemes: Set<String> = ["tastefuliapp", "cuveeapp"]
        if isTastefuliBeta { schemes.insert("tastefulibetaapp") }
        return schemes
    }

    /// Preserve the rest of the URL/HTML verbatim, including escaping and query arguments.
    public static func normalize(_ text: String) -> String {
        guard isTastefuliBeta else { return text }
        return text.replacingOccurrences(
            of: "(?i)(?<![a-z0-9+.-])tastefuliapp://",
            with: "tastefulibetaapp://",
            options: .regularExpression
        )
    }

    public static func normalize(_ url: URL) -> URL {
        guard isTastefuliBeta, url.scheme?.lowercased() == "tastefuliapp" else { return url }
        let raw = url.absoluteString
        guard let colon = raw.firstIndex(of: ":") else { return url }
        return URL(string: preferred + raw[colon...]) ?? url
    }
}

/// Typed persisted-string access keeps this independent of SwiftData's private backing storage.
/// Add new models/string attributes here when expanding the SDK's persisted content schema.
enum BetaDeepLinkStorage {
    // Closures capture only immutable key paths, never a model or context.
    // Models and contexts are supplied and used on the caller's executor.
    private struct Entry: @unchecked Sendable {
        let normalize: (any PersistentModel) -> Void
    }

    private static func entry<Model: PersistentModel>(
        _ type: Model.Type,
        required: [ReferenceWritableKeyPath<Model, String>] = [],
        optional: [ReferenceWritableKeyPath<Model, String?>] = []
    ) -> Entry {
        func normalize(_ model: Model) {
            for key in required {
                let old = model[keyPath: key]
                let updated = AppDeepLinkScheme.normalize(old)
                if old != updated { model[keyPath: key] = updated }
            }
            for key in optional {
                guard let old = model[keyPath: key] else { continue }
                let updated = AppDeepLinkScheme.normalize(old)
                if old != updated { model[keyPath: key] = updated }
            }
        }
        return Entry(normalize: { model in
            if let model = model as? Model { normalize(model) }
        })
    }

    static func save(_ context: ModelContext) throws {
        if AppDeepLinkScheme.isTastefuliBeta {
            for model in context.insertedModelsArray + context.changedModelsArray {
                for entry in entries { entry.normalize(model) }
            }
        }
        try context.save()
    }

    private static let entries: [Entry] = [
        entry(Customer.self, optional: [\.avatar_url, \.merchant_user_email_address,
                                       \.merchant_user_id, \.merchant_user_name,
                                       \.merchant_user_display_name, \.role, \.claim_code]),
        entry(Affiliate.self,
            optional: [
                \.affiliate_code, \.affiliate_param, \.affiliate_description, \.header_image_url,
                \.logo_image_url, \.name, \.slug, \.title
            ]),
        entry(CTABucket.self,
            optional: [
                \.type, \.name, \.deeplink_url
            ]),
        entry(CTABucketItem.self,
            optional: [
                \.badge_icon, \.badge_color_hex_primary, \.badge_color_hex_secondary, \.color_hex_secondary,
                \.color_hex_primary, \.text_color_hex, \.gradient_css, \.badge_gradient_css,
                \.badge_text_color_hex, \.deeplink_url, \.badge_title, \.title, \.desc, \.subtext,
                \.badge_placement
            ]),
        entry(CTAPage.self,
            optional: [
                \.slug, \.name
            ]),
        entry(Channel.self,
            optional: [
                \.name, \.description_text, \.default_timezone, \.default_currency, \.default_badge_method
            ]),
        entry(Collection.self,
            optional: [
                \.code, \.desc, \.name, \.badge_method, \.currency, \.timezone, \.sort_channel_name
            ]),
        entry(CollectionGroup.self,
            optional: [
                \.name
            ]),
        entry(CollectionOrder.self,
            optional: [
                \.tagTypeRaw, \.searchableRaw
            ]),
        entry(CollectionTrait.self,
            optional: [
                \.name
            ]),
        entry(CollectionVersion.self,
            optional: [
                \.name
            ]),
        entry(ContentItem.self,
            optional: [
                \.title, \.desc, \.episode_name
            ]),
        entry(Personality.self,
            optional: [
                \.name, \.desc, \.badge_title, \.badge_text_color_hex, \.badge_gradient_css
            ]),
        entry(ContentPersonalityAssociation.self,
            optional: [
                \.relationship
            ]),
        entry(DeliveryMethod.self,
            optional: [
                \.shipping_type, \.state_abbreviation, \.state_display_name, \.country, \.shipping_cost_note,
                \.shipping_speed_note
            ]),
        entry(Experience.self,
            required: [
                \.name
            ],
            optional: [
                \.booking_link, \.booking_terms, \.affiliate_unlock_code, \.experience_description,
                \.experience_description_secondary, \.discount_code, \.experience_type, \.header_image_url,
                \.qualifier_text, \.qualifier_title, \.reservation_api, \.reservation_notice,
                \.reservation_options, \.reservation_type, \.stripe_product_id, \.terms_and_conditions,
                \.unit_label, \.badge_title, \.badge_subtitle, \.badge_color_hex, \.badge_text_color_hex,
                \.badge_gradient_css, \.cancellation_fee, \.reservations_provider, \.preferabli_image_url
            ]),
        entry(ExperiencePrice.self,
            optional: [
                \.age_range, \.experience_economics, \.pricing_mode, \.price_type, \.stripe_product_price_id
            ]),
        entry(ExperienceType.self,
            optional: [
                \.icon_url, \.image_url, \.name
            ]),
        entry(Food.self,
            optional: [
                \.name, \.desc, \.keywords, \.food_category_name, \.food_category_url, \.primary_image_url,
                \.food_category_icon_svg_url
            ]),
        entry(FoodCategory.self,
            optional: [
                \.name, \.icon_url, \.icon_svg_url
            ]),
        entry(GenAIMessage.self,
            optional: [
                \.sessionId, \.transactionId, \.source, \.utterance, \.userAction, \.userOptions,
                \.userSelection, \.reportedIssue
            ]),
        entry(GenAIUtterance.self,
            required: [
                \.type, \.subType
            ]),
        entry(GenAIUtteranceContent.self,
            optional: [
                \.entityName, \.name, \.recognitionType, \.displayData
            ]),
        entry(Itinerary.self,
            optional: [
                \.name, \.type, \.desc, \.curator_personality_description, \.color_hex_primary, \.badge_title,
                \.badge_icon, \.badge_color_hex_primary, \.badge_color_hex_secondary, \.badge_gradient_css,
                \.badge_text_color_hex, \.distance_unit
            ]),
        entry(ItineraryItem.self,
            optional: [
                \.time, \.name, \.desc, \.type
            ]),
        entry(ItineraryMarketTrait.self,
            required: [
                \.key
            ]),
        entry(ItineraryItemAssociation.self,
            optional: [
                \.desc, \.local_tip_title, \.local_tip, \.button_title, \.button_deeplink_url, \.button_icon
            ]),
        entry(ItineraryHighlight.self,
            optional: [
                \.icon_url, \.name, \.desc, \.type
            ]),
        entry(Location.self,
            optional: [
                \.zip_code, \.country_code
            ]),
        entry(Market.self,
            optional: [
                \.name, \.desc, \.image_url, \.country_code, \.distance_unit, \.currency_code
            ]),
        entry(MarketTrait.self,
            optional: [
                \.type, \.name, \.icon_url
            ]),
        entry(Media.self,
            optional: [
                \.path, \.type, \.mime_type
            ]),
        entry(Occasion.self,
            required: [
                \.name
            ]),
        entry(PreferabliUser.self,
            optional: [
                \.country, \.display_name, \.email, \.phone, \.fname, \.lname, \.location, \.claim_code,
                \.zip_code, \.intercom_hmac, \.avatar_background_color_hex, \.avatar_text_color_hex
            ]),
        entry(PreferenceData.self,
            optional: [
                \.title, \.details
            ]),
        entry(Product.self,
            optional: [
                \.brand, \.grape, \.name, \.region, \.type, \.category, \.subcategory, \.product_hash,
                \.country_code, \.temporaryName
            ]),
        entry(ProductProfile.self,
            optional: [
                \.trait1Name, \.trait2Name, \.trait3Name, \.trait4Name, \.flavor1Name, \.flavor2Name,
                \.flavor3Name, \.flavor4Name, \.flavor1Image, \.flavor2Image, \.flavor3Image, \.flavor4Image,
                \.food_category_1_name, \.food_category_2_name, \.food_category_3_name,
                \.food_category_4_name, \.food_category_1_icon_png_url, \.food_category_2_icon_png_url,
                \.food_category_3_icon_png_url, \.food_category_4_icon_png_url
            ]),
        entry(ProductRecipe.self,
            required: [
                \.key
            ]),
        entry(ProfileStyle.self,
            optional: [
                \.keywords
            ]),
        entry(PushNotificationReceipt.self,
            required: [
                \.notification_id, \.title, \.message
            ]),
        entry(Recipe.self,
            optional: [
                \.merchant_recipe_id, \.url, \.primary_image_url, \.desc, \.name
            ]),
        entry(RecipeGroup.self,
            optional: [
                \.internal_notes, \.name, \.icon_svg_url, \.type
            ]),
        entry(Reservation.self,
            optional: [
                \.customer_slug, \.date, \.status, \.brand_name, \.brand_logo_image_url, \.experience_name,
                \.experience_header_image_url, \.experience_preferabli_image_url, \.booking_account_id,
                \.booking_confirmation_ref, \.booking_group_lead, \.booking_meeting_address, \.booking_type,
                \.booking_confirmed_time, \.booking_customer_slug, \.booking_date,
                \.booking_modification_link, \.booking_payment_method_id, \.booking_specific_requests,
                \.booking_status
            ]),
        entry(ReservationRequestGuest.self,
            required: [
                \.key
            ],
            optional: [
                \.price_age_range, \.price_experience_economics, \.price_pricing_mode, \.price_price_type,
                \.price_stripe_product_price_id
            ]),
        entry(Search.self,
            required: [
                \.text
            ]),
        entry(Style.self,
            required: [
                \.type
            ],
            optional: [
                \.desc, \.name, \.primary_image_url, \.product_category
            ]),
        entry(Tag.self,
            required: [
                \.searchableContent
            ],
            optional: [
                \.comment, \.location, \.badge, \.tagged_in_channel_name, \.type, \.value, \.occasion, \.bin
            ]),
        entry(UserCollection.self,
            optional: [
                \.relationship_type
            ]),
        entry(Venue.self,
            required: [
                \.name
            ],
            optional: [
                \.address_l1, \.address_l2, \.city, \.country, \.display_name, \.phone, \.email_address,
                \.state, \.url, \.url_facebook, \.url_instagram, \.url_twitter, \.url_youtube, \.zip_code,
                \.notes
            ]),
        entry(VenueHour.self,
            optional: [
                \.weekday, \.open_time, \.close_time
            ]),
        entry(VenueImage.self,
            required: [
                \.key
            ]),
        entry(VenueMarketTrait.self,
            required: [
                \.key
            ]),
    ]
}
