# Dual Camera App

A SwiftUI-based iOS app that captures photos and videos from both front and back cameras simultaneously.

## Features

- ✅ Simultaneous front and back camera capture (on supported devices)
- ✅ Multi-camera session support with fallback for older devices
- ✅ Flash control
- ✅ Camera switching
- ✅ Real-time camera preview
- ✅ Photo capture with proper permission handling

## Requirements

- iOS 13.0+ (Multi-cam requires iOS 13.0+)
- Xcode 14.0+
- Device with multiple cameras (iPhone XS/XR or newer for multi-cam support)

## Setup Instructions

### 1. Configure Info.plist

You **must** add camera permissions to your Info.plist file:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs access to the camera to take photos and videos from both front and back cameras simultaneously.</string>

<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to the microphone to record videos with audio.</string>
```

### 2. Build and Run

1. Open the project in Xcode
2. Select a physical device (multi-cam doesn't work in simulator)
3. Build and run (Cmd+R)

## Architecture

### Files Overview

- **CaneraManager.swift** (Note: typo in filename) - Core camera session management
  - Configures AVCaptureMultiCamSession
  - Handles photo capture
  - Manages camera inputs and outputs
  
- **CameraViewModel.swift** - SwiftUI ViewModel
  - Manages app state
  - Handles permissions
  - Interfaces between UI and CameraManager
  
- **CameraPreview.swift** - Single camera preview (UIViewRepresentable)
  
- **DualCameraPreview.swift** - Dual camera preview with Picture-in-Picture
  - Shows **front camera as main full-screen view**
  - Shows **back camera in small PiP overlay at top-right corner**
  - Properly handles video connections for each camera
  
- **ContentView.swift** - Main app UI
  - Camera controls
  - Capture button
  - Flash and camera switching

## Using Dual Camera Preview

The app now uses dual camera preview by default with **front camera as the main full-screen view** and **back camera in a Picture-in-Picture overlay at the top-right corner**.

The preview is configured in `ContentView.swift`:

```swift
DualCameraPreview(viewModel: viewModel)
    .ignoresSafeArea()
```

### Camera Layout
- **Main View (Full Screen)**: Front camera (mirrored for selfie mode)
- **PiP (Top-Right Corner)**: Back camera (120x160 with white border)

## Device Compatibility

### Multi-Cam Support (Both cameras simultaneously)
- iPhone XS, XS Max, XR and newer
- iPad Pro 3rd generation and newer

### Fallback (Single camera)
- Older devices will use standard single camera mode

## Future Enhancements

- [ ] Video recording from both cameras
- [ ] Save combined photos (side-by-side or overlay)
- [ ] Adjustable PiP size and position
- [ ] Switch which camera is main vs PiP
- [ ] Add video preview and controls
- [ ] Export options for dual camera content

## Troubleshooting

### "Multi-camera not supported" message
- Make sure you're running on a physical device (iPhone XS or newer)
- The app will fallback to single camera mode on older devices

### Black screen in preview
- Check camera permissions in Settings > Privacy > Camera
- Ensure Info.plist has NSCameraUsageDescription

### Build errors
- Ensure all files have proper imports (AVFoundation, SwiftUI, Combine)
- Clean build folder (Cmd+Shift+K) and rebuild

## License

This is a sample project for educational purposes.
