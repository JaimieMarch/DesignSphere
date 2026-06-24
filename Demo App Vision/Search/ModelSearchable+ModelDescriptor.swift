// Bridges the catalog's model descriptor to the package's decoupled search
// engine. The conformance lives app-side because ModelDescriptor's enclosing
// CollaborativeSessionController is visionOS 26+ only, while the package itself
// floors at visionOS 1.0; the app's deployment target is 26.0 so it is always
// available here. `@retroactive` acknowledges the deliberate cross-module
// conformance.

import XRShareCollaboration

extension CollaborativeSessionController.ModelDescriptor: @retroactive ModelSearchable {
    public var searchName: String { name }
    public var searchCategoryKey: String { category.rawValue }
}

extension CollaborativeSessionController.ModelDescriptor: @retroactive DesignCatalogItem {
    public var advisorID: String { id }
    public var categoryKey: String { category.rawValue }
    public var isTextured: Bool { type.hasBakedMaterials }
}
