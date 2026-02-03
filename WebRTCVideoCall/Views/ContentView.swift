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

    // MARK: - Core
    @StateObject private var signaling = SignalingClient()
    @StateObject private var rtc: WebRTCManager

    // MARK: - UI State
    @State private var uiState: AppUIState = .connecting
    @State private var targetUserId: String = ""

    // MARK: - Init (SAME signaling instance)
    init() {
        let signalingClient = SignalingClient()
        _signaling = StateObject(wrappedValue: signalingClient)
        _rtc = StateObject(wrappedValue: WebRTCManager(signaling: signalingClient))
    }

    var body: some View {
        ZStack {
            switch uiState {

            case .connecting:
                connectingView

            case .ready:
                readyView

            case .outgoingCall(let to):
                outgoingCallView(to: to)

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
}

private extension ContentView {

    var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Connecting to server...")
                .font(.headline)
        }
    }
}


private extension ContentView {

    func bindSignaling() {
        signaling.onEvent = { event in
            DispatchQueue.main.async {
                switch event {

                case .connected:
                    uiState = .ready

                case .incomingCall(let from):
                    uiState = .incomingCall(from: from)

                case .callAccepted:
                    uiState = .inCall

                case .offerReceived:
                    uiState = .inCall

                case .answerReceived:
                    uiState = .inCall

                case .callEnded:
                    endCall()

                default:
                    break
                }
            }
        }
    }

    func endCall() {
        rtc.endCall()
        uiState = .ready
    }
}
private extension ContentView {

    var readyView: some View {
        VStack(spacing: 24) {

            Text("📞 WebRTC Video Call")
                .font(.largeTitle)
                .bold()

            VStack(spacing: 6) {
                Text("Your User ID")
                    .font(.caption)
                    .foregroundColor(.gray)

                Text(shortUserId(signaling.myUserId))
                    .font(.title2)
                    .bold()

            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {

                Text("Call another user")
                    .font(.headline)

                TextField("Enter User ID", text: $targetUserId)
                    .textFieldStyle(.roundedBorder)

                Button {
                    rtc.startCallAsSender(to: targetUserId)
                    uiState = .outgoingCall(to: targetUserId)
                } label: {
                    Text("Start Video Call")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(targetUserId.isEmpty)
            }
        }
        .padding()
    }
}
private extension ContentView {

    func outgoingCallView(to userId: String) -> some View {
        VStack(spacing: 20) {
            ProgressView()
            Text("Calling \(userId)...")
                .font(.headline)

            Button("Cancel Call") {
                endCall()
            }
            .foregroundColor(.red)
        }
    }
}
private extension ContentView {

    func incomingCallView(from userId: String) -> some View {
        VStack(spacing: 24) {

            Text("📲 Incoming Call")
                .font(.largeTitle)
                .bold()

            Text("From")
                .foregroundColor(.gray)

            Text(shortUserId(userId))
                .font(.title2)
                .bold()


            HStack(spacing: 20) {

                Button {
                    rtc.acceptIncomingCall()
                    uiState = .inCall
                } label: {
                    Text("Accept")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button {
                    endCall()
                } label: {
                    Text("Reject")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
        .padding()
    }
}
private extension ContentView {

    var videoCallView: some View {
        ZStack {

            // REMOTE (FULL SCREEN)
            VideoRendererView(
                videoTrack: rtc.remoteVideoTrack,
                isLocal: false
            )
            .ignoresSafeArea()

            // LOCAL (SMALL FLOATING)
            VStack {
                HStack {
                    Spacer()
                    VideoRendererView(
                        videoTrack: rtc.localVideoTrack,
                        isLocal: true
                    )
                    .frame(width: 120, height: 160)
                    .cornerRadius(12)
                    .padding()
                }
                Spacer()
            }

            // END CALL BUTTON
            VStack {
                Spacer()
                Button {
                    endCall()
                } label: {
                    Text("End Call")
                        .padding()
                        .frame(width: 160)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(30)
                }
                .padding(.bottom, 40)
            }
        }
    }

}

extension ContentView {
    private func shortUserId(_ id: String?) -> String {
        guard let id else { return "--" }
        if id.count <= 8 { return id }

        let start = id.prefix(2)
        let end = id.suffix(2)
        return "\(start)…\(end)"
    }

}
