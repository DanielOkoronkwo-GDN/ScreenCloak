//
//  ScreenCloakTests.swift
//  ScreenCloakTests
//

import Testing
import SwiftUI
import UIKit
@testable import ScreenCloak

// MARK: - Helpers

/// Hosts a SwiftUI view in a real, visible window, so UIKit lays it out as it would on screen.
@MainActor
private func host<V: View>(_ view: V) -> UIWindow {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = UIHostingController(rootView: view)
    window.makeKeyAndVisible()
    return window
}

/// Waits for UIKit work that is scheduled for a later run loop turn, such as the secure layer set-up.
@MainActor
private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

private extension UIView {
    func descendants<T: UIView>(ofType type: T.Type) -> [T] {
        subviews.flatMap { subview -> [T] in
            (subview as? T).map { [$0] + subview.descendants(ofType: type) } ?? subview.descendants(ofType: type)
        }
    }

    var isSecureCanvas: Bool { String(describing: Swift.type(of: self)).contains("Canvas") }
}

/// How tall a view wants to be when it is given a phone-width column. An empty view measures zero.
@MainActor
private func measuredHeight<V: View>(of view: V) -> CGFloat {
    UIHostingController(rootView: view)
        .sizeThatFits(in: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude))
        .height
}

/// Records that a SwiftUI view appeared on screen.
private final class AppearanceProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func markAppeared() { lock.lock(); value = true; lock.unlock() }
    var appeared: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

private struct StubPermission: ScreenshotPermissionProvider {
    let allowsScreenshots: Bool
}

/// Counts events delivered from a closure that may be called from any context.
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ScreenshotEvent] = []

    func record(_ event: ScreenshotEvent) { lock.lock(); storage.append(event); lock.unlock() }
    var events: [ScreenshotEvent] { lock.lock(); defer { lock.unlock() }; return storage }
}

// MARK: - Options

@Suite("ProtectionOptions")
struct ProtectionOptionsTests {

    @Test("Raw values never change, since callers may store them", arguments: [
        (ProtectionOptions.screenshots, 0x01),
        (.screenSharing, 0x02),
        (.inactivity, 0x04),
    ])
    func rawValues(option: ProtectionOptions, expected: Int) {
        #expect(option.rawValue == expected)
    }

    @Test("all contains every option")
    func allContainsEverything() {
        #expect(ProtectionOptions.all.contains(.screenshots))
        #expect(ProtectionOptions.all.contains(.screenSharing))
        #expect(ProtectionOptions.all.contains(.inactivity))
        #expect(ProtectionOptions.all.rawValue == 0x07)
    }

    @Test("Options combine and stay separate")
    func combining() {
        let options: ProtectionOptions = [.screenshots, .screenSharing]

        #expect(options.contains(.screenshots))
        #expect(options.contains(.screenSharing))
        #expect(!options.contains(.inactivity))
    }

    @Test("Removing one option leaves the rest")
    func removing() {
        var options = ProtectionOptions.all
        options.remove(.inactivity)

        #expect(options == [.screenshots, .screenSharing])
    }
}

// MARK: - Events

@Suite("ScreenshotEvent")
struct ScreenshotEventTests {

    @Test("Defaults to now, with no screen identifier")
    func defaults() {
        let before = Date()
        let event = ScreenshotEvent(wasBlocked: true)

        #expect(event.screenIdentifier == nil)
        #expect(event.wasBlocked)
        #expect(event.timestamp >= before)
        #expect(event.timestamp <= Date())
    }

    @Test("Keeps the values it is given")
    func keepsValues() {
        let when = Date(timeIntervalSince1970: 1_000)

        let event = ScreenshotEvent(timestamp: when, screenIdentifier: "feed", wasBlocked: false)

        #expect(event.timestamp == when)
        #expect(event.screenIdentifier == "feed")
        #expect(!event.wasBlocked)
    }
}

// MARK: - iOS canary

@Suite("iOS secure layer")
@MainActor
struct SecureLayerCanaryTests {

