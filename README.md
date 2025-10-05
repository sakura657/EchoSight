# EchoSight - AI-Powered Navigation Assistant for the Visually Impaired

> 🎯 **Elevator Pitch**  
> 
> EchoSight is an iOS AR navigation assistant designed for visually impaired users, combining cutting-edge technologies to provide real-time obstacle awareness and intelligent voice interaction. The app leverages iPhone's LiDAR sensor for precise distance measurement, on-device object recognition (FastViT Core ML model), and cloud-based visual language model (Google's Gemini 2.5 Flash Lite) to deliver comprehensive environmental understanding.
>
> With two specialized modes—Obstacle Avoidance for safety-focused navigation and Voice Interaction for natural scene exploration—EchoSight empowers blind and low-vision users to navigate their surroundings with greater confidence and independence.
>
> **Developed by**: Bobby Tang & Yuan Gao

## 📱 Demo

### Obstacle Avoidance Mode
<!-- Place obstacle avoidance mode GIF here -->
![Obstacle Avoidance Mode Demo](./Resources/Demo2.gif)

### Voice Interaction Mode
<!-- Place voice interaction mode GIF here -->
![Voice Interaction Mode Demo](./Resources/Demo1.gif)

## ✨ Core Features

### 🚨 Obstacle Avoidance Mode
- **Real-time LiDAR Distance Measurement**: Continuously scans forward obstacles, auto-triggers danger warning when < 0.5m
- **Object Recognition**: On-device object classification using FastViT Core ML model
- **Smart Voice Announcements**: Automatically speaks detected object name and distance (e.g., "Chair, 0.8 meters")
- **Strong Haptic Feedback**: Provides 6 intense vibration pulses + continuous rumble when approaching obstacles
- **AI Avoidance Suggestions**: Automatically invokes VLM to provide brief avoidance guidance (≤10 words) when warning triggers

### 💬 Voice Interaction Mode
- **Continuous Speech Recognition**: Real-time voice recognition based on Apple Speech Framework (supports on-device processing)
- **Natural Language Conversation**: Users can freely ask questions (e.g., "What's ahead?" "Is it safe to walk?")
- **Environment Description**: Automatically describes the current environment when switching to this mode
- **Scene-Aware Q&A**: Answers user questions by combining camera feed and VLM (Gemini 2.5 Flash Lite)
- **Echo Cancellation**: Uses voiceChat audio mode to prevent TTS output from interfering with ASR

### 🔄 Common Features
- **Mode Switching**: One-tap toggle between obstacle avoidance and voice interaction modes
- **Pause/Resume Mechanism**: Automatically pauses speech recognition during TTS playback to prevent echo interference
- **Cooldown Control**: Prevents overly frequent warnings and voice announcements
- **Visual + Audio Dual Output**: UI display + TTS speech for multi-sensory feedback

## 📁 Project Structure

```
EchoSight/
├── EchoSightApp.swift             # App entry point
├── ContentView.swift              # Main UI (SwiftUI)
│                                  # - Mode switching logic
│                                  # - Speech recognition integration
│                                  # - VLM interaction handling
│                                  # - Haptic feedback
├── ARManager.swift                # AR session management
│                                  # - LiDAR scene reconstruction
│                                  # - Multi-point raycast distance measurement
│                                  # - FastViT object recognition
│                                  # - Camera frame image extraction
├── VLMService.swift               # VLM service client
│                                  # - Obstacle avoidance advice
│                                  # - Natural language scene Q&A
│                                  # - Environment description
│                                  # - OpenRouter API integration
├── SpeechRecognitionService.swift # Speech recognition service
│                                  # - Continuous voice listening
│                                  # - Silence detection (3s timeout)
│                                  # - Pause/resume mechanism
│                                  # - Echo cancellation configuration
├── Config.swift                   # Configuration management
│                                  # - API key loading
│                                  # - Read from Secrets.plist
└── FastViTMA36F16.mlpackage/      # FastViT Core ML model
                                   # - On-device object recognition
                                   # - 1000+ category support
```

## 📋 Requirements

- **Device**: iPhone 12 Pro or newer (LiDAR required)
- **OS**: iOS 15.0+
- **Development**: Xcode 14.0+
- **Language**: Swift 5.9+
- **Permissions**:
  - Camera access
  - Microphone access
  - Speech recognition

## 🚀 Setup

### 1. Clone the Project
```bash
git clone https://github.com/sakura657/EchoSight.git
cd EchoSight
open EchoSight.xcodeproj
```

### 2. Configure Permissions
The project has pre-configured permission descriptions in Info.plist:
- `NSCameraUsageDescription` - For AR scene reconstruction and object recognition
- `NSMicrophoneUsageDescription` - For speech recognition
- `NSSpeechRecognitionUsageDescription` - For speech recognition service

### 3. Configure API Key
Create `EchoSight/Secrets.plist` file (**NOT committed to Git**):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>OPENROUTER_API_KEY</key>
	<string>your_openrouter_api_key_here</string>
