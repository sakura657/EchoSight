//
//  SpeechRecognitionService.swift
//  EchoSight
//
//  This service handles continuous speech recognition (ASR)
//

import Foundation
import Speech
import AVFoundation
import Combine

class SpeechRecognitionService: ObservableObject {
    
    @Published var isListening = false
    @Published var isAuthorized = false
    
    // Use en-US recognizer with dictation hint
    private var speechRecognizer: SFSpeechRecognizer? = {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        recognizer?.defaultTaskHint = .dictation
        return recognizer
    }()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // Continuous listening callback
    private var onQueryDetected: ((String) -> Void)?
    
    // Silence timer and minimum words
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 3.0
    @Published var currentTranscription = ""
    private let minimumWordCount = 2
    
    // Pause/resume to avoid capturing TTS output
    private var isPaused = false
    private var shouldResumeAfterPause = false
    
    // Retry controls
    private var retryCount = 0
    private let maxRetries = 3
    
    // Serialize session start/restart
    private var isStarting = false
    private var restartWorkItem: DispatchWorkItem?
    
    // Audio session state
    private var audioSessionConfigured = false
    
    // Drop initial empty buffers during mic warm-up
    private var droppedSilentBuffers = 0
    private let maxDroppedSilentBuffers = 5
    
    // Removed Whisper integration
    
    init() {
        
    }
    
    /// Clear current transcription immediately (for UI responsiveness)
    func clearTranscription() {
        DispatchQueue.main.async {
            self.currentTranscription = ""
        }
    }
    
