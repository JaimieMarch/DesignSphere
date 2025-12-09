// Enums for supported material types for future customization features
// Used to generate procedural materials applied to 3D models
import RealityKit
import SwiftUI

enum MaterialOption: String, CaseIterable, Identifiable, Codable {
    case woodOak = "Oak Wood"
    case woodWalnut = "Walnut Wood"
    case woodMaple = "Maple Wood"
    case metalBrushed = "Brushed Metal"
    case metalChrome = "Chrome"
    case metalBlack = "Black Metal"
    case fabricLinen = "Linen Fabric"
    case fabricVelvet = "Velvet Fabric"
    case leatherBrown = "Brown Leather"
    case leatherBlack = "Black Leather"
    case glass = "Glass"
    case marble = "Marble"
    case concrete = "Concrete"
    case plastic = "Plastic"
    
    var id: String { rawValue }
    
    // Define standardized colors for materials
    var color: Color {
        switch self {
        case .woodOak: return Color(red: 0.76, green: 0.60, blue: 0.42)
        case .woodWalnut: return Color(red: 0.40, green: 0.26, blue: 0.13)
        case .woodMaple: return Color(red: 0.85, green: 0.75, blue: 0.60)
        case .metalBrushed: return Color.gray
        case .metalChrome: return Color(white: 0.9)
        case .metalBlack: return Color(white: 0.15)
        case .fabricLinen: return Color(red: 0.93, green: 0.91, blue: 0.84)
        case .fabricVelvet: return Color(red: 0.20, green: 0.20, blue: 0.40)
        case .leatherBrown: return Color(red: 0.55, green: 0.35, blue: 0.20)
        case .leatherBlack: return Color(white: 0.10)
        case .glass: return Color.white.opacity(0.3)
        case .marble: return Color(white: 0.95)
        case .concrete: return Color(white: 0.60)
        case .plastic: return Color.white
        }
    }
    
    // Constructs SimpleMaterial with roughness and metallic properties set
    // tuned for each material category.
    func createMaterial() -> SimpleMaterial {
        var material = SimpleMaterial()
        
        switch self {
        case .woodOak, .woodWalnut, .woodMaple:
            material.color = .init(tint: UIColor(color))
            material.roughness = 0.7
            material.metallic = 0.0
            
        case .metalBrushed, .metalChrome, .metalBlack:
            material.color = .init(tint: UIColor(color))
            material.metallic = 0.9
            material.roughness = self == .metalChrome ? 0.1 : 0.3
            
        case .fabricLinen, .fabricVelvet:
            material.color = .init(tint: UIColor(color))
            material.roughness = 0.9
            material.metallic = 0.0
            
        case .leatherBrown, .leatherBlack:
            material.color = .init(tint: UIColor(color))
            material.roughness = 0.5
            material.metallic = 0.0
            
        case .glass:
            material.color = .init(tint: UIColor(color))
            material.roughness = 0.0
            material.metallic = 0.1
            
        case .marble:
            material.color = .init(tint: UIColor(color))
            material.roughness = 0.2
            material.metallic = 0.1
            
        case .concrete:
            material.color = .init(tint: UIColor(color))
            material.roughness = 0.8
            material.metallic = 0.0
            
        case .plastic:
            material.color = .init(tint: UIColor(color))
            material.roughness = 0.4
            material.metallic = 0.0
        }
        
        return material
    }
}