</dict>
</plist>
```

> 💡 **Tip**: The app searches for API keys in this priority order:  
> `Secrets.plist` → `Info.plist` → Environment variables  
> See `Config.swift` for implementation details.

### 4. Get OpenRouter API Key
1. Visit [OpenRouter](https://openrouter.ai/)
2. Sign up and obtain an API key
3. Add the key to the `Secrets.plist` file above

### 5. Build and Run
- Select a LiDAR-capable device (iPhone 12 Pro or newer)
- Press `Cmd+R` to build and run
- Grant all permissions on first launch

## 📖 Usage Guide

### Basic Operations
1. **Launch App**: The app automatically starts AR + LiDAR scanning and voice listening
2. **Mode Switching**: Tap the top toggle button to switch between two modes
   - 🟠 **Orange Icon**: Obstacle Avoidance Mode
   - 🔵 **Blue Icon**: Voice Interaction Mode

### Using Obstacle Avoidance Mode
- 📏 **Real-time Distance**: Bottom banner shows current distance (in meters)
- ⚠️ **Danger Warning**: When distance < 0.5m, displays red warning + strong vibration
- 🏷️ **Object Recognition**: Top area shows recognized object name
- 🔊 **Voice Announcements**: Automatically speaks object and distance (5s cooldown)
- 🤖 **AI Suggestions**: AI automatically provides brief avoidance guidance when warning triggers

### Using Voice Interaction Mode
- 🎤 **Free Questioning**: Simply speak your question, no button needed (auto-sends after 3s silence)
- 🌍 **Environment Description**: Automatically describes environment when switching to this mode
- 💬 **Conversation Examples**:
  - "What's ahead?"
  - "Is it safe to walk?"
  - "Describe my surroundings"
  - "How far is the obstacle?"
- 📱 **Real-time Feedback**: 
  - Green box shows speech being recognized
  - Blue box shows AI response
  - AI response is automatically read aloud

### Important Notes
- ⚡ **Battery Consumption**: LiDAR and continuous speech recognition consume significant power
- 🌐 **Network Required**: Voice interaction mode requires internet connection (for VLM API)
- 🎯 **Best Usage**: Works best in well-lit environments with rich visual features
- 🔇 **Echo Handling**: Speech recognition automatically pauses during TTS playback to avoid interference

## 🔒 Security and Git Hygiene

### Protecting Sensitive Information
- ⚠️ **Do NOT commit secrets**: `.gitignore` is configured to exclude:
  - `EchoSight/Secrets.plist`
  - `.env*`
  - Large model weight files
  - Core ML compiled products

### Best Practices
- Store all API keys in `Secrets.plist`
- Never hardcode sensitive information in code
- Rotate API keys regularly
- Avoid committing large binary files (model weights should be downloaded externally or use Git LFS)

## 🔧 Technical Details

### Performance Optimizations
- **FastViT Throttling**: Runs every 1 second or 60 frames to avoid impacting speech recognition performance
- **Image Update Limiting**: VLM snapshots update every 0.5 seconds to reduce CPU load
- **CIContext Reuse**: Uses hardware-accelerated CIContext uniformly for image processing
- **Background Thread Processing**: Vision requests and image conversions execute on background threads
- **Autorelease Pools**: Uses `autoreleasepool` to prevent memory spikes from ARFrame retention

### Speech Processing Details
- **On-Device First**: iOS 13+ prioritizes on-device speech recognition to reduce latency
- **Echo Cancellation**: Uses `voiceChat` audio mode for system-level echo handling
- **Silence Detection**: Auto-sends query after 3 seconds of silence
- **Minimum Word Filter**: Requires at least 2 words to process, reducing false recognitions
- **Contextual Hints**: Provides common phrase list to improve recognition accuracy

### VLM Integration
- **Model**: Defaults to `google/gemini-2.5-flash-lite-preview-09-2025`
- **Image Compression**: Auto-compresses images to under 15MB, balancing quality and speed
- **Prompt Engineering**: Optimized prompts for visually impaired users, requesting concise replies (10-20 words)
- **Custom Model**: Can modify the `model` constant in `VLMService.swift`

### AR Tracking
- **Multi-Point Raycasting**: Uses 3 screen points for raycasting to improve detection reliability
- **Ground Detection**: Automatically identifies downward-pointing to ground scenarios to avoid false alarms
- **Mesh Reconstruction**: Uses LiDAR scene mesh reconstruction for improved accuracy
- **Plane Detection**: Enables both horizontal and vertical plane detection
- **Depth Semantics**: Enables sceneDepth on supported devices for enhanced scene understanding

## 📝 Tech Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| UI Framework | SwiftUI | Declarative interface building |
| AR Engine | ARKit + RealityKit | LiDAR scanning and scene reconstruction |
| Object Recognition | Core ML (FastViT) | On-device real-time object classification |
| Speech Recognition | Speech Framework | Continuous speech-to-text |
| Speech Synthesis | AVSpeechSynthesizer | Text-to-speech announcements |
| Haptic Feedback | Core Haptics | Strong vibration warnings |
| VLM API | OpenRouter (Gemini 2.5 Flash Lite) | Visual Q&A and environment understanding |
| Configuration | PropertyList | Secure API key storage |

## 🛠️ Troubleshooting

### Common Issues

**Q: Speech recognition not working?**
- Check if microphone permission is granted
- Ensure system speech recognition permission is enabled
- Try restarting the app
- Check if TTS is currently playing (ASR pauses automatically)

**Q: VLM response errors?**
- Verify API key in `Secrets.plist` is correct
- Ensure network connection is stable
- Check OpenRouter account balance
- Review Xcode console logs for detailed errors

**Q: LiDAR distance measurements inaccurate?**
- Confirm device supports LiDAR (iPhone 12 Pro+)
- Avoid use in extremely bright or completely dark environments
- Ensure camera lens is clean
- Wait for AR tracking state to reach "Tracking OK"

**Q: Object recognition inaccurate?**
- FastViT model is trained on 1000+ categories; some objects may be recognized as similar categories
- Ensure objects are in appropriate lighting and distance range
- Avoid rapid device movement (triggers excessiveMotion limitation)

## 📧 Contact

For questions or suggestions, please open an issue.

---

**Committed to making technology more inclusive and empowering visually impaired users to explore the world with greater confidence.** 🌍✨
