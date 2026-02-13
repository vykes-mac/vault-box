import SwiftUI
import PDFKit

// MARK: - DocumentDetailView

struct DocumentDetailView: View {
    let item: VaultItem
    let vaultService: VaultService

    @Environment(\.dismiss) private var dismiss

    @State private var tempFileURL: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vaultBackground.ignoresSafeArea()

                if isLoading {
                    ProgressView("Decrypting document...")
                        .foregroundStyle(Color.vaultTextSecondary)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(Color.vaultDestructive)
                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(Color.vaultTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if let url = tempFileURL {
                    if item.originalFilename.lowercased().hasSuffix(".pdf") {
                        PDFViewRepresentable(url: url)
                    } else if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                        // Image-based document (scanned ID, passport photo, etc.)
                        ScrollView([.horizontal, .vertical]) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.vaultTextSecondary)
                            Text(item.originalFilename)
                                .font(.headline)
                            Text("Preview not available for this file type.")
                                .font(.body)
                                .foregroundStyle(Color.vaultTextSecondary)
                        }
                    }
                }
            }
            .navigationTitle(item.originalFilename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if tempFileURL != nil {
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = tempFileURL {
                    ActivityView(activityItems: [url])
                }
            }
        }
        .task {
            await loadDocument()
        }
        .onDisappear {
            cleanupTempFile()
        }
    }

    // MARK: - Actions

    private func loadDocument() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let url = try await vaultService.decryptDocumentURL(for: item)
            tempFileURL = url
        } catch {
            errorMessage = "This document couldn't be opened. It may be corrupted."
        }
    }

    private func cleanupTempFile() {
        guard let url = tempFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        tempFileURL = nil
    }
}

// MARK: - PDFViewRepresentable

struct PDFViewRepresentable: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
