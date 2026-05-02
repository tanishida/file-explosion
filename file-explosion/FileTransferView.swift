import SwiftUI
import WebRTC
import CryptoKit

class FileTransferViewModel: NSObject, ObservableObject, SignalingManagerDelegate, WebRTCManagerDelegate {
    func signalingManagerDidReceiveJoin(_ manager: SignalingManager) {
        // Only automatically create an offer if we are the Sender waiting for someone else to connect.
        // Wait, NO, we decided only the Receiver creates an offer to prevent glare.
    }
    
    func signalingManagerDidDisconnect(_ manager: SignalingManager) {
        print("Signaling Disconnected")
    }
    
    @Published var roomId: String = ""
    @Published var connectionState: RTCIceConnectionState = .new
    @Published var isConnected = false
    @Published var isReceiving = false
    @Published var receivedDataSize: Int = 0
    @Published var totalDataSize: Int = 0
    @Published var receivedFileUrl: URL?
    @Published var receivedFileName: String = ""
    @Published var isSending: Bool = false
    @Published var sendProgress: Double = 0.0
    @Published var errorMessage: String?
    @Published var isWaitingForPeer: Bool = false
    
    private var signalingManager: SignalingManager?
    private var webrtcManager: WebRTCManager?
    private var secureFileManager: SecureFileManager?
    private var secureKeyManager: SecureKeyManager?
    
    private let receiveQueue = DispatchQueue(label: "com.limitbox.receiveQueue")
    private var tempReceiveURL: URL?
    private var receiveFileHandle: FileHandle?
    private var internalReceivedDataSize: Int = 0
    private var lastReceiveUIUpdateTime: TimeInterval = 0
    private var finishReceiveWorkItem: DispatchWorkItem?
    
    override init() {
        self.roomId = DeviceManager.shared.myDeviceId
        self.secureKeyManager = SecureKeyManager()
        if let keyManager = self.secureKeyManager {
            self.secureFileManager = SecureFileManager(keyManager: keyManager)
        }
        super.init()
    }
    
    func startSignaling() {
        // Setup Signaling with configurable URL
        let defaultUrl = "wss://echo.websocket.events" // Reverted back to a safe default placeholder since user is using an environment variable
        let envUrl = ProcessInfo.processInfo.environment["SIGNALING_SERVER_URL"]
        let plistUrl = Bundle.main.object(forInfoDictionaryKey: "SIGNALING_SERVER_URL") as? String
        
        let urlString = envUrl ?? plistUrl ?? defaultUrl
        
        guard let url = URL(string: urlString) else { return }
        self.signalingManager = SignalingManager(url: url)
        self.signalingManager?.delegate = self
        self.signalingManager?.connect()
        
        self.webrtcManager = WebRTCManager()
        self.webrtcManager?.delegate = self
        self.webrtcManager?.setupConnection()
    }
    
    func disconnect() {
        signalingManager?.disconnect()
    }
    
    func resetRoomId() {
        self.roomId = DeviceManager.shared.myDeviceId
    }
    
    func joinRoom() {
        guard !roomId.isEmpty else { return }
        self.errorMessage = nil
        self.isWaitingForPeer = true
        signalingManager?.joinRoom(roomId: roomId)
    }
    
