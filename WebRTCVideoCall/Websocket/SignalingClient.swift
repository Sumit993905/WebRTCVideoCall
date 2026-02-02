//
//  SignalingClient.swift
//  WebRTCVideoCall
//
//  Created by Sumit Raj Chingari on 02/02/26.
//

import Foundation
import Combine

protocol SignalingServiceDelegate: AnyObject {
    func didReceiveOffer(_ sdp: String)
    func didReceiveAnswer(_ sdp: String)
    func didReceiveIceCandidate(_ candidate: [String: Any])
}

final class SignalingService: NSObject,ObservableObject {

    private var webSocketTask: URLSessionWebSocketTask?
    weak var delegate: SignalingServiceDelegate?

    // MARK: - Connect
    func connect() {
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
        webSocketTask?.receive { [weak self] result in
            switch result {

            case .failure(let error):
                print("❌ [Signaling] Receive error:", error)

            case .success(let message):
                if case .string(let text) = message {
                    print("📩 [Signaling] Received:", text)
                    self?.handleMessage(text)
                }
            }

            self?.receive()
        }
    }

    // MARK: - Handle incoming signal
    private func handleMessage(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else {
            print("⚠️ [Signaling] Invalid message")
            return
        }

        print("🔎 [Signaling] Type:", type)

        switch type {
        case "offer":
            delegate?.didReceiveOffer(json["sdp"] as! String)

        case "answer":
            delegate?.didReceiveAnswer(json["sdp"] as! String)

        case "ice-candidate":
            delegate?.didReceiveIceCandidate(
                json["candidate"] as! [String: Any]
            )

        default:
            print("⚠️ [Signaling] Unknown type")
        }
    }

    // MARK: - Send
    func send(_ dict: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let text = String(data: data, encoding: .utf8)!
        print("📤 [Signaling] Sending:", text)

        webSocketTask?.send(.string(text)) { error in
            if let error = error {
                print("❌ [Signaling] Send error:", error)
            }
        }
    }
}

// MARK: - URLSession Delegate
extension SignalingService: URLSessionWebSocketDelegate {

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("✅ [Signaling] WebSocket OPEN")
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        print("🔌 [Signaling] WebSocket CLOSED")
    }
}
