import Foundation

protocol SignalingManagerDelegate: AnyObject {
    func signalingManager(_ manager: SignalingManager, didReceiveOffer offer: [String: Any])
    func signalingManager(_ manager: SignalingManager, didReceiveAnswer answer: [String: Any])
    func signalingManager(_ manager: SignalingManager, didReceiveIceCandidate candidate: [String: Any])
    func signalingManagerDidConnect(_ manager: SignalingManager)
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
        let message: [String: Any] = ["type": "join", "roomId": roomId]
        self.sendRawMessage(message)
    }
    
    func sendOffer(offer: [String: Any], roomId: String) {
        let message: [String: Any] = ["type": "offer", "sdp": offer, "roomId": roomId]
        self.sendRawMessage(message)
    }
    
    func sendAnswer(answer: [String: Any], roomId: String) {
        let message: [String: Any] = ["type": "answer", "sdp": answer, "roomId": roomId]
        self.sendRawMessage(message)
    }
    
    func sendIceCandidate(candidate: [String: Any], roomId: String) {
        let message: [String: Any] = ["type": "iceCandidate", "candidate": candidate, "roomId": roomId]
        self.sendRawMessage(message)
    }
    
    private func sendRawMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: []) else { return }
        let stringMessage = String(data: data, encoding: .utf8)!
        let webSocketMessage = URLSessionWebSocketTask.Message.string(stringMessage)
        
        self.webSocketTask?.send(webSocketMessage) { [weak self] error in
            if let error = error {
                print("Failed to send message: \(error)")
            }
        }
    }
    
    private func receiveMessage() {
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
                print("Error receiving WebSocket message: \(error)")
            }
            
            self.receiveMessage()
        }
    }
    
    private func handleIncomingMessage(text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }
        
        switch type {
        case "offer":
            if let sdp = json["sdp"] as? [String: Any] {
                self.delegate?.signalingManager(self, didReceiveOffer: sdp)
            }
        case "answer":
            if let sdp = json["sdp"] as? [String: Any] {
                self.delegate?.signalingManager(self, didReceiveAnswer: sdp)
            }
        case "iceCandidate":
            if let candidate = json["candidate"] as? [String: Any] {
                self.delegate?.signalingManager(self, didReceiveIceCandidate: candidate)
            }
        default:
            break
        }
    }
    
    func disconnect() {
        self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
    }
}
