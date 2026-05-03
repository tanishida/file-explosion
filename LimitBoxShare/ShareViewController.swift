import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    
    private let appGroupID = "group.com.kawase.hiroaki.limitbox"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.processSharedItems()
        }
    }
    
    private func processSharedItems() {
        guard let extensionContext = self.extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            completeRequest()
            return
        }
        
        let dispatchGroup = DispatchGroup()
        
        for item in inputItems {
            guard let attachments = item.attachments else { continue }
            
            for provider in attachments {
                dispatchGroup.enter()
                
                // 画像として直接読み込める場合（Twitter等）
                if provider.canLoadObject(ofClass: UIImage.self) {
                    provider.loadObject(ofClass: UIImage.self) { [weak self] (image, error) in
                        if let uiImage = image as? UIImage, let data = uiImage.jpegData(compressionQuality: 1.0) {
                            self?.saveDataToSharedContainer(data: data, extensionString: "jpg")
                            dispatchGroup.leave()
                        } else {
                            self?.fallbackToDataLoading(provider: provider, dispatchGroup: dispatchGroup)
                        }
                    }
                } else {
                    self.fallbackToDataLoading(provider: provider, dispatchGroup: dispatchGroup)
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            self.completeRequest()
        }
    }
    
    private func fallbackToDataLoading(provider: NSItemProvider, dispatchGroup: DispatchGroup) {
        // 1. 動画の判定
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            let movieType = provider.registeredTypeIdentifiers.first {
                UTType($0)?.conforms(to: .movie) == true
            } ?? UTType.movie.identifier
            
            provider.loadFileRepresentation(forTypeIdentifier: movieType) { [weak self] (url, error) in
                defer { dispatchGroup.leave() }
                guard let sourceURL = url, error == nil else {
                    print("動画の読み込みに失敗しました: \(String(describing: error))")
                    return
                }
                
                var ext = sourceURL.pathExtension
                if ext.isEmpty {
                    if let utType = UTType(movieType), let prefExt = utType.preferredFilenameExtension {
                        ext = prefExt
                    } else {
                        ext = "mp4" // 動画のデフォルト拡張子
                    }
                }
                self?.saveToSharedContainer(sourceURL: sourceURL, forceExtension: ext)
            }
            
        // 2. 画像の判定 (UTType.image)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let imageType = provider.registeredTypeIdentifiers.first {
                UTType($0)?.conforms(to: .image) == true
            } ?? UTType.image.identifier
            
            provider.loadDataRepresentation(forTypeIdentifier: imageType) { [weak self] (data, error) in
                if let data = data, error == nil {
                    // 拡張子を決定
                    var ext = "jpg"
                    if let utType = UTType(imageType), let prefExt = utType.preferredFilenameExtension {
                        ext = prefExt
                    }
                    self?.saveDataToSharedContainer(data: data, extensionString: ext)
                    dispatchGroup.leave()
                } else {
                    // フォールバック
                    provider.loadItem(forTypeIdentifier: imageType, options: nil) { (item, error) in
                        defer { dispatchGroup.leave() }
                        if let url = item as? URL, let fallbackData = try? Data(contentsOf: url) {
                            var ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                            self?.saveDataToSharedContainer(data: fallbackData, extensionString: ext)
                        } else if let image = item as? UIImage, let fallbackFromImage = image.jpegData(compressionQuality: 1.0) {
                            self?.saveDataToSharedContainer(data: fallbackFromImage, extensionString: "jpg")
                        } else if let fallbackData = item as? Data {
                            self?.saveDataToSharedContainer(data: fallbackData, extensionString: "jpg")
                        }
                    }
                }
            }
            
        // 3. Web URLからの共有
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) && !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (item, error) in
                defer { dispatchGroup.leave() }
                if let url = item as? URL {
                    let ext = url.pathExtension.lowercased()
                    // 動画や画像への直リンクだった場合
                    if ["jpg", "jpeg", "png", "gif", "mp4", "mov"].contains(ext) {
                        if let data = try? Data(contentsOf: url) {
                            self?.saveDataToSharedContainer(data: data, extensionString: url.pathExtension)
                        }
                    } else {
                        // URLをテキスト形式で保存（任意）
                        if let data = url.absoluteString.data(using: .utf8) {
                            self?.saveDataToSharedContainer(data: data, extensionString: "txt")
                        }
                    }
                }
            }
            
        // 4. その他のファイル (PDFやZIPなど)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
            let itemType = provider.registeredTypeIdentifiers.first { UTType($0) != nil } ?? UTType.item.identifier
            provider.loadFileRepresentation(forTypeIdentifier: itemType) { [weak self] (url, error) in
                defer { dispatchGroup.leave() }
                guard let sourceURL = url, error == nil else { return }
                
                var ext = sourceURL.pathExtension
                if ext.isEmpty {
                    if let utType = UTType(itemType), let prefExt = utType.preferredFilenameExtension {
                        ext = prefExt
                    } else {
                        ext = "data"
                    }
                }
                self?.saveToSharedContainer(sourceURL: sourceURL, forceExtension: ext)
            }
        } else {
            dispatchGroup.leave()
        }
    }
    
    private func saveDataToSharedContainer(data: Data, extensionString: String) {
        let fileManager = FileManager.default
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }
        
        let inboxURL = containerURL.appendingPathComponent("Inbox", isDirectory: true)
        if !fileManager.fileExists(atPath: inboxURL.path) {
            try? fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        }
        
        let fileName = UUID().uuidString + "." + extensionString
        let destinationURL = inboxURL.appendingPathComponent(fileName)
        
        do {
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            print("データの保存中にエラーが発生しました: \(error)")
        }
    }
    
    private func saveToSharedContainer(sourceURL: URL, forceExtension: String) {
        let fileManager = FileManager.default
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }
        
        let inboxURL = containerURL.appendingPathComponent("Inbox", isDirectory: true)
        if !fileManager.fileExists(atPath: inboxURL.path) {
            try? fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        }
        
        let destinationURL = inboxURL.appendingPathComponent(UUID().uuidString + "." + forceExtension)
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }
        
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            print("ファイルのコピー中エラー: \(error)")
        }
    }
    
    private func completeRequest() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
