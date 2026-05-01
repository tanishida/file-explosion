import Foundation
import CryptoKit

class SecureFileManager {
    // 共有鍵 (実際は鍵交換などで安全に共有された対称鍵を想定)
    private var symmetricKey: SymmetricKey
    
    // WebRTCのDataChannelでの送信に適したサイズ (例: 64KB = 65536)
    // 実際の利用では送信パケットサイズの上限を考慮して設定します
    private let chunkSize = 65536 
    
    init(key: SymmetricKey) {
        self.symmetricKey = key
    }
    
    /// ファイルを暗号化してチャンクに分割する
    /// - Parameter data: 送信したい元のファイルデータ
    /// - Returns: 暗号化されたチャンクデータの配列
    func encryptAndChunk(data: Data) throws -> [Data] {
        // 全体を一括で暗号化する以外にもチャンクごとに暗号化する方法がありますが、
        // 今回はシンプルに全体を暗号化してから分割します。
        // （巨大なファイルの場合は、ストリーム暗号やチャンクごとの暗号化が推奨されます）
        
        let sealedBox = try AES.GCM.seal(data, using: self.symmetricKey)
        guard let encryptedData = sealedBox.combined else {
            throw NSError(domain: "SecureFileManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to combine encrypted data"])
        }
        
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
        
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: self.symmetricKey)
        
        return decryptedData
    }
}
