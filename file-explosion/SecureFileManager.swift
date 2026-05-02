import Foundation
import CryptoKit

class SecureFileManager {
    private var secureKeyManager: SecureKeyManager
    
    // WebRTCのDataChannelでの送信に適したサイズ (例: 16KB = 16384)
    // 実際の利用では送信パケットサイズの上限を考慮して設定します
    private let chunkSize = 16384
    
    init(keyManager: SecureKeyManager) {
        self.secureKeyManager = keyManager
    }
    
    func encrypt(chunk: Data) throws -> Data {
        return try secureKeyManager.encrypt(data: chunk)
    }
    
    func decrypt(chunk: Data) throws -> Data {
        return try secureKeyManager.decrypt(data: chunk)
    }
    
    /// ファイルを暗号化してチャンクに分割する
    /// - Parameter data: 送信したい元のファイルデータ
    /// - Returns: 暗号化されたチャンクデータの配列
    func encryptAndChunk(data: Data) throws -> [Data] {
        let encryptedData = try secureKeyManager.encrypt(data: data)
        
        var chunks: [Data] = []
        var offset = 0
        let totalSize = encryptedData.count
        
        while offset < totalSize {
            let nextOffset = min(offset + chunkSize, totalSize)
            let chunk = encryptedData.subdata(in: offset..<nextOffset)
            chunks.append(chunk)
            offset = nextOffset
        }
        
        return chunks
    }
    
    /// 受け取ったチャンクを結合して復号する
    /// - Parameter chunks: 受信した暗号化チャンクデータの配列
    /// - Returns: 復号された元のファイルデータ
    func reassembleAndDecrypt(chunks: [Data]) throws -> Data {
        // すべてのチャンクを結合
        var combinedData = Data()
        for chunk in chunks {
            combinedData.append(chunk)
        }
        
        return try secureKeyManager.decrypt(data: combinedData)
    }
}
