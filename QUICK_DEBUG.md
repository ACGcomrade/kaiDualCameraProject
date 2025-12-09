# QUICK DEBUGGING STEPS

## 🚨 White Screen Issue - Follow These Steps

### Step 1: Test Basic SwiftUI (30 seconds)
1. Open `dualCameraApp.swift`
2. Temporarily change line 13:
   ```swift
   // FROM:
   ContentView()
   
   // TO:
   TestView()
   ```
3. Run app (Cmd+R)

**If you see GREEN screen with text:**
- ✅ SwiftUI is working
- ❌ Issue is in camera/preview setup
- Go to Step 2

**If you still see WHITE screen:**
- ❌ Build/project issue
- Clean build folder (Cmd+Shift+K)
- Delete app from device
- Rebuild

### Step 2: Check Console Logs
1. Open Console (Cmd+Shift+C)
2. Run app with ContentView (change back from TestView)
3. Look for FIRST ❌ or where logs stop

**Search console for:**
- `❌` (errors)
- `⚠️` (warnings)
- Last log before app stops

### Step 3: Identify the Issue

#### You See: `❌ CameraViewModel: Camera access denied`
**Solution:** Settings → Privacy → Camera → Enable

#### You See: `⚠️ Multi-cam NOT supported`
**Solution:** Use iPhone XS/XR or newer, or modify code for single cam

#### You See: `❌ Could not get back camera device`
**Solution:** Run on real device, not simulator

#### You See: `❌ Cannot add back camera connection`
**Solution:** Session config issue, share console output

#### Logs stop at: `🔵 CameraViewModel: Initializing...`
**Solution:** Check CameraSettings.shared is accessible

#### Logs stop at: `🎥 CameraManager: configureSession called`
**Solution:** Session setup failing, check device compatibility

#### Preview created but black: `✅ Preview layers setup complete`
**Solution:** Session might not be running, check session.startRunning()

### Step 4: Common Quick Fixes

```swift
// 1. Clean build
Cmd + Shift + K

// 2. Delete app from device
Long press → Delete

// 3. Restart device
Power off → Power on

// 4. Reset permissions
Settings → General → Reset → Reset Location & Privacy
```

## 📋 Info.plist Requirements

**MUST HAVE** these three keys:

```xml
<key>NSCameraUsageDescription</key>
<string>Dual camera capture</string>

<key>NSMicrophoneUsageDescription</key>
<string>Video with audio</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>Save photos and videos</string>
```

## 🔍 Console Search Terms

Type in console filter:
- `❌` → See all errors
- `⚠️` → See all warnings  
- `CameraManager` → Camera setup
- `DualCameraPreview` → Preview issues
- `Permission` → Authorization issues

## 📸 Testing Basic Functions

### Photo Capture Test
1. Launch app
2. Wait for preview (both cameras)
3. Tap white circle button
4. Should see preview thumbnails
5. Check Photos app

### Video Recording Test
1. Tap camera/video switch button (bottom right)
2. Capture button turns red
3. Tap red button to start
4. See recording timer
5. Tap square to stop
6. Check Photos app

### Gallery Test
1. Tap photo icon (bottom left)
2. Sheet opens
3. See grid of photos/videos
4. Videos show play icon
5. Tap video to play

## 🎯 Expected Behavior

### Launch (2 seconds)
1. Black screen appears
2. Permission dialog (first time)
3. Camera preview loads
4. See both cameras

### Preview
- Back camera: Full screen
- Front camera: Small box top-right
- Both updating in real-time
- Smooth 30 FPS

### Capture
- Instant photo capture
- Preview thumbnails appear
- Background save
- Success alert

## 📱 Device Requirements

**Minimum for Multi-Cam:**
- iPhone XS, XS Max, XR or newer
- iPad Pro 2018 or newer
- iOS 13.0+

**Will work but single camera only:**
- iPhone 8 and older
- Falls back to back camera only

## 🆘 Still Having Issues?

Share these in debug output:

```
1. Device model: _______
2. iOS version: _______
3. First ❌ error in console: _______
4. Console output from launch to error
5. Screenshot of white screen
```

## 💡 Pro Tips

1. **Always check console first** - Errors tell you exactly what's wrong
2. **Look for emoji** - Easy to spot issues (❌ ⚠️)
3. **Test incrementally** - Use TestView to isolate issues
4. **Check permissions** - Most common issue
5. **Use real device** - Simulator doesn't support camera

---

## One-Line Fixes for Common Issues

| Issue | One-Line Fix |
|-------|--------------|
| White screen | Change to TestView, test SwiftUI |
| Permission denied | Settings → Privacy → Camera → Enable |
| No device | Use iPhone XS+ or disable multi-cam |
| Black preview | Check session.startRunning() called |
| No capture | Check photo outputs added to session |
| No save | Grant photo library access |
| Gallery empty | Check Photos app permissions |

---

**Most issues will show in console with ❌ - Check there first!**
