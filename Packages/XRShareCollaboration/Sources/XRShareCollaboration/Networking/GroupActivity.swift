//
//  XRShareActivity.swift
//  XR Share
//
//  Configuring GroupAcitivty for Group Activities
//

import Foundation
import GroupActivities
import UIKit
import SwiftUI
import CoreTransferable

public struct DemoActivity: GroupActivity, Transferable, Sendable {
    public static let activityIdentifier = "com.Demo.DemoActivity"
    
    public init() {}
    
    public var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = "Demo App Session"
        metadata.subtitle = "Collaborative 3D Models"
        metadata.previewImage = UIImage(named: "AppIcon")?.cgImage
        metadata.type = .generic
        return metadata
    }
}
