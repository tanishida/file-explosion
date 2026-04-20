import Foundation
import CryptoKit
import Security

class KeyManager {
    static let keyTag = "com.deadmanswitch.encryptionkey".data(using: .utf8)!
    
    // チャンク処理用のサイズ設定（10MBずつ処理する）
    static let chunkSize = 1024 * 1024 * 10
    static let encryptedChunkSize = chunkSize + 28
    
    static func createAndSaveKey() {
        if hasKey() { return }
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data(Array($0)) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: keyTag, kSecValueData as String: keyData
        ]
        SecItemAdd(query as CFDictionary, nil)
    }
    
    static func destroyKey() {
        let query: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: keyTag]
        SecItemDelete(query as CFDictionary)
    }
    
    static func hasKey() -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: keyTag, kSecReturnData as String: true]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }
    
    private static func getKey() -> SymmetricKey? {
        let query: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: keyTag, kSecReturnData as String: true]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let keyData = item as? Data {
            return SymmetricKey(data: keyData)
        }
        return nil
    }
    
    static func encryptFile(inputURL: URL, outputURL: URL) -> Bool {
        guard let key = getKey() else { return false }
        do {
            let input = try FileHandle(forReadingFrom: inputURL)
            FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: nil)
            let output = try FileHandle(forWritingTo: outputURL)
            
            defer { try? input.close(); try? output.close() }
            
            var isEOF = false
            while !isEOF {
                try autoreleasepool {
                    if let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
                        let sealedBox = try AES.GCM.seal(chunk, using: key)
                        if let combined = sealedBox.combined {
                            try output.write(contentsOf: combined)
                        }
                    } else {
                        isEOF = true
                    }
                }
            }
            return true
        } catch {
            print("暗号化エラー: \(error)")
            return false
        }
    }
    
    static func decryptFile(inputURL: URL, outputURL: URL) -> Bool {
        guard let key = getKey() else { return false }
        do {
            let input = try FileHandle(forReadingFrom: inputURL)
            FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: nil)
            let output = try FileHandle(forWritingTo: outputURL)
            
            defer { try? input.close(); try? output.close() }
            
            var isEOF = false
            while !isEOF {
                try autoreleasepool {
                    if let chunk = try input.read(upToCount: encryptedChunkSize), !chunk.isEmpty {
                        let sealedBox = try AES.GCM.SealedBox(combined: chunk)
                        let decryptedData = try AES.GCM.open(sealedBox, using: key)
                        try output.write(contentsOf: decryptedData)
                    } else {
                        isEOF = true
                    }
                }
            }
            return true
        } catch {
            print("復号エラー: \(error)")
            return false
        }
    }
}
