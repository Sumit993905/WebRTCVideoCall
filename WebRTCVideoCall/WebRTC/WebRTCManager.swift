import Foundation
import WebRTC
import AVFoundation
import Combine

// MARK: - Call Side
enum CallSide {
    case none
    case sender
    case receiver
}

// MARK: - SDP State
enum SDPFlowState {
    case idle
    case localOfferSet
    case remoteOfferSet
    case stable
}

@MainActor
final class WebRTCManager: NSObject, ObservableObject {
    @Published var localVideoTrack: RTCVideoTrack?
    @Published var remoteVideoTrack: RTCVideoTrack?

    private let signaling: SignalingClient
    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection!
    private var videoCapturer: RTCCameraVideoCapturer?
    
    private(set) var side: CallSide = .none
    private var remoteUserId: String?

    init(signaling: SignalingClient) {
        self.signaling = signaling
        RTCInitializeSSL()
        
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
        
        super.init()
        setupPeerConnection()
        configureAudioSession() // Zaroori setup
        bindSignaling()
    }

    private func configureAudioSession() {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        try? session.setCategory(AVAudioSession.Category.playAndRecord.rawValue, with: [.defaultToSpeaker, .allowBluetooth])
        try? session.setMode(AVAudioSession.Mode.videoChat.rawValue)
        try? session.setActive(true)
        session.unlockForConfiguration()
    }

    private func setupPeerConnection() {
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)
    }

    // Signaling events handle logic
    private func bindSignaling() {
        signaling.onEvent = { [weak self] event in
            guard let self = self else { return }
            Task { @MainActor in
                switch event {
                case .callAccepted(let from):
                    self.remoteUserId = from
                    if self.side == .sender { self.createAndSendOffer() }
                case .offerReceived(let sdp, let from):
                    self.remoteUserId = from
                    self.side = .receiver
                    self.handleRemoteOffer(sdp)
                case .answerReceived(let sdp):
                    self.handleRemoteAnswer(sdp)
                case .iceReceived(let candidate):
                    self.peerConnection.add(candidate)
                case .callEnded:
                    self.endCall()
                default: break
                }
            }
        }
    }

    func startCallAsSender(to userId: String) {
        side = .sender
        remoteUserId = userId
        startLocalMedia()
        signaling.startCall(to: userId)
    }

    func acceptIncomingCall() {
        guard let remoteUserId else { return }
        side = .receiver
        startLocalMedia()
        signaling.acceptCall(from: remoteUserId)
    }

    private func createAndSendOffer() {
        Task {
            let constraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"], optionalConstraints: nil)
            let offer = try await peerConnection.offer(for: constraints)
            try await peerConnection.setLocalDescription(offer)
            signaling.sendOffer(to: remoteUserId!, sdp: offer.sdp)
        }
    }

    private func handleRemoteOffer(_ sdp: String) {
        Task {
            let offer = RTCSessionDescription(type: .offer, sdp: sdp)
            try await peerConnection.setRemoteDescription(offer)
            let constraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"], optionalConstraints: nil)
            let answer = try await peerConnection.answer(for: constraints)
            try await peerConnection.setLocalDescription(answer)
            signaling.sendAnswer(to: remoteUserId!, sdp: answer.sdp)
        }
    }

    private func handleRemoteAnswer(_ sdp: String) {
        Task {
            let answer = RTCSessionDescription(type: .answer, sdp: sdp)
            try await peerConnection.setRemoteDescription(answer)
        }
    }

    private func startLocalMedia() {
        let audioTrack = factory.audioTrack(with: factory.audioSource(with: nil), trackId: "audio0")
        peerConnection.add(audioTrack, streamIds: ["stream0"])

        let videoSource = factory.videoSource()
        let videoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
        self.localVideoTrack = videoTrack
        peerConnection.add(videoTrack, streamIds: ["stream0"])

        videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        startCameraCapture()
    }

    private func startCameraCapture() {
        guard let device = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .front }),
              let format = RTCCameraVideoCapturer.supportedFormats(for: device).last,
              let fps = format.videoSupportedFrameRateRanges.first?.minFrameRate else { return }
        videoCapturer?.startCapture(with: device, format: format, fps: Int(fps))
    }

    func endCall() {
        peerConnection.close()
        side = .none
        localVideoTrack = nil
        remoteVideoTrack = nil
        setupPeerConnection() // Reset for next call
    }
}

extension WebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        
    }
    
    func peerConnection(_ pc: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let remoteUserId else { return }
        // Turant bhejo, queue mat karo
        signaling.sendICE(to: remoteUserId, candidate: candidate)
    }

    func peerConnection(_ pc: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        if let track = rtpReceiver.track as? RTCVideoTrack {
            DispatchQueue.main.async { self.remoteVideoTrack = track }
        }
    }
    // Other stubs...
    func peerConnection(_ pc: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnectionShouldNegotiate(_ pc: RTCPeerConnection) {}
    func peerConnection(_ pc: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ pc: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
}
