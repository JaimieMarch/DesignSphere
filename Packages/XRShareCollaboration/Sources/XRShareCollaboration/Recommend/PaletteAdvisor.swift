//
//  PaletteAdvisor.swift
//  XRShareCollaboration
//
//  Curated, designer-friendly colour palettes for finishing the "Customizable"
//  (untextured) models. UI-agnostic (plain RGB components, 0...1) so the package
//  stays free of SwiftUI/UIKit; the app maps these to materials.
//

import Foundation

public struct PaletteColor: Sendable, Hashable, Identifiable {
    public let name: String
    public let red: Double
    public let green: Double
    public let blue: Double

    public var id: String { "\(name)-\(red)-\(green)-\(blue)" }

    public init(_ name: String, _ red: Double, _ green: Double, _ blue: Double) {
        self.name = name
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct DesignPalette: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let colors: [PaletteColor]
}

public enum PaletteAdvisor {
    public static let palettes: [DesignPalette] = [
        DesignPalette(id: "warm-neutrals", name: "Warm Neutrals", colors: [
            PaletteColor("Cream", 0.96, 0.93, 0.86),
            PaletteColor("Beige", 0.87, 0.80, 0.69),
            PaletteColor("Taupe", 0.66, 0.58, 0.49),
            PaletteColor("Warm Gray", 0.50, 0.46, 0.42),
            PaletteColor("Terracotta", 0.78, 0.45, 0.34),
        ]),
        DesignPalette(id: "scandinavian", name: "Scandinavian", colors: [
            PaletteColor("Off White", 0.96, 0.96, 0.94),
            PaletteColor("Light Gray", 0.84, 0.85, 0.86),
            PaletteColor("Pale Blue", 0.74, 0.82, 0.86),
            PaletteColor("Blond Wood", 0.85, 0.73, 0.55),
            PaletteColor("Soft Black", 0.18, 0.18, 0.20),
        ]),
        DesignPalette(id: "forest", name: "Forest", colors: [
            PaletteColor("Sage", 0.71, 0.76, 0.65),
            PaletteColor("Olive", 0.50, 0.53, 0.36),
            PaletteColor("Moss", 0.36, 0.45, 0.31),
            PaletteColor("Deep Green", 0.18, 0.30, 0.24),
            PaletteColor("Bark", 0.40, 0.31, 0.24),
        ]),
        DesignPalette(id: "coastal", name: "Coastal", colors: [
            PaletteColor("White", 0.98, 0.98, 0.97),
            PaletteColor("Sand", 0.90, 0.84, 0.72),
            PaletteColor("Seafoam", 0.69, 0.84, 0.80),
            PaletteColor("Sky", 0.55, 0.72, 0.84),
            PaletteColor("Navy", 0.16, 0.25, 0.40),
        ]),
        DesignPalette(id: "bold-accent", name: "Bold Accent", colors: [
            PaletteColor("Charcoal", 0.20, 0.21, 0.24),
            PaletteColor("White", 0.97, 0.97, 0.97),
            PaletteColor("Mustard", 0.85, 0.65, 0.20),
            PaletteColor("Teal", 0.16, 0.55, 0.56),
            PaletteColor("Coral", 0.90, 0.45, 0.40),
        ]),
        DesignPalette(id: "monochrome", name: "Monochrome", colors: [
            PaletteColor("White", 0.97, 0.97, 0.97),
            PaletteColor("Light Gray", 0.78, 0.78, 0.78),
            PaletteColor("Mid Gray", 0.55, 0.55, 0.55),
            PaletteColor("Dark Gray", 0.32, 0.32, 0.32),
            PaletteColor("Black", 0.12, 0.12, 0.12),
        ]),
    ]
}
