//
//  Storage+DTOUpserts.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation
import SwiftData


extension Storage {
    
    // MARK: Product
    
    @discardableResult
    nonisolated static func upsertProduct(from dto: ProductDTO, tempProductId: Int? = nil, in ctx: ModelContext) throws -> Product {
        
        let product : Product
        if let pid = tempProductId, let temp = try Storage.fetchById(Product.self, id: pid, in: ctx) {
            product = temp
            product.id = dto.id
        } else {
            product = try fetchOrInsert(Product.self, id: dto.id, in: ctx) { Product(id: dto.id) }
        }
        
        product.name = dto.name
        product.created_at = dto.created_at ?? product.created_at
        product.updated_at = dto.updated_at ?? product.updated_at
        product.brand = dto.brand
        product.decant = dto.decant
        product.grape = dto.grape
        product.brand_lat = dto.brand_lat
        product.brand_lon = dto.brand_lon
        product.show_year_dropdown = dto.show_year_dropdown
        product.recommendable = dto.recommendable
        product.region = dto.region
        product.type = dto.type
        product.category = dto.category
        product.subcategory = dto.subcategory
        product.brand_id = dto.brand_id
        product.product_hash = dto.hash
        product.country_code = dto.country_code
        
        // Primary image
        if let imgDTO = dto.primary_image {
            let media = try upsertMedia(from: imgDTO, in: ctx)
            if product.primary_image !== media {            // <-- add this line
                product.primary_image = media
            }
        }
        
        // Variants
        var mostRecentYear = product.cachedMostRecentVariant?.year ??  -2
        if let vDTOs = dto.variants {
            for vDTO in vDTOs {
                let variant = try upsertVariant(from: vDTO, product: product, in: ctx)
                if (variant.year > mostRecentYear) {
                    mostRecentYear = variant.year
                    product.cachedMostRecentVariant = variant
                }
            }
        }
        
        if let latest_variant_num_dollar_signs = dto.latest_variant_num_dollar_signs, latest_variant_num_dollar_signs != 0 {
            if product.variants.isEmpty {
                let variant = Variant(id: PreferabliTools.generateRandomLongId(), year: Variant.CURRENT_VARIANT_YEAR, product: product)
                product.cachedMostRecentVariant = variant
                variant.num_dollar_signs = dto.latest_variant_num_dollar_signs!
                ctx.insert(variant)
            }
        }
        
        return product
    }
    
    // MARK: ProductProfile
    
    @discardableResult
    nonisolated static func upsertProductProfile(from dto: ProductProfileDTO,
                                                 for product: Product,
                                                 in ctx: ModelContext) throws -> ProductProfile {
        let profile = try fetchOrInsert(ProductProfile.self, id: product.id, in: ctx) { ProductProfile(product: product) }
        
        profile.product = product
        
        if product.profile !== profile {
            product.profile = profile
        }
        
        // 3) Assign fields (your existing mapping)
        profile.refreshed_at = Date()
        profile.trait1Name  = dto.trait1Name
        profile.trait2Name  = dto.trait2Name
        profile.trait3Name  = dto.trait3Name
        profile.trait4Name  = dto.trait4Name
        profile.trait1Level = dto.trait1Level
        profile.trait2Level = dto.trait2Level
        profile.trait3Level = dto.trait3Level
        profile.trait4Level = dto.trait4Level
        profile.flavor1Name = dto.flavor1Name
        profile.flavor2Name = dto.flavor2Name
        profile.flavor3Name = dto.flavor3Name
        profile.flavor4Name = dto.flavor4Name
        profile.flavor1Image = dto.flavor1Image
        profile.flavor2Image = dto.flavor2Image
        profile.flavor3Image = dto.flavor3Image
        profile.flavor4Image = dto.flavor4Image
        profile.food_category_1_name         = dto.food_category_1_name
        profile.food_category_2_name         = dto.food_category_2_name
        profile.food_category_3_name         = dto.food_category_3_name
        profile.food_category_4_name         = dto.food_category_4_name
        profile.food_category_1_icon_png_url = dto.food_category_1_icon_png_url
        profile.food_category_2_icon_png_url = dto.food_category_2_icon_png_url
        profile.food_category_3_icon_png_url = dto.food_category_3_icon_png_url
        profile.food_category_4_icon_png_url = dto.food_category_4_icon_png_url
        
        return profile
    }
    
