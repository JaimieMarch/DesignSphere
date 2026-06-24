//
//  DesignAdvisor.swift
//  XRShareCollaboration
//
//  On-device, deterministic design recommendations over the catalog — no
//  network, no API, no cost. Works on any `DesignCatalogItem` (a category key
//  plus a finish flag) so it stays decoupled from the catalog's concrete types
//  and is unit-testable with mocks. Category keys mirror ModelCategory.rawValue.
//

import Foundation

/// Anything the advisor can reason about and recommend.
public protocol DesignCatalogItem {
    var advisorID: String { get }
    var categoryKey: String { get }   // "seating", "tables", … (ModelCategory.rawValue)
    var isTextured: Bool { get }
}

public struct DesignAdvisor {
    public init() {}

    /// A room the user can ask the advisor to furnish.
    public enum RoomType: String, CaseIterable, Identifiable, Sendable {
        case livingRoom
        case bedroom
        case office
        case diningRoom

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .livingRoom: return "Living Room"
            case .bedroom: return "Bedroom"
            case .office: return "Home Office"
            case .diningRoom: return "Dining Room"
            }
        }

        public var icon: String {
            switch self {
            case .livingRoom: return "sofa.fill"
            case .bedroom: return "bed.double.fill"
            case .office: return "desktopcomputer"
            case .diningRoom: return "fork.knife"
            }
        }

        /// Ordered category slots that compose the room. Repeats are intentional
        /// (e.g. two dining chairs); slots whose category has no catalog models
        /// are simply skipped.
        var categorySlots: [String] {
            switch self {
            case .livingRoom:
                return ["seating", "tables", "media", "lighting", "decor", "seating"]
            case .bedroom:
                return ["beds", "storage", "tables", "lighting", "decor"]
            case .office:
                return ["tables", "seating", "storage", "lighting", "media"]
            case .diningRoom:
                return ["tables", "seating", "seating", "lighting", "storage"]
            }
        }
    }

    /// Categories that pair well with a given category, best first.
    private static let affinity: [String: [String]] = [
        "seating": ["tables", "lighting", "decor", "media"],
        "tables": ["seating", "lighting", "decor"],
        "media": ["seating", "storage", "lighting"],
        "beds": ["storage", "tables", "lighting", "decor"],
        "storage": ["lighting", "decor", "tables"],
        "lighting": ["seating", "tables", "decor"],
        "decor": ["seating", "tables", "lighting"],
    ]

    // MARK: - Room sets

    /// A coordinated set of models for a room: one per slot, preferring textured
    /// models and never repeating a model.
    public func roomSet<Item: DesignCatalogItem>(for room: RoomType, from catalog: [Item]) -> [Item] {
        var used = Set<String>()
        var result: [Item] = []
        for slot in room.categorySlots {
            let candidates = catalog.filter { $0.categoryKey == slot && !used.contains($0.advisorID) }
            guard let pick = preferredPick(from: candidates) else { continue }
            used.insert(pick.advisorID)
            result.append(pick)
        }
        return result
    }

    // MARK: - Complete the space

    /// Given the categories already placed, suggest complementary models the
    /// scene is missing, ranked by affinity and favouring not-yet-present types.
    public func complements<Item: DesignCatalogItem>(
        placedCategories: [String],
        placedIDs: Set<String>,
        from catalog: [Item],
        limit: Int = 6
    ) -> [Item] {
        let present = Set(placedCategories)

        var scores: [String: Int] = [:]
        for placed in placedCategories {
            for (index, complement) in (Self.affinity[placed] ?? []).enumerated() {
                scores[complement, default: 0] += (4 - min(index, 3))
            }
        }
        guard !scores.isEmpty else { return [] }

        // Boost categories not yet in the room so the suggestions add variety.
        let rankedCategories = scores.keys.sorted {
            let lhs = scores[$0]! + (present.contains($0) ? 0 : 3)
            let rhs = scores[$1]! + (present.contains($1) ? 0 : 3)
            if lhs != rhs { return lhs > rhs }
            return $0 < $1
        }

        var result: [Item] = []
        var used = placedIDs
        for category in rankedCategories {
            let candidates = catalog.filter { $0.categoryKey == category && !used.contains($0.advisorID) }
            if let pick = preferredPick(from: candidates) {
                used.insert(pick.advisorID)
                result.append(pick)
            }
            if result.count >= limit { break }
        }
        return result
    }

    // MARK: - Similar

    /// Same-category alternatives to a model, preferring a matching finish.
    public func similar<Item: DesignCatalogItem>(to item: Item, from catalog: [Item], limit: Int = 6) -> [Item] {
        let sameCategory = catalog.filter { $0.categoryKey == item.categoryKey && $0.advisorID != item.advisorID }
        let ranked = sameCategory.sorted { lhs, rhs in
            let lhsMatch = lhs.isTextured == item.isTextured
            let rhsMatch = rhs.isTextured == item.isTextured
            if lhsMatch != rhsMatch { return lhsMatch }
            return lhs.advisorID < rhs.advisorID
        }
        return Array(ranked.prefix(limit))
    }

    // MARK: - Category picks

    /// Models drawn from the given category keys, preferring textured models —
    /// used when a (natural-language) request names categories rather than a room.
    public func models<Item: DesignCatalogItem>(
        inCategories keys: [String],
        from catalog: [Item],
        maxPerCategory: Int = 2
    ) -> [Item] {
        var used = Set<String>()
        var result: [Item] = []
        for key in keys {
            let candidates = catalog.filter { $0.categoryKey == key && !used.contains($0.advisorID) }
            let textured = candidates.filter { $0.isTextured }
            let tier = (textured.isEmpty ? candidates : textured).shuffled()
            for pick in tier.prefix(maxPerCategory) {
                used.insert(pick.advisorID)
                result.append(pick)
            }
        }
        return result
    }

    // MARK: - Selection

    /// Prefer textured candidates; pick randomly within the preferred tier for
    /// variety across repeated requests.
    private func preferredPick<Item: DesignCatalogItem>(from candidates: [Item]) -> Item? {
        guard !candidates.isEmpty else { return nil }
        let textured = candidates.filter { $0.isTextured }
        let tier = textured.isEmpty ? candidates : textured
        return tier.randomElement()
    }
}
