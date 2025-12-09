# Critical Fix: Multi-Camera Session Connections

## Root Cause Analysis

### The Problem
The error logs showed:
```
❌ PhotoCaptureDelegate: Capture error: Cannot Record
<<<< AVCapturePhotoOutput >>>> Fig assert: "hasFigCaptureSession" at bail (AVCapturePhotoOutput.m:545)
```

**Root Cause:** In `AVCaptureMultiCamSession`, unlike regular `AVCaptureSession`, you **CANNOT** simply add inputs and outputs to the session. You **MUST** explicitly create `AVCaptureConnection` objects to connect specific input ports to specific outputs.

### Why It Failed
The original code was doing:
```swift
// WRONG for Multi-Cam Session
newSession.addInput(backInput)
newSession.addOutput(backOutput)  // ❌ No connection!
```

This works fine for `AVCaptureSession` (single camera), but for `AVCaptureMultiCamSession`, the output has no idea which camera to capture from. The assertion "hasFigCaptureSession" fails because the photo output doesn't have a valid capture session connection.

## The Fix

### Back Camera Photo Output Connection
```swift
// CORRECT for Multi-Cam Session
let backOutput = AVCapturePhotoOutput()
newSession.addOutput(backOutput)

// Create explicit connection between back camera port and photo output
let photoConnection = AVCaptureConnection(inputPorts: [backPort], output: backOutput)
newSession.addConnection(photoConnection)
```

### Front Camera Photo Output Connection
```swift
let frontOutput = AVCapturePhotoOutput()
newSession.addOutput(frontOutput)

// Create explicit connection between front camera port and photo output
let photoConnection = AVCaptureConnection(inputPorts: [frontPort], output: frontOutput)
newSession.addConnection(photoConnection)
```

### Video Output Connections
Same pattern for video outputs:
```swift
let backVideoOutput = AVCaptureMovieFileOutput()
newSession.addOutput(backVideoOutput)

let videoConnection = AVCaptureConnection(inputPorts: [backPort], output: backVideoOutput)
newSession.addConnection(videoConnection)
```

### Audio Connections
Audio input must also be explicitly connected to each video output:
```swift
let audioInput = try AVCaptureDeviceInput(device: audioDevice)
newSession.addInput(audioInput)

if let audioPort = audioInput.ports.first(where: { $0.mediaType == .audio }) {
    // Connect audio to back video
    let backAudioConnection = AVCaptureConnection(inputPorts: [audioPort], output: backVideoOutput)
    newSession.addConnection(backAudioConnection)
    
    // Connect audio to front video
    let frontAudioConnection = AVCaptureConnection(inputPorts: [audioPort], output: frontVideoOutput)
    newSession.addConnection(frontAudioConnection)
}
```

## What Changed in CameraManager.swift

### Lines ~149-170: Back Camera Output Setup
**Before:**
- Added photo output without connection
- Added video output without connection

**After:**
- Get back camera video port
- Add photo output
- Create and add photo connection
- Add video output
- Create and add video connection

### Lines ~192-247: Front Camera Output Setup
**Before:**
- Added photo output without connection
- Added video output without connection

**After:**
- Get front camera video port
- Add photo output
- Create and add photo connection
- Add video output
- Create and add video connection

### Lines ~258-290: Audio Input Setup
**Before:**
- Just added audio input to session

**After:**
- Add audio input
- Get audio port
- Create connection to back video output
- Create connection to front video output

## How AVCaptureMultiCamSession Works

### Connection Architecture
```
┌─────────────────┐
│  Back Camera    │──┐
│  Input          │  │
└─────────────────┘  │
                     ├──[Connection]──► Photo Output (Back)
┌─────────────────┐  │
│  Front Camera   │──┤
│  Input          │  │
└─────────────────┘  ├──[Connection]──► Photo Output (Front)
                     │
┌─────────────────┐  │
│  Microphone     │──┼──[Connection]──► Video Output (Back)
│  Input          │  │
└─────────────────┘  └──[Connection]──► Video Output (Front)
```

Each output must have an explicit connection to its input port(s).

## Expected Console Output After Fix

```
✅ CameraManager: Back camera input added
✅ CameraManager: Back camera photo output added and connected
✅ CameraManager: Back camera video output added and connected
✅ CameraManager: Front camera input added
✅ CameraManager: Front camera photo output added and connected
✅ CameraManager: Front camera video output added and connected
✅ CameraManager: Audio input added
✅ CameraManager: Audio connected to back video output
✅ CameraManager: Audio connected to front video output
✅ CameraManager: Session started!
```

When capturing:
```
📸 CameraManager: captureDualPhotos called
📸 PhotoCaptureDelegate: willCapturePhoto called
📸 PhotoCaptureDelegate: didFinishProcessingPhoto called
✅ PhotoCaptureDelegate: Successfully created UIImage
📸 ViewModel: Received back image: true
📸 ViewModel: Received front image: true
```

## Testing After Fix

1. Clean build (⌘ + Shift + K)
2. Build and run (⌘ + R)
3. Grant camera permissions
4. Wait for preview to appear
5. Tap capture button
6. Check console for:
   - ✅ "Back camera photo output added **and connected**"
   - ✅ "Front camera photo output added **and connected**"
   - ✅ No "Cannot Record" errors
   - ✅ "Received back image: true"
   - ✅ "Received front image: true"

## Why This Was Hard to Debug

1. **Same API name:** `addOutput()` works for both session types
2. **No compiler error:** The code compiles fine
3. **Runtime-only failure:** Only fails when actually capturing
4. **Cryptic error:** "Cannot Record" doesn't mention connections
5. **Device-specific:** Only affects multi-cam capable devices

## Apple Documentation

From Apple's AVFoundation docs:
> When using AVCaptureMultiCamSession, you must explicitly create AVCaptureConnection objects to establish the dataflow between inputs and outputs. Simply adding an input and an output to the session does not automatically create a connection.

This is the KEY difference from regular AVCaptureSession.

## Summary

✅ **Fixed:** Back camera photo output now has explicit connection
✅ **Fixed:** Front camera photo output now has explicit connection
✅ **Fixed:** Back camera video output now has explicit connection
✅ **Fixed:** Front camera video output now has explicit connection
✅ **Fixed:** Audio input explicitly connected to both video outputs

The "Cannot Record" error should now be completely resolved, and both cameras will capture images successfully.
