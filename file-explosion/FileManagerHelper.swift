import Foundation

class FileManagerHelper {
    
    class StorageCleaner {
        static func clearAllTempAndCacheData() {
            let fileManager = FileManager.default
            
            let tempUrl = fileManager.temporaryDirectory
            if let tempFiles = try? fileManager.contentsOfDirectory(at: tempUrl, includingPropertiesForKeys: nil) {
                for file in tempFiles {
                    try? fileManager.removeItem(at: file)
                }
            }
            
            if let cacheUrl = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
                if let cacheFiles = try? fileManager.contentsOfDirectory(at: cacheUrl, includingPropertiesForKeys: nil) {
                    for file in cacheFiles {
                        try? fileManager.removeItem(at: file)
                    }
                }
            }
        }
    }
    
    // 📁 秘密の暗号化ファイルを保存する「絶対に消えない」専用ディレクトリ
    static var secretDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("SecretFiles")
        
        // フォルダが無ければ作る
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    // ▼ 🆕 追加：サムネイル専用の隠しディレクトリ
    static var thumbnailDirectory: URL {
        let dir = secretDirectory.appendingPathComponent(".thumbnails")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    // 🗑️ 解読したファイル（キャッシュ）を置くディレクトリ（Cachesフォルダ配下）
    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("DecryptedCache")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    // 🆕 新しく暗号化するファイルのための安全な名前（URL）を生成
    static func generateNewFileURL(originalExtension: String) -> URL {
        let fileName = UUID().uuidString + "." + originalExtension
        return secretDirectory.appendingPathComponent(fileName)
    }
    
    // 🔍 復号した一時ファイル（キャッシュ）を保存・読み込みする場所を取得
    static func getCacheURL(for file: SecretFile) -> URL {
        return cacheDirectory.appendingPathComponent(file.url.lastPathComponent)
    }
    
    // ▼ 🆕 追加：サムネイルファイルのURLを取得
    static func getThumbnailURL(for file: SecretFile) -> URL {
        return thumbnailDirectory.appendingPathComponent(file.url.lastPathComponent + ".thumb")
    }
    
    // 📥 保存されているすべての「秘密のファイル」を取得してリストにする
    static func getAllSecretFiles() -> [SecretFile] {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: secretDirectory, includingPropertiesForKeys: nil)
            // 隠しファイル（.DS_Storeなど）を除外
            let validURLs = fileURLs.filter { !$0.lastPathComponent.hasPrefix(".") }
            
            return validURLs.map { SecretFile(url: $0) }
        } catch {
            print("ファイル一覧の取得に失敗: \(error)")
            return []
        }
    }
    
    // 🧹 アプリを閉じた時などに、一時ファイル（キャッシュ）をすべて削除して証拠隠滅する
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
    
    // 🧹 tmpフォルダだけを掃除する（復号キャッシュは残す）
    static func clearTempDirectory() {
        let fileManager = FileManager.default
        let tempURL = fileManager.temporaryDirectory
        if let files = try? fileManager.contentsOfDirectory(at: tempURL, includingPropertiesForKeys: nil) {
            for file in files { try? fileManager.removeItem(at: file) }
        }
    }
    
    // 🕐 指定秒数以上前に作られた復号キャッシュだけを削除する
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
    
    // 🚨 緊急事態（自爆タイマーや初期化）用：暗号化された元データも含めて【全て】を完全に消去する
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
