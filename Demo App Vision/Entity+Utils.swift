//
// Adapted from GoncharKit by Sergiy Gonchar
// https://github.com/gonchar/GoncharKit
//
// MIT License
//
// Copyright (c) Sergiy Gonchar
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
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
