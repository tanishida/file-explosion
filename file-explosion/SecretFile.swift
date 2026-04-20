import Foundation
import UniformTypeIdentifiers

// UI側（ContentViewやGalleryView）でファイルを扱いやすくするための構造体
struct SecretFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    
    // ▼ ファイルの拡張子から、それが画像かどうかを自動判定する
    var isImage: Bool {
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.conforms(to: .image)
        }
        return false
    }
    
    // ▼ 動画かどうかを自動判定する
    var isVideo: Bool {
        if let type = UTType(filenameExtension: url.pathExtension) {
            // .movie, .video, .audiovisualContent などを広くカバー
            return type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent)
        }
        return false
    }
    
    // ▼ PDFかどうかを自動判定する
    var isPDF: Bool {
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.conforms(to: .pdf)
        }
        return false
    }
}
