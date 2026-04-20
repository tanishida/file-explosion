import SwiftUI
import AVKit
import PDFKit
import ImageIO

struct FileThumbnailView: View {
    let file: SecretFile
    let onTap: () -> Void
    
    @State private var thumbnailImage: UIImage? = nil
    @State private var loadTask: Task<Void, Never>? = nil
    
    static let memCache = NSCache<NSString, UIImage>()
    
    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.15))
            
            if let image = thumbnailImage {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 100, height: 100).clipped()
            } else {
                if file.isVideo { Image(systemName: "play.rectangle.fill").foregroundColor(.blue).font(.title) }
                else if file.isImage { Image(systemName: "photo.fill").foregroundColor(.green).font(.title) }
                else if file.isPDF { Image(systemName: "doc.richtext.fill").foregroundColor(.red).font(.title) }
                else { Image(systemName: "doc.fill").foregroundColor(.gray).font(.title) }
            }
        }
        .frame(width: 100, height: 100).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.5), lineWidth: 1))
        .overlay(Group { if file.isVideo && thumbnailImage != nil { Image(systemName: "play.fill").font(.system(size: 40)).foregroundColor(.white).shadow(radius: 4) } })
        .onTapGesture { onTap() }
        .onAppear {
            let cacheKey = file.url.lastPathComponent as NSString
            if let cached = Self.memCache.object(forKey: cacheKey) {
                self.thumbnailImage = cached
            } else {
                loadTask = Task { await loadThumbnail() }
            }
        }
        .onDisappear { loadTask?.cancel() }
    }
    
    private func loadThumbnail() async {
        let cacheKey = file.url.lastPathComponent as NSString
        
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            if Task.isCancelled { return nil }
            let thumbURL = FileManagerHelper.getThumbnailURL(for: file)
            
            if FileManager.default.fileExists(atPath: thumbURL.path) {
                let tempThumbURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".thumb.tmp")
                if KeyManager.decryptFile(inputURL: thumbURL, outputURL: tempThumbURL) {
                    defer { try? FileManager.default.removeItem(at: tempThumbURL) }
                    if let data = try? Data(contentsOf: tempThumbURL), let img = UIImage(data: data) {
                        // ▼ 🆕 バックグラウンドでの超高速デコード（カクつき完全解消）
                        return (await img.byPreparingForDisplay()) ?? img
                    }
                }
            }
            
            if Task.isCancelled { return nil }
            let cacheURL = FileManagerHelper.getCacheURL(for: file)
            let isCached = FileManager.default.fileExists(atPath: cacheURL.path)
            let targetURL = isCached ? cacheURL : FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tmp")
            
            if !isCached { guard KeyManager.decryptFile(inputURL: file.url, outputURL: targetURL) else { return nil } }
            defer { if !isCached { try? FileManager.default.removeItem(at: targetURL) } }
            
            if Task.isCancelled { return nil }
            
            if let img = createThumbnailImage(from: targetURL) {
                if let jpegData = img.jpegData(compressionQuality: 0.4) {
                    let unencryptedThumbURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                    try? jpegData.write(to: unencryptedThumbURL)
                    _ = KeyManager.encryptFile(inputURL: unencryptedThumbURL, outputURL: thumbURL)
                    try? FileManager.default.removeItem(at: unencryptedThumbURL)
                }
                return (await img.byPreparingForDisplay()) ?? img
            }
            return nil
        }.value
        
        if !Task.isCancelled, let finalImage = image {
            Self.memCache.setObject(finalImage, forKey: cacheKey)
            await MainActor.run { self.thumbnailImage = finalImage }
        }
    }
    
    private func createThumbnailImage(from url: URL) -> UIImage? {
        if file.isImage {
            let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 150, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) { return UIImage(cgImage: cgImage) }
        } else if file.isVideo {
            let generator = AVAssetImageGenerator(asset: AVAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 150, height: 150)
            if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) { return UIImage(cgImage: cgImage) }
        } else if file.isPDF {
            if let document = PDFDocument(url: url), let page = document.page(at: 0) { return page.thumbnail(of: CGSize(width: 150, height: 150), for: .mediaBox) }
        }
        return nil
    }
}

// （※以下、GalleryView と DetailView、PDFKitView は変更なしでそのまま残してください！）
struct GalleryView: View {
    let files: [SecretFile]
    @State var currentIndex: Int
    @Environment(\.dismiss) var dismiss
    @State private var isLandscapeMode = false
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $currentIndex) { ForEach(Array(files.enumerated()), id: \.element.id) { index, file in DetailView(file: file, isVisible: currentIndex == index, isLandscapeMode: isLandscapeMode).tag(index) } }
                .tabViewStyle(.page(indexDisplayMode: .never)).ignoresSafeArea().onChange(of: currentIndex) { _ in withAnimation { isLandscapeMode = false } }
            
            HStack {
                Text("\(currentIndex + 1) / \(files.count)").font(.headline).foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 8).background(Color.black.opacity(0.6)).cornerRadius(20)
                if files.indices.contains(currentIndex) && files[currentIndex].isVideo { Button(action: { withAnimation(.easeInOut(duration: 0.3)) { isLandscapeMode.toggle() } }) { Image(systemName: isLandscapeMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").font(.system(size: 16, weight: .bold)).foregroundColor(.white).padding(10).background(Color.black.opacity(0.6)).clipShape(Circle()) }.padding(.leading, 10) }
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").font(.system(size: 30)).foregroundColor(.white.opacity(0.8)) }
            }.padding(.horizontal).padding(.top, 40)
        }
    }
}

