//
//  ARManager.swift
//  EchoSight
//
//  This class manages ARKit session, LiDAR scene reconstruction,
//  distance to nearest obstacles, and object recognition.
//

import RealityKit
import ARKit
import Combine
import Vision
import CoreML

class ARManager: NSObject, ARSessionDelegate, ObservableObject {
    
    let arView = ARView()
    @Published var distance: Float = 0.0
    @Published var isPointingAtGround: Bool = false
    @Published var trackingState: String = "Initializing..."
    @Published var isTrackingNormal: Bool = false
    
    // Use a history array for recognized objects
    @Published var objectHistory: [String] = []
    
    // Current frame image for VLM
    @Published var currentFrameImage: UIImage?
    
    private var timer: Timer?
    
    private var visionRequests = [VNRequest]()
    private var isVisionRequestInProgress = false
    private let maxHistoryCount = 5 // max history count
    
    // Performance: reuse CIContext
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // Limit FastViT frequency to avoid impacting speech recognition
    private var lastVisionProcessTime: Date?
    private let visionProcessInterval: TimeInterval = 0.5 // run every 0.5s
    private var frameSkipCounter = 0
    private let frameSkipThreshold = 30 // process every 30 frames
    
    // Prevent ARFrame retention and overwork by limiting image updates
    private var isProcessingFrameImage = false
    private var lastImageUpdateTime: Date?
    private let imageUpdateInterval: TimeInterval = 0.3

    override init() {
        super.init()
        arView.session.delegate = self
        setupVision()
        print("FastViT throttled: every \(visionProcessInterval)s to reduce CPU and avoid speech impact")
    }
    
    private func setupVision() {
        do {
            let model = try VNCoreMLModel(for: FastViTMA36F16().model)
            let request = VNCoreMLRequest(model: model) { (request, error) in
                DispatchQueue.main.async {
                    if let results = request.results as? [VNClassificationObservation] {
                        self.processVisionClassificationResults(results)
                    }
                    self.isVisionRequestInProgress = false
                }
            }
            request.imageCropAndScaleOption = .scaleFit
            self.visionRequests = [request]
        } catch {
            print("Failed to load Core ML model: \(error)")
        }
    }
    
    private func processVisionClassificationResults(_ results: [VNClassificationObservation]) {
        if let topResult = results.first {
            if topResult.confidence > 0.6 {
                let fullIdentifier = topResult.identifier
                
                // Extract only the first word before comma (highest confidence result)
                let identifier = fullIdentifier.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? fullIdentifier
                
                self.objectHistory = [identifier]
                
                print("FastViT: \(identifier) (conf: \(String(format: "%.2f", topResult.confidence)))")
            } else {
                self.objectHistory = []
            }
        } else {
            self.objectHistory = []
        }
    }

    /// ARSessionDelegate method, called every frame
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Copy pixelBuffer reference immediately; do not retain ARFrame
        let pixelBuffer = frame.capturedImage
        
        // Skip heavy work while tracking is not normal to reduce frame pressure
        guard isTrackingNormal else {
            // Still update distance via raycasts in timer; avoid image/Vision
            return
        }

