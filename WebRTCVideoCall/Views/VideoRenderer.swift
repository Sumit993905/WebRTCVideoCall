//
//  VideoRenderer.swift
//  WebRTCVideoCall
//
//  Created by Sumit Raj Chingari on 02/02/26.
//

import SwiftUI
import WebRTC

struct VideoRendererView: UIViewRepresentable {

    let videoTrack: RTCVideoTrack?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill

        // 🔗 Attach track ONLY ONCE
        if let track = videoTrack {
            track.add(view)
            context.coordinator.attachedTrack = track
            print("🎥 [Renderer] Track attached")
        }

        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        // ⚠️ IMPORTANT
        // SwiftUI re-render pe kuch bhi mat karo
        // WebRTC renderer yahin toot ta hai agar yahan add/remove kiya
    }

    static func dismantleUIView(
        _ uiView: RTCMTLVideoView,
        coordinator: Coordinator
    ) {
        // 🧹 Proper cleanup
        if let track = coordinator.attachedTrack {
            track.remove(uiView)
            print("🧹 [Renderer] Track detached")
        }
        coordinator.attachedTrack = nil
    }

    final class Coordinator {
        var attachedTrack: RTCVideoTrack?
    }
}