    @discardableResult
    nonisolated static func upsertPreferenceData(from dto: PreferenceDataDTO,
                                                 for product: Product,
                                                 in ctx: ModelContext) throws -> PreferenceData {
        var preference_data = product.preference_data
        if (preference_data == nil) {
            preference_data = PreferenceData(product: product)
            ctx.insert(preference_data!)
        }
        
        let data = preference_data!
        
        data.refreshed_at = Date()
        data.title  = dto.title
        data.confidence_code = dto.confidence_code
        data.details = dto.details
        data.formatted_predict_rating = dto.formatted_predict_rating
        
        return data
    }
    
    
    // MARK: Variant
    
    @discardableResult
    nonisolated static func upsertVariant(from dto: VariantDTO, product: Product, in ctx: ModelContext) throws -> Variant {
        let v : Variant
        if let temp = product.getVariantWithYear(year: dto.year) {
            v = temp
            v.id = dto.id
        } else {
            v = try fetchOrInsert(Variant.self, id: dto.id, in: ctx) { Variant(id: dto.id, year: dto.year, product: product) }
        }
        v.created_at = dto.created_at ?? v.created_at
        v.updated_at = dto.updated_at ?? v.updated_at
        v.num_dollar_signs = dto.num_dollar_signs ?? v.num_dollar_signs
        v.price = dto.price ?? v.price
        v.recommendable = dto.recommendable ?? v.recommendable
        v.year = dto.year
        
        if let imgDTO = dto.primary_image {
            let media = try upsertMedia(from: imgDTO, in: ctx)
            if v.primary_image !== media {            // <-- add this line
                v.primary_image = media
            }
        }
        
        let currentMostRecentVariantYear = product.cachedMostRecentVariant?.year ?? -2
        if (v.year > currentMostRecentVariantYear) {
            product.cachedMostRecentVariant = v
        }
        
        return v
    }
    
    // MARK: Tag
    
    @discardableResult
    nonisolated static func upsertTag(from dto: TagDTO, variant: Variant, tempTagId: Int? = nil, in ctx: ModelContext) throws -> Tag {
        let t : Tag
        if let tid = tempTagId, let temp = try Storage.fetchById(Tag.self, id: tid, in: ctx) {
            t = temp
            t.id = dto.id
        } else {
            t = try fetchOrInsert(Tag.self, id: dto.id, in: ctx) { Tag(id: dto.id, collection_id: dto.collection_id, variant: variant) }
        }
        t.collection_id = dto.collection_id ?? t.collection_id
        t.comment = dto.comment ?? t.comment
        t.created_at = dto.created_at ?? t.created_at
        t.location = dto.location ?? t.location
        t.badge = dto.badge ?? t.badge
        t.tagged_in_collection_id = dto.tagged_in_collection_id ?? t.tagged_in_collection_id
        t.tagged_in_channel_id = dto.tagged_in_channel_id ?? t.tagged_in_channel_id
        t.tagged_in_channel_name = dto.tagged_in_channel_name ?? t.tagged_in_channel_name
        t.type = dto.type ?? t.type
        t.updated_at = dto.updated_at ?? t.updated_at
        t.user_id = dto.user_id ?? t.user_id
        t.value = dto.value ?? t.value
        t.bin = dto.bin ?? t.bin
        t.variant_id = dto.variant_id ?? t.variant_id
        t.quantity = dto.quantity ?? t.quantity
        t.format_ml = dto.format_ml ?? t.format_ml
        t.price = dto.price ?? t.price
        t.customer_id = dto.customer_id ?? t.customer_id
        
        let product = variant.product
        let newDate = t.created_at ?? .now
        
        if t.isRating() {
            let currentDate = product.cachedMostRecentRating?.created_at ?? .distantPast
            if newDate >= currentDate {
                product.cachedMostRecentRating = t
            }
        } else if t.isWishlist() {
            let currentDate = product.cachedWishlist?.created_at ?? .distantPast
            if newDate >= currentDate {
                product.cachedWishlist = t
            }
        }
        
        return t
    }
    
