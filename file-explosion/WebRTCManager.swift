import Foundation
import WebRTC

protocol WebRTCManagerDelegate: AnyObject {
    func webRTCManager(_ manager: WebRTCManager, didChangeConnectionState state: RTCIceConnectionState)
    func webRTCManager(_ manager: WebRTCManager, didReceiveData data: Data)
    func webRTCManager(_ manager: WebRTCManager, shouldSendIceCandidate candidate: RTCIceCandidate)
    func webRTCManager(_ manager: WebRTCManager, shouldSendOffer offer: RTCSessionDescription)
    func webRTCManager(_ manager: WebRTCManager, shouldSendAnswer answer: RTCSessionDescription)
}

class WebRTCManager: NSObject {
    weak var delegate: WebRTCManagerDelegate?
    
    private var peerConnectionFactory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    
    override init() {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        self.peerConnectionFactory = RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
        super.init()
    }
    
    func setupConnection() {
        let config = RTCConfiguration()
        
        let stunServer = RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
        let turnServer = RTCIceServer(urlStrings: ["turn:YOUR_VPS_IP:3478"],
                                      username: "your_username",
                                      credential: "your_password")
        
        config.iceServers = [stunServer, turnServer]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        
        self.peerConnection = peerConnectionFactory.peerConnection(with: config, constraints: constraints, delegate: self)
        
        self.setupDataChannel()
    }
    
    private func setupDataChannel() {
        let config = RTCDataChannelConfiguration()
        config.isOrdered = true
        
        if let dataChannel = self.peerConnection?.dataChannel(forLabel: "fileTransferChannel", configuration: config) {
            dataChannel.delegate = self
            self.dataChannel = dataChannel
        }
    }
    
    func createOffer() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        self.peerConnection?.offer(for: constraints) { [weak self] (description, error) in
            guard let self = self, let sdp = description else { return }
            self.peerConnection?.setLocalDescription(sdp, completionHandler: { error in
                self.delegate?.webRTCManager(self, shouldSendOffer: sdp)
            })
        }
    }
    
    func handleReceivedOffer(_ offer: RTCSessionDescription) {
        self.peerConnection?.setRemoteDescription(offer, completionHandler: { [weak self] error in
            guard let self = self else { return }
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            self.peerConnection?.answer(for: constraints, completionHandler: { (description, error) in
                guard let answer = description else { return }
                self.peerConnection?.setLocalDescription(answer, completionHandler: { error in
                    self.delegate?.webRTCManager(self, shouldSendAnswer: answer)
                })
            })
        })
    }
    
    func handleReceivedAnswer(_ answer: RTCSessionDescription) {
        self.peerConnection?.setRemoteDescription(answer, completionHandler: { error in
            // Handle error if needed
        })
    }
    
    func addIceCandidate(_ candidate: RTCIceCandidate) {
        self.peerConnection?.add(candidate)
    }
    
    func sendData(_ data: Data) {
        guard let dataChannel = self.dataChannel, dataChannel.readyState == .open else {
            print("DataChannel is not open")
            return
        }
        let buffer = RTCDataBuffer(data: data, isBinary: true)
        let success = dataChannel.sendData(buffer)
        if !success {
            print("Failed to send data over DataChannel")
        }
    }
}

extension WebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async {
            self.delegate?.webRTCManager(self, didChangeConnectionState: newState)
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        self.delegate?.webRTCManager(self, shouldSendIceCandidate: candidate)
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        dataChannel.delegate = self
        self.dataChannel = dataChannel
    }
}

extension WebRTCManager: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("DataChannel state changed: \(dataChannel.readyState.rawValue)")
    }
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        DispatchQueue.main.async {
            self.delegate?.webRTCManager(self, didReceiveData: buffer.data)
        }
    }
}
