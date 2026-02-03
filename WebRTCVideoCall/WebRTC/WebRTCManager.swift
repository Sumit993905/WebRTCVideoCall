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

    // MARK: - UI Bindings
    @Published var localVideoTrack: RTCVideoTrack?
    @Published var remoteVideoTrack: RTCVideoTrack?

    // MARK: - Core
    private let signaling: SignalingClient
    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection!

    private var videoCapturer: RTCCameraVideoCapturer?

    // MARK: - State
    private(set) var side: CallSide = .none
    private(set) var sdpState: SDPFlowState = .idle

    private var pendingICE: [RTCIceCandidate] = []
    private var remoteUserId: String?

    // MARK: - Init
    init(signaling: SignalingClient) {
        self.signaling = signaling

        RTCInitializeSSL()
        factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )

        super.init()
        setupPeerConnection()
        bindSignaling()
        print("🤝 [WebRTC] PeerConnection ready")
    }

    // MARK: - PeerConnection
    private func setupPeerConnection() {
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
        ]

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        peerConnection = factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        )
    }

    // MARK: - Signaling Bind
    private func bindSignaling() {
        signaling.onEvent = { [weak self] event in
            guard let self else { return }

            switch event {

            case .incomingCall(let from):
                self.remoteUserId = from
                print("📲 Incoming call from \(from)")

            case .callAccepted(let from):
                self.remoteUserId = from
                print("✅ Call accepted by \(from)")
                self.createAndSendOffer()

            case .offerReceived(let sdp, let from):
                self.remoteUserId = from
                self.handleRemoteOffer(sdp)

            case .answerReceived(let sdp):
                self.handleRemoteAnswer(sdp)

            case .iceReceived(let candidate):
                self.handleRemoteICE(candidate)

            case .callEnded:
                self.endCall()

            default:
                break
            }
        }
    }

    // MARK: - Call Flow
    func startCallAsSender(to userId: String) {
        guard side == .none else { return }

        side = .sender
        remoteUserId = userId
        startLocalMedia()

        print("📞 Sender started call → \(userId)")
        signaling.startCall(to: userId)
    }

    func acceptIncomingCall() {
        guard side == .none, let remoteUserId else { return }

        side = .receiver
        startLocalMedia()

        print("✅ Receiver accepted call")
        signaling.acceptCall(from: remoteUserId)
    }

    // MARK: - Offer / Answer
    private func createAndSendOffer() {
        guard side == .sender, let remoteUserId else { return }

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )

        Task {
            do {
                let offer = try await peerConnection.offer(for: constraints)
                try await peerConnection.setLocalDescription(offer)
                sdpState = .localOfferSet
                signaling.sendOffer(to: remoteUserId, sdp: offer.sdp)
                print("📤 OFFER sent")
            } catch {
                print("❌ Failed to create/send OFFER: \(error)")
                return
            }
        }
    }

    private func handleRemoteOffer(_ sdp: String) {
        guard side == .receiver else { return }

        Task {
            do {
                let offer = RTCSessionDescription(type: .offer, sdp: sdp)
                try await peerConnection.setRemoteDescription(offer)
                sdpState = .remoteOfferSet
                print("📥 OFFER received")
                await createAndSendAnswer()
            } catch {
                print("❌ Failed to handle remote OFFER: \(error)")
                return
            }
        }
    }

    private func createAndSendAnswer() async {
        guard side == .receiver, let remoteUserId else { return }

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )

        do {
            let answer = try await peerConnection.answer(for: constraints)
            try await peerConnection.setLocalDescription(answer)
            sdpState = .stable
            signaling.sendAnswer(to: remoteUserId, sdp: answer.sdp)
            flushICE()
            print("📤 ANSWER sent")
        } catch {
            print("❌ Failed to create/send ANSWER: \(error)")
            return
        }
    }

    private func handleRemoteAnswer(_ sdp: String) {
        guard side == .sender else { return }

        Task {
            do {
                let answer = RTCSessionDescription(type: .answer, sdp: sdp)
                try await peerConnection.setRemoteDescription(answer)
                sdpState = .stable
                flushICE()
                print("📥 ANSWER received")
            } catch {
                print("❌ Failed to handle remote ANSWER: \(error)")
                return
            }
        }
    }

    // MARK: - ICE
    private func handleRemoteICE(_ candidate: RTCIceCandidate) {
        if sdpState == .stable {
            peerConnection.add(candidate)
        } else {
            pendingICE.append(candidate)
            print("🧊 ICE queued")
        }
    }

    private func flushICE() {
        pendingICE.forEach { peerConnection.add($0) }
        pendingICE.removeAll()
        print("❄️ ICE flushed")
    }

    // MARK: - Media
    private func startLocalMedia() {

        // Audio
        let audioTrack = factory.audioTrack(
            with: factory.audioSource(with: nil),
            trackId: "audio0"
        )
        peerConnection.add(audioTrack, streamIds: ["stream0"])

        // Video
        let videoSource = factory.videoSource()
        let videoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
        localVideoTrack = videoTrack
        peerConnection.add(videoTrack, streamIds: ["stream0"])

        videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        startCameraCapture()
        print("🎥🎙 Local media started")
    }

    private func startCameraCapture() {
        guard
            let device = RTCCameraVideoCapturer.captureDevices()
                .first(where: { $0.position == .front }),
            let format = RTCCameraVideoCapturer.supportedFormats(for: device)
                .sorted(by: {
                    $0.formatDescription.dimensions.width >
                    $1.formatDescription.dimensions.width
                }).first,
            let fps = format.videoSupportedFrameRateRanges.first?.maxFrameRate
        else { return }

        videoCapturer?.startCapture(
            with: device,
            format: format,
            fps: Int(fps)
        )
    }

    // MARK: - End Call
    func endCall() {
        peerConnection.close()
        pendingICE.removeAll()
        side = .none
        sdpState = .idle
        print("❌ Call ended")
    }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        
    }
    

    func peerConnection(
        _ pc: RTCPeerConnection,
        didGenerate candidate: RTCIceCandidate
    ) {
        guard let remoteUserId else { return }

        if sdpState == .stable {
            signaling.sendICE(to: remoteUserId, candidate: candidate)
        } else {
            pendingICE.append(candidate)
        }
    }

    /// ✅ Unified Plan correct callback
    func peerConnection(
        _ pc: RTCPeerConnection,
        didAdd rtpReceiver: RTCRtpReceiver,
        streams: [RTCMediaStream]
    ) {
        guard
            let track = rtpReceiver.track as? RTCVideoTrack
        else { return }

        remoteVideoTrack = track
        print("📺 Remote video track attached")
    }

    // unused
    func peerConnection(_ pc: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ pc: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ pc: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
