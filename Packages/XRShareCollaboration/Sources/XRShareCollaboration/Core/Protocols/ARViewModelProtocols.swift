//
//  ARViewModelProtocols.swift
//  XR Share
//
// Types for AR View Model functionality

import Foundation
import RealityKit

#if os(iOS)
import ARKit
#endif

// MARK: - Shared Types

/// User roles in the application
enum UserRole: String, Codable {
    case host = "host"
    case viewer = "viewer"
    case localSession = "local"
}

/// Represents a discovered session
struct Session: Identifiable, Hashable {
    let sessionID: String
    let sessionName: String
    let participantID: String
    var id: String { sessionID }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(sessionID)
        hasher.combine(participantID)
    }
    
    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.participantID == rhs.participantID
    }
}

