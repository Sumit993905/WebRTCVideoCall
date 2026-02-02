import Foundation
import Combine

protocol SignalingServiceDelegate: AnyObject {
    func didReceiveOffer(_ sdp: String)
    func didReceiveAnswer(_ sdp: String)
    func didReceiveIceCandidate(_ candidate: [String: Any])
}

final class SignalingService: NSObject, ObservableObject {

    // MARK: - Properties
    private var webSocketTask: URLSessionWebSocketTask?
    weak var delegate: SignalingServiceDelegate?

    @Published private(set) var isConnected: Bool = false

    // MARK: - Connect
    func connect() {

        guard !isConnected else {
            print("⚠️ [Signaling] Already connected, skipping connect()")
            return
        }

        print("🔌 [Signaling] Connecting WebSocket")

        let session = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: .main
        )

        webSocketTask = session.webSocketTask(
            with: AppConfig.signalingURL
        )

        webSocketTask?.resume()
        receive()
    }

    // MARK: - Receive loop
    private func receive() {

        guard isConnected || webSocketTask != nil else {
            print("⚠️ [Signaling] Receive stopped (socket not active)")
            return
        }

        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {

            case .failure(let error):
                print("❌ [Signaling] Receive error:", error)
                self.cleanup()

            case .success(let message):
                if case .string(let text) = message {
                    print("📩 [Signaling] Received:", text)
                    self.handleMessage(text)
                    self.receive() // 🔁 continue loop
                }
            }
        }
    }

    // MARK: - Handle incoming signal
    private func handleMessage(_ text: String) {

        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else {
            print("⚠️ [Signaling] Invalid JSON message")
            return
        }

        print("🔎 [Signaling] Type:", type)

        switch type {

        case "offer":
            if let sdp = json["sdp"] as? String {
                delegate?.didReceiveOffer(sdp)
            }

        case "answer":
            if let sdp = json["sdp"] as? String {
                delegate?.didReceiveAnswer(sdp)
            }

        case "ice-candidate":
            if let candidate = json["candidate"] as? [String: Any] {
                delegate?.didReceiveIceCandidate(candidate)
            }

        case "busy":
            print("⛔ [Signaling] Server busy – another peer already connected")

        case "peer-left":
            print("👋 [Signaling] Peer left the call")

        default:
            print("⚠️ [Signaling] Unknown type:", type)
        }
    }

    // MARK: - Send
    func send(_ dict: [String: Any]) {

        guard isConnected else {
            print("❌ [Signaling] Send failed – socket not connected")
            return
        }

        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8)
        else {
            print("❌ [Signaling] Failed to encode message")
            return
        }

        print("📤 [Signaling] Sending:", text)

        webSocketTask?.send(.string(text)) { error in
            if let error {
                print("❌ [Signaling] Send error:", error)
            }
        }
    }

    // MARK: - Cleanup
    private func cleanup() {
        print("🧹 [Signaling] Cleaning up socket")
        webSocketTask = nil
        isConnected = false
    }
}

// MARK: - URLSessionWebSocketDelegate
extension SignalingService: URLSessionWebSocketDelegate {

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("✅ [Signaling] WebSocket OPEN")
        isConnected = true
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        print("🔌 [Signaling] WebSocket CLOSED")
        cleanup()
    }
}
