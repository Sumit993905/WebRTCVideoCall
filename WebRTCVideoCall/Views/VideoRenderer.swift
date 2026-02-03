import SwiftUI
import WebRTC

struct VideoRendererView: UIViewRepresentable {

    let videoTrack: RTCVideoTrack?
    var isLocal: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {

        // Remove old track safely
        if let oldTrack = context.coordinator.currentTrack {
            oldTrack.remove(uiView)
        }

        // Attach new track
        if let track = videoTrack {
            track.add(uiView)
            context.coordinator.currentTrack = track
        }

        // Mirror local camera
        uiView.transform = isLocal
            ? CGAffineTransform(scaleX: -1, y: 1)
            : .identity
    }

    final class Coordinator {
        var currentTrack: RTCVideoTrack?
    }
}
