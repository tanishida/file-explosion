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
