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
                let variant = Variant(id: generateRandomLongId(), year: Variant.CURRENT_VARIANT_YEAR, product: product)
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
        let v: Variant
        if let temp = product.getVariantWithYear(year: dto.year) {
            v = temp
        } else {
            v = try fetchOrInsert(Variant.self, id: dto.id, in: ctx) {
                Variant(id: dto.id, year: dto.year, product: product)
            }
        }
        
        // ✅ Re-assert required fields
        v.id = dto.id
        v.year = dto.year
        if v.product.id != product.id { v.product = product }
        
        v.created_at = dto.created_at ?? v.created_at
        v.updated_at = dto.updated_at ?? v.updated_at
        v.num_dollar_signs = dto.num_dollar_signs ?? v.num_dollar_signs
        v.price = dto.price ?? v.price
        v.recommendable = dto.recommendable ?? v.recommendable
        
        if let imgDTO = dto.primary_image {
            let media = try upsertMedia(from: imgDTO, in: ctx)
            if v.primary_image !== media { v.primary_image = media }
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
        } else if t.tag_type == .COLLECTION, Storage.isCellarCollectionID(t.collection_id) {
            let currentDate = product.cachedCellar?.created_at ?? .distantPast
            if newDate >= currentDate {
                product.cachedCellar = t
            }
        }
        
        return t
    }
    
    // MARK: Media
    
    @discardableResult
    nonisolated static func upsertMedia(from dto: MediaDTO, in ctx: ModelContext) throws -> Media {
        let m = try fetchOrInsert(Media.self, id: dto.id, in: ctx) { Media(id: dto.id) }
        m.id = dto.id
        m.path = dto.path ?? m.path
        m.created_at = dto.created_at ?? m.created_at
        m.updated_at = dto.updated_at ?? m.updated_at
        m.type = dto.type ?? m.type
        return m
    }
    
    @discardableResult
    nonisolated static func upsertExperience(from dto: ExperienceDTO, venue: Venue, in ctx: ModelContext) throws -> Experience {
        
        let e = try fetchOrInsert(Experience.self, id: dto.id, in: ctx) {
            Experience(id: dto.id, venue: venue)
        }
        
        // Timestamps
        e.created_at = dto.created_at ?? e.created_at
        e.updated_at = dto.updated_at ?? e.updated_at
        
        // Fields
        e.name = dto.name ?? e.name
        e.desc = dto.description ?? e.desc
        e.primary_inventory_id = dto.primary_inventory_id ?? e.primary_inventory_id
        
        e.reservations_provider = dto.reservations_provider ?? e.reservations_provider
        e.booking_link = dto.booking_link ?? e.booking_link
        e.discount_code = dto.discount_code ?? e.discount_code
        
        // Images (replace list if present)
        if let imgs = dto.images {
            e.images = try imgs.map { try upsertMedia(from: $0, in: ctx) }
        }
        
        return e
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
        c.desc = dto.description ?? c.desc
        c.end_date = dto.end_date ?? c.end_date
        c.updated_at = dto.updated_at ?? c.updated_at
        c.auto_wili = dto.auto_wili ?? c.auto_wili
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
        
        if let img = dto.primary_image {
            c.primary_image = try upsertMedia(from: img, in: ctx)
        } else {
            c.primary_image = nil
        }
        
        if let v = dto.venue {
            c.venue = try upsertVenue(from: v, in: ctx)
        }
        if let vers = dto.versions {
            c.versions = try vers.map { try upsertCollectionVersion(from: $0, collection: c, in: ctx) }
        }
        //        if let traits = dto.traits {
        //            c.traits = try traits.map { try upsertCollectionTrait(from: $0, in: ctx) }
        //        }
        
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
        let collection = try upsertCollection(from: dto.collection, in: ctx)
        let uc = try fetchOrInsert(UserCollection.self, id: dto.id, in: ctx) { UserCollection(id: dto.id, collection_id: dto.collection_id, collection: collection) }
        uc.relationship_type = dto.relationship_type ?? uc.relationship_type
        uc.created_at = dto.created_at ?? uc.created_at
        uc.updated_at = dto.updated_at ?? uc.updated_at
        
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
    nonisolated static func upsertCustomer(from dto: CustomerDTO, in ctx: ModelContext) throws -> Customer {
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
    nonisolated static func upsertLocation(from dto: LocationDTO, in ctx: ModelContext) throws -> Location {
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
    nonisolated static func upsertReservation(from dto: ReservationDTO, in ctx: ModelContext) throws -> Reservation {
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
        let s = try fetchOrInsert(Style.self, id: dto.id, in: ctx) { Style(id: dto.id, type: dto.type) }
        s.created_at        = dto.created_at ?? s.created_at
        s.updated_at        = dto.updated_at ?? s.updated_at
        s.desc              = dto.description
        s.name              = dto.name
        s.type              = dto.type
        s.primary_image_url = dto.primary_image_url
        s.product_category  = dto.product_category
        profile_style?.style = s
        
        s.locations.removeAll()
        
        for locationDTO in dto.locations {
            let location = try upsertLocation(from: locationDTO, in: ctx)
            s.locations.append(location)
        }
        
        
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
        u.avatar_background_color_hex                 = dto.avatar_background_color_hex ?? u.avatar_background_color_hex
        u.avatar_text_color_hex                 = dto.avatar_text_color_hex ?? u.avatar_text_color_hex
        
        if let avatarDTO = dto.avatar {
            let media = try upsertMedia(from: avatarDTO, in: ctx)
            u.avatar = media
        } else {
            u.avatar = nil
        }
        
        return u
    }
    
    // MARK: - Channel
    
    @discardableResult
    nonisolated static func upsertChannel(from dto: ChannelDTO, in ctx: ModelContext) throws -> Channel {
        let c = try fetchOrInsert(Channel.self, id: dto.id, in: ctx) { Channel(id: dto.id) }
        
        // Core fields
        c.account_id = dto.account_id ?? c.account_id
        c.name = dto.name ?? c.name
        c.description_text = dto.description ?? c.description_text
        c.order = dto.order ?? c.order
        c.archived = dto.archived ?? c.archived
        c.published = dto.published ?? c.published
        
        // Display defaults
        c.default_display_vintages = dto.default_display_vintages ?? c.default_display_vintages
        c.default_display_variants = dto.default_display_variants ?? c.default_display_variants
        c.default_display_variant_details = dto.display_variant_details ?? c.default_display_variant_details
        c.default_display_price = dto.default_display_price ?? c.default_display_price
        c.default_display_quantity = dto.default_display_quantity ?? c.default_display_quantity
        c.default_display_bin = dto.default_display_bin ?? c.default_display_bin
        c.default_downweight_previous_recs_duration = dto.default_downweight_previous_recs_duration ?? c.default_downweight_previous_recs_duration
        
        // Download flags
        c.has_download_pdf = dto.has_download_pdf ?? c.has_download_pdf
        c.has_download_csv = dto.has_download_csv ?? c.has_download_csv
        c.has_download_xlsx = dto.has_download_xlsx ?? c.has_download_xlsx
        
        // Channel classification
        c.is_retailer = dto.is_retailer ?? c.is_retailer
        c.is_producer = dto.is_producer ?? c.is_producer
        c.is_restaurant = dto.is_restaurant ?? c.is_restaurant
        c.is_hospitality = dto.is_hospitality ?? c.is_hospitality
        c.is_event = dto.is_event ?? c.is_event
        c.is_verified = dto.is_verified ?? c.is_verified
        
        // Defaults
        c.default_timezone = dto.default_timezone ?? c.default_timezone
        c.default_currency = dto.default_currency ?? c.default_currency
        c.default_badge_method = dto.default_badge_method ?? c.default_badge_method
        
        // Cutoffs
        c.num_dollar_signs_cutoff_1 = dto.num_dollar_signs_cutoff_1 ?? c.num_dollar_signs_cutoff_1
        c.num_dollar_signs_cutoff_2 = dto.num_dollar_signs_cutoff_2 ?? c.num_dollar_signs_cutoff_2
        c.num_dollar_signs_cutoff_3 = dto.num_dollar_signs_cutoff_3 ?? c.num_dollar_signs_cutoff_3
        c.num_dollar_signs_cutoff_4 = dto.num_dollar_signs_cutoff_4 ?? c.num_dollar_signs_cutoff_4
        c.num_dollar_signs_cutoff_5 = dto.num_dollar_signs_cutoff_5 ?? c.num_dollar_signs_cutoff_5
        
        // FX
        c.currency_exchange_multiplier_from_foreign_to_usd =
        dto.currency_exchange_multiplier_from_foreign_to_usd ?? c.currency_exchange_multiplier_from_foreign_to_usd
        
        // Optional IDs
        c.featured_collection_id = dto.featured_collection_id ?? c.featured_collection_id
        c.primary_inventory_id = dto.primary_inventory_id ?? c.primary_inventory_id
        c.primary_questionnaire_id = dto.primary_questionnaire_id ?? c.primary_questionnaire_id
        c.default_curation_batch_id = dto.default_curation_batch_id ?? c.default_curation_batch_id
        c.default_curation_questions_batch_id = dto.default_curation_questions_batch_id ?? c.default_curation_questions_batch_id
        c.max_number_of_venues = dto.max_number_of_venues ?? c.max_number_of_venues
        
        // Timestamps
        c.created_at = dto.created_at ?? c.created_at
        c.updated_at = dto.updated_at ?? c.updated_at
        
        // Primary image
        if let imgDTO = dto.primary_image {
            let media = try upsertMedia(from: imgDTO, in: ctx)
            if c.primary_image !== media {
                c.primary_image = media
            }
        }
        
        // Images
        if let imgDTOs = dto.images {
            c.images = try imgDTOs.map { try upsertMedia(from: $0, in: ctx) }
        }
        
        // Join rows: channel_venues (preserve per-edge flags)
        if let joinDTOs = dto.channel_venues {
            c.channel_venues = try joinDTOs.map { j in
                let cv = try fetchOrInsert(ChannelVenue.self, id: j.id, in: ctx) { ChannelVenue(id: j.id) }
                
                cv.is_primary = j.is_primary ?? cv.is_primary
                cv.archived = j.archived ?? cv.archived
                
                if cv.channel?.id != c.id {
                    cv.channel = c
                }
                
                if let vDTO = j.venue {
                    let v = try upsertVenue(from: vDTO, in: ctx)
                    if cv.venue?.id != v.id {
                        cv.venue = v
                    }
                }
                
                return cv
            }
        }
        
        return c
    }
    
    /// API is the source of truth:
    /// - Upserts the entire market forest
    /// - Deletes any Market (any depth) not present in dto forest
    @discardableResult
    nonisolated static func upsertMarketsSourceOfTruth(
        from rootDTOs: [MarketDTO],
        in ctx: ModelContext
    ) throws -> [Market] {
        
        // 1) Collect all market IDs in the incoming forest
        var keepMarketIDs = Set<Int>()
        keepMarketIDs.reserveCapacity(rootDTOs.count * 2)
        
        func collect(_ dto: MarketDTO) {
            keepMarketIDs.insert(dto.id)
            for child in dto.submarkets { collect(child) }
        }
        for dto in rootDTOs { collect(dto) }
        
        // 2) Delete any local Markets not in keep set
        try deleteMarketsNotInSet(keepMarketIDs, in: ctx)
        
        // 3) Upsert the forest (root parent = nil)
        var roots: [Market] = []
        roots.reserveCapacity(rootDTOs.count)
        
        for dto in rootDTOs {
            let m = try upsertMarketTreeNodeSourceOfTruth(from: dto, parent: nil, in: ctx)
            roots.append(m)
        }
        
        return roots
    }
    
    nonisolated private static func deleteMarketsNotInSet(
        _ keep: Set<Int>,
        in ctx: ModelContext
    ) throws {
        // Fetch all markets (you can optimize later with propertiesToFetch if needed)
        let all = try ctx.fetch(FetchDescriptor<Market>())
        
        for m in all where !keep.contains(m.id) {
            ctx.delete(m) // cascades to submarkets + traits because of deleteRule
        }
    }
    
    @discardableResult
    nonisolated private static func upsertMarketTreeNodeSourceOfTruth(
        from dto: MarketDTO,
        parent: Market?,
        in ctx: ModelContext
    ) throws -> Market {
        
        // Fetch-or-insert by unique ID
        let market = try fetchOrInsert(Market.self, id: dto.id, in: ctx) { Market(id: dto.id) }
        
        // Fields
        market.name = dto.name ?? market.name
        market.desc = dto.description ?? market.desc
        market.image_url = dto.image_url ?? market.image_url
        market.order = dto.order ?? market.order
        market.country_code = dto.country_code ?? market.country_code
        market.latitude = dto.latitude ?? market.latitude
        market.longitude = dto.longitude ?? market.longitude
        market.top_level = dto.top_level ?? market.top_level
        market.created_at = dto.created_at ?? market.created_at
        market.updated_at = dto.updated_at ?? market.updated_at
        
        // Parent
        if market.parent?.id != parent?.id {
            market.parent = parent
        }
        
        // ✅ Traits: source of truth per market (upsert + delete missing)
        try upsertMarketTraitsSourceOfTruth(from: dto.traits, for: market, in: ctx)
        
        // ✅ Children: recurse, then replace list (source of truth)
        var newChildren: [Market] = []
        newChildren.reserveCapacity(dto.submarkets.count)
        
        for childDTO in dto.submarkets {
            let child = try upsertMarketTreeNodeSourceOfTruth(from: childDTO, parent: market, in: ctx)
            newChildren.append(child)
        }
        
        // Replace children list (keeps ordering from API)
        if !sameIDs(market.submarkets, newChildren) {
            market.submarkets = newChildren
        }
        
        return market
    }
    
    nonisolated private static func sameIDs(_ a: [Market], _ b: [Market]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) where x.id != y.id { return false }
        return true
    }
    
    /// Source of truth:
    /// - Upsert all traits in DTO
    /// - Delete any local MarketTrait linked to this market that isn't in DTO
    nonisolated private static func upsertMarketTraitsSourceOfTruth(
        from traitDTOs: [MarketTraitDTO],
        for market: Market,
        in ctx: ModelContext
    ) throws {
        
        let keepTraitIDs = Set(traitDTOs.map { $0.id })
        
        // 1) Delete missing traits for this market
        // Safer than global delete because trait IDs are assumed unique, but linkage matters most.
        if !market.traits.isEmpty {
            for existing in market.traits where !keepTraitIDs.contains(existing.id) {
                ctx.delete(existing)
            }
        }
        
        // 2) Upsert / build new ordered list
        var newTraits: [MarketTrait] = []
        newTraits.reserveCapacity(traitDTOs.count)
        
        for tDTO in traitDTOs {
            let t = try fetchOrInsert(MarketTrait.self, id: tDTO.id, in: ctx) { MarketTrait(id: tDTO.id) }
            
            t.type = tDTO.type ?? t.type
            t.name = tDTO.name ?? t.name
            t.order = tDTO.order ?? t.order
            t.icon_url = tDTO.icon_url ?? t.icon_url
            t.created_at = tDTO.created_at ?? t.created_at
            t.updated_at = tDTO.updated_at ?? t.updated_at
            
            // Maintain relationship + denormalized market_id
            if t.market?.id != market.id {
                t.market = market
            }
            if t.market_id != market.id {
                t.market_id = market.id
            }
            
            newTraits.append(t)
        }
        
        // 3) Replace market.traits to match API ordering
        // (This also ensures SwiftData relationship is correct even if a trait existed but wasn’t linked.)
        if !sameTraitIDs(market.traits, newTraits) {
            market.traits = newTraits
        }
    }
    
    nonisolated private static func sameTraitIDs(_ a: [MarketTrait], _ b: [MarketTrait]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) where x.id != y.id { return false }
        return true
    }
}

