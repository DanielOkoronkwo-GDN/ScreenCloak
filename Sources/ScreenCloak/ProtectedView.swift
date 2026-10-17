//
//  ProtectedView.swift
//  ScreenCloak
//

import SwiftUI
import Combine
import UIKit

// MARK: - Secure canvas lookup

/// Finds the secure rendering layer that iOS gives a secure text field.
///
/// Content placed inside this layer is left out of screenshots and screen recordings. It is found by
/// looking for a subview whose class name contains "Canvas", which is an internal UIKit detail that
/// could change in a future iOS release. `ScreenCloakTests` includes a test that fails if it does.
enum SecureCanvas {
    static func find(in textField: UITextField) -> UIView? {
        textField.subviews.first(where: {
            String(describing: type(of: $0)).contains("Canvas")
        })
    }
}

// MARK: - Protected View Implementation

struct ProtectedView<Content: View, Placeholder: View>: UIViewRepresentable {
    let options: ProtectionOptions
    let screenIdentifier: String?
    let onScreenshot: ((ScreenshotEvent) -> Void)?
    let placeholder: Placeholder
    let content: Content

    init(
        options: ProtectionOptions,
        screenIdentifier: String? = nil,
        onScreenshot: ((ScreenshotEvent) -> Void)? = nil,
        @ViewBuilder placeholder: () -> Placeholder,
        @ViewBuilder content: () -> Content
    ) {
        self.options = options
        self.screenIdentifier = screenIdentifier
        self.onScreenshot = onScreenshot
        self.placeholder = placeholder()
        self.content = content()
    }

    func makeUIView(context: Context) -> ProtectedContainerView {
        let containerView = ProtectedContainerView()
        context.coordinator.screenIdentifier = screenIdentifier
        context.coordinator.onScreenshot = onScreenshot
        context.coordinator.setup(with: containerView, options: options)
        return containerView
    }

    func updateUIView(_ uiView: ProtectedContainerView, context: Context) {
        context.coordinator.screenIdentifier = screenIdentifier
        context.coordinator.onScreenshot = onScreenshot
        context.coordinator.updateContent(content: content, placeholder: placeholder)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ProtectedContainerView, context: Context) -> CGSize? {
        // Safe Area & Layout Strategy:
        // - Return nil (no size override) to let SwiftUI handle natural sizing
        // - This allows proper safe area handling and ScrollView sizing
        // - Auto Layout constraints (in addSubviewAndFill) respect safe areas
        // - Only override size if we detect NaN/infinity to prevent crashes

        // If we get a valid proposed size, pass it through
        if let width = proposal.width, let height = proposal.height,
           !width.isInfinite, !height.isInfinite,
           !width.isNaN, !height.isNaN {
            return nil
        }

        // Only if we get invalid values (infinity/NaN), return safe defaults
        // This prevents the CALayer NaN crashes
        if let width = proposal.width, let height = proposal.height {
            let safeWidth = (width.isInfinite || width.isNaN) ? UIScreen.main.bounds.width : width
            let safeHeight = (height.isInfinite || height.isNaN) ? UIScreen.main.bounds.height : height

            // Only return explicit size if we detected bad values
            if width.isInfinite || height.isInfinite || width.isNaN || height.isNaN {
                return CGSize(width: safeWidth, height: safeHeight)
            }
        }

        return nil
    }

    static func dismantleUIView(_ uiView: ProtectedContainerView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    // MARK: - Coordinator

    class Coordinator {
        var contentHostingController: UIHostingController<Content>?
        var placeholderHostingController: UIHostingController<Placeholder>?
        var secureTextField: UITextField?
        var secureCanvasView: UIView?
        var containerView: ProtectedContainerView?

        /// Kept current by `makeUIView` and `updateUIView`, so the latest closure is always the one called.
        var screenIdentifier: String?
        var onScreenshot: ((ScreenshotEvent) -> Void)?

        private var cancellables = Set<AnyCancellable>()
        private var isContentHidden = false

        func setup(with containerView: ProtectedContainerView, options: ProtectionOptions) {
            self.containerView = containerView

            // Setup screenshot protection if needed
            if options.contains(.screenshots) {
                setupScreenshotProtection()

                // Detect when screenshot is taken and briefly show placeholder
                NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)
                    .sink { [weak self] _ in
                        self?.handleScreenshotTaken()
                    }
                    .store(in: &cancellables)
            }

            // Setup inactivity protection
            if options.contains(.inactivity) {
                NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
                    .sink { [weak self] _ in
                        self?.setContentHidden(true)
                    }
                    .store(in: &cancellables)

                NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
                    .sink { [weak self] _ in
                        self?.setContentHidden(false)
                    }
                    .store(in: &cancellables)
            }

            // Setup screen sharing protection
            if options.contains(.screenSharing) {
                NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)
                    .sink { [weak self] notification in
                        let isCaptured = (notification.object as? UIScreen)?.isCaptured ?? false
                        self?.setContentHidden(isCaptured)
                    }
                    .store(in: &cancellables)
            }
        }

