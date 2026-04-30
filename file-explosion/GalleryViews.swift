import SwiftUI
import AVKit
import PDFKit
import ImageIO

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import UIKit
typealias PlatformImage = UIImage
typealias PlatformViewRepresentable = UIViewRepresentable
typealias PlatformView = UIView

// AVPlayerLayerをUIViewに埋め込みネイティブ再生バーを非表示にする（Mac Catalyst・Designed for iPad両対応）
import AVFoundation
struct AVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.player = player
        return view
    }
    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
    }
    class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var player: AVPlayer? {
            get { playerLayer.player }
            set {
                playerLayer.player = newValue
                playerLayer.videoGravity = .resizeAspect
            }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}

#elseif os(macOS)
import AppKit
import AVFoundation
typealias PlatformImage = NSImage
typealias PlatformViewRepresentable = NSViewRepresentable
typealias PlatformView = NSView

// ネイティブmacOS: AVPlayerLayerをNSViewに埋め込みネイティブ再生バーを非表示にする
struct AVPlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.player = player
        return view
    }
    func updateNSView(_ nsView: PlayerNSView, context: Context) {
        nsView.player = player
    }
    class PlayerNSView: NSView {
        var player: AVPlayer? {
            didSet { playerLayer.player = player }
        }
        private let playerLayer = AVPlayerLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            playerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(playerLayer)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }
    }
}

extension NSImage {
    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
    
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}
#endif

extension Image {
    init(platformImage: PlatformImage) {
#if os(macOS)
        self.init(nsImage: platformImage)
#else
        self.init(uiImage: platformImage)
#endif
    }
}

private func preparedImage(_ image: PlatformImage) async -> PlatformImage {
#if os(macOS)
    return image
#else
    return await image.byPreparingForDisplay() ?? image
#endif
}

// --------------------------------------------------------
// サムネイルビュー
// --------------------------------------------------------
struct FileThumbnailView: View {
    let file: SecretFile
    let onTap: () -> Void
    
    @State private var thumbnailImage: PlatformImage?
    @State private var loadTask: Task<Void, Never>?
    
    static let memCache = NSCache<NSString, PlatformImage>()
    
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = thumbnailImage {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholderIcon
                }
            }
            .clipped()
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
            )
            .overlay {
                if file.isVideo, thumbnailImage != nil {
                    Image(systemName: "play.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                        .shadow(radius: 4)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture(perform: onTap)
            .onAppear {
                let cacheKey = file.url.lastPathComponent as NSString
                if let cached = Self.memCache.object(forKey: cacheKey) {
                    thumbnailImage = cached
                } else {
                    loadTask = Task { await loadThumbnail() }
                }
            }
            .onDisappear {
                loadTask?.cancel()
            }
    }
    
    @ViewBuilder
    private var placeholderIcon: some View {
        if file.isVideo {
            Image(systemName: "play.rectangle.fill")
                .foregroundColor(.blue)
                .font(.title)
        } else if file.isImage {
            Image(systemName: "photo.fill")
                .foregroundColor(.green)
                .font(.title)
        } else if file.isPDF {
            Image(systemName: "doc.richtext.fill")
                .foregroundColor(.red)
                .font(.title)
        } else {
            Image(systemName: "doc.fill")
                .foregroundColor(.gray)
                .font(.title)
        }
    }
    
    private func loadThumbnail() async {
        let cacheKey = file.url.lastPathComponent as NSString
        if let cached = Self.memCache.object(forKey: cacheKey) {
            await MainActor.run { thumbnailImage = cached }
            return
        }
        
        let file = self.file
        let imageData = await Task.detached(priority: .userInitiated) { () -> Data? in
            if Task.isCancelled { return nil }
            
            let thumbURL = FileManagerHelper.getThumbnailURL(for: file)
            if FileManager.default.fileExists(atPath: thumbURL.path) {
                let tempThumbURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".thumb.tmp")
                
                if KeyManager.decryptFile(inputURL: thumbURL, outputURL: tempThumbURL) {
                    defer { try? FileManager.default.removeItem(at: tempThumbURL) }
                    if let data = try? Data(contentsOf: tempThumbURL) {
                        return data
                    }
                }
            }
            
            if Task.isCancelled { return nil }
            
            let cacheURL = FileManagerHelper.getCacheURL(for: file)
            let isCached = FileManager.default.fileExists(atPath: cacheURL.path)
            let targetURL = isCached
            ? cacheURL
            : FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tmp")
            
            if !isCached,
               !KeyManager.decryptFile(inputURL: file.url, outputURL: targetURL) {
                return nil
            }
            
            defer {
                if !isCached {
                    try? FileManager.default.removeItem(at: targetURL)
                }
            }
            
            if Task.isCancelled { return nil }
            
            guard let jpegData = await Self.createThumbnailData(for: file, from: targetURL) else {
                return nil
            }
            
            let tempImageURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".jpg")
            try? jpegData.write(to: tempImageURL)
            _ = KeyManager.encryptFile(inputURL: tempImageURL, outputURL: thumbURL)
            try? FileManager.default.removeItem(at: tempImageURL)
            
            return jpegData
        }.value
        
        guard !Task.isCancelled,
              let imageData,
              let rawImage = PlatformImage(data: imageData) else { return }
#if os(macOS)
        let image = rawImage
#else
        let image = await preparedImage(rawImage)
#endif
        
        Self.memCache.setObject(image, forKey: cacheKey)
        await MainActor.run {
            thumbnailImage = image
        }
    }
    
    private static func createThumbnailData(for file: SecretFile, from url: URL) async -> Data? {
        if file.isImage {
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 150,
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary
            
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
#if os(macOS)
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    .jpegData(compressionQuality: 0.4)
#else
                return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.4)
#endif
            }
        } else if file.isVideo {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 150, height: 150)
            
            if let cgImage = try? await generator.image(at: .zero).image {
#if os(macOS)
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    .jpegData(compressionQuality: 0.4)
#else
                return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.4)
