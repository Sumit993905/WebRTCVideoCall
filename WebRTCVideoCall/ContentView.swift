import SwiftUI

// MARK: - Call UI State
enum CallUIState {
    case disconnected
    case connecting
    case connected
    case calling
}

// MARK: - Root View
struct ContentView: View {

    // 🔗 Services (EK HI JAGAH CREATE HONGE)
    @StateObject private var signaling: SignalingService
    @StateObject private var rtc: WebRTCService

    // 🧠 UI State
    @State private var state: CallUIState = .disconnected

    // ✅ Proper dependency injection (NO lifecycle bug)
    init() {
        let signaling = SignalingService()
        _signaling = StateObject(wrappedValue: signaling)
        _rtc = StateObject(wrappedValue: WebRTCService(signaling: signaling))
    }

    var body: some View {
        ZStack {
            switch state {

            case .disconnected:
                connectView

            case .connecting:
                connectingView

            case .connected:
                readyToCallView

            case .calling:
                VideoCallView(
                    rtc: rtc,
                    onEndCall: endCall
                )
            }
        }
    }

    // MARK: - CONNECT VIEW
    private var connectView: some View {
        VStack(spacing: 20) {
            Text("WebRTC Video Call")
                .font(.largeTitle)

            Button("Connect to Server") {
                print("🔌 UI: Connect tapped")
                state = .connecting
                signaling.connect()

                // 🔧 Temporary (later real callback se replace hoga)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    print("✅ UI: Connected")
                    state = .connected
                }
            }
            .padding()
        }
    }

    // MARK: - CONNECTING VIEW
    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Connecting to server...")
        }
    }

    // MARK: - READY TO CALL VIEW
    private var readyToCallView: some View {
        VStack(spacing: 20) {

            Text("✅ Connected")
                .foregroundColor(.green)
                .font(.title2)

            Button("Start Video Call") {
                print("📞 UI: Start Call tapped")
                rtc.startCall()
                state = .calling
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }

    // MARK: - END CALL HANDLER
    private func endCall() {
        print("❌ UI: End Call tapped")
        rtc.endCall()          // 👈 WebRTC cleanup
        state = .connected    // back to ready state
    }
}

// MARK: - VIDEO CALL VIEW
struct VideoCallView: View {

    @ObservedObject var rtc: WebRTCService
    let onEndCall: () -> Void

    var body: some View {
        ZStack {

            // 🔹 REMOTE VIDEO (FULL SCREEN)
            VideoRendererView(
                videoTrack: rtc.remoteVideoTrack
            )
            .ignoresSafeArea()

            // 🔹 LOCAL VIDEO (SMALL)
            VStack {
                HStack {
                    Spacer()
                    VideoRendererView(
                        videoTrack: rtc.localVideoTrack
                    )
                    .frame(width: 120, height: 160)
                    .cornerRadius(12)
                    .padding()
                }
                Spacer()
            }

            // 🔴 END CALL BUTTON
            VStack {
                Spacer()
                Button(action: onEndCall) {
                    Text("End Call")
                        .font(.headline)
                        .padding()
                        .frame(width: 140)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(30)
                }
                .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    ContentView()
}