        func updateContent(content: Content, placeholder: Placeholder) {
            // Update or create content hosting controller FIRST
            if let existingController = contentHostingController {
                existingController.rootView = content
            } else {
                let controller = UIHostingController(rootView: content)
                controller.view.backgroundColor = .clear

                // Don't interfere with layout margins
                controller.view.layoutMargins = .zero
                controller.view.preservesSuperviewLayoutMargins = false

                self.contentHostingController = controller

                if let secureCanvas = secureCanvasView {
                    // Add to secure canvas for screenshot protection
                    secureCanvas.addSubviewAndFill(controller.view)
                } else if let containerView = containerView {
                    // Add directly to container if no screenshot protection
                    containerView.addSubviewAndFill(controller.view)
                }
            }

            // Update or create placeholder hosting controller
            // This goes ON TOP so it shows when we want it to
            if let existingController = placeholderHostingController {
                existingController.rootView = placeholder
                existingController.view.isHidden = !isContentHidden
            } else {
                let controller = UIHostingController(rootView: placeholder)
                controller.view.backgroundColor = .clear // Transparent, placeholder has its own background
                controller.view.isHidden = !isContentHidden // Hidden by default
                controller.view.alpha = 1.0 // Ensure it's fully opaque when visible
                self.placeholderHostingController = controller

                if let containerView = containerView {
                    containerView.addSubviewAndFill(controller.view)
                    // Bring to front so it covers the secure canvas when visible
                    containerView.bringSubviewToFront(controller.view)
                }
            }
        }

        private func setupScreenshotProtection() {
            // Create a secure text field to harvest its secure rendering layer
            let textField = UITextField()
            textField.isSecureTextEntry = true
            textField.isUserInteractionEnabled = false
            textField.backgroundColor = .clear
            self.secureTextField = textField

            // We need to add it to a window's view hierarchy temporarily to access its secure layer
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let containerView = self.containerView,
                      let textField = self.secureTextField else { return }

                // Add text field to container temporarily
                containerView.addSubview(textField)
                textField.frame = containerView.bounds

                // Extract the secure canvas view
                if let canvasView = SecureCanvas.find(in: textField) {
                    self.secureCanvasView = canvasView
                    canvasView.translatesAutoresizingMaskIntoConstraints = false
                    canvasView.backgroundColor = .clear // Transparent so placeholder shows through
                    canvasView.isOpaque = false
                    containerView.addSubview(canvasView)

                    NSLayoutConstraint.activate([
                        canvasView.topAnchor.constraint(equalTo: containerView.topAnchor),
                        canvasView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                        canvasView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                        canvasView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
                    ])

                    // Move existing content to secure canvas if it exists
                    if let contentView = self.contentHostingController?.view {
                        contentView.removeFromSuperview()
                        canvasView.addSubviewAndFill(contentView)
                    }
                }

                // Remove the text field from the view hierarchy
                textField.removeFromSuperview()
            }
        }

        private func setContentHidden(_ hidden: Bool) {
            isContentHidden = hidden

            guard let placeholderView = placeholderHostingController?.view else { return }

            if hidden {
                // Bring to front and show
                containerView?.bringSubviewToFront(placeholderView)
                placeholderView.isHidden = false
            } else {
                // Hide
                placeholderView.isHidden = true
            }
        }

        private func handleScreenshotTaken() {
            // Notify the caller about the screenshot
            let event = ScreenshotEvent(
                timestamp: Date(),
                screenIdentifier: screenIdentifier,
                wasBlocked: true  // Content was protected
            )
            onScreenshot?(event)

            // Briefly show the placeholder to give user feedback
            // The screenshot is already taken at this point (and will be blank due to secure layer)
            // This just provides visual feedback to the user
            guard let placeholderView = placeholderHostingController?.view else { return }

            DispatchQueue.main.async { [weak self] in
                // Bring to front and show placeholder with animation
                self?.containerView?.bringSubviewToFront(placeholderView)

                UIView.animate(withDuration: 0.2) {
                    placeholderView.isHidden = false
                    placeholderView.alpha = 1.0
                }

                // Hide it again after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self = self else { return }

                    // Only hide if content shouldn't be hidden for other reasons
                    if !self.isContentHidden {
                        UIView.animate(withDuration: 0.2) {
                            placeholderView.alpha = 0.0
                        } completion: { _ in
                            placeholderView.isHidden = true
                            placeholderView.alpha = 1.0 // Reset for next time
                        }
                    }
                }
            }
        }

        func cleanup() {
            cancellables.removeAll()
            contentHostingController?.view.removeFromSuperview()
            placeholderHostingController?.view.removeFromSuperview()
            secureCanvasView?.removeFromSuperview()
            secureTextField?.removeFromSuperview()

            contentHostingController = nil
            placeholderHostingController = nil
            secureTextField = nil
            secureCanvasView = nil
            containerView = nil
        }
    }
}

// MARK: - Protected Container View

class ProtectedContainerView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        // Don't interfere with layout - be a transparent passthrough
        insetsLayoutMarginsFromSafeArea = false
        layoutMargins = .zero
        preservesSuperviewLayoutMargins = false
        clipsToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Pass through actual safe area insets so content can properly .ignoresSafeArea()
    // If we return .zero, content has nothing to extend into
}

// MARK: - UIView Extension

private extension UIView {
    func addSubviewAndFill(_ subview: UIView) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subview)
        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: topAnchor),
            subview.leadingAnchor.constraint(equalTo: leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: trailingAnchor),
            subview.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
