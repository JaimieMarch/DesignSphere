//
//  XRLog.swift
//  XRShareCollaboration
//
//  Tiny gate for verbose diagnostic logging (placement, normalization, …) so
//  that chatter stays out of the console during normal use — even in Debug
//  builds. Flip `XRLog.isVerbose = true` (from the debugger or a test) to
//  surface it.
//

import Foundation

public enum XRLog {
    /// Off by default so normal runs have a quiet console. Not synchronized —
    /// it's a development toggle, not production state.
    nonisolated(unsafe) public static var isVerbose = false

    static func verbose(_ message: @autoclosure () -> String) {
        if isVerbose { print(message()) }
    }
}
