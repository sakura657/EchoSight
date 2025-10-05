//
//  ContentView.swift
//  EchoSight
//
//  This view shows the AR camera feed and provides user feedback.
//

import SwiftUI
import RealityKit
import AVFoundation
import CoreHaptics

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arManager: ARManager

    func makeUIView(context: Context) -> ARView {
        return arManager.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var arManager = ARManager()
    @StateObject private var speechRecognition = SpeechRecognitionService()  // Apple Speech recognizer
    private let speechSynthesizer = AVSpeechSynthesizer()
    @State private var speechDelegate: SpeechSynthesizerDelegate?
    @State private var hapticEngine: CHHapticEngine?
    
    @State private var distanceString = "Point camera at an object"
    @State private var isWarning = false
    
    @State private var speechFeedbackTimer: Timer?
    private let warningDistance: Float = 0.5  // trigger warning at 0.5m
    
    // VLM state
    @State private var vlmResponse = ""
    @State private var showVLMResponse = false
    @State private var isProcessingVLM = false
    @State private var hasTriggeredVLMForCurrentWarning = false
    @State private var isSpeakingVLMResponse = false  // Track if currently speaking VLM response
    @State private var isSpeakingObjectName = false   // Track if currently speaking object info
    
    // Warning cooldown - shorter for more frequent haptic feedback
    @State private var lastWarningTime: Date?
    private let warningCooldown: TimeInterval = 1.5  // Reduced from 3.0 to 1.5 seconds for more responsive haptics
    
    // MARK: - Mode Management
    // Two modes: obstacle avoidance (true) and voice interaction (false)
    @State private var isObstacleMode = true
    @State private var hasDescribedEnvironmentInVoiceMode = false

    var body: some View {
        ZStack {
            ARViewContainer(arManager: arManager)
                .ignoresSafeArea()

            // Layout UI elements at top and bottom
            VStack {
                // MARK: - Top: Mode toggle and AI suggestions
                VStack(alignment: .center, spacing: 8) {
                    // Mode Toggle
                    HStack(spacing: 12) {
                        Image(systemName: isObstacleMode ? "eye.trianglebadge.exclamationmark.fill" : "bubble.left.and.bubble.right.fill")
                            .foregroundColor(isObstacleMode ? .orange : .blue)
                            .font(.title3)
                        
                        Toggle("", isOn: $isObstacleMode)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .orange))
                            .frame(width: 51)
                        
                        Text(isObstacleMode ? "Obstacle Avoidance" : "Voice Interaction")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    .padding(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(20)
                    
                    // Show object history only in Obstacle Mode
                    if isObstacleMode {
                        ForEach(Array(arManager.objectHistory.enumerated()), id: \.offset) { index, name in
                            Text(name.capitalized)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(10)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    
                    // VLM response
                    if showVLMResponse && !vlmResponse.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "brain.head.profile")
                                    .foregroundColor(.blue)
                                Text("AI Suggestion:")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            }
                            
                            Text(verbatim: vlmResponse)
                                .font(.body)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(12)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Speech listening indicator
                    if speechRecognition.isListening {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .foregroundColor(.green)
                                .symbolEffect(.pulse, options: .repeating)
                            Text("Voice Active")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                    }
                }
                .padding()
                .animation(.easeInOut, value: arManager.objectHistory)
                .animation(.easeInOut, value: showVLMResponse)
                .animation(.easeInOut, value: speechRecognition.isListening)
                .animation(.easeInOut, value: isObstacleMode)
                
                Spacer()

                // MARK: - Bottom: live transcription (SFSpeechRecognizer)
                VStack(spacing: 8) {
                    // Show live recognized text
                    if !speechRecognition.currentTranscription.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "mic.circle.fill")
                                    .foregroundColor(.green)
                                    .symbolEffect(.pulse, options: .repeating)
                                Text("Listening:")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                                Spacer()
                                // Word count
                                Text("\(speechRecognition.currentTranscription.split(separator: " ").count) words")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            Text(speechRecognition.currentTranscription)
                                .font(.body)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.7))
                        .cornerRadius(12)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity.animation(.easeOut(duration: 0.3))
                        ))
                    }
                    
                    // Distance and warning banner
                    Text(distanceString)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding()
                        .background((isWarning ? Color.red : Color.black).opacity(0.7))
                        .cornerRadius(15)
                        .animation(.easeInOut, value: isWarning)
                }
                .padding(.bottom, 5)
            }
            .padding()
            .animation(.easeInOut, value: speechRecognition.currentTranscription)
        }
        .onAppear {
            arManager.startSession()
            prepareHaptics()
            setupSpeechSynthesizer()
            
            // Request speech recognition permission and start listening on success
            speechRecognition.requestAuthorization { authorized in
                if authorized {
                    // Delay start to ensure AR and audio are ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.startVoiceListening()
                    }
                } else {
                    print("Speech recognition permission denied; voice features disabled")
                }
            }
        }
        .onDisappear {
            arManager.stopSession()
            speechRecognition.stopContinuousListening()
        }
        .onChange(of: arManager.distance) { _, newDistance in
            handleDistanceUpdate(distance: newDistance)
        }
        .onChange(of: isWarning) { _, newWarning in
            if newWarning {
                hasTriggeredVLMForCurrentWarning = false
            }
        }
        // Observe entire history array changes
        .onChange(of: arManager.objectHistory) { _, newHistory in
            // When a new object is added, speak it once with cooldown
            if let newObjectName = newHistory.first {
                handleObjectNameUpdate(name: newObjectName)
            }
        }
        .onChange(of: arManager.isPointingAtGround) { _, isPointingDown in
            if isPointingDown {
                self.isWarning = false
                self.distanceString = "Scanning Ground"
                speechFeedbackTimer?.invalidate()
                speechFeedbackTimer = nil
            }
        }
        .onChange(of: isObstacleMode) { _, newMode in
            handleModeChange(isObstacleMode: newMode)
        }
    }
    
    /// Handle distance updates, UI text and haptic feedback in real time.
    private func handleDistanceUpdate(distance: Float) {
        guard !arManager.isPointingAtGround else {
            self.distanceString = "Scanning Ground"
            self.isWarning = false
            return
        }

        if distance > 0 {
            // In Voice Interaction Mode: simply show distance without warnings
            if !isObstacleMode {
                self.isWarning = false
                self.distanceString = String(format: "%.2f m", distance)
                return
            }
            
            // In Obstacle Avoidance Mode: show warnings and haptics
            if distance < warningDistance {
                // Check cooldown
                let now = Date()
                let shouldTriggerWarning: Bool
                
                if let lastTime = lastWarningTime {
                    shouldTriggerWarning = now.timeIntervalSince(lastTime) > warningCooldown
                } else {
                    shouldTriggerWarning = true
                }
                
                if shouldTriggerWarning {
                    self.isWarning = true
                    self.distanceString = String(format: "Danger! %.1f m", distance)
                    provideHapticFeedback(isWarning: true)
                    lastWarningTime = now
                    
                    // Trigger VLM advice once per warning (only in obstacle mode)
                    if !hasTriggeredVLMForCurrentWarning {
                        hasTriggeredVLMForCurrentWarning = true
                        requestVLMObstacleAvoidance(distance: distance)
                    }
                } else {
                    // Within cooldown: only update distance
                    self.distanceString = String(format: "Caution: %.1f m", distance)
                }
            } else {
                self.isWarning = false
                self.distanceString = String(format: "%.2f m", distance)
                
                // Reset VLM trigger when safe again
                if distance > warningDistance + 0.3 {
                    hasTriggeredVLMForCurrentWarning = false
                }
            }
        } else {
            self.isWarning = false
            self.distanceString = "Path Clear"
        }
    }
    
    /// Speak newly recognized object name with cooldown (only in obstacle mode).
    private func handleObjectNameUpdate(name: String) {
        guard speechFeedbackTimer == nil else { return }
        
        // Only speak object names in obstacle mode
        guard isObstacleMode else { return }
        
        if !name.isEmpty {
            provideSpeechFeedback(objectName: name, distance: arManager.distance)
            
            // 5s cooldown to reduce frequency
            speechFeedbackTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                self.speechFeedbackTimer?.invalidate()
                self.speechFeedbackTimer = nil
            }
        }
    }

    /// Speak TTS only.
    private func provideSpeechFeedback(objectName: String, distance: Float) {
        guard !objectName.isEmpty, distance > 0 else { return }
        
        let utteranceString = "\(objectName.capitalized), \(String(format: "%.1f meters", distance))"
        let utterance = AVSpeechUtterance(string: utteranceString)
        
        // Set English voice with increased volume
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.volume = 1.0  // Maximum volume for better audibility
        
        // Mark that we are speaking object info now
        isSpeakingObjectName = true
        
        speechSynthesizer.speak(utterance)
    }

    /// Trigger haptics with enhanced feedback for better awareness.
    private func provideHapticFeedback(isWarning: Bool) {
        guard let engine = hapticEngine, isWarning else { return }
        
        // Create very strong, longer haptic pattern with multiple pulses
        do {
            var events: [CHHapticEvent] = []
            
            // Create a pattern with 6 strong pulses for maximum noticeability
            for i in 0..<6 {
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                let event = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensity, sharpness],
                    relativeTime: TimeInterval(i) * 0.12  // 120ms apart for rapid, intense feedback
                )
                events.append(event)
            }
            
            // Add continuous rumble effect between pulses for extra intensity
            let continuousIntensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8)
            let continuousSharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            let continuousEvent = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [continuousIntensity, continuousSharpness],
                relativeTime: 0,
                duration: 0.7  // Duration covers all pulses
            )
            events.append(continuousEvent)
            
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            // Silently fail for haptic errors to reduce log noise
            // Haptic feedback is non-critical
        }
    }
    
    /// Prepare haptic engine
    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            
            // Handle engine reset (e.g., after audio session interruptions)
            engine.resetHandler = {
                print("Haptic engine reset")
                do {
                    try engine.start()
                } catch {
                    print("Failed to restart haptic engine after reset")
                }
            }
            
            // Handle engine stopped
            engine.stoppedHandler = { reason in
                print("Haptic engine stopped: \(reason.rawValue)")
            }
            
            try engine.start()
            hapticEngine = engine
            print("Haptic engine initialized successfully")
        } catch {
            print("Error creating haptic engine: \(error.localizedDescription)")
        }
    }
    
    /// Setup speech synthesizer delegate to pause ASR during TTS
    private func setupSpeechSynthesizer() {
        let delegate = SpeechSynthesizerDelegate()
        delegate.onStartSpeaking = { [weak speechRecognition] in
            speechRecognition?.pauseListening()
        }
        delegate.onFinishSpeaking = {
            // Resume ASR after any speech finishes
            self.speechRecognition.resumeListening()
            // If the last utterance was object info, clear history after 2 seconds
            if self.isSpeakingObjectName {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if self.isSpeakingObjectName {
                        withAnimation {
                            self.arManager.objectHistory.removeAll()
                            self.isSpeakingObjectName = false
                        }
                    }
                }
            }
        }
        delegate.onFinishVLMSpeaking = {
            // Close the VLM response UI 1 second after speech finishes
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.isSpeakingVLMResponse {
                    withAnimation {
                        self.showVLMResponse = false
                        self.isSpeakingVLMResponse = false
                    }
                }
            }
        }
        speechDelegate = delegate
        speechSynthesizer.delegate = delegate
    }
    
    // MARK: - VLM interactions
    
    /// Start continuous voice listening
    private func startVoiceListening() {
        speechRecognition.startContinuousListening { recognizedText in
            self.handleVoiceQuery(recognizedText)
        }
    }
    
    /// Handle voice query (auto triggered)
    private func handleVoiceQuery(_ query: String) {
        print("Handle voice query: \(query)")
        
        // Clear transcription immediately for fresh UI and state
        speechRecognition.clearTranscription()
        
        // Stop current TTS to prioritize new query
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
            print("Stopped previous speech output")
        }
        
        // Use recognized text to query VLM
        guard let currentImage = arManager.currentFrameImage else {
            speakText("Unable to capture image")
            return
        }
        
        // Prevent duplicate processing
        guard !isProcessingVLM else {
            print("VLM is processing; skip this query")
            return
        }
        
        isProcessingVLM = true
        
        // Auto-clear ASR transcription shortly after sending request
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.speechRecognition.currentTranscription = ""
        }
        
        VLMService.shared.handleNaturalLanguageQuery(query: query, image: currentImage) { result in
            DispatchQueue.main.async {
                self.isProcessingVLM = false
                
                switch result {
                case .success(let response):
                    self.vlmResponse = response
                    self.showVLMResponse = true
                    self.isSpeakingVLMResponse = true
                    self.speakVLMText(response)
                    
                case .failure(let error):
                    print("VLM request failed: \(error.localizedDescription)")
                    self.speakText("Sorry, I couldn't process your request")
                }
            }
        }
    }
    
    /// Request VLM obstacle avoidance advice when warning triggers
    private func requestVLMObstacleAvoidance(distance: Float) {
        guard let currentImage = arManager.currentFrameImage else {
            return
        }
        
        // Use latest detected object
        let detectedObject = arManager.objectHistory.first ?? "obstacle"
        
        isProcessingVLM = true
        
        VLMService.shared.getObstacleAvoidanceAdvice(image: currentImage, detectedObject: detectedObject, distance: distance) { result in
            DispatchQueue.main.async {
                self.isProcessingVLM = false
                
                switch result {
                case .success(let advice):
                    self.vlmResponse = advice
                    self.showVLMResponse = true
                    self.isSpeakingVLMResponse = true
                    self.speakVLMText(advice)
                    
                case .failure(let error):
                    print("VLM advice request failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Speak text (TTS)
    private func speakText(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        
        // Set English voice with increased volume
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.volume = 1.0  // Maximum volume for better audibility
        
        speechSynthesizer.speak(utterance)
    }
    
    /// Speak VLM response text (will auto-close UI after speech finishes)
    private func speakVLMText(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        
        // Set English voice with increased volume
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.volume = 1.0  // Maximum volume for better audibility
        
        speechSynthesizer.speak(utterance)
    }
    
    // MARK: - Mode Management
    
    /// Handle mode change between obstacle avoidance and voice interaction
    private func handleModeChange(isObstacleMode: Bool) {
        print("Mode changed to: \(isObstacleMode ? "Obstacle Avoidance" : "Voice Interaction")")
        
        // Stop any ongoing speech
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        // Clear VLM response display
        withAnimation {
            showVLMResponse = false
            vlmResponse = ""
            isSpeakingVLMResponse = false
        }
        
        if isObstacleMode {
            // Switched to obstacle avoidance mode
            hasDescribedEnvironmentInVoiceMode = false
            // Reset VLM processing flag to ensure clean state
            isProcessingVLM = false
            speakText("Obstacle avoidance mode activated")
            
        } else {
            // Switched to voice interaction mode
            speakText("Voice interaction mode activated")
            
            // Reset flag to allow environment description
            hasDescribedEnvironmentInVoiceMode = false
            
            // Wait for any ongoing VLM processing to complete before describing environment
            if isProcessingVLM {
                print("Waiting for VLM processing to complete before environment description")
                // Schedule retry after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if !self.isObstacleMode {  // Still in voice mode
                        self.describeEnvironmentForVoiceMode()
                    }
                }
            } else {
                // Automatically describe environment when entering voice interaction mode
                describeEnvironmentForVoiceMode()
            }
        }
    }
    
    /// Describe the current environment when entering voice interaction mode
    private func describeEnvironmentForVoiceMode() {
        // Prevent duplicate descriptions
        guard !hasDescribedEnvironmentInVoiceMode else { return }
        
        guard let currentImage = arManager.currentFrameImage else {
            print("No image available for environment description")
            return
        }
        
        // Prevent duplicate processing
        guard !isProcessingVLM else {
            print("VLM is processing; skip environment description")
            return
        }
        
        isProcessingVLM = true
        hasDescribedEnvironmentInVoiceMode = true
        
        // Small delay to allow mode switch speech to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            VLMService.shared.describeEnvironment(image: currentImage) { result in
                DispatchQueue.main.async {
                    self.isProcessingVLM = false
                    
                    switch result {
                    case .success(let description):
                        self.vlmResponse = description
                        self.showVLMResponse = true
                        self.isSpeakingVLMResponse = true
                        self.speakVLMText(description)
                        
                    case .failure(let error):
                        print("Environment description failed: \(error.localizedDescription)")
                        self.speakText("Unable to describe environment")
                    }
                }
            }
        }
    }
    
    // Playback session switching removed to avoid audio session churn
}

// MARK: - Speech Synthesizer Delegate
class SpeechSynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onStartSpeaking: (() -> Void)?
    var onFinishSpeaking: (() -> Void)?
    var onFinishVLMSpeaking: (() -> Void)?
    
    private var isVLMUtterance = false
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("Speech started; pause ASR and switch to playback")
        
        // Check if this is a VLM response (longer text, typically > 10 words)
        let wordCount = utterance.speechString.split(separator: " ").count
        isVLMUtterance = wordCount > 5  // VLM responses are usually longer
        
        DispatchQueue.main.async {
            self.onStartSpeaking?()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("Speech finished; resume listening")
        DispatchQueue.main.async {
            self.onFinishSpeaking?()
            
            // If this was a VLM response, trigger VLM-specific callback
            if self.isVLMUtterance {
                self.onFinishVLMSpeaking?()
                self.isVLMUtterance = false
            }
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("Speech cancelled; resume listening")
        DispatchQueue.main.async {
            self.onFinishSpeaking?()
            self.isVLMUtterance = false
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif


