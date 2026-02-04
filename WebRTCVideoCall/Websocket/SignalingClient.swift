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

    // MARK: - CONFIG
    // Note: Har restart par Ngrok URL change hoti hai, usey update karte rahein.
    private let signalingURL = URL(string: "wss://maneuverable-cognatic-jaydon.ngrok-free.dev")!

    // MARK: - Published
    @Published var isConnected = false
    @Published var myUserId: String?

    // MARK: - Callback
    var onEvent: ((SignalingEvent) -> Void)?

    // MARK: - Internal vars
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?

    // MARK: - Connect
    func connect() {
        guard socket == nil else { return }

        print("🔌 [Signaling] Connecting to: \(signalingURL)")

        session = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: .main // Main thread par callbacks milenge
        )

        socket = session?.webSocketTask(with: signalingURL)
        socket?.resume()
        receiveLoop()
    }

    // MARK: - Receive Loop (Recursive)
    private func receiveLoop() {
        socket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                print("❌ [Signaling] Receive error: \(error.localizedDescription)")
                self.isConnected = false
                
            case .success(let message):
                if case .string(let text) = message {
                    self.handleMessage(text)
                }
                // Keep listening for the next message
                self.receiveLoop()
            }
        }
    }

    // MARK: - Handle Incoming Messages (Safe Parsing)
    private func handleMessage(_ text: String) {
        print("📩 [Signaling] Received Raw: \(text)")

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            print("⚠️ [Signaling] Could not parse JSON")
            return
        }

        switch type {
        case "registered":
            if let id = json["userId"] as? String {
                self.myUserId = id
                self.isConnected = true
                onEvent?(.connected(userId: id))
                print("✅ [Signaling] Registered ID: \(id)")
            }

        case "incoming-call":
            if let from = json["from"] as? String {
                onEvent?(.incomingCall(from: from))
            }

        case "call-accepted":
            if let from = json["from"] as? String {
                onEvent?(.callAccepted(from: from))
            }

        case "offer":
            if let sdp = json["sdp"] as? String, let from = json["from"] as? String {
                onEvent?(.offerReceived(sdp: sdp, from: from))
            }

        case "answer":
            if let sdp = json["sdp"] as? String {
                onEvent?(.answerReceived(sdp: sdp))
            }

        case "ice-candidate":
            if let c = json["candidate"] as? [String: Any],
               let sdp = c["candidate"] as? String,
               let sdpMLineIndex = c["sdpMLineIndex"] as? Int32 {
                let ice = RTCIceCandidate(
                    sdp: sdp,
                    sdpMLineIndex: sdpMLineIndex,
                    sdpMid: c["sdpMid"] as? String
                )
                onEvent?(.iceReceived(candidate: ice))
            }

        case "end-call":
            onEvent?(.callEnded)

        default:
            print("⚠️ [Signaling] Unknown event type: \(type)")
        }
    }

    // MARK: - Send Helpers (Robust)

    func startCall(to userId: String) {
        send(["type": "start-call", "to": userId])
    }

    func acceptCall(from userId: String) {
        send(["type": "call-accepted", "to": userId])
    }

    func sendOffer(to userId: String, sdp: String) {
        send(["type": "offer", "to": userId, "sdp": sdp])
    }

    func sendAnswer(to userId: String, sdp: String) {
        send(["type": "answer", "to": userId, "sdp": sdp])
    }

    func sendICE(to userId: String, candidate: RTCIceCandidate) {
        let iceDict: [String: Any] = [
            "sdpMid": candidate.sdpMid ?? "",
            "sdpMLineIndex": candidate.sdpMLineIndex,
            "candidate": candidate.sdp
        ]
        send(["type": "ice-candidate", "to": userId, "candidate": iceDict])
    }

    func endCall(to userId: String) {
        send(["type": "end-call", "to": userId])
    }

    // MARK: - Private Raw Send
    private func send(_ payload: [String: Any]) {
        guard let socket = socket, isConnected else {
            print("❌ [Signaling] Cannot send, socket not connected")
            return
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            if let text = String(data: data, encoding: .utf8) {
                print("📤 [Signaling] Sending: \(text)")
                socket.send(.string(text)) { error in
                    if let error = error {
                        print("❌ [Signaling] Send error: \(error)")
                    }
                }
            }
        } catch {
            print("❌ [Signaling] JSON Serialization error: \(error)")
        }
    }

    func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        isConnected = false
    }
}

// MARK: - URLSessionWebSocketDelegate
extension SignalingClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("🌐 [Signaling] WebSocket Connected")
        DispatchQueue.main.async {
            self.isConnected = true
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("🔌 [Signaling] WebSocket Disconnected")
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}
