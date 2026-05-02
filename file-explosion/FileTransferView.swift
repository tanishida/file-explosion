import SwiftUI
import WebRTC
import CryptoKit

class FileTransferViewModel: NSObject, ObservableObject, SignalingManagerDelegate, WebRTCManagerDelegate {
    func signalingManagerDidReceiveJoin(_ manager: SignalingManager) {
        // Only automatically create an offer if we are the Sender waiting for someone else to connect.
        // Or, we can let UI drive it explicitly. For now, if we receive join, create offer if we don't have one.
        // A better robust way:
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
    
    private var signalingManager: SignalingManager?
    private var webrtcManager: WebRTCManager?
    private var secureFileManager: SecureFileManager?
    private var secureKeyManager: SecureKeyManager?
    
    private var receivedChunks: [Data] = []
    
    override init() {
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
    
    func joinRoom() {
        guard !roomId.isEmpty else { return }
        self.errorMessage = nil
        signalingManager?.joinRoom(roomId: roomId)
    }
    
    func joinRoomAndOffer() {
        guard !roomId.isEmpty else { return }
        self.errorMessage = nil
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
        }
    }
    
    func webRTCManager(_ manager: WebRTCManager, didReceiveMessage message: String) {
        if let data = message.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           dict["type"] as? String == "metadata" {
            DispatchQueue.main.async {
                self.totalDataSize = dict["totalSize"] as? Int ?? 0
                self.receivedFileName = dict["fileName"] as? String ?? "received_file"
                self.receivedChunks.removeAll()
                self.receivedDataSize = 0
                self.isReceiving = true
                self.receivedFileUrl = nil
            }
        }
    }
    
    func webRTCManager(_ manager: WebRTCManager, didReceiveData data: Data) {
        DispatchQueue.main.async {
            self.isReceiving = true
            self.receivedChunks.append(data)
            self.receivedDataSize += data.count
            
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.finishReceiving), object: nil)
            
            if self.totalDataSize > 0 && self.receivedDataSize >= self.totalDataSize {
                self.finishReceiving()
            } else {
                self.perform(#selector(self.finishReceiving), with: nil, afterDelay: 3.0)
            }
        }
    }
    
    @objc private func finishReceiving() {
        self.isReceiving = false
        // Reassemble and decrypt
        if let secureFileManager = self.secureFileManager {
            do {
                let finalData = try secureFileManager.reassembleAndDecrypt(chunks: self.receivedChunks)
                
                // Directly encrypt and place it into the app's secret directory
                let originalExtension = (self.receivedFileName as NSString).pathExtension
                let finalExtension = originalExtension.isEmpty ? "data" : originalExtension
                let newSecureURL = FileManagerHelper.generateNewFileURL(originalExtension: finalExtension)
                
                let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dat")
                try finalData.write(to: tempUrl)
                
                KeyManager.createAndSaveKey()
                _ = KeyManager.encryptFile(inputURL: tempUrl, outputURL: newSecureURL)
                try? FileManager.default.removeItem(at: tempUrl)
                
                self.receivedFileUrl = newSecureURL
                
                // Fire a notification to ContentView that files changed
                NotificationCenter.default.post(name: Notification.Name("P2PFileReceived"), object: nil)
            } catch {
                print("Failed to reassemble or decrypt: \(error)")
            }
        }
        self.receivedChunks.removeAll()
        self.receivedDataSize = 0
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
        guard let data = try? Data(contentsOf: url),
              let secureFileManager = self.secureFileManager,
              let webrtcManager = self.webrtcManager else { return }
        
        self.isSending = true
        self.sendProgress = 0.0
        self.receivedFileUrl = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let chunks = try secureFileManager.encryptAndChunk(data: data)
                let totalSize = chunks.reduce(0) { $0 + $1.count }
                
                let metadata: [String: Any] = [
                    "type": "metadata",
                    "fileName": url.lastPathComponent,
                    "totalSize": totalSize
                ]
                if let metaJSON = try? JSONSerialization.data(withJSONObject: metadata),
                   let metaString = String(data: metaJSON, encoding: .utf8) {
                    webrtcManager.sendMessage(metaString)
                }
                
                var sentSize = 0
                for chunk in chunks {
                    // Throttle if the DataChannel buffer gets too large (e.g. > 1MB)
                    while webrtcManager.bufferedAmount > 1024 * 1024 {
                        Thread.sleep(forTimeInterval: 0.05)
                        if self.connectionState != .connected && self.connectionState != .completed {
                            throw NSError(domain: "WebRTC", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection lost"])
                        }
                    }
                    
                    webrtcManager.sendData(chunk)
                    sentSize += chunk.count
                    let progress = Double(sentSize) / Double(totalSize)
                    DispatchQueue.main.async {
                        self.sendProgress = progress
                    }
                    Thread.sleep(forTimeInterval: 0.005)
                }
                
                DispatchQueue.main.async {
                    self.isSending = false
                    self.sendProgress = 1.0
                }
            } catch {
                print("Failed to encrypt and split data: \(error)")
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
    @State private var showFilePicker = false
    @State private var transferMode: TransferMode = .send
    
    enum TransferMode {
        case send
        case receive
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("モード", selection: $transferMode) {
                    Text("送信(送る)").tag(TransferMode.send)
                    Text("受信(受け取る)").tag(TransferMode.receive)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                if transferMode == .send {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. Room IDを設定して待機")
                        HStack {
                            TextField("Room ID", text: $viewModel.roomId)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Button("待機") {
                                viewModel.joinRoom()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.roomId.isEmpty || viewModel.isConnected)
                        }
                        
                        Text("2. 相手が接続したらファイルを選択")
                        if viewModel.isConnected {
                            Button("ファイルを送信") {
                                showFilePicker = true
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(10)
                        } else {
                            Text("未接続...")
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
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. 相手のRoom IDを入力して接続")
                        HStack {
                            TextField("Room ID", text: $viewModel.roomId)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Button("接続") {
                                viewModel.joinRoomAndOffer()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.roomId.isEmpty || viewModel.isConnected)
                        }
                        
                        Text("2. 受信待機")
                        if viewModel.isConnected {
                            Text("接続完了。ファイルを受信できます。")
                                .foregroundColor(.green)
                        } else {
                            Text("未接続...")
                                .foregroundColor(.secondary)
                        }
                        
                        if viewModel.isReceiving {
                            ProgressView("受信中... \(viewModel.receivedDataSize) bytes")
                        }
                        
                        if viewModel.isReceiving && viewModel.totalDataSize > 0 {
                            ProgressView("受信中...", value: Double(viewModel.receivedDataSize), total: Double(viewModel.totalDataSize))
                                .progressViewStyle(.linear)
                                .padding(.top, 8)
                            Text("\(Int((Double(viewModel.receivedDataSize) / Double(viewModel.totalDataSize)) * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if viewModel.isReceiving {
                            ProgressView("受信中... \(viewModel.receivedDataSize) bytes")
                        }
                        
                        if let receivedUrl = viewModel.receivedFileUrl {
                            Text("受信完了!")
                                .foregroundColor(.green)
                            Text("アプリ内に保存されました:")
                                .font(.caption)
                            Text(viewModel.receivedFileName)
                                .font(.caption)
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
        .sheet(isPresented: $showFilePicker) {
            SecretFilePickerView { selectedFile in
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + selectedFile.fileExtension)
                if KeyManager.decryptFile(inputURL: selectedFile.url, outputURL: tempURL) {
                    viewModel.sendFile(url: tempURL)
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }
        }
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