    // MARK: Media
    
    @discardableResult
    nonisolated static func upsertMedia(from dto: MediaDTO, in ctx: ModelContext) throws -> Media {
        let m = try fetchOrInsert(Media.self, id: dto.id, in: ctx) { Media(id: dto.id) }
        m.path = dto.path ?? m.path
        m.created_at = dto.created_at ?? m.created_at
        m.updated_at = dto.updated_at ?? m.updated_at
        m.type = dto.type ?? m.type
        return m
    }
    
    // MARK: Venue
    
    @discardableResult
    nonisolated static func upsertVenue(from dto: VenueDTO, in ctx: ModelContext) throws -> Venue {
        let v = try fetchOrInsert(Venue.self, id: dto.id, in: ctx) { Venue(id: dto.id) }
        v.address_l1 = dto.address_l1 ?? v.address_l1
        v.address_l2 = dto.address_l2 ?? v.address_l2
        v.city = dto.city ?? v.city
        v.country = dto.country ?? v.country
        v.display_name = dto.display_name ?? v.display_name
        v.lat = dto.lat ?? v.lat
        v.lon = dto.lon ?? v.lon
        v.primary_inventory_id = dto.primary_inventory_id ?? v.primary_inventory_id
        v.featured_collection_id = dto.featured_collection_id ?? v.featured_collection_id
        v.is_virtual = dto.is_virtual ?? v.is_virtual
        v.name = dto.name ?? v.name
        v.phone = dto.phone ?? v.phone
        v.email_address = dto.email_address ?? v.email_address
        v.state = dto.state ?? v.state
        v.url = dto.url ?? v.url
        v.url_facebook = dto.url_facebook ?? v.url_facebook
        v.url_instagram = dto.url_instagram ?? v.url_instagram
        v.url_twitter = dto.url_twitter ?? v.url_twitter
        v.url_youtube = dto.url_youtube ?? v.url_youtube
        v.zip_code = dto.zip_code ?? v.zip_code
        v.notes = dto.notes ?? v.notes
        
        if let imgs = dto.images {
            v.images = try imgs.map { try upsertMedia(from: $0, in: ctx) }
        }
        if let hrs = dto.hours {
            v.hours = try hrs.map { try upsertVenueHour(from: $0, in: ctx) }
        }
        if let dms = dto.active_delivery_methods {
            v.active_delivery_methods = try dms.map { try upsertDeliveryMethod(from: $0, in: ctx) }
        }
        if let cols = dto.collections {
            v.collections = try cols.map { try upsertCollection(from: $0, in: ctx) }
        }
        
        return v
    }
    
    @discardableResult
    nonisolated static func upsertVenueHour(from dto: VenueHourDTO, in ctx: ModelContext) throws -> VenueHour {
        let h = try fetchOrInsert(VenueHour.self, id: dto.id, in: ctx) { VenueHour(id: dto.id) }
        h.weekday = dto.weekday ?? h.weekday
        h.open_time = dto.open_time ?? h.open_time
        h.close_time = dto.close_time ?? h.close_time
        h.is_closed = dto.is_closed ?? h.is_closed
        return h
    }
    
    @discardableResult
    nonisolated static func upsertDeliveryMethod(from dto: DeliveryMethodDTO, in ctx: ModelContext) throws -> DeliveryMethod {
        let d = try fetchOrInsert(DeliveryMethod.self, id: dto.id, in: ctx) { DeliveryMethod(id: dto.id) }
        d.shipping_type = dto.shipping_type ?? d.shipping_type
        d.state_abbreviation = dto.state_abbreviation ?? d.state_abbreviation
        d.state_display_name = dto.state_display_name ?? d.state_display_name
        d.country = dto.country ?? d.country
        d.shipping_cost_note = dto.shipping_cost_note ?? d.shipping_cost_note
        d.shipping_speed_note = dto.shipping_speed_note ?? d.shipping_speed_note
        return d
    }
    
    // MARK: Collection tree
    
