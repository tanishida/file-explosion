import SwiftUI
import AVKit
import PDFKit
import ImageIO

// --- アクション定義 ---
enum GalleryAction {
    case export(SecretFile)
    case move(SecretFile)
    case delete(SecretFile)
}

// --------------------------------------------------------
// サムネイルビュー
// --------------------------------------------------------
struct FileThumbnailView: View {
    let file: SecretFile
    let onTap: () -> Void
    @State private var thumbnailImage: UIImage? = nil
    @State private var loadTask: Task<Void, Never>? = nil
    static let memCache = NSCache<NSString, UIImage>()
    
    var body: some View {
        Rectangle().fill(Color.secondary.opacity(0.15)).aspectRatio(1, contentMode: .fit).overlay {
            if let image = thumbnailImage { Image(uiImage: image).resizable().scaledToFill() } else {
                if file.isVideo { Image(systemName: "play.rectangle.fill").foregroundColor(.blue).font(.title) }
                else if file.isImage { Image(systemName: "photo.fill").foregroundColor(.green).font(.title) }
                else if file.isPDF { Image(systemName: "doc.richtext.fill").foregroundColor(.red).font(.title) }
                else { Image(systemName: "doc.fill").foregroundColor(.gray).font(.title) }
            }
        }.clipped().cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.5), lineWidth: 1)).overlay(Group { if file.isVideo && thumbnailImage != nil { Image(systemName: "play.fill").font(.system(size: 40)).foregroundColor(.white).shadow(radius: 4) } }).contentShape(RoundedRectangle(cornerRadius: 12)).onTapGesture { onTap() }
            .onAppear { let cacheKey = file.url.lastPathComponent as NSString; if let cached = Self.memCache.object(forKey: cacheKey) { self.thumbnailImage = cached } else { loadTask = Task { await loadThumbnail() } } }
            .onDisappear { loadTask?.cancel() }
    }
    
    private func loadThumbnail() async {
        let cacheKey = file.url.lastPathComponent as NSString; let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in if Task.isCancelled { return nil }; let thumbURL = FileManagerHelper.getThumbnailURL(for: file)
            if FileManager.default.fileExists(atPath: thumbURL.path) { let tempThumbURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".thumb.tmp"); if KeyManager.decryptFile(inputURL: thumbURL, outputURL: tempThumbURL) { defer { try? FileManager.default.removeItem(at: tempThumbURL) }; if let data = try? Data(contentsOf: tempThumbURL), let img = UIImage(data: data) { return (await img.byPreparingForDisplay()) ?? img } } }
            if Task.isCancelled { return nil }; let cacheURL = FileManagerHelper.getCacheURL(for: file); let isCached = FileManager.default.fileExists(atPath: cacheURL.path); let targetURL = isCached ? cacheURL : FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tmp")
            if !isCached { guard KeyManager.decryptFile(inputURL: file.url, outputURL: targetURL) else { return nil } }; defer { if !isCached { try? FileManager.default.removeItem(at: targetURL) } }
            if Task.isCancelled { return nil }; if let img = createThumbnailImage(from: targetURL) { if let jpegData = img.jpegData(compressionQuality: 0.4) { let unencryptedThumbURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg"); try? jpegData.write(to: unencryptedThumbURL); _ = KeyManager.encryptFile(inputURL: unencryptedThumbURL, outputURL: thumbURL); try? FileManager.default.removeItem(at: unencryptedThumbURL) }; return (await img.byPreparingForDisplay()) ?? img }; return nil
        }.value; if !Task.isCancelled, let finalImage = image { Self.memCache.setObject(finalImage, forKey: cacheKey); await MainActor.run { self.thumbnailImage = finalImage } }
    }
    private func createThumbnailImage(from url: URL) -> UIImage? { if file.isImage { let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 150, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary; if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) { return UIImage(cgImage: cgImage) } } else if file.isVideo { let generator = AVAssetImageGenerator(asset: AVAsset(url: url)); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 150, height: 150); if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) { return UIImage(cgImage: cgImage) } } else if file.isPDF { if let document = PDFDocument(url: url), let page = document.page(at: 0) { return page.thumbnail(of: CGSize(width: 150, height: 150), for: .mediaBox) } } ; return nil }
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
    
    @Environment(\.dismiss) var dismiss
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
            Color.black.opacity(dragOffset == .zero ? 1.0 : max(0, 1.0 - Double(abs(dragOffset.height) / 300))).ignoresSafeArea()
            
            if files.isEmpty { Color.clear.ignoresSafeArea() } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        DetailView(file: file, isVisible: currentIndex == index, isLandscapeMode: isLandscapeMode, globalDragOffset: $dragOffset, showUI: $showUI)
                            .tag(index)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never)).ignoresSafeArea()
                
                VStack {
                    HStack {
                        Text("\(currentIndex + 1) / \(files.count)").font(.headline).foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 8).background(Color.black.opacity(0.6)).cornerRadius(20)
                        if files.indices.contains(currentIndex) && files[currentIndex].isVideo { Button(action: { withAnimation(.easeInOut(duration: 0.3)) { isLandscapeMode.toggle() } }) { Image(systemName: isLandscapeMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").font(.system(size: 16, weight: .bold)).foregroundColor(.white).padding(10).background(Color.black.opacity(0.6)).clipShape(Circle()) }.padding(.leading, 10) }
                        Spacer()
                        Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.system(size: 30)).foregroundColor(.white.opacity(0.8)) }
                    }.padding(.horizontal).padding(.top, 10)
                    Spacer()
                    if files.indices.contains(currentIndex) {
                        HStack {
                            Button(action: { exportCurrentFile() }) { Image(systemName: "square.and.arrow.up").font(.title2).foregroundColor(.white) }
                            Spacer()
                            Button(action: { onToggleFavorite(files[currentIndex]) }) { Image(systemName: isFavorite(files[currentIndex]) ? "heart.fill" : "heart").font(.title2).foregroundColor(isFavorite(files[currentIndex]) ? .pink : .white) }
                            Spacer()
                            Button(action: { showingMoveDialog = true }) { Image(systemName: "folder").font(.title2).foregroundColor(.white) }
                            Spacer()
                            Button(action: { showingDeleteConfirm = true }) { Image(systemName: "trash").font(.title2).foregroundColor(.white) }
                        }
                        .padding(.horizontal, 40).padding(.vertical, 15)
                        .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top))
                    }
                }
                .opacity(showUI && dragOffset == .zero ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.2), value: showUI)
                .animation(.easeInOut(duration: 0.2), value: dragOffset == .zero)
            }
        }
        .confirmationDialog("移動先を選択", isPresented: $showingMoveDialog, titleVisibility: .visible) { Button("未分類に戻す") { if files.indices.contains(currentIndex) { onMove(files[currentIndex], nil) } }; ForEach(appFolders.filter { $0.category == currentCategory }) { folder in Button(folder.name) { if files.indices.contains(currentIndex) { onMove(files[currentIndex], folder) } } }; Button("キャンセル", role: .cancel) {} }
        .alert("削除の確認", isPresented: $showingDeleteConfirm) {
            Button("キャンセル", role: .cancel) { }
            Button("削除", role: .destructive) {
                if files.indices.contains(currentIndex) {
                    onDelete(files[currentIndex])
                    
                    StorageCleaner.clearAllTempAndCacheData()
                }
            }
        } message: { Text("このファイルを完全に削除しますか？") }
        .sheet(isPresented: $showShareSheet, onDismiss: { cleanupExportedFiles() }) { ShareSheet(activityItems: filesToShare) }
        .overlay { if isProcessing { ZStack { Color.black.opacity(0.4).ignoresSafeArea(); VStack(spacing: 20) { ProgressView().scaleEffect(1.5).tint(.white); Text("復号中...").font(.callout).fontWeight(.bold).foregroundColor(.white) }.padding(30).background(Color.black.opacity(0.8)).cornerRadius(15) } } }
    }
    
    func exportCurrentFile() { guard files.indices.contains(currentIndex) else { return }; isProcessing = true; let file = files[currentIndex]; DispatchQueue.global(qos: .userInitiated).async { let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Export_" + file.url.lastPathComponent); if KeyManager.decryptFile(inputURL: file.url, outputURL: tempURL) { DispatchQueue.main.async { isProcessing = false; filesToShare = [tempURL]; showShareSheet = true } } else { DispatchQueue.main.async { isProcessing = false } } } }
    func cleanupExportedFiles() { for url in filesToShare { try? FileManager.default.removeItem(at: url) }; filesToShare.removeAll() }
}

// --------------------------------------------------------
// 詳細表示ビュー（3層レイヤー＆ジェスチャー完璧版）
// --------------------------------------------------------
struct DetailView: View {
    let file: SecretFile
    var isVisible: Bool
    var isLandscapeMode: Bool
    @Binding var globalDragOffset: CGSize
    @Binding var showUI: Bool
    
    @State private var decryptedURL: URL? = nil
    @State private var isDecrypting = true
    @State private var player: AVPlayer? = nil
    
    @State private var isPlaying = false
    @State private var isMuted = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isDraggingSlider = false
    @State private var hideTask: Task<Void, Never>? = nil
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var zoomAnchor: UnitPoint = .center
    
    @Environment(\.dismiss) var dismiss
    
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: scale > 1.0 ? 0 : 20).onChanged { value in
            if scale > 1.0 {
                offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
            } else {
                if abs(value.translation.height) > abs(value.translation.width) { globalDragOffset = value.translation }
            }
        }.onEnded { value in
            if scale > 1.0 { lastOffset = offset }
            else {
                if abs(value.translation.height) > 120 && abs(value.translation.height) > abs(value.translation.width) { dismiss() }
                else { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { globalDragOffset = .zero } }
            }
        }
    }
    var zoomGesture: some Gesture { MagnificationGesture().onChanged { value in scale = lastScale * value }.onEnded { _ in lastScale = scale; if scale < 1.0 { withAnimation { resetZoom() } } } }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear.ignoresSafeArea()
                
                if let url = decryptedURL {
                    // ==========================================
                    // 1. メディアレイヤー（純粋に表示と回転・ズームだけを担当）
                    // ==========================================
                    Group {
                        if file.isVideo {
                            if let p = player { VideoPlayer(player: p).disabled(true) }
                        } else if file.isImage {
                            if let d = try? Data(contentsOf: url), let i = UIImage(data: d) { Image(uiImage: i).resizable().scaledToFit() }
                        }
                    }
                    .frame(width: isLandscapeMode ? geo.size.height : geo.size.width, height: isLandscapeMode ? geo.size.width : geo.size.height)
                    .rotationEffect(.degrees(isLandscapeMode ? 90 : 0))
                    .scaleEffect(scale == 1.0 ? max(0.8, 1.0 - abs(globalDragOffset.height)/1000) : scale, anchor: zoomAnchor)
                    .offset(scale > 1.0 ? offset : globalDragOffset)
                    
                    if file.isPDF {
                        // PDFは標準ジェスチャーを活かすためレイヤー化から除外
                        PDFKitView(url: url)
                            .frame(width: isLandscapeMode ? geo.size.height : geo.size.width, height: isLandscapeMode ? geo.size.width : geo.size.height)
                            .rotationEffect(.degrees(isLandscapeMode ? 90 : 0))
                    }
                    
                    // ==========================================
                    // 2. タッチ判定レイヤー（画面全体に広がり、向きに関係なく指の動きをキャッチ！）
                    // ==========================================
                    if !file.isPDF {
                        Color.clear.contentShape(Rectangle())
                            .gesture(dragGesture)
                            .simultaneousGesture(zoomGesture)
                            .onTapGesture(count: 2) { location in handleDoubleTap(at: location, in: geo.size) }
                            .onTapGesture {
                                withAnimation(.easeInOut) { showUI.toggle() }
                                if showUI && isPlaying { triggerAutoHide() }
                            }
                    }
                    
                    // ==========================================
                    // 3. UIコントロールレイヤー（ビデオ再生中のみ表示）
                    // ==========================================
                    if showUI && globalDragOffset == .zero {
                        if file.isVideo, let p = player {
                            VStack {
                                Spacer()
                                HStack(spacing: 12) {
                                    Button(action: {
                                        if isPlaying { p.pause() } else { p.play() }
                                        isPlaying.toggle()
                                        if isPlaying { triggerAutoHide() } else { hideTask?.cancel() }
                                    }) { Image(systemName: isPlaying ? "pause.fill" : "play.fill").foregroundColor(.white).font(.title2).frame(width: 44, height: 44) }
                                    
                                    Text(formatTime(currentTime)).font(.caption.monospacedDigit()).foregroundColor(.white)
                                    
                                    Slider(value: $currentTime, in: 0...(duration > 0 ? duration : 1)) { dragging in
                                        isDraggingSlider = dragging
                                        if !dragging { p.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600)) }
                                        if isPlaying && !dragging { triggerAutoHide() } else { hideTask?.cancel() }
                                    }.tint(.white)
                                    
                                    Button(action: {
                                        isMuted.toggle(); p.isMuted = isMuted
                                        if isPlaying { triggerAutoHide() }
                                    }) { Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").foregroundColor(.white).font(.headline).frame(width: 44, height: 44) }
                                }
                                .padding(.horizontal, 15).padding(.vertical, 8)
                                .background(Color.black.opacity(0.5)).cornerRadius(30)
                                .padding(.bottom, 90)
                                .padding(.horizontal, isLandscapeMode ? 80 : 10) // 横向き時は端を詰める
                                .transition(.opacity)
                            }
                            .frame(width: isLandscapeMode ? geo.size.height : geo.size.width, height: isLandscapeMode ? geo.size.width : geo.size.height)
                            .rotationEffect(.degrees(isLandscapeMode ? 90 : 0))
                        }
                    }
                } else if isDecrypting { VStack { ProgressView().scaleEffect(1.5).tint(.white); Text("解読中...").foregroundColor(.white).padding(.top) } }
            }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }.onAppear {
            let cache = FileManagerHelper.getCacheURL(for: file); if FileManager.default.fileExists(atPath: cache.path) { setupContent(url: cache) }
            else { DispatchQueue.global(qos: .userInitiated).async { if KeyManager.decryptFile(inputURL: file.url, outputURL: cache) { DispatchQueue.main.async { setupContent(url: cache) } } else { DispatchQueue.main.async { isDecrypting = false } } } }
        }
    }
    
    private func handleDoubleTap(at physicalLocation: CGPoint, in physicalSize: CGSize) {
        let viewWidth = isLandscapeMode ? physicalSize.height : physicalSize.width
        let viewHeight = isLandscapeMode ? physicalSize.width : physicalSize.height
        
        // 横向き（90度回転）の時は、指が触れた位置を「元画像の中のどこか」に逆算してあげる
        let localX = isLandscapeMode ? physicalLocation.y : physicalLocation.x
        let localY = isLandscapeMode ? (physicalSize.width - physicalLocation.x) : physicalLocation.y
        
        withAnimation(.spring()) {
            if scale == 1.0 {
                zoomAnchor = UnitPoint(x: localX / viewWidth, y: localY / viewHeight)
                scale = 2.5
                lastScale = 2.5
            } else { resetZoom() }
        }
    }
    
    private func triggerAutoHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled && isPlaying { await MainActor.run { withAnimation(.easeInOut) { showUI = false } } }
        }
    }
    
    private func setupContent(url: URL) {
        decryptedURL = url; isDecrypting = false;
        if file.isVideo {
            let newPlayer = AVPlayer(url: url); player = newPlayer;
            newPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in if !isDraggingSlider { currentTime = time.seconds } }
            if let durationTime = newPlayer.currentItem?.asset.duration { duration = durationTime.seconds }
            if isVisible { newPlayer.play(); isPlaying = true; triggerAutoHide() }
        }
    }
    private func formatTime(_ seconds: Double) -> String { let m = Int(seconds) / 60; let s = Int(seconds) % 60; return String(format: "%d:%02d", m, s) }
    private func resetZoom() { scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero; zoomAnchor = .center; globalDragOffset = .zero; showUI = true }
}

struct TransparentBackground: UIViewRepresentable { func makeUIView(context: Context) -> UIView { let view = UIView(); DispatchQueue.main.async { view.superview?.superview?.backgroundColor = .clear }; return view }; func updateUIView(_ uiView: UIView, context: Context) {} }
struct PDFKitView: UIViewRepresentable { let url: URL; func makeUIView(context: Context) -> PDFView { let v = PDFView(); v.document = PDFDocument(url: url); v.autoScales = true; return v }; func updateUIView(_ uiView: PDFView, context: Context) {} }
