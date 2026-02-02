import ARKit
import Vision
import CoreMotion

final class WorldTracker: NSObject, ARSessionDelegate {
    private let dispatchQueue: DispatchQueue
    private let configuration: ARWorldTrackingConfiguration
    private let arSession: ARSession
    
    // Hand tracking specific
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    private let visionQueue = DispatchQueue(label: "com.alvr.vision", qos: .userInteractive)
    
    #if DEBUG
    private var lastTickTime: Int64 = 0
    private var tps = 0
    #endif
    
    private var position: (Float, Float, Float) = (0, 1.6, 0)
    private var rotation: CMQuaternion = .init()
    
    private let isTrackOrientation: Bool
    private let isTrackPosition: Bool
    
    init(isTrackOrientation: Bool, isTrackPosition: Bool) {
        self.isTrackOrientation = isTrackOrientation
        self.isTrackPosition = isTrackPosition
        
        dispatchQueue = .init(label: "ARWorldTrackingSource", qos: .background)
        
        configuration = .init()
        // Plane detection helps ARKit ground the 6DoF coordinate system
        configuration.planeDetection = .horizontal
        
        arSession = ARSession()
        
        super.init()
        arSession.delegate = self
        
        // Configure Hand Tracking
        handPoseRequest.maximumHandCount = 2
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // --- 1. Head Tracking (6DoF) ---
        if isTrackOrientation {
            let transform = frame.camera.transform
            let quaternion = simd_quaternion(transform)
            self.rotation = .init(x: Double(quaternion.vector.x), 
                                  y: Double(quaternion.vector.y), 
                                  z: Double(quaternion.vector.z), 
                                  w: Double(quaternion.vector.w))
        }
        
        if isTrackPosition {
            let pos = frame.camera.transform.columns.3
            // Offset Y by 1.0 to simulate standing height if not calibrated
            self.position = (pos.x, pos.y + 1.0, pos.z)
        }
        
        // --- 2. Hand Tracking (Vision) ---
        visionQueue.async { [weak self] in
            guard let self = self else { return }
            let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .up, options: [:])
            do {
                try handler.perform([self.handPoseRequest])
                guard let observations = self.handPoseRequest.results else { return }
                
                for observation in observations {
                    self.processHandObservation(observation, frame: frame)
                }
            } catch {
                print("Vision Error: \(error)")
            }
        }
        
        #if DEBUG
        tps += 1
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if now - lastTickTime > 1000 {
            lastTickTime = now
            tps = 0
        }
        #endif
    }
    
    private func processHandObservation(_ observation: VNHumanHandPoseObservation, frame: ARFrame) {
        // Extract all 21 joints
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else { return }
        
        // Determine if Left or Right hand
        let chirality = observation.chirality == .left ? "left" : "right"
        
        // Example: Map the Wrist to a 3D point in the ARWorld
        if let wristPoint = recognizedPoints[.wrist], wristPoint.confidence > 0.5 {
            // Convert 2D image point to 3D ARKit coordinate
            let ray = frame.raycastQuery(from: wristPoint.location, allowing: .estimatedPlane, alignment: .any)
            alvr_report_hand_pose(chirality, joints_array)
        }
    }
    
    func start() {
        dispatchQueue.async { [weak self] in
            guard let self = self else { return }
            self.arSession.run(self.configuration)
        }
    }
    
    func stop() {
        arSession.pause()
    }
    
    func getPosition() -> (Float, Float, Float) { return position }
    func getRotation() -> CMQuaternion { return rotation }
    
    func getQuaterionRotation() -> AlvrQuat {
        let r = getRotation()
        return AlvrQuat(x: Float(r.x), y: Float(r.y), z: Float(r.z), w: Float(r.w))
    }
}