    @discardableResult
    nonisolated static func upsertCollection(from dto: CollectionDTO, in ctx: ModelContext) throws -> Collection {
        let c = try fetchOrInsert(Collection.self, id: dto.id, in: ctx) { Collection(id: dto.id) }
        
        c.channel_id = dto.channel_id ?? c.channel_id
        c.sort_channel_id = dto.sort_channel_id ?? c.sort_channel_id
        c.code = dto.code ?? c.code
        c.desc = dto.desc ?? c.desc
        c.end_date = dto.end_date ?? c.end_date
        c.updated_at = dto.updated_at ?? c.updated_at
        c.auto_wili = dto.auto_wili ?? c.auto_wili
        c.has_image = dto.has_image ?? c.has_image
        c.is_pinned = dto.is_pinned ?? c.is_pinned
        c.display_time = dto.display_time ?? c.display_time
        c.is_browsable = dto.is_browsable ?? c.is_browsable
        c.is_my_cellar = dto.is_my_cellar ?? c.is_my_cellar
        c.lbs_order = dto.lbs_order ?? c.lbs_order
        c.product_count = dto.product_count ?? c.product_count
        c.name = dto.name ?? c.name
        c.badge_method = dto.badge_method ?? c.badge_method
        c.currency = dto.currency ?? c.currency
        c.timezone = dto.timezone ?? c.timezone
        c.published = dto.published ?? c.published
        c.archived = dto.archived ?? c.archived
        c.display_price = dto.display_price ?? c.display_price
        c.display_quantity = dto.display_quantity ?? c.display_quantity
        c.display_bin = dto.display_bin ?? c.display_bin
        c.has_predict_order = dto.has_predict_order ?? c.has_predict_order
        c.is_randomized = dto.is_randomized ?? c.is_randomized
        c.display_group_headings = dto.display_group_headings ?? c.display_group_headings
        c.is_blind = dto.is_blind ?? c.is_blind
        c.start_date = dto.start_date ?? c.start_date
        c.created_at = dto.created_at ?? c.created_at
        c.venue_id = dto.venue_id ?? c.venue_id
        c.sort_channel_name = dto.sort_channel_name ?? c.sort_channel_name
        c.location_based_recs = dto.location_based_recs ?? c.location_based_recs
        
        if let img = dto.primary_image {
            c.primary_image = try upsertMedia(from: img, in: ctx)
        }
        if let v = dto.venue {
            c.venue = try upsertVenue(from: v, in: ctx)
        }
        if let vers = dto.versions {
            c.versions = try vers.map { try upsertCollectionVersion(from: $0, collection: c, in: ctx) }
        }
        if let traits = dto.traits {
            c.traits = try traits.map { try upsertCollectionTrait(from: $0, in: ctx) }
        }
        
        return c
    }
    
    // MARK: - CollectionVersion / CollectionGroup / CollectionOrder

    @discardableResult
    nonisolated static func upsertCollectionVersion(
        from dto: CollectionVersionDTO,
        collection: Collection,
        in ctx: ModelContext
    ) throws -> CollectionVersion {
        let v = try fetchOrInsert(CollectionVersion.self, id: dto.id, in: ctx) {
            CollectionVersion(id: dto.id, collection: collection)
        }
        
        // Basic fields
        v.created_at = dto.created_at ?? v.created_at
        v.updated_at = dto.updated_at ?? v.updated_at
        v.name       = dto.name       ?? v.name
        v.order      = dto.order      ?? v.order
        
        // Ensure parent is correct
        if v.collection.id != collection.id {
            v.collection = collection
        }
        
        // Groups (if present on the DTO)
        if let groupDTOs = dto.groups {
            v.groups = try groupDTOs.map { try upsertCollectionGroup(from: $0, version: v, in: ctx) }
        }
        
        return v
    }

