# Changelog

## 0.1.0 (unreleased)

First version, extracted from an app.

- `screenProtected` and `screenProtectedIfNeeded(_:permissionProvider:)` view modifiers, each with three ways to choose the placeholder: the standard one, custom text (title, message, and icon, any of which can be left out), or a custom view.
- `protected(_:placeholder:)`, a lower-level form of the custom view route that leaves safe area handling to you.
- `ProtectionOptions`: `.screenshots`, `.screenSharing`, `.inactivity`, `.all`.
- `ScreenshotPermissionProvider` for permission-based protection.
- Screenshot events through an `onScreenshot` closure on each modifier, with an optional `screenIdentifier`. This replaces the global handler the original code used.
- The default placeholder's icon uses the environment tint instead of an app-specific colour.
- Tests for the options, events, permission gating, and the protected view, plus a canary that fails if iOS stops providing the secure layer the library relies on.
