import SwiftUI
import UniformTypeIdentifiers

// MARK: - DocumentPickerView

struct DocumentPickerView: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let onDocumentsPicked: ([URL]) -> Void
    let onCancel: () -> Void

    init(
        allowedContentTypes: [UTType] = [.pdf, .png, .jpeg, .image],
        onDocumentsPicked: @escaping ([URL]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.allowedContentTypes = allowedContentTypes
        self.onDocumentsPicked = onDocumentsPicked
        self.onCancel = onCancel
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentsPicked: onDocumentsPicked, onCancel: onCancel)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentsPicked: ([URL]) -> Void
        let onCancel: () -> Void

        init(onDocumentsPicked: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onDocumentsPicked = onDocumentsPicked
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onDocumentsPicked(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