    /// Request speech recognition authorization
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self.isAuthorized = true
                    print("Speech recognition authorized")
                    completion(true)
                case .denied:
                    self.isAuthorized = false
                    print("Speech recognition permission denied")
                    completion(false)
                case .restricted:
                    self.isAuthorized = false
                    print("Speech recognition restricted on this device")
                    completion(false)
                case .notDetermined:
                    self.isAuthorized = false
                    print("Speech recognition authorization not determined")
                    completion(false)
                @unknown default:
                    self.isAuthorized = false
                    completion(false)
                }
            }
        }
    }
    
    /// Start continuous listening
    func startContinuousListening(onQueryDetected: @escaping (String) -> Void) {
        self.onQueryDetected = onQueryDetected
        startListeningSession()
    }
    
    /// Stop continuous listening
    func stopContinuousListening() {
        stopListeningSession()
        onQueryDetected = nil
    }
    
    /// Pause recognition (avoid echo during TTS)
    func pauseListening() {
        guard isListening else { return }
        
        isPaused = true
        shouldResumeAfterPause = true
        stopListeningSession()
        print("Speech recognition paused")
    }
    
    /// Resume recognition
    func resumeListening() {
        guard shouldResumeAfterPause else { return }
        
        isPaused = false
        shouldResumeAfterPause = false
        
        // Short delay to ensure TTS fully finishes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.startListeningSession()
            print("Speech recognition resumed")
        }
    }
    
    /// Start a listening session
    private func startListeningSession() {
        // Check authorization
        guard isAuthorized else {
            print("Speech recognition not authorized")
            return
        }
        
        // Prevent overlapping starts
        guard !isStarting else { return }
        isStarting = true
        
        // If already listening, stop first
        if isListening {
            stopListeningSession()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isStarting = false
                self.startListeningSession()
            }
            return
        }
        
        // Reset state
        currentTranscription = ""
        droppedSilentBuffers = 0
        
        // Configure audio session using Apple's built-in echo cancellation (voiceChat)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            if !audioSessionConfigured {
                try audioSession.setCategory(.playAndRecord,
                                            mode: .voiceChat,
                                            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .mixWithOthers])
                try audioSession.setPreferredInputNumberOfChannels(1)
                try audioSession.setPreferredIOBufferDuration(0.02)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                audioSessionConfigured = true
                print("Audio session configured with voiceChat for echo cancellation")
            }
        } catch {
            print("Audio session configuration failed: \(error)")
        }
        
        // Create request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            print("Failed to create recognition request")
            isStarting = false
            return
        }
        
        // Configure recognition
        recognitionRequest.shouldReportPartialResults = true
        
        // Add contextual strings
        recognitionRequest.contextualStrings = [
            "what ahead", "what's ahead", "what is ahead",
            "what's that", "what is that",
            "describe surroundings", "describe my surroundings",
            "is it safe", "is it safe to walk",
            "how far", "how far is", "how far is the obstacle",
            "turn left", "turn right", "move forward", "go straight",
            "chair", "table", "door", "wall", "stairs", "person",
            "obstacle", "object", "distance"
        ]
        
        // On-device if available
        if #available(iOS 13.0, *) {
            // Prefer on-device to reduce latency/jitter if supported
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        
        // Search/navigation scene hint
        if #available(iOS 16.0, *) {
            recognitionRequest.addsPunctuation = false  // fewer misrecognitions
        }
        
        // Input node
        let inputNode = audioEngine.inputNode
        
        // Start task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                
                DispatchQueue.main.async {
                    self.currentTranscription = transcription
                    
                    // Reset silence timer
                    self.resetSilenceTimer {
                        self.processTranscription()
                    }
                }
            }
            
            // Restart on error or final
            if let error = error {
                let errorMsg = error.localizedDescription
                print("Speech recognition error: \(errorMsg)")
            }
            
            if error != nil || result?.isFinal == true {
                DispatchQueue.main.async {
                    self.stopListeningSession()
                    
                    // Don't restart while paused (TTS in progress)
                    if self.isPaused { return }
                    
                    // Debounced restart to avoid duplicates
                    self.restartWorkItem?.cancel()
                    let delay = TimeInterval(min(self.retryCount + 2, 5))
                    let work = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        print("Restart continuous listening...")
                        self.startListeningSession()
                    }
                    self.restartWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                }
            }
        }
        
        // Use hardware input format to avoid format mismatch when installing tap
        let recordingFormat = inputNode.inputFormat(forBus: 0)
        
        // Validate basic properties
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            print("Invalid audio format detected, aborting session")
            isStarting = false
            return
        }
        
        print("Using audio format: \(recordingFormat.channelCount) ch, \(recordingFormat.sampleRate) Hz")
        
        // Remove existing tap if any
        if inputNode.numberOfInputs > 0 {
            inputNode.removeTap(onBus: 0)
        }
        
        // Install tap with hardware (input) format to match the microphone stream
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // Drop a few initial empty buffers during mic warm-up
            if buffer.frameLength == 0 {
                if self.droppedSilentBuffers < self.maxDroppedSilentBuffers {
                    self.droppedSilentBuffers += 1
                }
                return
            }
            
            guard let request = self.recognitionRequest else { return }
            request.append(buffer)
        }
        
        // Start engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isListening = true
                self.isStarting = false
                print("Start continuous listening")
            }
        } catch {
            self.isStarting = false
            print("Audio engine failed to start: \(error)")
        }
    }
    
    /// Stop session
    private func stopListeningSession() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        // Safely remove tap before stopping engine
        let inputNode = audioEngine.inputNode
        if inputNode.numberOfInputs > 0 {
            inputNode.removeTap(onBus: 0)
        }
        
        // End audio before stopping engine to avoid zero-size buffers
        recognitionRequest?.endAudio()
        
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // Reset audio engine to prevent format mismatch on restart
        audioEngine.reset()
        
        // Prefer finishing the task over cancel to reduce spurious errors
        recognitionTask?.finish()
        
        recognitionTask = nil
        recognitionRequest = nil
        
        DispatchQueue.main.async {
            self.isListening = false
        }
    }
    
    /// Process recognized text
    private func processTranscription() {
        // Ignore during pause
        guard !isPaused else {
            print("Paused; ignore result")
            // Clear transcription after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                self.currentTranscription = ""
            }
            return
        }
        
        let text = currentTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Filter noise with minimum word count
        let wordCount = text.split(separator: " ").count
        
        if wordCount >= minimumWordCount {
            print("Valid query (\(wordCount) words): \(text)")
            onQueryDetected?(text)
            
            // Caller will clear transcription
        } else if !text.isEmpty {
            print("Query too short (\(wordCount) words): ignored")
            // Clear short queries immediately
            currentTranscription = ""
        } else {
            // Clear empty text
            currentTranscription = ""
        }
    }
    
    /// Reset silence timer
    private func resetSilenceTimer(completion: @escaping () -> Void) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { _ in
            completion()
        }
    }
}


