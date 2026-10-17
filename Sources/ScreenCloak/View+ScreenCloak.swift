//
//  View+ScreenCloak.swift
//  ScreenCloak
//

import SwiftUI

// MARK: - Protect a view

public extension View {

    /// Protects the view and shows a text placeholder while it is hidden.
    ///
    /// With no arguments you get the standard placeholder: an icon, a title, and a message. Change any of them,
    /// or pass `nil` to leave one out.
    ///
    /// ```swift
    /// content.screenProtected()                                          // standard placeholder
    /// content.screenProtected(title: "Private", message: "Hidden while sharing")
    /// content.screenProtected(title: "Private", message: nil, systemImage: nil)
    /// ```
    ///
    /// The text is localised through your app's string catalog. The icon uses the environment tint, so apply
    /// `.tint(...)` above this modifier to colour it. The placeholder covers the whole screen, including the safe areas.
    ///
    /// - Parameters:
    ///   - options: What to protect against. Defaults to `.all`.
    ///   - title: The headline, or `nil` for none.
    ///   - message: The explanation under the title, or `nil` for none.
    ///   - systemImage: The name of an SF Symbol shown above the text, or `nil` for none.
    ///   - screenIdentifier: A name for this screen, passed along in `ScreenshotEvent`.
    ///   - onScreenshot: Called on the main thread when a screenshot is taken while the view is on screen.
    func screenProtected(
        _ options: ProtectionOptions = .all,
        title: LocalizedStringKey? = "Content Protected",
        message: LocalizedStringKey? = "This content is protected from screenshots and screen recording.",
        systemImage: String? = "eye.slash.fill",
        screenIdentifier: String? = nil,
        onScreenshot: ((ScreenshotEvent) -> Void)? = nil
    ) -> some View {
        protected(options, screenIdentifier: screenIdentifier, onScreenshot: onScreenshot) {
            StandardPlaceholder(title: title, message: message, systemImage: systemImage)
        }
        .ignoresSafeArea(edges: .all)
    }

    /// Protects the view and shows your own view while it is hidden.
    ///
    /// ```swift
    /// content.screenProtected {
    ///     VStack {
    ///         Image("logo")
    ///         Text("Back in a moment")
    ///     }
    /// }
    /// ```
    ///
    /// Your view is drawn over a black, full-screen background in white text, and the placeholder covers the
    /// safe areas. To use another background, give your view its own background that fills the screen.
    ///
    /// - Parameters:
    ///   - options: What to protect against. Defaults to `.all`.
    ///   - screenIdentifier: A name for this screen, passed along in `ScreenshotEvent`.
    ///   - onScreenshot: Called on the main thread when a screenshot is taken while the view is on screen.
    ///   - placeholder: The view shown instead of the content while it is hidden.
    func screenProtected<Placeholder: View>(
        _ options: ProtectionOptions = .all,
        screenIdentifier: String? = nil,
        onScreenshot: ((ScreenshotEvent) -> Void)? = nil,
        @ViewBuilder placeholder: () -> Placeholder
    ) -> some View {
        protected(options, screenIdentifier: screenIdentifier, onScreenshot: onScreenshot, placeholder: placeholder)
            .ignoresSafeArea(edges: .all)
    }

    /// The lower-level form of `screenProtected(_:screenIdentifier:onScreenshot:placeholder:)`.
    ///
    /// It does the same, but leaves safe area handling to you, so the placeholder only covers the area the
    /// view itself occupies.
    func protected<Placeholder: View>(
        _ options: ProtectionOptions = .all,
        screenIdentifier: String? = nil,
        onScreenshot: ((ScreenshotEvent) -> Void)? = nil,
        @ViewBuilder placeholder: () -> Placeholder
    ) -> some View {
        ProtectedView(
            options: options,
            screenIdentifier: screenIdentifier,
            onScreenshot: onScreenshot,
            placeholder: {
                // Wrap the placeholder in a container so it fills the area and reads clearly.
                ZStack {
                    Color.black.ignoresSafeArea()
                    placeholder()
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            },
            content: { self }
        )
    }
}

// MARK: - Protect only when needed

public extension View {

    /// Protects the view only when the permission provider does not allow screenshots, with a text placeholder.
    ///
    /// The text parameters work as they do in `screenProtected(_:title:message:systemImage:screenIdentifier:onScreenshot:)`.
    @ViewBuilder
    func screenProtectedIfNeeded(
        _ options: ProtectionOptions = .all,
        permissionProvider: ScreenshotPermissionProvider,
        title: LocalizedStringKey? = "Content Protected",
        message: LocalizedStringKey? = "This content is protected from screenshots and screen recording.",
        systemImage: String? = "eye.slash.fill",
        screenIdentifier: String? = nil,
        onScreenshot: ((ScreenshotEvent) -> Void)? = nil
    ) -> some View {
        if permissionProvider.allowsScreenshots {
            self
        } else {
            self.screenProtected(
                options,
                title: title,
                message: message,
                systemImage: systemImage,
                screenIdentifier: screenIdentifier,
                onScreenshot: onScreenshot
            )
        }
    }

    /// Protects the view only when the permission provider does not allow screenshots, with your own placeholder.
    @ViewBuilder
    func screenProtectedIfNeeded<Placeholder: View>(
        _ options: ProtectionOptions = .all,
        permissionProvider: ScreenshotPermissionProvider,
        screenIdentifier: String? = nil,
        onScreenshot: ((ScreenshotEvent) -> Void)? = nil,
        @ViewBuilder placeholder: () -> Placeholder
    ) -> some View {
        if permissionProvider.allowsScreenshots {
            self
        } else {
            self.screenProtected(
                options,
                screenIdentifier: screenIdentifier,
                onScreenshot: onScreenshot,
                placeholder: placeholder
            )
        }
    }
}

// MARK: - Standard placeholder

/// The standard placeholder: an optional icon, title, and message.
struct StandardPlaceholder: View {
    let title: LocalizedStringKey?
    let message: LocalizedStringKey?
    let systemImage: String?

    var body: some View {
        VStack(spacing: 16) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
            }

            if let title {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            if let message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}
