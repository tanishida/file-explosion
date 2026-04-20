import Foundation

class FileManagerHelper {
    
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
    
    // 🗑️ 解読したファイル（キャッシュ）を「一時的」に置くディレクトリ
    static var cacheDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DecryptedCache")
        
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
