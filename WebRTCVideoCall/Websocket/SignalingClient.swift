import Foundation
import Combine
import WebRTC

// MARK: - Signaling Events
enum SignalingEvent {
    case connected(userId: String)
    case incomingCall(from: String)
    case callAccepted(from: String)
    case offerReceived(sdp: String, from: String)
    case answerReceived(sdp: String)
    case iceReceived(candidate: RTCIceCandidate)
    case callEnded
}


final class SignalingClient: NSObject, ObservableObject {

    // MARK: - CONFIG (YAHI NGROK URL)
    private let signalingURL = URL(
        string: "wss://maneuverable-cognatic-jaydon.ngrok-free.dev"
    )!

    // MARK: - Published
    @Published var isConnected = false
    @Published var myUserId: String?

    // MARK: - Callback
    var onEvent: ((SignalingEvent) -> Void)?

    // MARK: - Internal
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?

    // MARK: - Connect
    func connect() {
        guard socket == nil else {
            print("⚠️ [Signaling] Already connected")
            return
        }

        print("🔌 [Signaling] Connecting → \(signalingURL)")

        session = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: .main
        )

        socket = session?.webSocketTask(with: signalingURL)
        socket?.resume()
        receiveLoop()
    }

    // MARK: - Receive Loop
    private func receiveLoop() {
        socket?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .failure(let error):
                print("❌ [Signaling] Receive error:", error)

            case .success(let message):
                if case .string(let text) = message {
                    self.handleMessage(text)
                }
            }

            // keep listening
            self.receiveLoop()
        }
    }

    // MARK: - Handle Message
    private func handleMessage(_ text: String) {
        print("📩 [Signaling] Received:", text)

        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else {
            print("⚠️ Invalid signaling message")
            return
        }

        switch type {

        case "registered":
            let id = json["userId"] as! String
            myUserId = id
            isConnected = true
            onEvent?(.connected(userId: id))
            print("✅ Registered as:", id)

        case "incoming-call":
            let from = json["from"] as! String
            onEvent?(.incomingCall(from: from))

        case "call-accepted":
            let from = json["from"] as! String
            onEvent?(.callAccepted(from: from))

        case "offer":
            onEvent?(
                .offerReceived(
                    sdp: json["sdp"] as! String,
                    from: json["from"] as! String
                )
            )

        case "answer":
            onEvent?(.answerReceived(sdp: json["sdp"] as! String))

        case "ice-candidate":
            let c = json["candidate"] as! [String: Any]
            let ice = RTCIceCandidate(
                sdp: c["candidate"] as! String,
                sdpMLineIndex: c["sdpMLineIndex"] as! Int32,
                sdpMid: c["sdpMid"] as? String
            )
            onEvent?(.iceReceived(candidate: ice))

        case "end-call":
            onEvent?(.callEnded)

        default:
            print("⚠️ Unknown signaling type:", type)
        }
    }

    // MARK: - Send Helpers

    func sendRegister() {
        send(["type": "register"])
    }

    func startCall(to userId: String) {
        send([
            "type": "start-call",
            "to": userId
        ])
    }

    func acceptCall(from userId: String) {
        send([
            "type": "call-accepted",
            "to": userId
        ])
    }

    func sendOffer(to userId: String, sdp: String) {
        send([
            "type": "offer",
            "to": userId,
            "sdp": sdp
        ])
    }

    func sendAnswer(to userId: String, sdp: String) {
        send([
            "type": "answer",
            "to": userId,
            "sdp": sdp
        ])
    }

    func sendICE(to userId: String, candidate: RTCIceCandidate) {
        send([
            "type": "ice-candidate",
            "to": userId,
            "candidate": [
                "sdpMid": candidate.sdpMid ?? "",
                "sdpMLineIndex": candidate.sdpMLineIndex,
                "candidate": candidate.sdp
            ]
        ])
    }

    func endCall(to userId: String) {
        send([
            "type": "end-call",
            "to": userId
        ])
    }

    // MARK: - Raw Send
    private func send(_ payload: [String: Any]) {
        guard let socket else {
            print("❌ [Signaling] Socket not connected")
            return
        }

        let data = try! JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8)!

        print("📤 [Signaling] Sending:", text)

        socket.send(.string(text)) { error in
            if let error {
                print("❌ [Signaling] Send error:", error)
            }
        }
    }

    // MARK: - Disconnect
    func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        isConnected = false
        print("🔌 [Signaling] Disconnected")
    }
}

// MARK: - WebSocket Delegate
extension SignalingClient: URLSessionWebSocketDelegate {

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("🌐 [Signaling] WebSocket OPEN")
        sendRegister()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        print("🔌 [Signaling] WebSocket CLOSED")
        isConnected = false
    }
}
