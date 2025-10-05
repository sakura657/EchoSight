import SwiftUI
import RealityKit
import AVFoundation
import CoreHaptics

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arManager: ARManager

    func makeUIView(context: Context) -> ARView {
        print("ARViewContainer: Creating ARView")
        return arManager.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        print("ARViewContainer: Updating ARView, session running: \(arManager.isSessionRunning)")
        // Keep minimal; do not rewire sessions here
    }
}

struct ContentView: View {
    @StateObject private var navigationARManager = ARManager()
    @StateObject private var indoorARManager = ARManager()
    @StateObject private var speechRecognition = SpeechRecognitionService()
    private let speechSynthesizer = AVSpeechSynthesizer()
    @State private var speechDelegate: SpeechSynthesizerDelegate?
    @State private var hapticEngine: CHHapticEngine?
    
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView(arManager: navigationARManager, speechRecognition: speechRecognition, speechSynthesizer: speechSynthesizer, speechDelegate: $speechDelegate, hapticEngine: $hapticEngine)
                .tabItem {
                    Image(systemName: "location.fill")
                    Text("Navigation")
                }
                .tag(0)
            
            ObjectRecognitionView(arManager: indoorARManager, speechRecognition: speechRecognition, speechSynthesizer: speechSynthesizer, speechDelegate: $speechDelegate, hapticEngine: $hapticEngine)
                .tabItem {
                    Image(systemName: "eye.fill")
                    Text("Indoor")
                }
                .tag(1)
        }
        .onAppear {
            prepareHaptics()
            setupSpeechSynthesizer()
            
            // Start Navigation AR session immediately
            print("Starting Navigation AR session on app appear")
            navigationARManager.startSession()
            
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
            navigationARManager.stopSession()
            indoorARManager.stopSession()
            speechRecognition.stopContinuousListening()
        }
        .onChange(of: selectedTab) { _, newTab in
            print("Tab changed to: \(newTab)")
            
            if newTab == 0 {
                // Switch to Navigation tab
                print("Stopping Indoor AR session...")
                indoorARManager.stopSession()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    print("Starting Navigation AR session...")
                    self.navigationARManager.startSession()
                }
            } else {
                // Switch to Indoor tab
                print("Stopping Navigation AR session...")
                navigationARManager.stopSession()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    print("Starting Indoor AR session...")
                    self.indoorARManager.startSession()
                }
            }
        }
    }
    
    // MARK: - Common Setup Methods
    
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
    
    /// Start continuous voice listening
    private func startVoiceListening() {
        speechRecognition.startContinuousListening { recognizedText in
            // This will be handled by individual views
        }
    }
}

// MARK: - Navigation View (Obstacle Avoidance)
struct NavigationView: View {
    @ObservedObject var arManager: ARManager
    @ObservedObject var speechRecognition: SpeechRecognitionService
    let speechSynthesizer: AVSpeechSynthesizer
    @Binding var speechDelegate: SpeechSynthesizerDelegate?
    @Binding var hapticEngine: CHHapticEngine?
    
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
                // MARK: - Top: Navigation AI suggestions
                VStack(alignment: .center, spacing: 8) {
                    // Mode indicator
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                        Text("Navigation Mode")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
                    
                    // VLM response for navigation
                    if showVLMResponse && !vlmResponse.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "brain.head.profile")
                                    .foregroundColor(.blue)
                                Text("Navigation Advice:")
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
                .animation(.easeInOut, value: showVLMResponse)
                .animation(.easeInOut, value: speechRecognition.isListening)
                
                Spacer()

                // MARK: - Bottom: live transcription and distance info
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
            startNavigationMode()
        }
        .onChange(of: arManager.distance) { _, newDistance in
            handleDistanceUpdate(distance: newDistance)
        }
        .onChange(of: isWarning) { _, newWarning in
            if newWarning {
                hasTriggeredVLMForCurrentWarning = false
            }
        }
        .onChange(of: arManager.isPointingAtGround) { _, isPointingDown in
            if isPointingDown {
                self.isWarning = false
                self.distanceString = "扫描地面"
                speechFeedbackTimer?.invalidate()
                speechFeedbackTimer = nil
            }
        }
        .onChange(of: speechRecognition.currentTranscription) { _, newTranscription in
            if !newTranscription.isEmpty {
                handleNavigationVoiceQuery(newTranscription)
            }
        }
    }
    
    // MARK: - Navigation Mode Methods
    
    private func startNavigationMode() {
        // Start voice listening for navigation queries
        speechRecognition.startContinuousListening { recognizedText in
            // This will be handled by onChange
        }
    }
    
    private func handleNavigationVoiceQuery(_ query: String) {
        print("Navigation voice query: \(query)")
        
        // Clear transcription immediately
        speechRecognition.clearTranscription()
        
        // Stop current TTS
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        // Use recognized text to query VLM for navigation
        guard let currentImage = arManager.currentFrameImage else {
            speakText("Unable to capture image")
            return
        }
        
        guard !isProcessingVLM else {
            print("VLM is processing; skip this query")
            return
        }
        
        isProcessingVLM = true
        
        // Auto-clear ASR transcription shortly after sending request
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.speechRecognition.currentTranscription = ""
        }
        
        VLMService.shared.handleNavigationQuery(query: query, image: currentImage) { result in
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
                    print("VLM navigation request failed: \(error.localizedDescription)")
                    self.speakText("Sorry, couldn't process your navigation request")
                }
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
            print("Failed to play haptic pattern: \(error.localizedDescription)")
        }
    }
    
    /// Speak text (TTS)
    private func speakText(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        configureNaturalVoice(utterance: utterance)
        speechSynthesizer.speak(utterance)
    }
    
    /// Configure natural-sounding voice parameters
    private func configureNaturalVoice(utterance: AVSpeechUtterance) {
        utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-US.Allison")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.15
        utterance.postUtteranceDelay = 0.1
    }
}