struct DetailView: View {
    let file: SecretFile
    var isVisible: Bool
    var isLandscapeMode: Bool
    @State private var decryptedURL: URL? = nil
    @State private var isDecrypting = true
    @State private var player: AVPlayer? = nil
    @State private var scale: CGFloat = 1.0; @State private var lastScale: CGFloat = 1.0; @State private var offset: CGSize = .zero; @State private var lastOffset: CGSize = .zero; @State private var zoomAnchor: UnitPoint = .center
    var dragGesture: some Gesture { DragGesture(minimumDistance: scale > 1.0 ? 0 : 10000).onChanged { value in if isLandscapeMode { offset = CGSize(width: lastOffset.width + value.translation.height, height: lastOffset.height - value.translation.width) } else { offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height) } }.onEnded { _ in lastOffset = offset } }
    var zoomGesture: some Gesture { MagnificationGesture().onChanged { value in scale = lastScale * value }.onEnded { _ in lastScale = scale; if scale < 1.0 { withAnimation { resetZoom() } } } }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if let url = decryptedURL {
                    if file.isVideo { if let p = player { VideoPlayer(player: p).scaleEffect(scale, anchor: zoomAnchor).offset(offset).gesture(dragGesture).simultaneousGesture(zoomGesture).onTapGesture(count: 2, coordinateSpace: .local) { location in handleDoubleTap(at: location, in: geo.size) }.onChange(of: isVisible) { visible in if visible { p.play() } else { p.pause(); resetZoom() } }.onDisappear { p.pause() }.frame(width: isLandscapeMode ? geo.size.height : geo.size.width, height: isLandscapeMode ? geo.size.width : geo.size.height).rotationEffect(.degrees(isLandscapeMode ? 90 : 0)).position(x: geo.size.width / 2, y: geo.size.height / 2) } }
                    else if file.isImage { if let d = try? Data(contentsOf: url), let i = UIImage(data: d) { Image(uiImage: i).resizable().scaledToFit().scaleEffect(scale, anchor: zoomAnchor).offset(offset).gesture(dragGesture).simultaneousGesture(zoomGesture).onTapGesture(count: 2, coordinateSpace: .local) { location in handleDoubleTap(at: location, in: geo.size) }.onChange(of: isVisible) { visible in if !visible { resetZoom() } }.frame(width: isLandscapeMode ? geo.size.height : geo.size.width, height: isLandscapeMode ? geo.size.width : geo.size.height).rotationEffect(.degrees(isLandscapeMode ? 90 : 0)).position(x: geo.size.width / 2, y: geo.size.height / 2) } }
                    else if file.isPDF { PDFKitView(url: url).frame(width: geo.size.width, height: geo.size.height).position(x: geo.size.width / 2, y: geo.size.height / 2) }
                    else { Text("プレビュー非対応").foregroundColor(.white).position(x: geo.size.width / 2, y: geo.size.height / 2) }
                } else if isDecrypting { VStack { ProgressView().scaleEffect(1.5).tint(.white); Text("解読中...").foregroundColor(.white).padding(.top) }.position(x: geo.size.width / 2, y: geo.size.height / 2) }
            }
        }.onAppear { let cache = FileManagerHelper.getCacheURL(for: file); if FileManager.default.fileExists(atPath: cache.path) { setupContent(url: cache) } else { DispatchQueue.global(qos: .userInitiated).async { if KeyManager.decryptFile(inputURL: file.url, outputURL: cache) { DispatchQueue.main.async { setupContent(url: cache) } } else { DispatchQueue.main.async { isDecrypting = false } } } } }
    }
    private func setupContent(url: URL) { decryptedURL = url; isDecrypting = false; if file.isVideo { let newPlayer = AVPlayer(url: url); player = newPlayer; if isVisible { newPlayer.play() } } }
    private func handleDoubleTap(at location: CGPoint, in size: CGSize) { let viewWidth = isLandscapeMode ? size.height : size.width; let viewHeight = isLandscapeMode ? size.width : size.height; withAnimation(.spring()) { if scale == 1.0 { zoomAnchor = UnitPoint(x: location.x / viewWidth, y: location.y / viewHeight); scale = 2.5; lastScale = 2.5 } else { resetZoom() } } }
    private func resetZoom() { scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero; zoomAnchor = .center }
}

struct PDFKitView: UIViewRepresentable { let url: URL; func makeUIView(context: Context) -> PDFView { let v = PDFView(); v.document = PDFDocument(url: url); v.autoScales = true; return v }; func updateUIView(_ uiView: PDFView, context: Context) {} }
