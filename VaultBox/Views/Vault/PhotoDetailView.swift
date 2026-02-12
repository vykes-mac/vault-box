import SwiftUI
import Photos
import AVKit

// MARK: - PhotoDetailView

struct PhotoDetailView: View {
    let items: [VaultItem]
    let initialIndex: Int
    let vaultService: VaultService

    @Environment(\.dismiss) private var dismiss
    @Environment(AppPrivacyShield.self) private var privacyShield

    @State private var currentIndex: Int
    @State private var showBars = true
    @State private var showInfoPanel = false
    @State private var showShareSheet = false
    @State private var showDeleteConfirm = false
    @State private var decryptedImages: [UUID: UIImage] = [:]
    @State private var shareImage: UIImage?
    @State private var showVideoPlayer = false

    init(items: [VaultItem], initialIndex: Int, vaultService: VaultService) {
        self.items = items
        self.initialIndex = initialIndex
        self.vaultService = vaultService
        _currentIndex = State(initialValue: initialIndex)
    }

    private var currentItem: VaultItem {
        items[currentIndex]
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Paged viewer
            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Group {
                        if item.type == .video {
                            VideoThumbnailPageView(
                                image: decryptedImages[item.id],
                                onSingleTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showBars.toggle()
                                    }
                                },
                                onPlayTap: { showVideoPlayer = true }
                            )
                        } else {
                            PhotoPageView(
                                image: decryptedImages[item.id],
                                onSingleTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showBars.toggle()
                                    }
                                }
                            )
                        }
                    }
                    .tag(index)
                    .task {
                        await loadThumbnailOrImage(for: item)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Overlay bars
            if showBars {
                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)
            }

            if privacyShield.isVisible {
                Color.black
                    .ignoresSafeArea()
                    .overlay {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .zIndex(10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBar(hidden: !showBars)
        .sheet(isPresented: $showInfoPanel) {
            infoPanelSheet
                .presentationDetents([.medium])
                .presentationBackground(Color.vaultBackground)
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ActivityView(activityItems: [image])
            }
        }
        .fullScreenCover(isPresented: $showVideoPlayer) {
            VideoPlayerView(item: currentItem, vaultService: vaultService)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            closeForPrivacy()
        }
        .confirmationDialog(
            "Delete Item?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteCurrentItem()
            }
        } message: {
            Text("This item will be permanently deleted from your vault.")
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 20) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
            }

            Spacer()

            Button {
                Task { await vaultService.toggleFavorite(currentItem) }
            } label: {
                Image(systemName: currentItem.isFavorite ? "heart.fill" : "heart")
                    .font(.title3)
            }

            Button {
                shareCurrentItem()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
            }

            moreMenu
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - More Menu

    private var moreMenu: some View {
        Menu {
            Button {
                // Move to Album — will be wired in F12
            } label: {
                Label("Move to Album", systemImage: "folder")
            }

            Button {
                copyCurrentItem()
            } label: {
                Label("Copy Photo", systemImage: "doc.on.doc")
            }

            Button {
                exportToCameraRoll()
            } label: {
                Label("Export to Camera Roll", systemImage: "square.and.arrow.down")
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Text(currentItem.originalFilename)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Button { showInfoPanel = true } label: {
                Image(systemName: "info.circle")
                    .font(.body)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Info Panel

    private var infoPanelSheet: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Filename", value: currentItem.originalFilename)
                    LabeledContent("Date", value: currentItem.createdAt.formatted(date: .long, time: .shortened))
                    if let w = currentItem.pixelWidth, let h = currentItem.pixelHeight {
                        LabeledContent("Dimensions", value: "\(w) × \(h)")
                    }
                    LabeledContent("File Size", value: formatFileSize(currentItem.fileSize))
                    LabeledContent("Type", value: currentItem.type.rawValue.capitalized)
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showInfoPanel = false }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadThumbnailOrImage(for item: VaultItem) async {
        guard decryptedImages[item.id] == nil else { return }
        if item.type == .video {
            // For videos, show the decrypted thumbnail
            guard let image = try? await vaultService.decryptThumbnail(for: item) else { return }
            decryptedImages[item.id] = image
        } else {
            guard let image = try? await vaultService.decryptFullImage(for: item) else { return }
            decryptedImages[item.id] = image
        }
    }

    private func shareCurrentItem() {
        Task {
            guard let image = try? await vaultService.decryptFullImage(for: currentItem) else { return }
            shareImage = image
            showShareSheet = true
        }
    }

    private func copyCurrentItem() {
        Task {
            guard let image = try? await vaultService.decryptFullImage(for: currentItem) else { return }
            UIPasteboard.general.image = image
        }
    }

    private func exportToCameraRoll() {
        Task {
            guard let image = try? await vaultService.decryptFullImage(for: currentItem) else { return }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
    }

    private func deleteCurrentItem() {
        let item = currentItem
        Haptics.deleteConfirmed()
        Task {
            try? await vaultService.deleteItems([item])
            dismiss()
        }
    }

    private func closeForPrivacy() {
        showVideoPlayer = false
        dismiss()
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Photo Page View

private struct PhotoPageView: View {
    let image: UIImage?
    let onSingleTap: () -> Void

    var body: some View {
        if let image {
            ZoomableImageView(
                image: image,
                maxZoom: Constants.maxZoomScale,
                doubleTapZoom: Constants.doubleTapZoomScale,
                onSingleTap: onSingleTap
            )
        } else {
            ProgressView()
                .tint(.white)
                .onTapGesture(perform: onSingleTap)
        }
    }
}

// MARK: - Video Thumbnail Page View

private struct VideoThumbnailPageView: View {
    let image: UIImage?
    let onSingleTap: () -> Void
    let onPlayTap: () -> Void

    var body: some View {
        ZStack {
            // Background tap area for bar toggle
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onSingleTap)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .allowsHitTesting(false)
            } else {
                ProgressView()
                    .tint(.white)
                    .allowsHitTesting(false)
            }

            // Play button overlay
            Button(action: onPlayTap) {
                Circle()
                    .fill(.black.opacity(0.5))
                    .frame(width: 70, height: 70)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .offset(x: 3)
                    )
            }
        }
    }
}

// MARK: - ZoomableImageView (UIKit wrapper)

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let maxZoom: CGFloat
    let doubleTapZoom: CGFloat
    let onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ZoomScrollView {
        let scrollView = ZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = maxZoom
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.setImage(image)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap)
        )
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: ZoomScrollView, context: Context) {
        context.coordinator.parent = self
        if scrollView.imageView.image !== image {
            scrollView.setImage(image)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableImageView

        init(parent: ZoomableImageView) {
            self.parent = parent
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomScrollView)?.centerContent()
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? ZoomScrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let point = gesture.location(in: scrollView.imageView)
                let scale = parent.doubleTapZoom
                let size = CGSize(
                    width: scrollView.bounds.width / scale,
                    height: scrollView.bounds.height / scale
                )
                let origin = CGPoint(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2
                )
                scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }

        @objc func handleSingleTap() {
            parent.onSingleTap()
        }
    }
}

// MARK: - ZoomScrollView

final class ZoomScrollView: UIScrollView {
    let imageView = UIImageView()
    private var currentImageSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage) {
        imageView.image = image
        currentImageSize = image.size
        zoomScale = minimumZoomScale
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard currentImageSize.width > 0, bounds.width > 0, bounds.height > 0 else { return }

        if zoomScale <= minimumZoomScale + 0.01 {
            let scale = min(bounds.width / currentImageSize.width, bounds.height / currentImageSize.height)
            let fittedSize = CGSize(
                width: currentImageSize.width * scale,
                height: currentImageSize.height * scale
            )
            imageView.frame = CGRect(origin: .zero, size: fittedSize)
            contentSize = fittedSize
        }

        centerContent()
    }

    func centerContent() {
        let imageFrame = imageView.frame
        let verticalInset = max((bounds.height - imageFrame.height) / 2, 0)
        let horizontalInset = max((bounds.width - imageFrame.width) / 2, 0)
        contentInset = UIEdgeInsets(
            top: verticalInset, left: horizontalInset,
            bottom: verticalInset, right: horizontalInset
        )
    }
}

// MARK: - ActivityView (Share Sheet)

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
