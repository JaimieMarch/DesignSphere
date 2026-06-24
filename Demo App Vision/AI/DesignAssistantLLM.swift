//
//  DesignAssistantLLM.swift
//  DesignSphere
//
//  Optional natural-language layer over DesignAdvisor, powered by Apple's
//  on-device Foundation Models (visionOS 26). Free, private, no API key — but
//  only available on Apple-Intelligence-capable hardware, so it's gated behind
//  an availability check and degrades to the assistant's quick actions when
//  unavailable (e.g. in the simulator).
//

import Foundation
import XRShareCollaboration

#if canImport(FoundationModels)
import FoundationModels
#endif

@available(visionOS 26.0, *)
@MainActor
enum DesignAssistantLLM {

    /// Whether on-device generation is usable right now.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    struct Interpretation {
        var room: DesignAdvisor.RoomType?
        var categoryKeys: [String]
    }

    /// Maps a free-text request ("a cozy minimalist reading nook") to a room
    /// and/or furniture categories the advisor can act on. Returns nil when the
    /// on-device model is unavailable or fails.
    static func interpret(_ request: String) async -> Interpretation? {
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        do {
            let session = LanguageModelSession(instructions: """
            You help furnish a room from a furniture catalog. From the user's request, \
            choose an optional room type and the furniture categories that fit.
            Room types: livingRoom, bedroom, office, diningRoom. Use an empty string if none applies.
            Categories: seating, tables, lighting, storage, decor, media, beds.
            """)
            let reply = try await session.respond(to: request, generating: GeneratedDesignRequest.self)
            let content = reply.content
            let validCategories = Set(["seating", "tables", "lighting", "storage", "decor", "media", "beds"])
            return Interpretation(
                room: DesignAdvisor.RoomType(rawValue: content.room),
                categoryKeys: content.categories.map { $0.lowercased() }.filter(validCategories.contains)
            )
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}

#if canImport(FoundationModels)
@available(visionOS 26.0, *)
@Generable
struct GeneratedDesignRequest {
    @Guide(description: "Room type the user described: one of livingRoom, bedroom, office, diningRoom, or an empty string if none.")
    var room: String

    @Guide(description: "Furniture categories that fit the request, from: seating, tables, lighting, storage, decor, media, beds.")
    var categories: [String]
}
#endif
