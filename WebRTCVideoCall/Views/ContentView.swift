import SwiftUI
import WebRTC

// MARK: - UI States
enum AppUIState {
    case connecting
    case ready
    case outgoingCall(to: String)
    case incomingCall(from: String)
    case inCall
}


struct ContentView: View {
    @StateObject private var signaling = SignalingClient()
    @StateObject private var rtc: WebRTCManager
    
    @State private var uiState: AppUIState = .connecting
    @State private var targetUserId: String = ""

    init() {
        let s = SignalingClient()
        _signaling = StateObject(wrappedValue: s)
        _rtc = StateObject(wrappedValue: WebRTCManager(signaling: s))
    }

    var body: some View {
        ZStack {
            switch uiState {
            case .connecting:
                VStack { ProgressView(); Text("Connecting...") }
            case .ready:
                readyView
            case .outgoingCall(let to):
                VStack { Text("Calling \(to)..."); Button("Cancel") { endCall() } }
            case .incomingCall(let from):
                incomingCallView(from: from)
            case .inCall:
                videoCallView
            }
        }
        .onAppear {
            bindSignaling()
            signaling.connect()
        }
    }

    private var readyView: some View {
        VStack(spacing: 20) {
            Text("My ID: \(signaling.myUserId ?? "...")").bold()
            TextField("Enter Target ID", text: $targetUserId).textFieldStyle(.roundedBorder)
            Button("Start Call") {
                rtc.startCallAsSender(to: targetUserId)
                uiState = .outgoingCall(to: targetUserId)
            }.buttonStyle(.borderedProminent)
        }.padding()
    }

    private func incomingCallView(from: String) -> some View {
        VStack {
            Text("Incoming from \(from)")
            HStack {
                Button("Accept") { rtc.acceptIncomingCall() }.foregroundColor(.green)
                Button("Reject") { endCall() }.foregroundColor(.red)
            }
        }
    }

    private var videoCallView: some View {
        ZStack {
            VideoRendererView(videoTrack: rtc.remoteVideoTrack, isLocal: false)
                .background(Color.black)
            
            VStack {
                HStack {
                    Spacer()
                    VideoRendererView(videoTrack: rtc.localVideoTrack, isLocal: true)
                        .frame(width: 120, height: 160).cornerRadius(12).padding()
                }
                Spacer()
                Button("End Call") { endCall() }
                    .padding().background(Color.red).foregroundColor(.white).clipShape(Capsule())
            }
        }
    }

    private func bindSignaling() {
        signaling.onEvent = { event in
            DispatchQueue.main.async {
                switch event {
                case .connected: uiState = .ready
                case .incomingCall(let from): uiState = .incomingCall(from: from)
                case .callAccepted, .offerReceived, .answerReceived:
                    uiState = .inCall // Kisi bhi state mein stream start ho sakti hai
                case .callEnded: endCall()
                default: break
                }
            }
        }
    }

    private func endCall() {
        rtc.endCall()
        uiState = .ready
    }
}
