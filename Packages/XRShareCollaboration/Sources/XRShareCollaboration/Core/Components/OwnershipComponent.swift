//
//  OwnershipComponent.swift
//  XR Share
//
// To track which participant owns or is manipulating an entity

import Foundation
import RealityKit

/// A component that tracks ownership of an entity in shareplay sessions with multiple users 
struct OwnershipComponent: Component {
    
    let participantID: UUID
    let timestamp: Date
    
    init(participantID: UUID) {
        self.participantID = participantID
        self.timestamp = Date()
    }
}
