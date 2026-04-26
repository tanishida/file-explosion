import Foundation
import UniformTypeIdentifiers

struct SecretFile: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let isImage: Bool
    let isVideo: Bool
    let isPDF: Bool
    
    init(url: URL) {
        self.url = url
        let uuidString = url.deletingPathExtension().lastPathComponent
        self.id = UUID(uuidString: uuidString) ?? UUID()
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
    
    // MARK: - 表示用プロパティ
    var displayName: String { url.deletingPathExtension().lastPathComponent }
    var fileExtension: String { url.pathExtension.uppercased() }
    var typeLabel: String {
        if isImage { return "画像" }
        if isVideo { return "動画" }
        if isPDF   { return "PDF" }
        return "ファイル"
    }
    var typeIcon: String {
        if isImage { return "photo.fill" }
        if isVideo { return "play.rectangle.fill" }
        if isPDF   { return "doc.richtext.fill" }
        return "doc.fill"
    }
    var fileSizeBytes: Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
    }
    var fileSizeLabel: String {
        let bytes = fileSizeBytes
        if bytes < 1_024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes)/1_024) }
        if bytes < 1_073_741_824 { return String(format: "%.1f MB", Double(bytes)/1_048_576) }
        return String(format: "%.1f GB", Double(bytes)/1_073_741_824)
    }
    var creationDate: Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
    }
    var creationDateLabel: String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: creationDate)
    }
}
