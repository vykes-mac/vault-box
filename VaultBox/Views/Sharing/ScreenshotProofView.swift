import SwiftUI

// MARK: - ScreenshotProofView

/// A container view that prevents its content from appearing in screenshots and screen recordings.
///
/// Uses the secure text entry technique: `UITextField.isSecureTextEntry = true` causes iOS
/// to create an internal subview (`_UITextLayoutCanvasView`) whose layer is marked as
/// protected from screen capture. Content hosted inside that subview inherits the protection.
/// This technique is used by banking apps, Netflix, and other security-sensitive apps.
/// Stable since iOS 13.
struct ScreenshotProofView<Content: View>: UIViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> ScreenshotProofUIView {
        let view = ScreenshotProofUIView()

        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.hostingController = hostingController

        view.addSecureContent(hostingController.view)

        return view
    }

    func updateUIView(_ uiView: ScreenshotProofUIView, context: Context) {
        context.coordinator.hostingController?.rootView = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var hostingController: UIHostingController<Content>?
    }
}

// MARK: - ScreenshotProofUIView

/// The UIKit view that hosts content inside a secure `UITextField` subview.
final class ScreenshotProofUIView: UIView {
    private let secureField = UITextField()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSecureField()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSecureField() {
        secureField.isSecureTextEntry = true
        secureField.isUserInteractionEnabled = false
        secureField.translatesAutoresizingMaskIntoConstraints = false

        // Add the text field to the view hierarchy so its internal subviews are created.
        // Do NOT set alpha to 0 — that can prevent the secure container from being created.
        addSubview(secureField)
        NSLayoutConstraint.activate([
            secureField.topAnchor.constraint(equalTo: topAnchor),
            secureField.bottomAnchor.constraint(equalTo: bottomAnchor),
            secureField.leadingAnchor.constraint(equalTo: leadingAnchor),
            secureField.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Force layout so the internal secure subview hierarchy is created
        secureField.layoutIfNeeded()
    }

    func addSecureContent(_ contentView: UIView) {
        // When isSecureTextEntry is true, UITextField creates an internal subview
        // (e.g. _UITextLayoutCanvasView) whose layer is flagged as secure. Content
        // added as a subview of this container is excluded from screenshots and
        // screen recordings by iOS.
        guard let secureContainer = secureField.subviews.first else {
            // Fallback: if internal structure has changed, add directly to self
            addSubview(contentView)
            contentView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                contentView.topAnchor.constraint(equalTo: topAnchor),
                contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
                contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
            return
        }

        // Enable interaction on the secure container so touches reach the content
        secureContainer.isUserInteractionEnabled = true
        secureContainer.addSubview(contentView)

        // Constrain the content to fill this view (not the secure container,
        // since the container may have its own sizing from the text field)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}
