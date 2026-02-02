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

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        uiView.subviews.forEach { $0.removeFromSuperview() }
        videoTrack?.add(uiView)
    }
}