#endif
            }
        } else if file.isPDF,
                  let document = PDFDocument(url: url),
                  let page = document.page(at: 0) {
            return page.thumbnail(of: CGSize(width: 150, height: 150), for: .mediaBox)
                .jpegData(compressionQuality: 0.4)
        }
        
        return nil
    }
}

// --------------------------------------------------------
// ギャラリービュー
// --------------------------------------------------------
struct GalleryView: View {
    var files: [SecretFile]
    @Binding var currentIndex: Int
    var appFolders: [AppFolder]
    var currentCategory: Int
    var isFavorite: (SecretFile) -> Bool
    var onToggleFavorite: (SecretFile) -> Void
    var onMove: (SecretFile, AppFolder?) -> Void
    var onDelete: (SecretFile) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var isLandscapeMode = false
    @State private var showingMoveDialog = false
    @State private var showingDeleteConfirm = false
    @State private var isProcessing = false
    @State private var showShareSheet = false
    @State private var filesToShare: [URL] = []
    @State private var dragOffset: CGSize = .zero
    @State private var showUI = true
    
    var body: some View {
        ZStack {
            TransparentBackground()
            Color.black
                .opacity(dragOffset == .zero ? 1.0 : max(0, 1.0 - Double(abs(dragOffset.height) / 300)))
                .ignoresSafeArea()
            
            if files.isEmpty {
                Color.clear.ignoresSafeArea()
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        DetailView(
                            file: file,
                            isVisible: currentIndex == index,
                            isLandscapeMode: isLandscapeMode,
                            globalDragOffset: $dragOffset,
                            showUI: $showUI
                        )
                        .tag(index)
                    }
                }
#if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
#else
                .tabViewStyle(.automatic)
#endif
                .ignoresSafeArea()
                
                VStack {
                    HStack {
                        Text("\(currentIndex + 1) / \(files.count)")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)
                        
                        if files.indices.contains(currentIndex), files[currentIndex].isVideo {
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isLandscapeMode.toggle()
                                }
                            } label: {
                                Image(systemName: isLandscapeMode
                                      ? "arrow.down.right.and.arrow.up.left"
                                      : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                            }
                            .padding(.leading, 10)
                        }
                        
                        Spacer()
                        
                        Button(action: dismiss.callAsFunction) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    
                    Spacer()
                    
                    if showUI {
                        galleryBottomBar
                            .transition(.move(edge: .bottom))
                    }
                }
                .opacity(showUI ? 1 : 0)
                .animation(.easeInOut, value: showUI)
            }
        }
        .gesture(
            dragOffset.height > 0
            ? DragGesture(minimumDistance: 30)
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        dismiss()
                    } else {
                        withAnimation(.spring()) {
                            dragOffset = .zero
                        }
                    }
                }
            : nil
        )
        .sheet(isPresented: $showShareSheet, onDismiss: cleanupExportedFiles) {
#if os(iOS)
            ShareSheet(activityItems: filesToShare)
#else
            MacExportSheet(urls: filesToShare)
#endif
        }
        .confirmationDialog("移動先を選択", isPresented: $showingMoveDialog, titleVisibility: .visible) {
            if files.indices.contains(currentIndex) {
                Button("未分類に戻す") { onMove(files[currentIndex], nil) }
                ForEach(appFolders.filter { $0.category == currentCategory }) { folder in
                    Button(folder.name) { onMove(files[currentIndex], folder) }
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("削除の確認", isPresented: $showingDeleteConfirm) {
            Button("キャンセル", role: .cancel) {}
            if files.indices.contains(currentIndex) {
                Button("削除", role: .destructive) { onDelete(files[currentIndex]) }
            }
        } message: {
            Text("このファイルを完全に削除しますか？")
        }
        .overlay {
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                }
            }
        }
    }
    
    var galleryBottomBar: some View {
        HStack(spacing: 20) {
            Button {
                guard files.indices.contains(currentIndex) else { return }
                onToggleFavorite(files[currentIndex])
            } label: {
                Image(systemName: files.indices.contains(currentIndex) && isFavorite(files[currentIndex]) ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundColor(files.indices.contains(currentIndex) && isFavorite(files[currentIndex]) ? .pink : .white)
            }
            
            Button {
                showingMoveDialog = true
            } label: {
                Image(systemName: "folder")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            Button {
                guard files.indices.contains(currentIndex) else { return }
                exportFile(files[currentIndex])
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            Button {
                showingDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 15)
        .background(Color.black.opacity(0.6))
        .cornerRadius(30)
        .padding(.bottom, 30)
    }
    
    func exportFile(_ file: SecretFile) {
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Export_" + file.url.lastPathComponent)
            
            if KeyManager.decryptFile(inputURL: file.url, outputURL: tempURL) {
                DispatchQueue.main.async {
                    filesToShare = [tempURL]
                    showShareSheet = true
                    isProcessing = false
                }
            } else {
                DispatchQueue.main.async {
                    isProcessing = false
                }
            }
        }
    }
    
    func cleanupExportedFiles() {
        filesToShare.forEach { try? FileManager.default.removeItem(at: $0) }
        filesToShare.removeAll()
    }
}

// --------------------------------------------------------
// 詳細ビュー（画像・動画・PDF）
// --------------------------------------------------------
struct DetailView: View {
    let file: SecretFile
    let isVisible: Bool
    let isLandscapeMode: Bool
    @Binding var globalDragOffset: CGSize
    @Binding var showUI: Bool
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var decryptedURL: URL?
    @State private var isDecrypting = false
    @State private var loadedImage: PlatformImage? // ← Add this for async image loading
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isDraggingSlider = false
    @State private var isMuted = false
    @State private var hideTask: Task<Void, Never>?
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var zoomAnchor: UnitPoint = .center
    @State private var isMacOrPad = false
    @State private var debugMessage = ""
    
    var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = lastScale * value
            }
            .onEnded { _ in
                lastScale = scale
                if scale < 1.0 {
                    withAnimation {
                        resetZoom()
                    }
                }
            }
    }
    
    var verticalDismissGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { value in
                if value.translation.height > 0,
                   value.translation.height > abs(value.translation.width) * 2 {
                    globalDragOffset = CGSize(width: 0, height: value.translation.height)
                }
            }
            .onEnded { _ in
                if globalDragOffset.height > 120 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        globalDragOffset = .zero
                    }
                }
            }
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear.ignoresSafeArea()
                
                if let url = decryptedURL {
                    contentView(url: url, in: geo.size)
                } else if isDecrypting {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("解読中...")
                            .foregroundColor(.white)
                            .padding(.top)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.yellow)
                        Text("読み込み待機中またはエラー")
                            .foregroundColor(.white)
                        Text("Visible: \(isVisible ? "Yes" : "No")")
                            .foregroundColor(.gray)
                        Text("Debug: \(debugMessage)")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