    @discardableResult
    nonisolated static func upsertCollectionGroup(
        from dto: CollectionGroupDTO,
        version: CollectionVersion,
        in ctx: ModelContext
    ) throws -> CollectionGroup {
        let g = try fetchOrInsert(CollectionGroup.self, id: dto.id, in: ctx) {
            CollectionGroup(id: dto.id, version: version)
        }

        g.created_at      = dto.created_at      ?? g.created_at
        g.updated_at      = dto.updated_at      ?? g.updated_at
        g.name            = dto.name            ?? g.name
        g.order           = dto.order           ?? g.order
        g.orderings_count = dto.orderings_count ?? g.orderings_count

        if g.version.id != version.id {
            g.version = version
        }

        // NOTE: we don't upsert orders here directly because we need Tags first.
        // The loader can handle that in a second pass once tags/products are in place.
        
        return g
    }

    @discardableResult
    nonisolated static func upsertCollectionOrder(
        from dto: CollectionOrderDTO,
        group: CollectionGroup,
        tag: Tag,
        in ctx: ModelContext
    ) throws -> CollectionOrder {
        let o = try fetchOrInsert(CollectionOrder.self, id: dto.id, in: ctx) {
            // Adjust this initializer to match your actual model init
            CollectionOrder(
                id: dto.id,
                tag_id: tag.id, order: dto.order ?? 0,
                group: group,
                tag: tag
            )
        }
        
        // Timestamps
        o.created_at = dto.created_at ?? o.created_at
        o.updated_at = dto.updated_at ?? o.updated_at
        
        // Order
       o.order = dto.order
        
        // Keep relationships in sync
        if o.group.id != group.id {
            o.group = group
        }
        if o.tag.id != tag.id {
            o.tag = tag
        }
        o.tag_id = tag.id
        
        return o
    }

    
    @discardableResult
    nonisolated static func upsertCollectionTrait(from dto: CollectionTraitDTO, in ctx: ModelContext) throws -> CollectionTrait {
        let t = try fetchOrInsert(CollectionTrait.self, id: dto.id, in: ctx) { CollectionTrait(id: dto.id) }
        t.name = dto.name ?? t.name
        t.order = dto.order ?? t.order
        t.restrict_to_ring_it = dto.restrict_to_ring_it ?? t.restrict_to_ring_it
        
//        if let cref = dto.collection?.id {
//            t.collection = try resolveCollection(id: cref, in: ctx)
//        }
        return t
    }
    
    // MARK: Profile & ProfileStyle
    
    @discardableResult
    nonisolated static func upsertProfile(from dto: ProfileDTO, in ctx: ModelContext) throws -> Profile {
        let p = try fetchOrInsert(Profile.self, id: dto.id, in: ctx) {
            Profile(id: dto.id)
        }

        // Core identity / ownership fields
        p.user_id = dto.user_id
        p.customer_id = dto.customer_id

        // Overall score
        p.score = dto.score

        // Per-category scores (all optionals, 1:1 mapping from DTO)
        p.score_red       = dto.score_red
        p.score_white     = dto.score_white
        p.score_rose      = dto.score_rose
        p.score_sparkling = dto.score_sparkling
        p.score_fortified = dto.score_fortified
        p.score_whiskey   = dto.score_whiskey
        p.score_tequila   = dto.score_tequila
        p.score_vodka     = dto.score_vodka
        p.score_gin       = dto.score_gin
        p.score_rum       = dto.score_rum      // assuming this is your rum score field
        p.score_sake      = dto.score_sake
        p.score_cocktail  = dto.score_cocktail
        p.score_beer      = dto.score_beer     // remember: RTD is combined with beer at analytics layer
        p.score_cheese    = dto.score_cheese

        // Timestamps (keep existing values if DTO doesn’t send them)
        p.created_at = dto.created_at ?? p.created_at
        p.updated_at = dto.updated_at ?? p.updated_at

        // Preference styles
        for pStyle in dto.preference_styles {
            try upsertProfileStyle(from: pStyle, profile: p, in: ctx)
        }
        
        ProfileAnalytics.recomputeAndStoreStats(for: p)

        return p
    }

    
    @discardableResult
    nonisolated static func upsertProfileStyle(from dto: ProfileStyleDTO, profile : Profile, in ctx: ModelContext) throws -> ProfileStyle {
        let ps = try fetchOrInsert(ProfileStyle.self, id: dto.id, in: ctx) { ProfileStyle(id: dto.id, style_id: dto.style_id) }
        ps.conflict = dto.conflict ?? ps.conflict
        ps.order_profile = dto.order_profile ?? ps.order_profile
        ps.order_recommend = dto.order_recommend ?? ps.order_recommend
        ps.rating = dto.rating ?? ps.rating
        ps.strength = dto.strength ?? ps.strength
        ps.style_id = dto.style_id ?? ps.style_id
        ps.recommend = dto.recommend ?? ps.recommend
        ps.refine = dto.refine ?? ps.refine
        ps.keywords = dto.keywords ?? ps.keywords
        ps.created_at = dto.created_at ?? ps.created_at
        ps.updated_at = dto.updated_at ?? ps.updated_at
        ps.profile = profile
        
        if let s = dto.style { ps.style = try upsertStyle(from: s, in: ctx) }
        
        return ps
    }
    
