import Foundation
import CryptoKit

enum SecureKeyManagerError: Error {
    case invalidBase64String
    case keyDerivationFailed
    case missingSymmetricKey
}

class SecureKeyManager {
    private let privateKey: Curve25519.KeyAgreement.PrivateKey
    private(set) var symmetricKey: SymmetricKey?
    
    init() {
        self.privateKey = Curve25519.KeyAgreement.PrivateKey()
    }
    
    /// 自身の公開鍵を抽出し、シグナリングで送れるようにBase64文字列として返す。
    func getMyPublicKeyBase64() -> String {
        return privateKey.publicKey.rawRepresentation.base64EncodedString()
    }
    
    /// 相手から受け取った公開鍵（Base64）と自身の秘密鍵を掛け合わせ、共通シークレットを導出する。
    func deriveSharedKey(from otherPartyPublicKeyBase64: String) throws {
        guard let data = Data(base64Encoded: otherPartyPublicKeyBase64) else {
            throw SecureKeyManagerError.invalidBase64String
        }
        let otherPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: data)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: otherPublicKey)
        
        let salt = "P2PFileTransferSalt".data(using: .utf8)!
        self.symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data(),
            outputByteCount: 32
        )
    }
    
    /// 保持しているSymmetricKeyを使い、AES.GCMでデータを暗号化する。
    func encrypt(data: Data) throws -> Data {
        guard let key = symmetricKey else {
            throw SecureKeyManagerError.missingSymmetricKey
        }
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw SecureKeyManagerError.keyDerivationFailed
        }
        return combined
    }
    
    /// 保持しているSymmetricKeyを使い、AES.GCMでデータを復号する。
    func decrypt(data: Data) throws -> Data {
        guard let key = symmetricKey else {
            throw SecureKeyManagerError.missingSymmetricKey
        }
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }
}
