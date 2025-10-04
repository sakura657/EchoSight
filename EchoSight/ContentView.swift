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
    
    // Warning cooldown
    @State private var lastWarningTime: Date?
    private let warningCooldown: TimeInterval = 3.0  // cooldown seconds

    var body: some View {
        ZStack {
            ARViewContainer(arManager: arManager)
                .ignoresSafeArea()

            // Layout UI elements at top and bottom
            VStack {
                // MARK: - Top: object history and AI suggestions
                VStack(alignment: .center, spacing: 8) {
                    // Iterate object history (use index as ID to avoid duplicates)
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
    }
    
    /// Handle distance updates, UI text and haptic feedback in real time.
    private func handleDistanceUpdate(distance: Float) {
        guard !arManager.isPointingAtGround else {
            self.distanceString = "Scanning Ground"
            self.isWarning = false
            return
        }

        if distance > 0 {
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
                    
                    // Trigger VLM advice once per warning
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
    
    /// Speak newly recognized object name with cooldown.
    private func handleObjectNameUpdate(name: String) {
        guard speechFeedbackTimer == nil else { return }
        
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
        
        // Natural voice parameters
        configureNaturalVoice(utterance: utterance)
        
        // Playback session switching removed to avoid audio session churn
        
        speechSynthesizer.speak(utterance)
    }

    /// Trigger haptics.
    private func provideHapticFeedback(isWarning: Bool) {
        guard let engine = hapticEngine, isWarning else { return }
        
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
        
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            // Keep minimal logging
            print("Failed to play haptic pattern: \(error.localizedDescription)")
        }
    }
    
    /// Prepare haptic engine
    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
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
        delegate.onFinishSpeaking = { [weak speechRecognition] in
            speechRecognition?.resumeListening()
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
                    self.speakText(response)
                    
                    // Auto hide after 15s
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                        withAnimation {
                            self.showVLMResponse = false
                        }
                    }
                    
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
                    self.speakText(advice)
                    
                    // Auto hide after 10s
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                        withAnimation {
                            self.showVLMResponse = false
                        }
                    }
                    
                case .failure(let error):
                    print("VLM advice request failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Speak text (TTS)
    private func speakText(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        
        // Natural voice parameters
        configureNaturalVoice(utterance: utterance)
        
        // Playback session switching removed to avoid audio session churn
        
        speechSynthesizer.speak(utterance)
    }
    
    /// Configure natural-sounding voice parameters
    private func configureNaturalVoice(utterance: AVSpeechUtterance) {
        // Use Allison (Enhanced) voice
        utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-US.Allison")
        
        // Tune speech parameters
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.15
        utterance.postUtteranceDelay = 0.1
    }
    
    // Playback session switching removed to avoid audio session churn
}

// MARK: - Speech Synthesizer Delegate
class SpeechSynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onStartSpeaking: (() -> Void)?
    var onFinishSpeaking: (() -> Void)?
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("Speech started; pause ASR and switch to playback")
        DispatchQueue.main.async {
            self.onStartSpeaking?()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("Speech finished; resume listening")
        DispatchQueue.main.async {
            self.onFinishSpeaking?()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("Speech cancelled; resume listening")
        DispatchQueue.main.async {
            self.onFinishSpeaking?()
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