// MARK: - Object Recognition View
struct ObjectRecognitionView: View {
    @ObservedObject var arManager: ARManager
    @ObservedObject var speechRecognition: SpeechRecognitionService
    let speechSynthesizer: AVSpeechSynthesizer
    @Binding var speechDelegate: SpeechSynthesizerDelegate?
    @Binding var hapticEngine: CHHapticEngine?
    
    // VLM state
    @State private var vlmResponse = ""
    @State private var showVLMResponse = false
    @State private var isProcessingVLM = false
    
    // Speech feedback timer
    @State private var speechFeedbackTimer: Timer?

    var body: some View {
        ZStack {
            ARViewContainer(arManager: arManager)
                .ignoresSafeArea()

            VStack {
                // MARK: - Top: Object recognition UI
                VStack(alignment: .center, spacing: 8) {
                    // Mode indicator
                    HStack {
                        Image(systemName: "eye.fill")
                            .foregroundColor(.green)
                        Text("Object Recognition Mode")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(8)
                    
                    // Object history
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
                    
                    // VLM response for object recognition
                    if showVLMResponse && !vlmResponse.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "brain.head.profile")
                                    .foregroundColor(.green)
                                Text("Object Analysis:")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                            }
                            
                            Text(verbatim: vlmResponse)
                                .font(.body)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(12)
                        .background(Color.green.opacity(0.8))
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

                // MARK: - Bottom: live transcription
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
                    
                    // Object recognition status
                    Text("Recognizing Objects...")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.green.opacity(0.7))
                        .cornerRadius(15)
                }
                .padding(.bottom, 5)
            }
            .padding()
            .animation(.easeInOut, value: speechRecognition.currentTranscription)
        }
        .onAppear {
            startObjectRecognitionMode()
        }
        .onChange(of: arManager.objectHistory) { _, newHistory in
            if let newObjectName = newHistory.first {
                handleObjectNameUpdate(name: newObjectName)
            }
        }
        .onChange(of: speechRecognition.currentTranscription) { _, newTranscription in
            if !newTranscription.isEmpty {
                handleObjectRecognitionVoiceQuery(newTranscription)
            }
        }
    }
    
    // MARK: - Object Recognition Methods
    
    private func startObjectRecognitionMode() {
        // Start voice listening for object recognition queries
        speechRecognition.startContinuousListening { recognizedText in
            // This will be handled by onChange
        }
    }
    
    private func handleObjectNameUpdate(name: String) {
        guard speechFeedbackTimer == nil else { return }
        
        if !name.isEmpty {
            provideSpeechFeedback(objectName: name)
            
            // 5s cooldown to reduce frequency
            speechFeedbackTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                self.speechFeedbackTimer?.invalidate()
                self.speechFeedbackTimer = nil
            }
        }
    }
    
    private func handleObjectRecognitionVoiceQuery(_ query: String) {
        print("Object recognition voice query: \(query)")
        
        // Clear transcription immediately
        speechRecognition.clearTranscription()
        
        // Stop current TTS
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        // Use recognized text to query VLM for object recognition
        guard let currentImage = arManager.currentFrameImage else {
            speakText("Unable to capture image")
            return
        }
        
        guard !isProcessingVLM else {
            print("VLM is processing; skip this query")
            return
        }
        
        isProcessingVLM = true
        
        // Auto-clear ASR transcription shortly after sending request
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.speechRecognition.currentTranscription = ""
        }
        
        VLMService.shared.handleObjectRecognitionQuery(query: query, image: currentImage) { result in
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
                    print("VLM object recognition request failed: \(error.localizedDescription)")
                    self.speakText("Sorry, couldn't process your object recognition request")
                }
            }
        }
    }
    
    private func provideSpeechFeedback(objectName: String) {
        guard !objectName.isEmpty else { return }
        
        let utteranceString = "Detected \(objectName.capitalized)"
        let utterance = AVSpeechUtterance(string: utteranceString)
        configureNaturalVoice(utterance: utterance)
        speechSynthesizer.speak(utterance)
    }
    
    private func speakText(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        configureNaturalVoice(utterance: utterance)
        speechSynthesizer.speak(utterance)
    }
    
    private func configureNaturalVoice(utterance: AVSpeechUtterance) {
        utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-US.Allison")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.15
        utterance.postUtteranceDelay = 0.1
    }
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


