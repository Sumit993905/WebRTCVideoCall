//
//  WebRTCManager.swift
//  WebRTCVideoCall
//
//  Created by Sumit Raj Chingari on 02/02/26.
//

import WebRTC
import Foundation
import Combine

final class WebRTCService: NSObject,ObservableObject {
    
    
    // MARK: - Media
    private var videoSource: RTCVideoSource?
    private var videoCapturer: RTCCameraVideoCapturer?
    private var capturer: RTCCameraVideoCapturer?
    private var localAudioTrack: RTCAudioTrack?
    @Published var localVideoTrack: RTCVideoTrack?
    @Published var remoteVideoTrack: RTCVideoTrack?



    // MARK: - Properties
    private let factory: RTCPeerConnectionFactory
    private let peerConnection: RTCPeerConnection
    private let signaling: SignalingService

    // MARK: - Init
    init(signaling: SignalingService) {

        RTCInitializeSSL()
        print("🔐 [WebRTC] SSL initialized")

        self.factory = RTCPeerConnectionFactory()
        self.signaling = signaling

        // --- RTC Configuration
        let config = RTCConfiguration()
        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
        ]
        config.sdpSemantics = .unifiedPlan
        print("🌍 [WebRTC] ICE configured")

        // --- Media Constraints (IMPORTANT)
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: [
                "DtlsSrtpKeyAgreement": "true"
            ]
        )

        guard let pc = factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: nil
        ) else {
            fatalError("❌ [WebRTC] Failed to create PeerConnection")
        }

        self.peerConnection = pc

        super.init()

        self.signaling.delegate = self
        self.peerConnection.delegate = self

        print("🤝 [WebRTC] PeerConnection ready")
    }

    // MARK: - Public
    func startCall() {
        print("📞 [WebRTC] startCall")
        signaling.connect()
        startLocalMedia()   // 👈 ADD THIS
        createOffer()
    }

    
    func startLocalMedia() {
        print("🎥🎙 [WebRTC] Starting local media")

        // ---- Audio
        let audioSource = factory.audioSource(with: nil)
        localAudioTrack = factory.audioTrack(
            with: audioSource,
            trackId: "audio0"
        )

        if let audioTrack = localAudioTrack {
            peerConnection.add(
                audioTrack,
                streamIds: ["stream0"]
            )
            print("🎙 [WebRTC] Audio track added")
        }

        // ---- Video
        videoSource = factory.videoSource()
        videoCapturer = RTCCameraVideoCapturer(delegate: videoSource!)

        localVideoTrack = factory.videoTrack(
            with: videoSource!,
            trackId: "video0"
        )

        if let videoTrack = localVideoTrack {
            peerConnection.add(
                videoTrack,
                streamIds: ["stream0"]
            )
            print("🎥 [WebRTC] Video track added")
        }

        startCameraCapture()
    }

    
    private func startCameraCapture() {
        guard
            let capturer = videoCapturer,
            let device = RTCCameraVideoCapturer.captureDevices()
                .first(where: { $0.position == .front }),
            let format = device.formats
                .sorted(by: {
                    CMVideoFormatDescriptionGetDimensions($0.formatDescription).width <
                    CMVideoFormatDescriptionGetDimensions($1.formatDescription).width
                }).last,
            let fpsRange = format.videoSupportedFrameRateRanges.first
        else {
            print("❌ [WebRTC] Camera setup failed")
            return
        }

        capturer.startCapture(
            with: device,
            format: format,
            fps: Int(fpsRange.maxFrameRate)
        )

        print("▶️ [WebRTC] Camera capture started")
    }


    // MARK: - Offer
    private func createOffer() {
        print("📝 [WebRTC] Creating OFFER")

        let offerConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )

        peerConnection.offer(for: offerConstraints) { [weak self] offer, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ [WebRTC] Offer error:", error)
                return
            }

            guard let offer = offer else {
                print("❌ [WebRTC] Offer is nil")
                return
            }

            self.peerConnection.setLocalDescription(offer) { error in
                if let error = error {
                    print("❌ [WebRTC] setLocalDescription error:", error)
                    return
                }

                print("📌 [WebRTC] Local OFFER set")

                self.signaling.send([
                    "type": "offer",
                    "sdp": offer.sdp
                ])
            }
        }
    }
    
    // MARK: - End Call (CLEANUP)
    func endCall() {
        print("🛑 [WebRTC] endCall started")

        // 1️⃣ Stop camera
        if let capturer = capturer {
            capturer.stopCapture {
                print("🎥 [WebRTC] Camera stopped")
            }
        }

        // 2️⃣ Remove local tracks from PeerConnection
        peerConnection.senders.forEach { sender in
            if let track = sender.track {
                print("➖ [WebRTC] Removing track:", track.kind)
            }
            peerConnection.removeTrack(sender)
        }

        // 3️⃣ Close PeerConnection
        peerConnection.close()
        print("🔌 [WebRTC] PeerConnection closed")

        // 4️⃣ Reset published tracks (UI auto update)
        DispatchQueue.main.async {
            self.localVideoTrack = nil
            self.remoteVideoTrack = nil
        }

        // 5️⃣ Reset local references
        videoSource = nil
        capturer = nil
        localVideoTrack = nil
        localAudioTrack = nil

        print("✅ [WebRTC] endCall completed")
    }

}
extension WebRTCService: SignalingServiceDelegate {