    // MARK: UserCollection
    
    @discardableResult
    nonisolated static func upsertUserCollection(from dto: UserCollectionDTO, in ctx: ModelContext) throws -> UserCollection {
        let uc = try fetchOrInsert(UserCollection.self, id: dto.id, in: ctx) { UserCollection(id: dto.id) }
        uc.relationship_type = dto.relationship_type ?? uc.relationship_type
        uc.collection_id = dto.collection_id ?? uc.collection_id
        uc.created_at = dto.created_at ?? uc.created_at
        uc.updated_at = dto.updated_at ?? uc.updated_at
        
//        if let col = dto.collection {
//            uc.collection = try upsertCollection(from: col, in: ctx)
//        } else if let cid = dto.collection_id {
//            uc.collection = try resolveCollection(id: cid, in: ctx)
//        }
        return uc
    }
    
    // MARK: Food
    
    @discardableResult
    nonisolated static func upsertFood(from dto: FoodDTO, in ctx: ModelContext) throws -> Food {
        let f = try fetchOrInsert(Food.self, id: dto.id, in: ctx) { Food(id: dto.id) }
        f.name = dto.name ?? f.name
        f.keywords = dto.keywords ?? f.keywords
        f.created_at = dto.created_at ?? f.created_at
        f.updated_at = dto.updated_at ?? f.updated_at
        return f
    }
    
    // MARK: - Customer
    
    @discardableResult
    static func upsertCustomer(from dto: CustomerDTO, in ctx: ModelContext) throws -> Customer {
        let c = try fetchOrInsert(Customer.self, id: dto.id, in: ctx) { Customer(id: dto.id) }
        c.created_at = dto.created_at ?? c.created_at
        c.updated_at = dto.updated_at ?? c.updated_at
        c.avatar_url = dto.avatar_url ?? c.avatar_url
        c.merchant_user_email_address   = dto.merchant_user_email_address ?? c.merchant_user_email_address
        c.merchant_user_id              = dto.merchant_user_id ?? c.merchant_user_id
        c.merchant_user_name            = dto.merchant_user_name ?? c.merchant_user_name
        c.merchant_user_display_name    = dto.merchant_user_display_name ?? c.merchant_user_display_name
        c.role                          = dto.role ?? c.role
        return c
    }
    
    // MARK: - Location
    
    @discardableResult
    static func upsertLocation(from dto: LocationDTO, in ctx: ModelContext) throws -> Location {
        let l = try fetchOrInsert(Location.self, id: dto.id, in: ctx) { Location(id: dto.id) }
        l.created_at = dto.created_at ?? l.created_at
        l.updated_at = dto.updated_at ?? l.updated_at
        if let lat = dto.latitude    { l.latitude = lat }
        if let lon = dto.longitude   { l.longitude = lon }
        if let zip = dto.zip_code    { l.zip_code = zip }
        return l
    }
    
    // MARK: - Reservation
    
    @discardableResult
    static func upsertReservation(from dto: ReservationDTO, in ctx: ModelContext) throws -> Reservation {
        let r = try fetchOrInsert(Reservation.self, id: dto.id, in: ctx) { Reservation(id: dto.id) }
        r.created_at     = dto.created_at ?? r.created_at
        r.updated_at     = dto.updated_at ?? r.updated_at
        r.region         = dto.region ?? r.region
        r.date           = dto.date ?? r.date
        r.title          = dto.title ?? r.title
        r.timeString     = dto.timeString ?? r.timeString
        r.imageURLString = dto.imageURLString ?? r.imageURLString
        return r
    }
    
