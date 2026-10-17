//
//  ScreenshotEvent.swift
//  ScreenCloak
//

import Foundation

/// Decides whether the current user or context may take screenshots.
///
/// Conform your own type (a user model, a feature flag store) and pass it to
/// `screenProtectedIfNeeded(_:permissionProvider:)`. Protection is applied only when
/// `allowsScreenshots` is `false`.
public protocol ScreenshotPermissionProvider {
    /// Whether the current context allows screenshots.
    var allowsScreenshots: Bool { get }
}

/// Describes a screenshot that was taken while protected content was on screen.
public struct ScreenshotEvent: Sendable {
    /// When the screenshot was taken.
    public let timestamp: Date
    /// The identifier you gave the protected view, if any.
    public let screenIdentifier: String?
    /// Whether the content was protected when the screenshot was taken.
    public let wasBlocked: Bool

    public init(timestamp: Date = Date(), screenIdentifier: String? = nil, wasBlocked: Bool) {
        self.timestamp = timestamp
        self.screenIdentifier = screenIdentifier
        self.wasBlocked = wasBlocked
    }
}
