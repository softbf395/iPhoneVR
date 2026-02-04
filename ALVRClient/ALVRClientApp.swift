import SwiftUI
import ARKit
import Vision
import Network
import "alvr_client_core.h" // Ensure this is linked in your Frameworks

// MARK: - ALVR Session Manager
class ALVRSessionManager: NSObject, ARSessionDelegate, ObservableObject {
    @Published var isStreaming = false
    @Published var hostname = "7470.client"
    @Published var localIP = "Detecting..."
    
    private let controlPort: UInt16 = 9943
    private let handRequest = VNDetectHumanHandPoseRequest()
    private var discoveryTimer: Timer?
    
    override init() {
        super.init()
        alvr_initialize(nil, nil, ALVR_LOG_LEVEL_INFO)
        self.localIP = getWiFiIPAddress() ?? "No WiFi Found"
    }
    
    func toggleStream() {
        isStreaming.toggle()
        if isStreaming { startDiscovery() } else { stopDiscovery() }
    }
    
    // MARK: - IP Discovery Logic
    func getWiFiIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }

        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) { // IPv4
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "pdp_ip0" { // en0 is standard WiFi
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }

    // MARK: - Handshake (56-byte)
    private func startDiscovery() {
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.sendDiscoveryPacket()
        }
    }
    
    private func stopDiscovery() { discoveryTimer?.invalidate() }
    
    private func sendDiscoveryPacket() {
        let broadcastAddr = NWEndpoint.hostPort(host: "255.255.255.255", port: NWEndpoint.Port(integerLiteral: controlPort))
        let connection = NWConnection(to: broadcastAddr, using: .udp)
        connection.start(queue: .global())
        
        var packet = Data(count: 56)
        let name = "ALVR".data(using: .utf8)!
        packet.replaceSubrange(0..<name.count, with: name)
        
        var proto = alvr_get_protocol_id().littleEndian
        packet.replaceSubrange(16..<24, with: Data(bytes: &proto, count: 8))
        
        let hostData = hostname.data(using: .utf8)!
        packet.replaceSubrange(24..<(24 + min(hostData.count, 32)), with: hostData.prefix(32))
        
        connection.send(content: packet, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - Tracking Update
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isStreaming else { return }
        var tracking = AlvrTracking()
        
        // Head
        let cam = frame.camera.transform
        tracking.head_pose.position = (cam.columns.3.x, cam.columns.3.y, cam.columns.3.z)
        let q = simd_quaternion(cam)
        tracking.head_pose.orientation = (q.vector.x, q.vector.y, q.vector.z, q.vector.w)
        
        // Hands
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .up)
        try? handler.perform([handRequest])
        if let results = handRequest.results {
            for res in results {
                let side = res.chirality == .left ? "left" : "right"
                if let wrist = try? res.recognizedPoint(.wrist) {
                    let pose = AlvrPose(orientation: (0,0,0,1), position: ((Float(wrist.location.x)-0.5)*1.5, (Float(wrist.location.y)-0.5)*-1.5, -0.4))
                    if side == "left" { tracking.left_hand_pose = pose; tracking.left_hand_enabled = true }
                    else { tracking.right_hand_pose = pose; tracking.right_hand_enabled = true }
                }
            }
        }
        alvr_send_tracking(tracking)
    }
}

// MARK: - SwiftUI Lobby
struct ALVRLobbyView: View {
    @StateObject private var mgr = ALVRSessionManager()
    
    var body: some View {
        ZStack {
            ARPassthroughView(sessionManager: mgr)
                .ignoresSafeArea()
                .overlay(mgr.isStreaming ? Color.clear : Color.black.opacity(0.75))

            VStack(spacing: 20) {
                if !mgr.isStreaming {
                    VStack(spacing: 10) {
                        Text("ALVR BRIDGE")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                        
                        VStack(spacing: 5) {
                            HStack {
                                Text("HOSTNAME:").bold()
                                Text(mgr.hostname).monospaced()
                            }
                            HStack {
                                Text("ALVR_IP:").bold()
                                Text(mgr.localIP).monospaced()
                            }
                        }
                        .font(.subheadline)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .foregroundColor(.white)
                    .padding(.top, 100)
                }
                
                Spacer()

                Button(action: { mgr.toggleStream() }) {
                    Label(mgr.isStreaming ? "DISCONNECT" : "START SESSION", 
                          systemImage: mgr.isStreaming ? "xmark.circle.fill" : "play.fill")
                        .font(.headline)
                        .frame(width: 240, height: 60)
                        .background(mgr.isStreaming ? Color.red : Color.cyan)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: (mgr.isStreaming ? Color.red : Color.cyan).opacity(0.4), radius: 20)
                }
                .padding(.bottom, 60)
            }
        }
    }
}

struct ARPassthroughView: UIViewRepresentable {
    let sessionManager: ALVRSessionManager
    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView(); v.session.delegate = sessionManager
        v.session.run(ARWorldTrackingConfiguration())
        return v
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