    func didReceiveOffer(_ sdp: String) {
        print("📥 [WebRTC] OFFER received")

        let desc = RTCSessionDescription(type: .offer, sdp: sdp)

        peerConnection.setRemoteDescription(desc) { [weak self] error in
            if let error = error {
                print("❌ [WebRTC] setRemoteDescription error:", error)
                return
            }

            print("📌 [WebRTC] Remote OFFER set")
            self?.createAnswer()
        }
    }

    private func createAnswer() {
        print("📝 [WebRTC] Creating ANSWER")

        let answerConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )

        peerConnection.answer(for: answerConstraints) { [weak self] answer, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ [WebRTC] Answer error:", error)
                return
            }

            guard let answer = answer else {
                print("❌ [WebRTC] Answer is nil")
                return
            }

            self.peerConnection.setLocalDescription(answer) { error in
                if let error = error {
                    print("❌ [WebRTC] setLocalDescription error:", error)
                    return
                }

                print("📌 [WebRTC] Local ANSWER set")

                self.signaling.send([
                    "type": "answer",
                    "sdp": answer.sdp
                ])
            }
        }
    }

    func didReceiveAnswer(_ sdp: String) {
        print("📥 [WebRTC] ANSWER received")

        let desc = RTCSessionDescription(type: .answer, sdp: sdp)

        peerConnection.setRemoteDescription(desc) { error in
            if let error = error {
                print("❌ [WebRTC] setRemoteDescription error:", error)
            } else {
                print("📌 [WebRTC] Remote ANSWER set")
            }
        }
    }

    func didReceiveIceCandidate(_ dict: [String: Any]) {
        print("🌐 [WebRTC] ICE received")

        guard
            let candidateSDP = dict["candidate"] as? String,
            let sdpMLineIndex = dict["sdpMLineIndex"] as? Int32
        else {
            print("❌ [WebRTC] Invalid ICE candidate")
            return
        }

        let sdpMid = dict["sdpMid"] as? String

        let candidate = RTCIceCandidate(
            sdp: candidateSDP,
            sdpMLineIndex: sdpMLineIndex,
            sdpMid: sdpMid
        )

        peerConnection.add(candidate)
    }
}
extension WebRTCService: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        
    }
    

    func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didGenerate candidate: RTCIceCandidate
    ) {
        print("🌐 [WebRTC] ICE generated")

        signaling.send([
            "type": "ice-candidate",
            "candidate": [
                "candidate": candidate.sdp,
                "sdpMLineIndex": candidate.sdpMLineIndex,
                "sdpMid": candidate.sdpMid ?? ""
            ]
        ])
    }

    func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd rtpReceiver: RTCRtpReceiver,
        streams: [RTCMediaStream]
    ) {
        if let videoTrack = rtpReceiver.track as? RTCVideoTrack {
            print("📺 [WebRTC] Remote VIDEO track received")
            // next step: UI render
        }

        if let audioTrack = rtpReceiver.track as? RTCAudioTrack {
            print("🔊 [WebRTC] Remote AUDIO track received")
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("🔄 [WebRTC] Signaling state:", stateChanged.rawValue)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("❄️ [WebRTC] ICE state:", newState.rawValue)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("📡 [WebRTC] ICE gathering:", newState.rawValue)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