    /// If this fails after an iOS update, the protection no longer works. The library finds the secure layer by
    /// looking for a "Canvas" subview of a secure text field, and iOS has stopped providing one.
    @Test("A secure text field still exposes a canvas view on this iOS version")
    func secureTextFieldExposesCanvas() async {
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()

        let field = UITextField(frame: controller.view.bounds)
        field.isSecureTextEntry = true
        controller.view.addSubview(field)

        let found = await waitUntil { SecureCanvas.find(in: field) != nil }

        #expect(found, "No Canvas subview found. ScreenCloak cannot hide content on this iOS version.")
    }
}

// MARK: - Protected view

@Suite("Protected view", .serialized)
@MainActor
struct ProtectedViewTests {

    @Test("Protected content is moved into the secure canvas")
    func contentLivesInSecureCanvas() async throws {
        let window = host(Text("Secret").screenProtected())

        let ready = await waitUntil {
            window.descendants(ofType: ProtectedContainerView.self).first?
                .subviews.contains(where: { $0.isSecureCanvas && !$0.subviews.isEmpty }) == true
        }

        #expect(ready, "The content hosting view never reached the secure canvas")
    }

    @Test("Without the screenshot option no secure canvas is created")
    func noCanvasWithoutScreenshotOption() async throws {
        let window = host(Text("Secret").screenProtected([.inactivity]))

        let container = try #require(await waitUntil { !window.descendants(ofType: ProtectedContainerView.self).isEmpty }
            ? window.descendants(ofType: ProtectedContainerView.self).first : nil)
        try? await Task.sleep(for: .milliseconds(200))

        let hasCanvas = container.subviews.contains { $0.isSecureCanvas }
        #expect(!hasCanvas)
    }

    @Test("A screenshot reports an event with the screen identifier")
    func screenshotReportsEvent() async {
        let log = EventLog()
        let window = host(Text("Secret").screenProtected(screenIdentifier: "home", onScreenshot: log.record))
        _ = await waitUntil { !window.descendants(ofType: ProtectedContainerView.self).isEmpty }

        NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)

        #expect(log.events.count == 1)
        #expect(log.events.first?.screenIdentifier == "home")
        #expect(log.events.first?.wasBlocked == true)
    }

    @Test("Screenshots are ignored when the screenshot option is off")
    func screenshotIgnoredWithoutOption() async {
        let log = EventLog()
        let window = host(Text("Secret").screenProtected([.inactivity], onScreenshot: log.record))
        _ = await waitUntil { !window.descendants(ofType: ProtectedContainerView.self).isEmpty }

        NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)

        #expect(log.events.isEmpty)
    }

    @Test("The placeholder shows while the app is inactive and hides when it returns")
    func placeholderFollowsActivity() async throws {
        let window = host(Text("Secret").screenProtected([.inactivity]))
        let container = try #require(await waitUntil { !window.descendants(ofType: ProtectedContainerView.self).isEmpty }
            ? window.descendants(ofType: ProtectedContainerView.self).first : nil)
        _ = await waitUntil { container.subviews.count >= 2 }

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        #expect(container.subviews.last?.isHidden == false, "Placeholder should cover the content while inactive")

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        #expect(container.subviews.last?.isHidden == true, "Placeholder should hide again when active")
    }
}

// MARK: - Permission gating

@Suite("screenProtectedIfNeeded", .serialized)
@MainActor
struct PermissionGatingTests {

    @Test("Content is protected when screenshots are not allowed")
    func protectedWhenNotAllowed() async {
        let window = host(Text("x").screenProtectedIfNeeded(permissionProvider: StubPermission(allowsScreenshots: false)))

        let protected = await waitUntil { !window.descendants(ofType: ProtectedContainerView.self).isEmpty }

        #expect(protected)
    }

    @Test("Content is left alone when screenshots are allowed")
    func unprotectedWhenAllowed() async {
        let window = host(Text("x").screenProtectedIfNeeded(permissionProvider: StubPermission(allowsScreenshots: true)))
        try? await Task.sleep(for: .milliseconds(200))

        #expect(window.descendants(ofType: ProtectedContainerView.self).isEmpty)
    }
}

// MARK: - Placeholder customisation

