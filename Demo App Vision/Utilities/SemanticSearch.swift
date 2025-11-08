import Foundation
import NaturalLanguage

/// Semantic search helper using on-device sentence embeddings.
/// if embeddings are unavailable, callers can fall back to existing logic.
@MainActor
final class SemanticSearch: ObservableObject {

    private let embedding: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: .english)
    @Published private(set) var vectors: [String: [Double]] = [:]

    /// Build or rebuild the index from catalog item names.
    func index(names: [String]) {
        guard let embedding = embedding else {
            vectors = [:]
            return
        }

        var out: [String: [Double]] = [:]
        out.reserveCapacity(names.count)

        for name in names {
            if let v = embedding.vector(for: name) {
                out[name] = v
            }
        }

        vectors = out
    }

    /// Returns names ranked by similarity to `query`.
    /// If embeddings are not available or fail, returns [].
    func search(_ query: String, within names: [String], topK: Int) -> [String] {
        guard
            let embedding = embedding,
            let qv = embedding.vector(for: query),
            !names.isEmpty
        else {
            return []
        }

        let scored: [(String, Double)] = names.compactMap { name in
            let v = vectors[name] ?? embedding.vector(for: name)
            guard let vec = v else { return nil }
            return (name, cosine(vec, qv))
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(min(topK, scored.count))
            .map { $0.0 }
    }

    private func cosine(_ a: [Double], _ b: [Double]) -> Double {
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }

        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<count {
            let x = a[i], y = b[i]
            dot += x * y
            na += x * x
            nb += y * y
        }
        let denom = sqrt(na) * sqrt(nb)
        return denom > 0 ? dot / denom : 0
    }
}
