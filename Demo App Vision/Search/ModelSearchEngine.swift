// Intent-aware search over the model catalog.
//
// Plain substring matching can only find models whose name literally contains
// the query, so "sofa" never surfaces "couch" and "seating" finds nothing.
// This engine understands the *idea* behind a query by matching it against a
// curated synonym vocabulary anchored on each model's category, so any seating
// term ("sofa", "couch", "recliner", "seating") recalls every seating item.
//
// Design note: an on-device NLEmbedding word-similarity tier was evaluated and
// rejected — furniture vocabulary is largely out-of-vocabulary (ottoman~stool,
// dresser~cabinet, mirror~tv all return 0.0) and the surviving signal is noisy
// (rug~sofa outscores bench~chair), so it added false positives rather than
// recall. A curated vocabulary is more reliable for a small, fixed catalog.
// The scoring is intentionally factored so a trained model (e.g. a CreateML
// text classifier, once query→selection data exists) could re-rank later.

import Foundation
import XRShareCollaboration

struct ModelSearchEngine {
    typealias Descriptor = CollaborativeSessionController.ModelDescriptor
    typealias Category = CollaborativeSessionController.ModelCategory

    /// A query token must match at least one of a model's terms this strongly
    /// for the model to be included. Exact term hits score 1.0, prefixes 0.85,
    /// substrings 0.7, so 0.55 admits partial typing ("tabl") but not noise.
    private let inclusionThreshold: Double = 0.55

    /// Concept words per category, beyond each model's own name. These make
    /// intent queries ("seating", "lighting") and cross-item recall ("sofa" →
    /// "chair") work deterministically for the catalog.
    private static let categoryTags: [Category: [String]] = [
        .seating: ["seating", "seat", "chair", "armchair", "sofa", "couch", "settee",
                   "loveseat", "sectional", "stool", "bench", "ottoman", "recliner", "lounge", "pouf"],
        .tables: ["table", "desk", "surface", "dining", "coffee", "nightstand",
                  "sidetable", "console", "workbench"],
        .lighting: ["lighting", "light", "lamp", "chandelier", "sconce", "pendant", "fixture"],
        .storage: ["storage", "closet", "cabinet", "shelf", "shelving", "bookshelf",
                   "bookcase", "wardrobe", "dresser", "drawer", "sideboard", "cupboard", "armoire"],
        .beds: ["bed", "mattress", "bedroom", "bunk", "headboard", "crib"],
        .media: ["media", "tv", "television", "monitor", "screen", "entertainment", "display"],
        .decor: ["decor", "decoration", "vase", "plant", "planter", "art", "artwork",
                 "ornament", "accent", "mirror", "painting", "rug", "sculpture"],
        .unknown: [],
        .all: []
    ]

    /// Returns the matching descriptors ordered by descending relevance.
    /// An empty query returns the input unchanged (preserving the caller's order).
    func search(_ query: String, in descriptors: [Descriptor]) -> [Descriptor] {
        let queryTokens = tokenize(query)
        guard !queryTokens.isEmpty else { return descriptors }

        return descriptors
            .map { ($0, score(queryTokens, for: $0)) }
            .filter { $0.1.best >= inclusionThreshold }
            // Rank by how completely the query is covered (average), then by the
            // strongest single hit, then alphabetically for stable ordering.
            .sorted {
                if $0.1.average != $1.1.average { return $0.1.average > $1.1.average }
                if $0.1.best != $1.1.best { return $0.1.best > $1.1.best }
                return $0.0.name.localizedCompare($1.0.name) == .orderedAscending
            }
            .map { $0.0 }
    }

    // MARK: - Scoring

    /// `best` = strongest single query-token hit (gates inclusion);
    /// `average` = mean best-hit across all query tokens (rewards covering the
    /// whole query, so "coffee table" ranks the coffee table above other tables).
    private func score(_ queryTokens: [String], for descriptor: Descriptor) -> (best: Double, average: Double) {
        let documentTokens = documentTokens(for: descriptor)
        guard !documentTokens.isEmpty else { return (0, 0) }

        let perToken = queryTokens.map { queryToken in
            documentTokens.map { similarity(queryToken, $0) }.max() ?? 0
        }
        let best = perToken.max() ?? 0
        let average = perToken.reduce(0, +) / Double(perToken.count)
        return (best, average)
    }

    private func similarity(_ query: String, _ term: String) -> Double {
        if query == term { return 1.0 }
        // Fuzzy matching only between tokens of length >= 3, so short tokens like
        // "tv" or the "in" in "65 In TV" match exactly but never as substrings
        // (otherwise "seat-in-g" or "din-in-g" would spuriously recall the TV).
        guard query.count >= 3, term.count >= 3 else { return 0.0 }
        if term.hasPrefix(query) || query.hasPrefix(term) { return 0.85 }
        if term.contains(query) || query.contains(term) { return 0.7 }
        return 0.0
    }

    // MARK: - Vocabulary

    private func documentTokens(for descriptor: Descriptor) -> [String] {
        var tokens = Set(tokenize(descriptor.name))
        tokens.insert(descriptor.category.rawValue)
        tokens.formUnion(tokenize(descriptor.category.label))
        tokens.formUnion(Self.categoryTags[descriptor.category] ?? [])
        return Array(tokens)
    }

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
