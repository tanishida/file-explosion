import SwiftUI
import AVKit
import PDFKit
import ImageIO

// --------------------------------------------------------
// ▼ 🆕 追加：フルスクリーンカバーの背景を透明にする魔法のパーツ
// --------------------------------------------------------
struct TransparentBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async { view.superview?.superview?.backgroundColor = .clear }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// --------------------------------------------------------
// アクション定義
// --------------------------------------------------------
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
    private func createThumbnailImage(from url: URL) -> UIImage? {
        if file.isImage { let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 150, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary; if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) { return UIImage(cgImage: cgImage) } } else if file.isVideo { let generator = AVAssetImageGenerator(asset: AVAsset(url: url)); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 150, height: 150); if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) { return UIImage(cgImage: cgImage) } } else if file.isPDF { if let document = PDFDocument(url: url), let page = document.page(at: 0) { return page.thumbnail(of: CGSize(width: 150, height: 150), for: .mediaBox) } }
        return nil
    }
}

// --------------------------------------------------------
// 写真アプリ風のフル機能ギャラリービュー
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
    
    // ▼ 🆕 追加：画面全体のスワイプダウン量を記録する変数
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            TransparentBackground() // 🆕 これがあることで背景が透明になります
            
            // ▼ 🆕 ドラッグ量に応じて背景の黒を透明にしていく（後ろのグリッドが見える！）
            Color.black
                .opacity(dragOffset == .zero ? 1.0 : max(0, 1.0 - Double(abs(dragOffset.height) / 300)))
                .ignoresSafeArea()
            
            if files.isEmpty {
                Color.clear.ignoresSafeArea()
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        // ▼ 🆕 DetailViewにdragOffsetを渡して連動させる
                        DetailView(file: file, isVisible: currentIndex == index, isLandscapeMode: isLandscapeMode, globalDragOffset: $dragOffset)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
                .onChange(of: currentIndex) { _ in withAnimation { isLandscapeMode = false } }
                
                VStack {
                    // --- 👆 上部ヘッダー ---
                    HStack {
                        Text("\(currentIndex + 1) / \(files.count)")
                            .font(.headline).foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.black.opacity(0.6)).cornerRadius(20)
                        if files.indices.contains(currentIndex) && files[currentIndex].isVideo { Button(action: { withAnimation(.easeInOut(duration: 0.3)) { isLandscapeMode.toggle() } }) { Image(systemName: isLandscapeMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").font(.system(size: 16, weight: .bold)).foregroundColor(.white).padding(10).background(Color.black.opacity(0.6)).clipShape(Circle()) }.padding(.leading, 10) }
                        Spacer()
                        Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.system(size: 30)).foregroundColor(.white.opacity(0.8)) }
                    }.padding(.horizontal).padding(.top, 10)
                    
                    Spacer()
                    
                    // --- 👇 下部ツールバー ---
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
                        .padding(.horizontal, 40)
                        .padding(.vertical, 15)
                        .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top))
                    }
                }
                // ▼ 🆕 ドラッグ中（引っ張っている最中）は上下のUIをスッと消す！
                .opacity(dragOffset == .zero ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.2), value: dragOffset == .zero)
            }
        }
        .confirmationDialog("移動先を選択", isPresented: $showingMoveDialog, titleVisibility: .visible) {
            Button("未分類に戻す") { if files.indices.contains(currentIndex) { onMove(files[currentIndex], nil) } }
            ForEach(appFolders.filter { $0.category == currentCategory }) { folder in
                Button(folder.name) { if files.indices.contains(currentIndex) { onMove(files[currentIndex], folder) } }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("削除の確認", isPresented: $showingDeleteConfirm) {
            Button("キャンセル", role: .cancel) { }
            Button("削除", role: .destructive) { if files.indices.contains(currentIndex) { onDelete(files[currentIndex]) } }
        } message: { Text("このファイルを完全に削除しますか？") }
            .sheet(isPresented: $showShareSheet, onDismiss: { cleanupExportedFiles() }) { ShareSheet(activityItems: filesToShare) }
            .overlay {
                if isProcessing { ZStack { Color.black.opacity(0.4).ignoresSafeArea(); VStack(spacing: 20) { ProgressView().scaleEffect(1.5).tint(.white); Text("復号中...").font(.callout).fontWeight(.bold).foregroundColor(.white) }.padding(30).background(Color.black.opacity(0.8)).cornerRadius(15) } }
            }
    }
    
    func exportCurrentFile() {
        guard files.indices.contains(currentIndex) else { return }
        isProcessing = true
        let file = files[currentIndex]
        DispatchQueue.global(qos: .userInitiated).async {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Export_" + file.url.lastPathComponent)
            if KeyManager.decryptFile(inputURL: file.url, outputURL: tempURL) {
                DispatchQueue.main.async { isProcessing = false; filesToShare = [tempURL]; showShareSheet = true }
            } else { DispatchQueue.main.async { isProcessing = false } }
        }
    }
    func cleanupExportedFiles() { for url in filesToShare { try? FileManager.default.removeItem(at: url) }; filesToShare.removeAll() }
}

// --------------------------------------------------------
// 詳細表示・PDF表示ビュー（スワイプダウン完全対応）
// --------------------------------------------------------
struct DetailView: View {
    let file: SecretFile
    var isVisible: Bool
    var isLandscapeMode: Bool
    @Binding var globalDragOffset: CGSize // 🆕
    
    @State private var decryptedURL: URL? = nil
    @State private var isDecrypting = true
    @State private var player: AVPlayer? = nil
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var zoomAnchor: UnitPoint = .center
    
