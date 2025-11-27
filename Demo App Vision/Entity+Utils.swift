//
// Credit to: https://github.com/gonchar/GoncharKit/blob/main/Sources/GoncharKit/utils/Entity%2BUtils.swift
// 

import RealityKit
import UIKit


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
  
  public func update(shaderGraphMaterial oldMaterial: ShaderGraphMaterial,
              _ handler: (inout ShaderGraphMaterial) throws -> Void) rethrows {
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

            var mats: [RealityKit.Material] = []
            for i in 0..<count {
   
                if copyPBRInputs {
                    if var newMaterial = material as? PhysicallyBasedMaterial,
                       let oldMaterial = modelComponent.materials[i] as? PhysicallyBasedMaterial {

            
                        var temp = oldMaterial
                        temp.baseColor = newMaterial.baseColor
                        newMaterial = temp



                        mats.append(newMaterial)
                    }
                } else {
                    mats.append(material)
                }
            }

            modelComponent.materials = mats
            components.set(modelComponent)
        }

        children.forEach { child in
            child.replaceAndStoreOldMaterials(material: material)
        }
    }
  
  public func restoreOriginalMaterials() {
    if var modelComponent = modelComponent {
      if let savedMats = components[SaveOriginalMaterialComponent.self] {
        for i in 0 ..< savedMats.originalMaterials.count {
          modelComponent.materials[i] = savedMats.originalMaterials[i]
        }
        components.set(modelComponent)
        components.remove(SaveOriginalMaterialComponent.self)
      }
    }
    
    for child in children {
      child.restoreOriginalMaterials()
    }
  }
  

  
}
