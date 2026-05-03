import Foundation

class StorageCleaner {
    /// バックグラウンド移行時：tmpだけ全削除、復号キャッシュは10分以上前のものだけ削除
    static func clearAllTempAndCacheData() {
        FileManagerHelper.clearTempDirectory()
        FileManagerHelper.clearExpiredDecryptedCache(olderThan: 600)
    }
    
    /// 復号キャッシュを全消去（アプリ終了時など）
    static func clearDecryptedCache() {
        FileManagerHelper.clearTempCache()
    }
    
    static func clearCachesExcept(currentCacheURL: URL) {
        let fileManager = FileManager.default
        if let files = try? fileManager.contentsOfDirectory(
            at: FileManagerHelper.cacheDirectory,
            includingPropertiesForKeys: nil
        ) {
            for file in files where file.lastPathComponent != currentCacheURL.lastPathComponent {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}

class FileManagerHelper {
    
    // 📁 秘密の暗号化ファイルを保存する専用ディレクトリ
    static var secretDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("SecretFiles")
        
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    // サムネイル専用の隠しディレクトリ
    static var thumbnailDirectory: URL {
        let dir = secretDirectory.appendingPathComponent(".thumbnails")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    // 復号済みキャッシュ保存先
    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("DecryptedCache")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    static func generateNewFileURL(originalExtension: String) -> URL {
        let fileName = UUID().uuidString + "." + originalExtension
        return secretDirectory.appendingPathComponent(fileName)
    }
    
    static func getCacheURL(for file: SecretFile) -> URL {
        cacheDirectory.appendingPathComponent(file.url.lastPathComponent)
    }
    
    static func getThumbnailURL(for file: SecretFile) -> URL {
        thumbnailDirectory.appendingPathComponent(file.url.lastPathComponent + ".thumb")
    }
    
    static func getAllSecretFiles() -> [SecretFile] {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: secretDirectory, includingPropertiesForKeys: nil)
            let validURLs = fileURLs.filter { !$0.lastPathComponent.hasPrefix(".") }
            return validURLs.map { SecretFile(url: $0) }
        } catch {
            print("ファイル一覧の取得に失敗: \(error)")
            return []
        }
    }
    
    static func clearTempCache() {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for url in fileURLs {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("キャッシュの削除に失敗: \(error)")
        }
    }
    
    static func clearTempDirectory() {
        let fileManager = FileManager.default
        let tempURL = fileManager.temporaryDirectory
        if let files = try? fileManager.contentsOfDirectory(at: tempURL, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }
    }
    
    static func clearExpiredDecryptedCache(olderThan seconds: TimeInterval = 600) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        
        let cutoff = Date().addingTimeInterval(-seconds)
        for file in files {
            if let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
               let created = attrs.creationDate,
               created < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }
    
    static func clearAllPlaintextResiduals() {
        let tmp = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            files.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        clearTempCache()
    }
    
    static func deleteAllFiles() {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: secretDirectory, includingPropertiesForKeys: nil)
            for url in fileURLs {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("全ファイルの削除に失敗: \(error)")
        }
    }
}

class ShareExtensionManager {
    static let shared = ShareExtensionManager()
    
    // 指定されたApp Group ID
    private let groupIdentifier = "group.com.kawase.hiroaki.limitbox"
    
    /// メインアプリ起動時（またはアクティブ時）にInboxフォルダを検知して処理を行う
    func processSharedFiles() {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            print("App GroupのコンテナURL取得に失敗しました。")
            return
        }
        
        let inboxURL = containerURL.appendingPathComponent("Inbox")
        if !FileManager.default.fileExists(atPath: inboxURL.path) {
            return
        }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: inboxURL, includingPropertiesForKeys: nil)
            var hasProcessed = false
            
            for fileURL in files {
                if fileURL.lastPathComponent.hasPrefix(".") { continue }
                
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileURL.lastPathComponent)
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }
                
                // メモリ節約のため moveItem を使用
                try FileManager.default.moveItem(at: fileURL, to: tempURL)
                
                let ext = tempURL.pathExtension
                let finalURL = FileManagerHelper.generateNewFileURL(originalExtension: ext)
                
                let success = KeyManager.encryptFile(inputURL: tempURL, outputURL: finalURL)
                
                if success {
                    try? FileManager.default.removeItem(at: tempURL)
                    hasProcessed = true
                    print("ファイルの移動および暗号化に成功しました: \(finalURL)")
                } else {
                    print("暗号化に失敗しました")
                }
            }
            
            // 念のため、エラーで残ったファイルや処理対象外だったゴミファイルを含め、Inboxの中身を全削除してクリーンにする
            if let remainings = try? FileManager.default.contentsOfDirectory(at: inboxURL, includingPropertiesForKeys: nil) {
                for item in remainings {
                    try? FileManager.default.removeItem(at: item)
                }
            }
            
            if hasProcessed {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("FilesDidUpdate"), object: nil)
                }
            }
        } catch {
            print("Inboxファイルの処理中にエラーが発生しました: \(error)")
        }
    }
}
