import RealityKit

public struct SaveOriginalMaterialComponent: Component {
    public var originalMaterials: [Material] = []

    public init(originalMaterials: [Material] = []) {
        self.originalMaterials = originalMaterials
    }
}

extension Entity {
    public var modelComponent: ModelComponent? {
        components[ModelComponent.self]
    }

    public var shaderGraphMaterial: ShaderGraphMaterial? {
        modelComponent?.materials.first as? ShaderGraphMaterial
    }

    public var physicallyBasedMaterial: PhysicallyBasedMaterial? {
        modelComponent?.materials.first as? PhysicallyBasedMaterial
    }

    public func update(
        shaderGraphMaterial oldMaterial: ShaderGraphMaterial,
        _ handler: (inout ShaderGraphMaterial) throws -> Void
    ) rethrows {
        var material = oldMaterial
        try handler(&material)

        if var component = modelComponent {
            component.materials = [material]
            components.set(component)
        }
    }

    public func replaceAndStoreOldMaterials(material: Material, copyPBRInputs: Bool = false) {
        if var modelComponent = modelComponent {
            let count = modelComponent.materials.count

            if components[SaveOriginalMaterialComponent.self] == nil {
                var saveMaterialComponent = SaveOriginalMaterialComponent()
                saveMaterialComponent.originalMaterials = modelComponent.materials
                components.set(saveMaterialComponent)
            }

            var materials: [RealityKit.Material] = []
            for index in 0..<count {
                if copyPBRInputs {
                    if var newMaterial = material as? PhysicallyBasedMaterial,
                       let oldMaterial = modelComponent.materials[index] as? PhysicallyBasedMaterial {
                        var temp = oldMaterial
                        temp.baseColor = newMaterial.baseColor
                        newMaterial = temp
                        materials.append(newMaterial)
                    }
                } else {
                    materials.append(material)
                }
            }

            modelComponent.materials = materials
            components.set(modelComponent)
        }

        children.forEach { child in
            child.replaceAndStoreOldMaterials(material: material)
        }
    }

    public func restoreOriginalMaterials() {
        if var modelComponent = modelComponent,
           let savedMaterials = components[SaveOriginalMaterialComponent.self] {
            for index in 0..<savedMaterials.originalMaterials.count {
                modelComponent.materials[index] = savedMaterials.originalMaterials[index]
            }
            components.set(modelComponent)
            components.remove(SaveOriginalMaterialComponent.self)
        }

        for child in children {
            child.restoreOriginalMaterials()
        }
    }
}
