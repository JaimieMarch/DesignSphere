//
//  Utilities.swift
//  XR Anatomy
//
//  Shared utilities and helpers used across the app
//


import Foundation
import SwiftUI
import UIKit

// MARK: - Alert Item

/// Present basic alertas via SwiftUI
struct AlertItem: Identifiable {
    
    let id = UUID()
    let title: String
    let message: String
    
    init(title: String, message: String) {
           self.title = title
           self.message = message
       }

}

// MARK: - Matrix Extensions

import simd

extension simd_float4x4 {
    
    // Extract the position (translation) from the matrix's fourth column
    var position: SIMD3<Float> {
        let t = self.columns.3
        return SIMD3<Float>(t.x, t.y, t.z)
    }

    // Converts a simd_float 4x4 matrix  to a Float array
    func toArray() -> [Float] {
        
        var array = [Float](repeating: 0, count: 16)
        
        // Column-major order for consistency
        array[0] = columns.0.x
        array[1] = columns.0.y
        array[2] = columns.0.z
        array[3] = columns.0.w
        
        array[4] = columns.1.x
        array[5] = columns.1.y
        array[6] = columns.1.z
        array[7] = columns.1.w
        
        array[8] = columns.2.x
        array[9] = columns.2.y
        array[10] = columns.2.z
        array[11] = columns.2.w
        
        array[12] = columns.3.x
        array[13] = columns.3.y
        array[14] = columns.3.z
        array[15] = columns.3.w
        
        return array
    }

    // Creates a simd_float4x4 matrix from a [Float] array
    static func fromArray(_ array: [Float]) -> simd_float4x4 {
        guard array.count >= 16 else {
            print("Warning: Array is too small for matrix conversion. Using identity matrix.")
            return matrix_identity_float4x4
        }
        
        // Column-major order for consistency
        let column0 = SIMD4<Float>(array[0], array[1], array[2], array[3])
        let column1 = SIMD4<Float>(array[4], array[5], array[6], array[7])
        let column2 = SIMD4<Float>(array[8], array[9], array[10], array[11])
        let column3 = SIMD4<Float>(array[12], array[13], array[14], array[15])
        
        return simd_float4x4(column0, column1, column2, column3)
}
}


/// Helper function to check if two matrices are approximately equal
func simd_almost_equal_elements(_ m1: simd_float4x4, _ m2: simd_float4x4, _ epsilon: Float) -> Bool {
    let a1 = m1.toArray()
    let a2 = m2.toArray()
    
    guard a1.count == a2.count else { return false }
    
    for i in 0..<a1.count {
        if abs(a1[i] - a2[i]) > epsilon {
            return false
        }
    }
    
    return true
}