    // MARK: - Style
    
    @discardableResult
    nonisolated static func upsertStyle(from dto: StyleDTO, profile_style: ProfileStyle? = nil, in ctx: ModelContext) throws -> Style {
        let s = try fetchOrInsert(Style.self, id: dto.id, in: ctx) { Style(id: dto.id) }
        s.created_at        = dto.created_at ?? s.created_at
        s.updated_at        = dto.updated_at ?? s.updated_at
        s.desc              = dto.desc
        s.name              = dto.name
        s.type              = dto.type
        s.primary_image_url = dto.primary_image_url
        s.product_category  = dto.product_category
        profile_style?.style = s
        return s
    }
    
    // MARK: - FoodCategory
    
    @discardableResult
    static func upsertFoodCategory(from dto: FoodCategoryDTO, in ctx: ModelContext) throws -> FoodCategory {
        let fc = try fetchOrInsert(FoodCategory.self, id: dto.id, in: ctx) { FoodCategory(id: dto.id) }
        fc.created_at = dto.created_at ?? fc.created_at
        fc.updated_at = dto.updated_at ?? fc.updated_at
        fc.name       = dto.name ?? fc.name
        fc.icon_url   = dto.icon_url ?? fc.icon_url
        return fc
    }
    
    /// Fetch (or create) a Search row by its `text`. Your model has no `id`.
    private static func fetchSearchByText(_ text: String, in ctx: ModelContext) throws -> Search? {
        var fd = FetchDescriptor<Search>(
            predicate: #Predicate<Search> { $0.text == text }
        )
        fd.fetchLimit = 1
        return try ctx.fetch(fd).first
    }
    
    @discardableResult
    static func upsertSearch(from dto: SearchDTO, in ctx: ModelContext) throws -> Search {
        if let existing = try fetchSearchByText(dto.text, in: ctx) {
            if let cnt = dto.count         { existing.count = cnt }
            if let d   = dto.last_searched { existing.last_searched = d }
            return existing
        }
        // Create new
        let new = Search(
            count: dto.count ?? 0,
            last_searched: dto.last_searched ?? Date(),
            text: dto.text
        )
        ctx.insert(new)
        return new
    }
    
    // MARK: - PreferabliUser
    
    // MARK: - Upsert
    
    @discardableResult
    nonisolated static func upsertPreferabliUser(from dto: PreferabliUserDTO, in ctx: ModelContext) throws -> PreferabliUser {
        let u = try fetchOrInsert(PreferabliUser.self, id: dto.id, in: ctx) { PreferabliUser(id: dto.id) }
        
        // Timestamps
        u.created_at            = dto.created_at ?? u.created_at
        u.updated_at            = dto.updated_at ?? u.updated_at
        
        u.country               = dto.country ?? u.country
        u.display_name          = dto.display_name ?? u.display_name
        u.email                 = dto.email ?? u.email
        u.is_team_preferabli    = dto.is_team_preferabli ?? u.is_team_preferabli
        u.fname                 = dto.fname ?? u.fname
        u.lname                 = dto.lname ?? u.lname
        u.claim_code            = dto.claim_code ?? u.claim_code
        u.has_merchant_access   = dto.has_merchant_access ?? u.has_merchant_access
        u.has_kiosks            = dto.has_kiosks ?? u.has_kiosks
        u.zip_code              = dto.zip_code ?? u.zip_code
        u.intercom_hmac         = dto.intercom_hmac ?? u.intercom_hmac
        u.rating_collection_id  = dto.rating_collection_id ?? u.rating_collection_id
        u.provided_feedback_at  = dto.provided_feedback_at ?? u.provided_feedback_at
        u.wishlist_collection_id = dto.wishlist_collection_id ?? u.wishlist_collection_id
        
        if let avatarDTO = dto.avatar {
            let media = try upsertMedia(from: avatarDTO, in: ctx)
            u.avatar = media
        }
        
        return u
    }
}