#if os(iOS)
            isMacOrPad = UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac
#else
            isMacOrPad = true
#endif
            
            if isVisible {
                setupOrDecrypt()
            }
        }
        .onChange(of: isVisible) { _, newValue in
            if newValue {
                if decryptedURL == nil {
                    setupOrDecrypt()
                } else {
                    player?.play()
                    isPlaying = true
                    triggerAutoHide()
                }
            } else {
                player?.pause()
                isPlaying = false
                hideTask?.cancel()
            }
        }
    }
    
    @ViewBuilder
    private func contentView(url: URL, in size: CGSize) -> some View {
        if file.isPDF {
            // PDF: scaleEffect/offset/rotationを使わずそのまま表示
            PDFKitView(url: url)
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .topLeading) {
                    if isMacOrPad {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white.opacity(0.85))
                                .shadow(radius: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(16)
                    }
                }
        } else {
            Group {
                if file.isVideo {
                    if let player {
                        if isMacOrPad {
                            AVPlayerLayerView(player: player)
                        } else {
                            VideoPlayer(player: player)
                        }
                    }
                } else if file.isImage {
                    if let image = loadedImage {
                        Image(platformImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView().tint(.white)
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)
                        Text(file.displayName)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("このファイル形式のプレビューはサポートされていません")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
            .frame(
                width: isLandscapeMode ? size.height : size.width,
                height: isLandscapeMode ? size.width : size.height
            )
            .rotationEffect(.degrees(isLandscapeMode ? 90 : 0))
            .scaleEffect(scale == 1.0 ? max(0.8, 1.0 - abs(globalDragOffset.height) / 1000) : scale, anchor: zoomAnchor)
            .offset(scale > 1.0 ? offset : globalDragOffset)
            .overlay {
                interactionOverlay(in: size)
            }
            .overlay {
                if showUI, globalDragOffset == .zero, file.isVideo, let player {
                    videoControls(player: player, in: size)
                    skipControls(player: player, in: size)
                }
            }
            .overlay(alignment: .topLeading) {
                if isMacOrPad, file.isVideo {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.85))
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                }
            }
        }
    }
    
    @ViewBuilder
    private func interactionOverlay(in size: CGSize) -> some View {
        if scale > 1.0 {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { location in
                    handleDoubleTap(at: location, in: size)
                }
                .onTapGesture {
                    withAnimation(.easeInOut) {
                        showUI.toggle()
                    }
                    if showUI, isPlaying {
                        triggerAutoHide()
                    }
                }
                .gesture(dragGesture(viewSize: size))
                .simultaneousGesture(zoomGesture)
        } else if isMacOrPad, file.isVideo {
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(verticalDismissGesture)
                .simultaneousGesture(zoomGesture)
                .onTapGesture(count: 2) { location in
                    handleDoubleTap(at: location, in: size)
                }
                .onTapGesture {
                    withAnimation(.easeInOut) { showUI.toggle() }
                    if showUI, isPlaying { triggerAutoHide() }
                }
        } else {
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(verticalDismissGesture)
                .simultaneousGesture(zoomGesture)
                .onTapGesture(count: 2) { location in
                    handleDoubleTap(at: location, in: size)
                }
                .onTapGesture {
                    withAnimation(.easeInOut) {
                        showUI.toggle()
                    }
                    if showUI, isPlaying {
                        triggerAutoHide()
                    }
                }
        }
    }
    
    private func dragGesture(viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: scale > 1.0 ? 10 : 20)
            .onChanged { value in
                if scale > 1.0 {
                    let newX = lastOffset.width + value.translation.width
                    let newY = lastOffset.height + value.translation.height
                    let maxX = viewSize.width * (scale - 1) / 2
                    let maxY = viewSize.height * (scale - 1) / 2
                    
                    offset = CGSize(
                        width: min(maxX, max(-maxX, newX)),
                        height: min(maxY, max(-maxY, newY))
                    )
                } else if abs(value.translation.height) > abs(value.translation.width) {
                    globalDragOffset = value.translation
                }
            }
            .onEnded { value in
                if scale > 1.0 {
                    lastOffset = offset
                } else if abs(value.translation.height) > 120,
                          abs(value.translation.height) > abs(value.translation.width) {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        globalDragOffset = .zero
                    }
                }
            }
    }
    
    @ViewBuilder
    private func skipControls(player: AVPlayer, in size: CGSize) -> some View {
        let viewWidth = isLandscapeMode ? size.height : size.width
        let btnSize = min(60, viewWidth * 0.12)
        
        HStack(spacing: min(20, viewWidth * 0.04)) {
            skipButton(icon: "gobackward.30", seconds: -30, player: player, size: btnSize)
            skipButton(icon: "gobackward.5", seconds: -5, player: player, size: btnSize)
            
            Button {
                if isPlaying {
                    player.pause()
                } else {
                    player.play()
                }
                isPlaying.toggle()
                if isPlaying {
                    triggerAutoHide()
                } else {
                    hideTask?.cancel()
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: btnSize * 0.5, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: btnSize * 1.2, height: btnSize * 1.2)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, min(10, viewWidth * 0.02))
            
            skipButton(icon: "goforward.5", seconds: 5, player: player, size: btnSize)
            skipButton(icon: "goforward.30", seconds: 30, player: player, size: btnSize)
        }
        .frame(
            width: isLandscapeMode ? size.height : size.width,
            height: isLandscapeMode ? size.width : size.height
        )
        .rotationEffect(.degrees(isLandscapeMode ? 90 : 0))
        .transition(.opacity)
        .allowsHitTesting(true)
    }
    
    private func skipButton(icon: String, seconds: Double, player: AVPlayer, size: CGFloat) -> some View {
        Button {
            let currentTime = player.currentTime()
            let newTime = CMTimeAdd(currentTime, CMTime(seconds: seconds, preferredTimescale: 600))
            player.seek(to: newTime)
            if isPlaying {
                triggerAutoHide()
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func videoControls(player: AVPlayer, in size: CGSize) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Button {
                    if isPlaying {
                        player.pause()
                    } else {
                        player.play()
                    }
                    isPlaying.toggle()
                    if isPlaying {
                        triggerAutoHide()
                    } else {
                        hideTask?.cancel()
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .foregroundColor(.white)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                
                Text(formatTime(currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white)
                
                Slider(value: $currentTime, in: 0...(duration > 0 ? duration : 1)) { dragging in
                    isDraggingSlider = dragging
                    if !dragging {
                        player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
                    }
                    if isPlaying && !dragging {
                        triggerAutoHide()
                    } else {
                        hideTask?.cancel()
                    }
                }
                .tint(.white)
                
                Button {
                    isMuted.toggle()
                    player.isMuted = isMuted
                    if isPlaying {
                        triggerAutoHide()
                    }
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundColor(.white)
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))
            .cornerRadius(30)
            .padding(.bottom, 90)
            .padding(.horizontal, isLandscapeMode ? 80 : 10)
            .transition(.opacity)
        }
        .frame(
            width: isLandscapeMode ? size.height : size.width,
            height: isLandscapeMode ? size.width : size.height
        )
        .rotationEffect(.degrees(isLandscapeMode ? 90 : 0))
    }
    
    private func setupOrDecrypt() {
        let cacheURL = FileManagerHelper.getCacheURL(for: file)
        
        let hasValidCache: Bool = {
            guard FileManager.default.fileExists(atPath: cacheURL.path) else {
                debugMessage = "No cache file."
                return false
            }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path) else {
                debugMessage = "No cache attrs."
                return false
            }
            let isValid = (attrs[.size] as? Int64 ?? 0) > 0
            if !isValid { debugMessage = "Cache file size is 0." }
            return isValid
        }()
        
        if hasValidCache {
            debugMessage = "Valid cache found. Setting up content."
            setupContent(url: cacheURL)
        } else {
            try? FileManager.default.removeItem(at: cacheURL)
            isDecrypting = true
            DispatchQueue.global(qos: .userInitiated).async {
                if let errorMsg = KeyManager.decryptFileWithMessage(inputURL: file.url, outputURL: cacheURL) {
                    DispatchQueue.main.async {
                        self.debugMessage = errorMsg
                        self.isDecrypting = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.debugMessage = "Decrypted successfully."
                        self.setupContent(url: cacheURL)
                    }
                }
            }
        }
    }
    
    private func handleDoubleTap(at physicalLocation: CGPoint, in physicalSize: CGSize) {
        let viewWidth = isLandscapeMode ? physicalSize.height : physicalSize.width
        let viewHeight = isLandscapeMode ? physicalSize.width : physicalSize.height
        
        let localX = isLandscapeMode ? physicalLocation.y : physicalLocation.x
        let localY = isLandscapeMode ? (physicalSize.width - physicalLocation.x) : physicalLocation.y
        
        withAnimation(.spring()) {
            if scale == 1.0 {
                zoomAnchor = UnitPoint(x: localX / viewWidth, y: localY / viewHeight)
                scale = 2.5
                lastScale = 2.5
            } else {
                resetZoom()
            }
        }
    }
    
    private func triggerAutoHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled, isPlaying {
                await MainActor.run {
                    withAnimation(.easeInOut) {
                        showUI = false
                    }
                }
            }
        }
    }
    
    private func setupContent(url: URL) {
        decryptedURL = url
        isDecrypting = false
        
        if file.isImage {
            Task {
                if let data = try? Data(contentsOf: url),
                   let rawImage = PlatformImage(data: data) {
                    let image = await preparedImage(rawImage)
                    await MainActor.run {
                        loadedImage = image
                    }
                }
            }
        }
        
        guard file.isVideo else { return }
        
        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        
        _ = newPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in
            if !isDraggingSlider {
                currentTime = time.seconds
            }
        }
        
        Task {
            if let duration = try? await newPlayer.currentItem?.asset.load(.duration) {
                await MainActor.run {
                    self.duration = duration.seconds
                }
            }
        }
        
        newPlayer.play()
        isPlaying = true
        triggerAutoHide()
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    private func resetZoom() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
        zoomAnchor = .center
        globalDragOffset = .zero
        showUI = true
    }
}

struct TransparentBackground: PlatformViewRepresentable {
#if os(macOS)
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.superview?.wantsLayer = true
            view.superview?.layer?.backgroundColor = NSColor.clear.cgColor
            view.superview?.superview?.wantsLayer = true
            view.superview?.superview?.layer?.backgroundColor = NSColor.clear.cgColor
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
#else
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
#endif
}

struct PDFKitView: PlatformViewRepresentable {
    let url: URL
    
#if os(macOS)
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = PDFDocument(url: url)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        return view
    }
    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
#else
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = PDFDocument(url: url)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .black
        // スクロール方向を縦に固定
        view.displayDirection = .vertical
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
#endif
}

#if os(macOS)
struct MacExportSheet: View {
    let urls: [URL]
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
            
            Text("書き出しの準備ができました")
                .font(.headline)
            
            if urls.count == 1 {
                Text(urls[0].lastPathComponent)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("\(urls.count)個のファイルを一時フォルダへ出力しました")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            HStack {
                Button("閉じる") {
                    dismiss()
                }
                
                Button("Finderで表示") {
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urls.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }
}
#endif
