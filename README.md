# ScreenCloak

Hide sensitive SwiftUI content from screenshots, screen recordings, screen sharing, and the app switcher.

```swift
import ScreenCloak

Text("Account balance: £1,204.50")
    .screenProtected()
```

- Content is left out of screenshots and recordings.
- A placeholder replaces it while the screen is shared or mirrored, and while the app is inactive.
- You can be told when someone takes a screenshot.
- Protection can depend on a permission, such as a user setting or a feature flag.

## Requirements

- iOS 18 or later
- Swift tools 5.9 or later

The unit tests run on the iOS 18.3 and iOS 27 simulators. Older iOS versions have not been tried. The simulator does not take real screenshots, so check the behaviour on a physical device in your own app before relying on it.

## Installation

In Xcode, choose **File ▸ Add Package Dependencies** and enter the repository URL.

Or add it to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/DanielOkoronkwo-GDN/ScreenCloak", from: "0.1.0")
]
```

Then add `ScreenCloak` to your target's dependencies.

## Usage

### Protect a view

```swift
SecretView()
    .screenProtected()
```

### Choose what to protect against

```swift
SecretView().screenProtected([.screenshots, .screenSharing])
```

| Option | Hides the content from |
|--------|------------------------|
| `.screenshots` | Screenshots and recordings. The content is drawn in a layer iOS leaves out of captures. |
| `.screenSharing` | Screen sharing, AirPlay, and mirroring. A placeholder is shown instead. |
| `.inactivity` | The app switcher. A placeholder is shown while the app is not active. |
| `.all` | All of the above. This is the default. |

### Choose what is shown while the content is hidden

There are three routes, all on `screenProtected` (and the same on `screenProtectedIfNeeded`).

**1. The standard placeholder.** An icon, a title, and a message. Use it as it is:

```swift
SecretView().screenProtected()
```

**2. Your own text.** Change the title, the message, or the icon. Pass `nil` to leave one out:

```swift
SecretView().screenProtected(
    title: "Members only",
    message: "This screen is hidden while you share your display.",
    systemImage: "lock.fill"
)

// Title only, no icon or message
SecretView().screenProtected(title: "Private", message: nil, systemImage: nil)
```

The text is localised through your app's string catalog, as any SwiftUI `Text` is.

**3. Your own view.** Anything you like:

```swift
SecretView().screenProtected {
    VStack(spacing: 12) {
        Image("logo")
        Text("Back in a moment")
    }
}
```

Your view is drawn on a black, full-screen background in white text. To use another background, give your view its own background that fills the screen.

The standard placeholder's icon uses the environment tint, so colour it with `.tint(...)` above the modifier:

```swift
SecretView()
    .screenProtected()
    .tint(.orange)
```

All three cover the whole screen, including the safe areas. If you want the placeholder to cover only the area the view occupies, use the lower-level `protected(_:placeholder:)`, which takes a custom view and leaves the safe areas alone.

### Protect only when needed

Conform a type to `ScreenshotPermissionProvider`, and protection is applied only when it returns `false`:

```swift
extension UserSettings: ScreenshotPermissionProvider {
    var allowsScreenshots: Bool { canTakeScreenshots }
}

SecretView()
    .screenProtectedIfNeeded(permissionProvider: settings)
```

### Find out about screenshots

```swift
SecretView()
    .screenProtected(screenIdentifier: "account") { event in
        analytics.log("screenshot", screen: event.screenIdentifier, blocked: event.wasBlocked)
    }
```

The closure runs on the main thread when a screenshot is taken while the view is on screen. iOS tells the app about a screenshot only after it has been taken, so this reports it but cannot stop it. The protected content is already left out of the image.

## How it works

iOS draws the contents of a secure text field in a layer that is left out of screenshots and recordings. ScreenCloak creates a secure text field, takes its internal canvas view, and places your content inside it. Placeholders are shown on top for screen sharing and inactivity, using the notifications iOS sends for those cases.

## Limitations

- **It depends on an internal UIKit detail.** The canvas view is found by looking for a subview whose class name contains "Canvas". A future iOS release could change this. The test suite includes a test that fails if it does, so run the tests when a new iOS arrives and check on a device.
- **It is not a security guarantee.** It cannot stop someone photographing the screen with another device, and it does not protect data that is already in your app's memory or on disk.
- **Screenshot events arrive after the fact.** See above.
- **It is a privacy aid, not DRM.** Treat it as one layer in a wider approach to sensitive data.

## Development

The tests need an iOS simulator, because they use UIKit:

```bash
xcodebuild test -scheme ScreenCloak \
  -destination 'platform=iOS Simulator,name=<any installed iOS 18+ simulator>'
```

`xcodebuild -showdestinations -scheme ScreenCloak` lists what is available.

## License

MIT. See [LICENSE](LICENSE).