        // Throttle image conversion for VLM snapshot and avoid concurrent work
        let nowImage = Date()
        let shouldUpdateImage = (lastImageUpdateTime == nil) || (nowImage.timeIntervalSince(lastImageUpdateTime!) >= imageUpdateInterval)
        if shouldUpdateImage && !isProcessingFrameImage {
            isProcessingFrameImage = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                autoreleasepool {
                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                    if let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) {
                        let image = UIImage(cgImage: cgImage)
                        DispatchQueue.main.async {
                            self.currentFrameImage = image
                            self.lastImageUpdateTime = Date()
                            self.isProcessingFrameImage = false
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.isProcessingFrameImage = false
                        }
                    }
                }
            }
        }
        
        // Throttle FastViT: every 30 frames or 0.5s
        frameSkipCounter += 1
        
        let now = Date()
        let shouldProcessByTime = lastVisionProcessTime == nil || 
                                  now.timeIntervalSince(lastVisionProcessTime!) >= visionProcessInterval
        let shouldProcessByFrame = frameSkipCounter >= frameSkipThreshold
        
        guard shouldProcessByTime || shouldProcessByFrame else { return }
        guard !isVisionRequestInProgress else { return }
        
        // Reset counters and timestamps
        frameSkipCounter = 0
        lastVisionProcessTime = now
        isVisionRequestInProgress = true
        
        // Vision classification on background without retaining ARFrame
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            autoreleasepool {
                let ci = CIImage(cvPixelBuffer: pixelBuffer)
                if let cg = self.ciContext.createCGImage(ci, from: ci.extent) {
                    let handler = VNImageRequestHandler(cgImage: cg, orientation: .right, options: [:])
                    do {
                        try handler.perform(self.visionRequests)
                    } catch {
                        print("Vision request failed: \(error)")
                        DispatchQueue.main.async {
                            self.isVisionRequestInProgress = false
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isVisionRequestInProgress = false
                    }
                }
            }
        }
    }
    
    /// Start AR session with LiDAR scene reconstruction
    func startSession() {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            print("Device does not support LiDAR mesh reconstruction")
            return
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .mesh
        
        // AR configuration for stable tracking
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        
        // Better scene understanding
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        
        // Run session and reset tracking
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        print("AR session started: mesh + plane detection + depth")
        
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(self.performMultiRaycast), userInfo: nil, repeats: true)
        }
    }
    
    func stopSession() {
        // Stop timer first
        timer?.invalidate()
        timer = nil
        
        // Pause AR session
        arView.session.pause()
        
        print("AR session paused")
    }
    
    /// Monitor AR tracking state
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        DispatchQueue.main.async {
            switch camera.trackingState {
            case .normal:
                self.trackingState = "Tracking OK"
                self.isTrackingNormal = true
                print("AR tracking normal")
            case .notAvailable:
                self.trackingState = "Tracking Not Available"
                self.isTrackingNormal = false
                print("AR tracking not available")
            case .limited(let reason):
                switch reason {
                case .initializing:
                    self.trackingState = "Initializing..."
                    self.isTrackingNormal = false
                    print("AR initializing...")
                case .excessiveMotion:
                    self.trackingState = "Move Slower"
                    self.isTrackingNormal = false
                    print("Device moving too fast")
                case .insufficientFeatures:
                    self.trackingState = "Point at textured surface"
                    self.isTrackingNormal = false
                    print("Insufficient features; aim at textured surface")
                case .relocalizing:
                    self.trackingState = "Relocalizing..."
                    self.isTrackingNormal = false
                    print("Relocalizing...")
                @unknown default:
                    self.trackingState = "Limited Tracking"
                    self.isTrackingNormal = false
                    print("AR tracking limited")
                }
            }
        }
    }
    
    /// Perform multiple raycasts from screen points to detect obstacles
    @objc private func performMultiRaycast() {
        let cameraTransform = arView.cameraTransform
        
        let forwardVector = -cameraTransform.matrix.columns.2.xyz
        let isPointingDown = forwardVector.y < -0.7
        
        let raycastPoints = [
            arView.center,
            CGPoint(x: arView.center.x - 150, y: arView.center.y),
            CGPoint(x: arView.center.x + 150, y: arView.center.y)
        ]
        
        var validDistances: [Float] = []
        
        for point in raycastPoints {
            let results = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any)
            
            if let firstResult = results.first {
                let worldPosition = SIMD3<Float>(firstResult.worldTransform.columns.3.x, firstResult.worldTransform.columns.3.y, firstResult.worldTransform.columns.3.z)
                let distanceToObstacle = simd_distance(cameraTransform.translation, worldPosition)

                if isPointingDown {
                    if distanceToObstacle < 0.7 {
                        validDistances.append(distanceToObstacle)
                    }
                } else {
                    validDistances.append(distanceToObstacle)
                }
            }
        }
        
        let closestDistance = validDistances.min() ?? 0.0
        self.distance = closestDistance
        self.isPointingAtGround = isPointingDown && closestDistance == 0.0
    }
}

extension SIMD4 {
    var xyz: SIMD3<Scalar> {
        return SIMD3<Scalar>(x, y, z)
    }
}