    @Environment(\.dismiss) var dismiss // 🆕 引っ張って画面を閉じるためのメソッド
    
    // ▼ 🆕 大幅改良：写真アプリと同じ動きをする神ジェスチャー
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: scale > 1.0 ? 0 : 20)
            .onChanged { value in
                if scale > 1.0 {
                    // ズーム中のパン（移動）処理
                    if isLandscapeMode { offset = CGSize(width: lastOffset.width + value.translation.height, height: lastOffset.height - value.translation.width) }
                    else { offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height) }
                } else {
                    // 🆕 ズームしていない時は、縦方向の引っ張りのみ検知する（横スワイプはTabViewに譲る）
                    if abs(value.translation.height) > abs(value.translation.width) {
                        globalDragOffset = value.translation
                    }
                }
            }
            .onEnded { value in
                if scale > 1.0 {
                    lastOffset = offset
                } else {
                    // 🆕 一定距離（120px）以上下に引っ張ったら画面を閉じる！
                    if abs(value.translation.height) > 120 && abs(value.translation.height) > abs(value.translation.width) {
                        dismiss()
                    } else {
                        // 途中で指を離したら、バネのように元に戻る
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            globalDragOffset = .zero
                        }
                    }
                }
            }
    }
    
    var zoomGesture: some Gesture { MagnificationGesture().onChanged { value in scale = lastScale * value }.onEnded { _ in lastScale = scale; if scale < 1.0 { withAnimation { resetZoom() } } } }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear.ignoresSafeArea() // 🆕 GalleryViewで背景を描画するためここは透明にする
                
                if let url = decryptedURL {
                    if file.isVideo {
                        if let p = player {
                            VideoPlayer(player: p)
                            // ▼ 🆕 引っ張っている間、画像を少しだけ小さくする（Apple特有の気持ちいい演出）
                                .scaleEffect(scale == 1.0 ? max(0.8, 1.0 - abs(globalDragOffset.height)/1000) : scale, anchor: zoomAnchor)
                            // ▼ 🆕 指の動きに合わせて画像も下に動く
                                .offset(scale > 1.0 ? offset : globalDragOffset)
                                .gesture(dragGesture)
                                .simultaneousGesture(zoomGesture)
                                .onTapGesture(count: 2, coordinateSpace: .local) { location in handleDoubleTap(at: location, in: geo.size) }
                                .onChange(of: isVisible) { visible in if visible { p.play() } else { p.pause(); resetZoom() } }
                                .onDisappear { p.pause() }
                                .frame(width: isLandscapeMode ? geo.size.height : geo.size.width, height: isLandscapeMode ? geo.size.width : geo.size.height)
                                .rotationEffect(.degrees(isLandscapeMode ? 90 : 0))
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                    } else if file.isImage {
                        if let d = try? Data(contentsOf: url), let i = UIImage(data: d) {
                            Image(uiImage: i).resizable().scaledToFit()
                            // ▼ 🆕 動画と同じく縮小＆移動エフェクトを追加
                                .scaleEffect(scale == 1.0 ? max(0.8, 1.0 - abs(globalDragOffset.height)/1000) : scale, anchor: zoomAnchor)
                                .offset(scale > 1.0 ? offset : globalDragOffset)
                                .gesture(dragGesture)
                                .simultaneousGesture(zoomGesture)
                                .onTapGesture(count: 2, coordinateSpace: .local) { location in handleDoubleTap(at: location, in: geo.size) }
                                .onChange(of: isVisible) { visible in if !visible { resetZoom() } }
                                .frame(width: isLandscapeMode ? geo.size.height : geo.size.width, height: isLandscapeMode ? geo.size.width : geo.size.height)
                                .rotationEffect(.degrees(isLandscapeMode ? 90 : 0))
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                    } else if file.isPDF {
                        // PDFは内部で縦スクロールするためスワイプダウンは適用しない（Appleのファイルアプリと同じ仕様）
                        PDFKitView(url: url)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    } else {
                        Text("プレビュー非対応").foregroundColor(.white).position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                } else if isDecrypting {
                    VStack { ProgressView().scaleEffect(1.5).tint(.white); Text("解読中...").foregroundColor(.white).padding(.top) }.position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
        }
        .onAppear {
            let cache = FileManagerHelper.getCacheURL(for: file)
            if FileManager.default.fileExists(atPath: cache.path) { setupContent(url: cache) }
            else { DispatchQueue.global(qos: .userInitiated).async { if KeyManager.decryptFile(inputURL: file.url, outputURL: cache) { DispatchQueue.main.async { setupContent(url: cache) } } else { DispatchQueue.main.async { isDecrypting = false } } } }
        }
    }
    
    private func setupContent(url: URL) { decryptedURL = url; isDecrypting = false; if file.isVideo { let newPlayer = AVPlayer(url: url); player = newPlayer; if isVisible { newPlayer.play() } } }
    private func handleDoubleTap(at location: CGPoint, in size: CGSize) { let viewWidth = isLandscapeMode ? size.height : size.width; let viewHeight = isLandscapeMode ? size.width : size.height; withAnimation(.spring()) { if scale == 1.0 { zoomAnchor = UnitPoint(x: location.x / viewWidth, y: location.y / viewHeight); scale = 2.5; lastScale = 2.5 } else { resetZoom() } } }
    private func resetZoom() { scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero; zoomAnchor = .center; globalDragOffset = .zero }
}

struct PDFKitView: UIViewRepresentable { let url: URL; func makeUIView(context: Context) -> PDFView { let v = PDFView(); v.document = PDFDocument(url: url); v.autoScales = true; return v }; func updateUIView(_ uiView: PDFView, context: Context) {} }
