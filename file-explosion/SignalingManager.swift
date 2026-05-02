import Foundation

protocol SignalingManagerDelegate: AnyObject {
    func signalingManager(_ manager: SignalingManager, didReceiveOffer offer: [String: Any], publicKey: String?)
    func signalingManager(_ manager: SignalingManager, didReceiveAnswer answer: [String: Any], publicKey: String?)
    func signalingManager(_ manager: SignalingManager, didReceiveIceCandidate candidate: [String: Any])
    func signalingManagerDidConnect(_ manager: SignalingManager)
    func signalingManagerDidReceiveJoin(_ manager: SignalingManager)
    func signalingManagerDidDisconnect(_ manager: SignalingManager)
    func signalingManager(_ manager: SignalingManager, didReceiveError errorMessage: String)
}

class SignalingManager {
    weak var delegate: SignalingManagerDelegate?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let url: URL
    
    init(url: URL) {
        self.url = url
    }
    
    func connect() {
        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration)
        self.webSocketTask = session.webSocketTask(with: self.url)
        self.webSocketTask?.resume()
        
        self.receiveMessage()
        self.delegate?.signalingManagerDidConnect(self)
    }
    
    func joinRoom(roomId: String) {
        let message: [String: Any] = [
            "action": "join",
            "roomId": roomId
        ]
        self.sendRawMessage(message)
    }
    
    func sendOffer(offer: [String: Any], publicKey: String, roomId: String) {
        let payload: [String: Any] = [
            "type": "offer",
            "sdp": offer["sdp"] as? String ?? "",
            "publicKey": publicKey
        ]
        let message: [String: Any] = [
            "action": "send",
            "roomId": roomId,
            "payload": payload
        ]
        self.sendRawMessage(message)
    }
    
    func sendAnswer(answer: [String: Any], publicKey: String, roomId: String) {
        let payload: [String: Any] = [
            "type": "answer",
            "sdp": answer["sdp"] as? String ?? "",
            "publicKey": publicKey
        ]
        let message: [String: Any] = [
            "action": "send",
            "roomId": roomId,
            "payload": payload
        ]
        self.sendRawMessage(message)
    }
    
    func sendIceCandidate(candidate: [String: Any], roomId: String) {
        let payload: [String: Any] = [
            "type": "iceCandidate",
            "candidate": candidate
        ]
        let message: [String: Any] = [
            "action": "send",
            "roomId": roomId,
            "payload": payload
        ]
        self.sendRawMessage(message)
    }
    
    private func sendRawMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: []) else { return }
        let stringMessage = String(data: data, encoding: .utf8)!
        print("↗️ [WS送信]: \(stringMessage)")
        
        let webSocketMessage = URLSessionWebSocketTask.Message.string(stringMessage)
        
        self.webSocketTask?.send(webSocketMessage) { [weak self] error in
            if let error = error {
                print("Failed to send message: \(error)")
            }
        }
    }
    
    func receiveMessage() {
        self.webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleIncomingMessage(text: text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncomingMessage(text: text)
                    }
                @unknown default:
                    break
                }
            case .failure(let error):
                print("⚠️ [WSエラー]: WebSocketが切断されました: \(error)")
                self.delegate?.signalingManagerDidDisconnect(self)
                return
            }
            
            // Continue receiving
            self.receiveMessage()
        }
    }
    
    private func handleIncomingMessage(text: String) {
        print("↙️ [WS受信]: \(text)")
        
        guard let data = text.data(using: .utf8) else {
            print("❌ Failed to decode message data as UTF8")
            return
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            print("❌ Failed to parse JSON")
            return
        }
        
        // System errors like Internal server error
        if let message = json["message"] as? String {
            if message == "Internal server error" {
                // Ignore silently, usually just an offline peer or minor Lambda glitch
                return
            } else if let connectionId = json["connectionId"] {
                // You can handle other specific message formats if needed
            }
        }
        
        // AWS Lambdaはpayloadの中身だけを抽出して転送するように変更されたため、
        // 常に一番上の階層の `type` を確認する。
        guard let type = json["type"] as? String else {
            return
        }
        
        switch type {
        case "join":
            print("🔹 受信したメッセージのタイプ: join")
            self.delegate?.signalingManagerDidReceiveJoin(self)
        case "offer":
            print("🔹 受信したメッセージのタイプ: offer")
            // We check for String SDP directly now, but previously client also wrapped it in dictionary,
            // let's support both just in case.
            let sdpString = json["sdp"] as? String ?? (json["sdp"] as? [String: Any])?["sdp"] as? String ?? ""
            let offerDict: [String: Any] = ["type": "offer", "sdp": sdpString]
            let pubKey = json["publicKey"] as? String
            self.delegate?.signalingManager(self, didReceiveOffer: offerDict, publicKey: pubKey)
        case "answer":
            print("🔹 受信したメッセージのタイプ: answer")
            let sdpString = json["sdp"] as? String ?? (json["sdp"] as? [String: Any])?["sdp"] as? String ?? ""
            let answerDict: [String: Any] = ["type": "answer", "sdp": sdpString]
            let pubKey = json["publicKey"] as? String
            self.delegate?.signalingManager(self, didReceiveAnswer: answerDict, publicKey: pubKey)
        case "iceCandidate":
            print("🔹 受信したメッセージのタイプ: iceCandidate")
            if let candidate = json["candidate"] as? [String: Any] {
                self.delegate?.signalingManager(self, didReceiveIceCandidate: candidate)
            }
        default:
            print("⚠️ 未知のメッセージタイプを受信しました: \(type)")
            break
        }
    }
    
    func disconnect() {
        self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
        self.delegate?.signalingManagerDidDisconnect(self)
    }
}
