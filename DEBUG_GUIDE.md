# Debug Guide - White Screen Issue

## What We Fixed

### 1. Fixed ContentView Settings Reference Bug
**Problem:** ContentView was referencing `settings` variable that no longer existed after we removed resolution settings.

**Fix:** Changed `settings` to `CameraSettings.shared` in the sheet presentation.

### 2. Added Comprehensive Debug Logging
Added extensive debug logging throughout the app to track execution flow:

#### CameraViewModel
- ✅ Initialization logging
- ✅ Permission check logging
- ✅ Camera setup logging

#### CameraManager  
- ✅ Session configuration logging
- ✅ Camera input/output setup logging
- ✅ Multi-cam support detection logging
- ✅ Session start logging

#### DualCameraPreview
- ✅ UIView creation logging
- ✅ Session observer logging
- ✅ Preview layer setup logging
- ✅ Camera connection logging

### 3. Added Visual Debugging
- Added black background color to ContentView for visual confirmation
- UI should show black screen even if camera fails to load

## How to Debug the White Screen

### Step 1: Check Console Logs
When you run the app, look for these log sequences in Xcode console:

**Expected successful flow:**
```
🟢 ContentView: onAppear called
🔵 CameraViewModel: Initializing...
🔵 CameraViewModel: Checking permissions...
🔐 CameraViewModel: checkPermission called
🔐 CameraViewModel: Current status: 3 (authorized)
✅ CameraViewModel: Camera authorized
🎥 CameraViewModel: Setting up camera session...
🎥 CameraManager: configureSession called
✅ CameraManager: Multi-cam IS supported
📱 CameraManager: Assigning session to main thread
🔧 CameraManager: Session configuration started
✅ CameraManager: Set session preset to .high
📷 CameraManager: Setting up back camera...
✅ CameraManager: Back camera input added
✅ CameraManager: Back camera photo output added
✅ CameraManager: Back camera video output added
📷 CameraManager: Setting up front camera...
✅ CameraManager: Front camera input added
✅ CameraManager: Front camera photo output added
✅ CameraManager: Front camera video output added
🎤 CameraManager: Setting up audio input...
✅ CameraManager: Audio input added
🔧 CameraManager: Session configuration committed
▶️ CameraManager: Starting session...
✅ CameraManager: Session started!
✅ CameraManager: isSessionRunning = true
🖼️ DualCameraPreview: makeUIView called
🖼️ DualCameraPreview: Session received in observer
🖼️ DualCameraPreview: Setting up preview layers...
🖼️ DualCameraPreview: Back preview layer created
🖼️ DualCameraPreview: Connecting back camera...
✅ DualCameraPreview: Back camera connected
✅ DualCameraPreview: Back preview layer added to view
🖼️ DualCameraPreview: PIP container created
🖼️ DualCameraPreview: Front preview layer created
🖼️ DualCameraPreview: Connecting front camera...
✅ DualCameraPreview: Front camera connected
✅ DualCameraPreview: Preview layers setup complete
```

### Step 2: Identify the Breaking Point
Look for where the log stops or shows errors (❌ or ⚠️ symbols).

**Common Issues:**

#### Permission Not Granted
```
❌ CameraViewModel: Camera access denied or restricted
```
**Solution:** Go to Settings → Privacy → Camera and enable for your app

#### Multi-Cam Not Supported
```
⚠️ CameraManager: Multi-cam NOT supported, using single camera
```
**Solution:** Run on iPhone XS/XR or newer (or use single camera mode)

#### Camera Not Found
```
❌ CameraManager: Could not get back camera device
```
**Solution:** Make sure you're running on a real device, not simulator

#### Preview Not Connected
```
❌ DualCameraPreview: Cannot add back camera connection
```
**Solution:** Check that camera inputs were added successfully

### Step 3: Check for Thread Issues

#### Main Thread Violation
If you see warnings like:
```
[SwiftUI] Publishing changes from background threads is not allowed
```
**What we did:** Ensured all UI updates happen on `DispatchQueue.main.async`

#### Session Configuration on Wrong Thread
Session should be configured on `sessionQueue`:
```swift
sessionQueue.async { [weak self] in
    self?.configureSession()
}
```

### Step 4: Verify Info.plist Permissions

Make sure you have these in Info.plist:
```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for dual camera capture</string>

<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for video recording</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>This app needs to save photos and videos to your library</string>
```

## Testing Checklist

Run the app and verify each step:

### Basic Startup
- [ ] App launches without crashing
- [ ] Screen is NOT white (should be black at minimum)
- [ ] Permission dialog appears (first launch)
- [ ] Console shows initialization logs

### Camera Preview
- [ ] Back camera preview appears (full screen)
- [ ] Front camera preview appears (PIP at top-right)
- [ ] Both previews update in real-time
- [ ] Preview rotates when device rotates

### Photo Capture
- [ ] Tap capture button in photo mode
- [ ] Flash indicator shows (if enabled)
- [ ] Preview thumbnail appears
- [ ] Console shows capture logs
- [ ] Photo saves to library
- [ ] Success alert appears

### Video Recording
- [ ] Switch to video mode (red capture button)
- [ ] Tap to start recording
- [ ] Recording indicator appears with timer
- [ ] Tap to stop recording
- [ ] Videos save to library
- [ ] Success alert appears

### Gallery
- [ ] Tap gallery button (bottom left)
- [ ] Gallery sheet opens
- [ ] Recent photos/videos display in grid
- [ ] Thumbnails are regular size (not too large)
- [ ] Tap video to play

## Quick Fixes

### If Nothing Shows Up
1. Clean build folder (Cmd+Shift+K)
2. Delete app from device
3. Rebuild and reinstall
4. Check console for first error

### If Preview is Black
1. Check camera permissions
2. Verify running on real device
3. Check console for connection errors
4. Try restarting device

### If Capture Doesn't Work
1. Check photo library permissions
2. Look for delegate callback logs in console
3. Verify outputs were added to session
4. Check file system space

### If Gallery is Empty
1. Grant photo library access
2. Check that saves completed successfully
3. Look for save confirmation logs
4. Open Photos app to verify

## Console Search Terms

To quickly find issues, search console for:
- `❌` - Errors
- `⚠️` - Warnings
- `CameraManager` - Camera setup issues
- `DualCameraPreview` - Preview issues
- `ViewModel` - Logic issues
- `Permission` - Permission issues
- `failed` or `error` - General errors

## Expected Behavior Summary

**Launch:**
- Black screen appears immediately
- Permission dialog shows (first time)
- Camera preview loads within 1-2 seconds

**Camera Preview:**
- Back camera full screen
- Front camera PIP top-right
- Both update in real-time
- 30 FPS smooth motion

**Photo Capture:**
- Instant capture
- Brief preview flash
- Thumbnails appear
- Save happens in background
- Alert confirms success

**Video Recording:**
- Red dot indicates recording
- Timer shows duration
- Stop button available
- Videos save after stop
- Alert confirms success

**Gallery:**
- Opens quickly
- Loads 50 recent items
- Thumbnails load progressively
- Videos show duration
- Tap to play videos

---

**If you're still seeing a white screen, share the console output and we can identify the exact issue!**
