//
//  TestWebRTC.swift
//  WebRTCVideoCall
//
//  Created by Sumit Raj Chingari on 02/02/26.
//

import Foundation
import WebRTC

func testWebRTC() {
    RTCInitializeSSL()
    let factory = RTCPeerConnectionFactory()
    print(factory)
}