    func joinRoomAndOffer() {
        guard !roomId.isEmpty else { return }
        self.errorMessage = nil
        self.isWaitingForPeer = true
        signalingManager?.joinRoom(roomId: roomId)
        
        // As the initiator (Receiver side connecting to Sender side), create offer shortly after joining
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.webrtcManager?.createOffer()
        }
    }
    
    // MARK: - SignalingManagerDelegate
    func signalingManager(_ manager: SignalingManager, didReceiveError errorMessage: String) {
        // Show error message on UI, but ignore if WebRTC is already connected
        if !self.isConnected {
            self.errorMessage = errorMessage
        }
    }
    
    func signalingManager(_ manager: SignalingManager, didReceiveOffer offer: [String: Any], publicKey: String?) {
        if let pubKeyStr = publicKey {
            try? secureKeyManager?.deriveSharedKey(from: pubKeyStr)
        }
        let sdp = RTCSessionDescription(type: .offer, sdp: offer["sdp"] as? String ?? "")
        webrtcManager?.handleReceivedOffer(sdp)
    }
    
    func signalingManager(_ manager: SignalingManager, didReceiveAnswer answer: [String: Any], publicKey: String?) {
        if let pubKeyStr = publicKey {
            try? secureKeyManager?.deriveSharedKey(from: pubKeyStr)
        }
        let sdp = RTCSessionDescription(type: .answer, sdp: answer["sdp"] as? String ?? "")
        webrtcManager?.handleReceivedAnswer(sdp)
    }
    
    func signalingManager(_ manager: SignalingManager, didReceiveIceCandidate candidateDict: [String: Any]) {
        let candidate = RTCIceCandidate(
            sdp: candidateDict["candidate"] as? String ?? "",
            sdpMLineIndex: candidateDict["sdpMLineIndex"] as? Int32 ?? 0,
            sdpMid: candidateDict["sdpMid"] as? String
        )
        webrtcManager?.addIceCandidate(candidate)
    }
    
    func signalingManagerDidConnect(_ manager: SignalingManager) {
        print("Signaling Connected")
    }
    
    // MARK: - WebRTCManagerDelegate
    func webRTCManager(_ manager: WebRTCManager, didChangeConnectionState state: RTCIceConnectionState) {
        DispatchQueue.main.async {
            self.connectionState = state
            self.isConnected = (state == .connected || state == .completed)
            if self.isConnected || state == .failed || state == .disconnected || state == .closed {
                self.isWaitingForPeer = false
            }
        }
    }
    
    func webRTCManager(_ manager: WebRTCManager, didReceiveMessage message: String) {
        if let data = message.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           dict["type"] as? String == "metadata" {
            DispatchQueue.main.async {
                self.totalDataSize = dict["totalSize"] as? Int ?? 0
                self.receivedFileName = dict["fileName"] as? String ?? "received_file"
                self.receivedFileUrl = nil
                self.receivedDataSize = 0
                self.isReceiving = true
            }
            receiveQueue.async {
                self.internalReceivedDataSize = 0
                let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dat")
                self.tempReceiveURL = tempUrl
                FileManager.default.createFile(atPath: tempUrl.path, contents: nil, attributes: nil)
                self.receiveFileHandle = try? FileHandle(forWritingTo: tempUrl)
            }
        }
    }
    
    func webRTCManager(_ manager: WebRTCManager, didReceiveData data: Data) {
        receiveQueue.async {
            guard let secureFileManager = self.secureFileManager,
                  let fileHandle = self.receiveFileHandle else { return }
            
            do {
                let decrypted = try secureFileManager.decrypt(chunk: data)
                try fileHandle.write(contentsOf: decrypted)
                self.internalReceivedDataSize += decrypted.count
                
                let total = self.totalDataSize
                let current = self.internalReceivedDataSize
                let isComplete = total > 0 && current >= total
                let now = Date().timeIntervalSince1970
                
                if now - self.lastReceiveUIUpdateTime > 0.1 || isComplete {
                    self.lastReceiveUIUpdateTime = now
                    
                    DispatchQueue.main.async {
                        self.isReceiving = true
                        self.receivedDataSize = current
                        self.finishReceiveWorkItem?.cancel()
                        
                        if isComplete {
                            self.processFinishedReceive()
                        } else {
                            let workItem = DispatchWorkItem { [weak self] in
                                self?.processFinishedReceive()
                            }
                            self.finishReceiveWorkItem = workItem
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
                        }
                    }
                }
            } catch {
                print("Failed to decrypt chunk: \(error)")
            }
        }
    }
    
    private func processFinishedReceive() {
        self.isReceiving = false
        // Reassemble and decrypt
        receiveQueue.async {
            try? self.receiveFileHandle?.close()
            self.receiveFileHandle = nil
            
            guard let tempUrl = self.tempReceiveURL else { return }
            self.tempReceiveURL = nil
            self.internalReceivedDataSize = 0
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                let originalExtension = (self.receivedFileName as NSString).pathExtension
                let finalExtension = originalExtension.isEmpty ? "data" : originalExtension
                let newSecureURL = FileManagerHelper.generateNewFileURL(originalExtension: finalExtension)
                
                KeyManager.createAndSaveKey()
                let success = KeyManager.encryptFile(inputURL: tempUrl, outputURL: newSecureURL)
                try? FileManager.default.removeItem(at: tempUrl)
                
                DispatchQueue.main.async {
                    if success {
                        self.receivedFileUrl = newSecureURL
                        NotificationCenter.default.post(name: Notification.Name("P2PFileReceived"), object: nil)
                    } else {
                        self.errorMessage = "ファイルの保存(暗号化)に失敗しました"
                    }
                }
            }
        }
    }
    
    func webRTCManager(_ manager: WebRTCManager, shouldSendIceCandidate candidateDict: [String: Any]) {
        // Delegate passing dictionary, not RTCIceCandidate directly
        signalingManager?.sendIceCandidate(candidate: candidateDict, roomId: roomId)
    }
    
    func webRTCManager(_ manager: WebRTCManager, shouldSendOffer offerDict: [String: Any]) {
        let pubKey = secureKeyManager?.getMyPublicKeyBase64() ?? ""
        signalingManager?.sendOffer(offer: offerDict, publicKey: pubKey, roomId: roomId)
    }
    
    func webRTCManager(_ manager: WebRTCManager, shouldSendAnswer answerDict: [String: Any]) {
        let pubKey = secureKeyManager?.getMyPublicKeyBase64() ?? ""
        signalingManager?.sendAnswer(answer: answerDict, publicKey: pubKey, roomId: roomId)
    }
    
    // MARK: - Sending files
    func sendFile(url: URL) {
        guard let secureFileManager = self.secureFileManager,
              let webrtcManager = self.webrtcManager else { return }
        
        self.isSending = true
        self.sendProgress = 0.0
        self.receivedFileUrl = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let totalSizeNumber = attrs[.size] as? NSNumber else {
                    throw NSError(domain: "WebRTC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get file size"])
                }
                
                let totalSize = totalSizeNumber.intValue
                
                let metadata: [String: Any] = [
                    "type": "metadata",
                    "fileName": url.lastPathComponent,
                    "totalSize": totalSize
                ]
                if let metaJSON = try? JSONSerialization.data(withJSONObject: metadata),
                   let metaString = String(data: metaJSON, encoding: .utf8) {
                    var success = false
                    while !success {
                        if self.connectionState != .connected && self.connectionState != .completed {
                            throw NSError(domain: "WebRTC", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection lost"])
                        }
                        success = webrtcManager.sendMessage(metaString)
                        if !success { Thread.sleep(forTimeInterval: 0.1) }
                    }
                }
                
                let fileHandle = try FileHandle(forReadingFrom: url)
                defer { try? fileHandle.close() }
                
                var sentSize = 0
                var lastUIUpdateTime = Date().timeIntervalSince1970
                let chunkSize = 16384 // 16KB
                
                var isEOF = false
                while !isEOF {
                    try autoreleasepool {
                        if self.connectionState != .connected && self.connectionState != .completed {
                            throw NSError(domain: "WebRTC", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection lost"])
                        }
                        
                        guard let chunk = try fileHandle.read(upToCount: chunkSize), !chunk.isEmpty else {
                            isEOF = true
                            return
                        }
                        
                        let encryptedChunk = try secureFileManager.encrypt(chunk: chunk)
                        
                        while webrtcManager.bufferedAmount > 2 * 1024 * 1024 {
                            Thread.sleep(forTimeInterval: 0.01)
                            if self.connectionState != .connected && self.connectionState != .completed {
                                throw NSError(domain: "WebRTC", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection lost"])
                            }
                        }
                        
                        var chunkSuccess = false
                        while !chunkSuccess {
                            if self.connectionState != .connected && self.connectionState != .completed {
                                throw NSError(domain: "WebRTC", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection lost"])
                            }
                            chunkSuccess = webrtcManager.sendData(encryptedChunk)
                            if !chunkSuccess { Thread.sleep(forTimeInterval: 0.01) }
                        }
                        
                        sentSize += chunk.count
                        let progress = Double(sentSize) / Double(totalSize)
                        
                        let now = Date().timeIntervalSince1970
                        if now - lastUIUpdateTime > 0.1 || sentSize == totalSize {
                            lastUIUpdateTime = now
                            DispatchQueue.main.async {
                                self.sendProgress = progress
                            }
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.isSending = false
                    self.sendProgress = 1.0
                }
            } catch {
                print("Failed to send data: \(error)")
                DispatchQueue.main.async {
                    self.isSending = false
                }
            }
        }
    }
}

struct FileTransferView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = FileTransferViewModel()
    @StateObject private var deviceManager = DeviceManager.shared
    @State private var showFilePicker = false
    @State private var showAddDeviceSheet = false
    @Binding var selectedFile: SecretFile?
    @Environment(\.scenePhase) var scenePhase
    
    enum TransferMode {
        case send
        case receive
    }
    
    @State private var transferMode: TransferMode = .send
    @State private var isPreparingToSend: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // My Device ID Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("あなたの端末ID:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Text(deviceManager.myDeviceId)
                            .font(.system(.subheadline, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer()
                        
                        Button {
#if os(iOS)
                            UIPasteboard.general.string = deviceManager.myDeviceId
#else
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(deviceManager.myDeviceId, forType: .string)
#endif
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
                
                Picker("モード", selection: $transferMode) {
                    Text("送信(送る)").tag(TransferMode.send)
                    Text("受信(受け取る)").tag(TransferMode.receive)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: transferMode) { _ in
                    if transferMode == .send {
                        viewModel.resetRoomId()
                    } else {
                        viewModel.roomId = ""
                    }
                }
                
                if transferMode == .send {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. 自分の端末IDで待機")
                        HStack {
                            Text("待機ID: \(viewModel.roomId)")
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            Button("待機") {
                                viewModel.joinRoom()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.roomId.isEmpty || viewModel.isConnected || viewModel.isWaitingForPeer)
                        }
                        
                        Text("2. 相手が接続したらファイルを選択")
                        if viewModel.isConnected {
                            HStack {
                                Button("ファイルを選択") {
                                    showFilePicker = true
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            if let file = selectedFile {
                                HStack(spacing: 12) {
                                    FileThumbnailView(file: file) {}
                                        .frame(width: 50, height: 50)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(file.displayName)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Text(file.fileSizeLabel)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            
                            Button(isPreparingToSend ? "準備中..." : "送信") {
                                if let file = selectedFile {
                                    isPreparingToSend = true
                                    DispatchQueue.global(qos: .userInitiated).async {
                                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + file.fileExtension)
                                        if KeyManager.decryptFile(inputURL: file.url, outputURL: tempURL) {
                                            DispatchQueue.main.async {
                                                viewModel.sendFile(url: tempURL)
                                                isPreparingToSend = false
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                                    try? FileManager.default.removeItem(at: tempURL)
                                                }
                                            }
                                        } else {
                                            DispatchQueue.main.async {
                                                isPreparingToSend = false
                                                viewModel.errorMessage = "ファイルの復号に失敗しました"
                                            }
                                        }
                                    }
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(selectedFile == nil ? Color.gray : Color.blue)
                            .cornerRadius(10)
                            .disabled(selectedFile == nil || viewModel.isSending || isPreparingToSend)
                        } else if viewModel.isWaitingForPeer {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("相手の接続を待機中...")
                                    .foregroundColor(.blue)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            Text("「待機」ボタンを押して接続をお待ちください")
                                .foregroundColor(.secondary)
                        }
                        
                        if viewModel.isSending {
                            ProgressView("送信中...", value: viewModel.sendProgress, total: 1.0)
                                .progressViewStyle(.linear)
                                .padding(.top, 8)
                            Text("\(Int(viewModel.sendProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if viewModel.sendProgress == 1.0 {
                            Text("送信完了!")
                                .foregroundColor(.green)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .onChange(of: viewModel.sendProgress) { _ in
                        if viewModel.sendProgress == 1.0 {
                            selectedFile = nil
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. 相手の端末を選択して接続")
                        
                        if !deviceManager.savedDevices.isEmpty {
                            Menu {
                                ForEach(deviceManager.savedDevices) { device in
                                    Button(device.name) {
                                        viewModel.roomId = device.deviceId
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(viewModel.roomId.isEmpty ? "保存した端末から選択" : "入力済み (変更可)")
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                }
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        
                        HStack {
                            TextField("相手の端末ID", text: $viewModel.roomId)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .disableAutocorrection(true)
#if os(iOS)
                                .autocapitalization(.none)
#endif
                            
                            Button("接続") {
                                viewModel.joinRoomAndOffer()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.roomId.isEmpty || viewModel.isConnected || viewModel.isWaitingForPeer)
                        }
                        
                        Button("+ 端末IDを新しく保存する") {
                            showAddDeviceSheet = true
                        }
                        .font(.caption)
                        .padding(.top, -4)
                        
                        Text("2. 受信待機")
                        if viewModel.isConnected {
                            Text("接続完了。ファイルを受信できます。")
                                .foregroundColor(.green)
                        } else if viewModel.isWaitingForPeer {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("相手の端末に接続中...")
                                    .foregroundColor(.blue)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            Text("「接続」ボタンを押してください")
                                .foregroundColor(.secondary)
                        }
                        
                        if viewModel.isReceiving {
                            if viewModel.totalDataSize > 0 {
                                ProgressView("受信中... \(formatBytes(viewModel.receivedDataSize)) / \(formatBytes(viewModel.totalDataSize))", value: Double(viewModel.receivedDataSize), total: Double(viewModel.totalDataSize))
                                    .progressViewStyle(.linear)
                                    .padding(.top, 8)
                                Text("\(Int((Double(viewModel.receivedDataSize) / Double(viewModel.totalDataSize)) * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                ProgressView("受信中... \(formatBytes(viewModel.receivedDataSize))")
                            }
                        }
                        
                        if let receivedUrl = viewModel.receivedFileUrl {
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.green)
                                Text("受信完了!")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Text("アプリ内に保存されました:")
                                    .font(.caption)
                                Text(viewModel.receivedFileName)
                                    .font(.caption)
                                    .bold()
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                HStack {
                    Text("Connection State: ")
                    Text("\(stateString(viewModel.connectionState))")
                        .foregroundColor(stateColor(viewModel.connectionState))
                }
                
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("閉じる") {
                        viewModel.disconnect()
                        dismiss()
                    }
                }
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .onAppear {
                viewModel.startSignaling()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                showFilePicker = false
                showAddDeviceSheet = false
            }
        }
        .sheet(isPresented: $showFilePicker) {
            SecretFilePickerView { file in
                self.selectedFile = file
            }
        }
        .sheet(isPresented: $showAddDeviceSheet) {
            AddDeviceView()
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    func stateString(_ state: RTCIceConnectionState) -> String {
        switch state {
        case .new: return "New"
        case .checking: return "Checking"
        case .connected: return "Connected"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .disconnected: return "Disconnected"
        case .closed: return "Closed"
        case .count: return "Count"
        @unknown default: return "Unknown"
        }
    }
    
    func stateColor(_ state: RTCIceConnectionState) -> Color {
        switch state {
        case .connected, .completed: return .green
        case .failed, .disconnected, .closed: return .red
        default: return .orange
        }
    }
}

struct SecretFilePickerView: View {
    @Environment(\.dismiss) var dismiss
    @State private var secretFiles: [SecretFile] = []
    @State private var selectedCategory: Int = 0
    var onSelect: (SecretFile) -> Void
    
    var filteredFiles: [SecretFile] {
        secretFiles.filter { f in
            switch selectedCategory {
            case 0: return f.isImage
            case 1: return f.isVideo
            case 2: return f.isPDF
            default: return !f.isImage && !f.isVideo && !f.isPDF
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("カテゴリ", selection: $selectedCategory) {
                    Text("写真").tag(0)
                    Text("動画").tag(1)
                    Text("PDF").tag(2)
                    Text("その他").tag(3)
                }
                .pickerStyle(.segmented)
                .padding()
                
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16)], spacing: 16) {
                        ForEach(filteredFiles) { file in
                            FileThumbnailView(file: file) {
                                onSelect(file)
                                dismiss()
                            }
                            .overlay(alignment: .bottom) {
                                Text(file.displayName)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.6))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                                    .padding(.bottom, 4)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("送信するファイルを選択")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .onAppear {
                secretFiles = FileManagerHelper.getAllSecretFiles()
            }
        }
    }
}

struct AddDeviceView: View {
    @Environment(\.dismiss) var dismiss
    @State private var deviceName: String = ""
    @State private var deviceId: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("端末情報")) {
                    TextField("端末の名前 (例: 自分のiPhone)", text: $deviceName)
                    TextField("端末ID", text: $deviceId)
#if os(iOS)
                        .autocapitalization(.none)
#endif
                        .disableAutocorrection(true)
                }
            }
            .navigationTitle("端末を保存")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        DeviceManager.shared.addSavedDevice(name: deviceName, deviceId: deviceId)
                        dismiss()
                    }
                    .disabled(deviceName.isEmpty || deviceId.isEmpty)
                }
            }
        }
    }
}