extension Storage {

    public nonisolated static func saveCellarCollectionIDs(_ cellarIds: [Int]) {
        let set = Set(cellarIds)
        CellarIDCacheStore.shared.set(set)

        Storage.getKeyStore().set(Array(set), forKey: cellarIDsKey)
    }

    public nonisolated static func loadCellarCollectionIDSetCached() -> Set<Int> {
        if !CellarIDCacheStore.shared.isEmpty() {
            return CellarIDCacheStore.shared.get()
        }

        let arr = Storage.getKeyStore().array(forKey: cellarIDsKey) as? [Int] ?? []
        let set = Set(arr)
        CellarIDCacheStore.shared.set(set)
        return set
    }

    public nonisolated static func isCellarCollectionID(_ id: Int) -> Bool {
        if CellarIDCacheStore.shared.contains(id) { return true }
        return loadCellarCollectionIDSetCached().contains(id)
    }
}

private let cellarIDsKey = "cellar_collection_ids_v1"

private final class CellarIDCacheStore: @unchecked Sendable {
    static let shared = CellarIDCacheStore()

    private var set: Set<Int> = []
    private let lock = NSLock()

    func get() -> Set<Int> {
        lock.lock(); defer { lock.unlock() }
        return set
    }

    func set(_ new: Set<Int>) {
        lock.lock(); defer { lock.unlock() }
        set = new
    }

    func contains(_ id: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return set.contains(id)
    }

    func isEmpty() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return set.isEmpty
    }
}
