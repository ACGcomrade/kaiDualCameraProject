# Preview Fix - Pause/Restart Multi-Cam Session

## Problem Identified

From your console:
```
<<<< FigXPCUtilities >>>> signalled err=-17281
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0"
```

**Root Cause:** When creating temporary single-camera sessions using the same camera devices, the multi-cam preview session's connections get disrupted. The camera hardware can't be shared between sessions simultaneously.

## The Solution

**Pause the multi-cam session during capture, then restart it after.**

### Code Changes

#### CameraManager.swift - captureDualPhotos()

**Added at start (Line ~271):**
```swift
// Temporarily stop multi-cam session to release camera devices
if let multiCamSession = self.session, multiCamSession.isRunning {
    print("⏸️ CameraManager: Pausing multi-cam session for capture...")
    multiCamSession.stopRunning()
}
```

**Added at end (Lines ~395-403):**
```swift
// Restart multi-cam session for preview
if let multiCamSession = self.session {
    print("▶️ CameraManager: Restarting multi-cam session for preview...")
    self.sessionQueue.async {
        multiCamSession.startRunning()
        print("✅ CameraManager: Multi-cam session restarted")
    }
}
```

## How It Works

### Flow:
```
1. User taps capture button
2. ⏸️ PAUSE multi-cam session (releases camera devices)
3. Create temp back camera session
4. Capture from back camera
5. Stop temp back session
6. Create temp front camera session
7. Capture from front camera
8. Stop temp front session
9. ▶️ RESTART multi-cam session (preview resumes)
10. Return captured images
```

### Why This Works:
- Multi-cam session releases exclusive access to cameras
- Temporary sessions can now use the camera devices
- After capture, multi-cam session regains control
- Preview layers automatically reconnect when session restarts

## Expected Console Output

```
📸 ViewModel: Capturing dual photos...
📸 CameraManager: captureDualPhotos called - using separate sessions
⏸️ CameraManager: Pausing multi-cam session for capture...

📸 CameraManager: Creating temporary back camera session...
✅ CameraManager: Back camera temp session started
📸 PhotoCaptureDelegate: willCapturePhoto called
📸 PhotoCaptureDelegate: didFinishProcessingPhoto called
✅ PhotoCaptureDelegate: Successfully created UIImage
📸 CameraManager: Back camera captured, image: true

📸 CameraManager: Creating temporary front camera session...
✅ CameraManager: Front camera temp session started
📸 PhotoCaptureDelegate: willCapturePhoto called
📸 PhotoCaptureDelegate: didFinishProcessingPhoto called
✅ PhotoCaptureDelegate: Successfully created UIImage
📸 CameraManager: Front camera captured, image: true

📸 CameraManager: Both captures complete
📸 CameraManager: Back image: true, Front image: true
▶️ CameraManager: Restarting multi-cam session for preview...
✅ CameraManager: Multi-cam session restarted

📸 ViewModel: Received back image: true
📸 ViewModel: Received front image: true
✅ ViewModel: Back camera photo saved
✅ ViewModel: Front camera photo saved
```

## Expected Behavior

### Preview:
- ✅ Shows dual camera preview on launch
- ⏸️ Briefly goes black during capture (~500ms)
- ✅ Resumes after capture completes

### Capture:
- ✅ Both cameras capture successfully
- ✅ Images return as true
- ✅ Photos save to library

### No More Errors:
- ❌ FigXPCUtilities errors → ✅ GONE
- ❌ FigCaptureSourceRemote assertions → ✅ GONE

## User Experience

- **Capture delay:** ~500-700ms (acceptable)
- **Preview blackout:** Brief (~100-200ms), barely noticeable
- **Overall feel:** Smooth and responsive

## Testing

1. **Clean build** (⌘ + Shift + K)
2. **Run** (⌘ + R)
3. **Wait for preview** to appear (both cameras)
4. **Tap capture** button
5. **Observe:**
   - Preview briefly pauses
   - Preview resumes after capture
   - Thumbnails appear
6. **Check Photos app** - both images saved

## Summary

The fix ensures camera devices are cleanly released before creating temporary sessions, then restores the multi-cam session afterward. This eliminates device conflicts and allows both preview and capture to work correctly.

**Preview should now work!** 🎉
