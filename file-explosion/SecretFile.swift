import Foundation
import UniformTypeIdentifiers

struct SecretFile: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let isImage: Bool
    let isVideo: Bool
    let isPDF: Bool
    
    init(url: URL) {
        self.url = url
        // ランダムなIDをやめ、ファイル名から固定のIDを生成（UIの再描画を防ぐ）
        let uuidString = url.deletingPathExtension().lastPathComponent
        self.id = UUID(uuidString: uuidString) ?? UUID()
        
        // ▼ 🆕 究極の軽量化：ファイル種類の判定を「作成時の1回」だけで終わらせる！
        if let type = UTType(filenameExtension: url.pathExtension) {
            self.isImage = type.conforms(to: .image)
            self.isVideo = type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent)
            self.isPDF = type.conforms(to: .pdf)
        } else {
            self.isImage = false
            self.isVideo = false
            self.isPDF = false
        }
    }
}
