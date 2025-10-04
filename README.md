# EchoSight - AI-Assisted Navigation for the Visually Impaired

A LiDAR-powered navigation assistant that combines ARKit, on-device vision (Core ML), Apple Speech, and a cloud VLM to deliver real-time obstacle distance, object recognition, and concise navigation tips.

## Features
- Obstacle distance with LiDAR (auto warning when < 0.5 m)
- Object recognition (FastViT) with recent history display
- Continuous voice interaction (Apple Speech)
- Scene-aware Q&A and obstacle-avoidance advice via VLM
- Visual + spoken responses and optional haptics

## Project Structure
```
EchoSight/
├── EchoSightApp.swift             # App entry
├── ContentView.swift              # UI (SwiftUI)
├── ARManager.swift                # AR + LiDAR + ML
├── VLMService.swift               # VLM client (OpenRouter)
├── SpeechRecognitionService.swift # Apple Speech (ASR)
└── FastViTMA36F16.mlpackage/      # Object recognition model
```

## Requirements
- Device: iPhone 12 Pro or newer (LiDAR)
- iOS: 15.0+
- Xcode: 14.0+
- Swift: 5.9+

## Setup
1) Clone and open the project
```bash
git clone https://github.com/yourusername/EchoSight.git
cd EchoSight
open EchoSight.xcodeproj
```

2) Permissions (configured in build settings; confirm in Info if needed)
- NSCameraUsageDescription
- NSMicrophoneUsageDescription
- NSSpeechRecognitionUsageDescription

3) Configure API keys (no hardcoding)
Create `EchoSight/Secrets.plist` (NOT committed) based on the example below:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>OPENROUTER_API_KEY</key>
	<string>your_openrouter_api_key</string>
</dict>
</plist>
```
The app reads `OPENROUTER_API_KEY` from `Secrets.plist`, Info.plist, or environment variables (in that order). See `Config.swift`.

4) Run
- Select a LiDAR-capable device
- Build and run (Cmd+R)
- Grant all permissions

## Usage
- The app automatically starts AR + LiDAR scanning, listens for voice queries, and shows/speaks distance/object info.
- When an obstacle is close, a brief avoidance tip is requested from the VLM and spoken on-device.

## Security and Git Hygiene
- Do NOT commit secrets. `.gitignore` already excludes `EchoSight/Secrets.plist`, `.env*`, and large model weights.
- Avoid committing large binary model weights or Core ML compiled products.

## Notes
- Whisper-based services have been removed. Apple Speech is used for ASR.
- The VLM client uses OpenRouter with `google/gemini-2.0-flash-exp:free` by default. You can change the model in `VLMService.swift`.

## License
MIT — see `LICENSE`.

## Contributing
PRs and issues are welcome.