@Suite("Standard placeholder parts")
@MainActor
struct StandardPlaceholderTests {

    private func height(title: LocalizedStringKey?, message: LocalizedStringKey?, systemImage: String?) -> CGFloat {
        measuredHeight(of: StandardPlaceholder(title: title, message: message, systemImage: systemImage))
    }

    @Test("Each part adds to the placeholder, so each can be switched on and off")
    func partsAreIndependent() {
        let nothing = height(title: nil, message: nil, systemImage: nil)
        let titleOnly = height(title: "Private", message: nil, systemImage: nil)
        let titleAndMessage = height(title: "Private", message: "Back in a moment", systemImage: nil)
        let everything = height(title: "Private", message: "Back in a moment", systemImage: "lock.fill")

        #expect(nothing == 0)
        #expect(titleOnly > nothing)
        #expect(titleAndMessage > titleOnly)
        #expect(everything > titleAndMessage)
    }

    @Test("The icon on its own, and the message on its own, are each shown")
    func partsShowOnTheirOwn() {
        #expect(height(title: nil, message: nil, systemImage: "lock.fill") > 0)
        #expect(height(title: nil, message: "Back in a moment", systemImage: nil) > 0)
    }

    @Test("Longer text takes more room, so the text passed in is what is laid out")
    func textIsUsed() {
        let short = height(title: nil, message: "Short", systemImage: nil)
        let long = height(
            title: nil,
            message: "A much longer message that has to wrap onto several lines when it is shown in a narrow column on a phone",
            systemImage: nil
        )

        #expect(long > short)
    }
}

@Suite("Placeholder customisation", .serialized)
@MainActor
struct PlaceholderCustomisationTests {

    @Test("A custom placeholder view is the one that appears when the content is hidden")
    func customViewAppears() async throws {
        let probe = AppearanceProbe()
        let view = Text("Secret").screenProtected([.inactivity]) {
            Color.clear.onAppear { probe.markAppeared() }
        }
        let window = host(view)
        _ = await waitUntil { !window.descendants(ofType: ProtectedContainerView.self).isEmpty }

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        let appeared = await waitUntil { probe.appeared }

        #expect(appeared, "The custom placeholder never appeared")
    }

    @Test("The permission-based custom view form also uses the custom placeholder")
    func permissionCustomViewAppears() async {
        let probe = AppearanceProbe()
        let view = Text("Secret").screenProtectedIfNeeded([.inactivity], permissionProvider: StubPermission(allowsScreenshots: false)) {
            Color.clear.onAppear { probe.markAppeared() }
        }
        let window = host(view)
        _ = await waitUntil { !window.descendants(ofType: ProtectedContainerView.self).isEmpty }

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        let appeared = await waitUntil { probe.appeared }

        #expect(appeared)
    }

    @Test("Custom text still protects the content")
    func customTextProtects() async {
        let window = host(Text("Secret").screenProtected(title: "Private", message: nil, systemImage: nil))

        let protected = await waitUntil { !window.descendants(ofType: ProtectedContainerView.self).isEmpty }

        #expect(protected)
    }

    @Test("Every call style resolves without ambiguity")
    func callStylesCompile() {
        let log = EventLog()
        let allowed = StubPermission(allowsScreenshots: true)

        _ = Text("x").screenProtected()
        _ = Text("x").screenProtected(.screenshots)
        _ = Text("x").screenProtected(title: "T", message: "M", systemImage: "lock")
        _ = Text("x").screenProtected(screenIdentifier: "id", onScreenshot: log.record)
        _ = Text("x").screenProtected(screenIdentifier: "id") { event in log.record(event) }
        _ = Text("x").screenProtected { Text("Custom") }
        _ = Text("x").screenProtected(.all, screenIdentifier: "id") { Text("Custom") }
        _ = Text("x").protected(.all) { Text("Custom") }
        _ = Text("x").screenProtectedIfNeeded(permissionProvider: allowed)
        _ = Text("x").screenProtectedIfNeeded(permissionProvider: allowed, title: "T")
        _ = Text("x").screenProtectedIfNeeded(permissionProvider: allowed) { Text("Custom") }
    }
}
