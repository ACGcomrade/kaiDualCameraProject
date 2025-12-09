# 🔍 DIAGNOSTIC GUIDE - App Stuck/Not Working

## 📋 Check These Things First

### 1. Check Xcode Console Output

When you run the app, open the **Console** (Cmd+Shift+C) and look for these log messages:

#### ✅ If you see these, permissions are working:
```
🔵 CameraViewModel: Initializing...
🔐 CameraViewModel: checkPermission called
🔐 CameraViewModel: Current status: 3  ← (3 = authorized)
✅ CameraViewModel: Camera authorized
🎥 CameraViewModel: Setting up camera session...
```

#### ❌ If you see this, permissions NOT granted:
```
🔐 CameraViewModel: Current status: 0  ← (0 = not determined)
⚠️ CameraViewModel: Permission not determined, requesting...
```
Or:
```
🔐 CameraViewModel: Current status: 2  ← (2 = denied)
❌ CameraViewModel: Camera access denied or restricted
```

#### 🔍 Camera session logs to look for:
```
🎥 CameraManager: configureSession called
✅ CameraManager: Multi-cam IS supported
✅ CameraManager: Back camera input added
✅ CameraManager: Front camera input added
✅ CameraManager: Session started!
```

### 2. Permission Dialog Should Appear

**On first launch**, you should see an iOS alert:
```
"dualCamera" Would Like to Access the Camera
[Don't Allow]  [OK]
```

**If you DON'T see this dialog:**
- Info.plist permissions are not loaded correctly
- OR you previously denied permission

---

## 🔧 FIXES FOR COMMON ISSUES

### Issue 1: No Permission Dialog Appears

**Cause:** Info.plist keys not loaded

**Fix:**
1. Check your Info.plist has these exact keys:
   - `NSCameraUsageDescription`
   - `NSPhotoLibraryAddUsageDescription`
   - `NSMicrophoneUsageDescription`

2. Verify in Xcode:
   - Project → Target → **Info** tab
   - Should see "Privacy - Camera Usage Description"

3. **Clean and rebuild:**
   ```
   Cmd+Shift+K (Clean)
   Delete app from device
   Cmd+R (Run again)
   ```

### Issue 2: Permission Dialog Appeared But Stuck on Black Screen

**Cause:** You tapped "Don't Allow" or session not starting

**Fix A - Reset Permissions:**
1. On device/simulator: **Settings** → **Privacy & Security** → **Camera**
2. Find your app "dualCamera"
3. Toggle **ON**
4. Go back to Settings → **Privacy & Security** → **Photos**
5. Set to **"Add Photos Only"** or **"All Photos"**
6. Kill and relaunch app

**Fix B - Reset All Permissions (Simulator):**
1. In simulator: **Settings** → **General** → **Transfer or Reset iPhone**
2. **Reset Location & Privacy**
3. Delete app
4. Rebuild and run

### Issue 3: UI Shows But Buttons Don't Work

**Check console for errors when tapping buttons**

Possible causes:
- Camera session not running
- Missing component files

**Add debug logging:**
Tap a button and check console for:
```
📸 ViewModel: Capturing dual photos...
```

If you see nothing, the button isn't connected.

### Issue 4: Black Screen with UI Visible

**Cause:** Camera preview not rendering

**Fix:**
Check console for these messages:
```
🖼️ DualCameraPreview: makeUIView called
🖼️ DualCameraPreview: Session received in observer
🖼️ DualCameraPreview: Setting up preview layers...
✅ DualCameraPreview: Back camera connected
```

If missing, camera session never started.

---

## 🧪 STEP-BY-STEP DIAGNOSTIC

### Step 1: Check Info.plist

In Xcode, select your project → Target → **Info** tab

You MUST see:
- ✅ Privacy - Camera Usage Description
- ✅ Privacy - Photo Library Additions Usage Description
- ✅ Privacy - Microphone Usage Description

**If missing → ADD THEM NOW!**

### Step 2: Check Permissions on Device

**On device/simulator:**
Settings → Privacy & Security → Camera → Your App → **Should be ON**

**If OFF or app not listed:**
- Delete app
- Clean build (Cmd+Shift+K)
- Rebuild and run

### Step 3: Read Console Logs

Run app with Console open (Cmd+Shift+C)

**Look for the FIRST error or warning** (❌ or ⚠️)

Common errors:
- `❌ CameraManager: Multi-cam NOT supported` → Device limitation
- `❌ CameraManager: Could not get back camera device` → Permission issue
- `❌ DualCameraPreview: Cannot add back camera connection` → Session issue

### Step 4: Test Capture Button

Tap the capture button (large circle in middle)

Console should show:
```
📸 ViewModel: Capturing dual photos...
📸 CameraManager: captureDualPhotos called
```

**If you see nothing** → Button not connected or app crashed

**If you see errors** → Share them for diagnosis

---

## 💡 MOST LIKELY CAUSES

### 1. Info.plist Not Loaded (90% of issues)

**Symptoms:**
- No permission dialog
- App stuck on black screen
- Console shows: "Current status: 0"

**Fix:**
Add the 3 permission keys to Info.plist (see ADD_THESE_TO_INFO_PLIST.txt)

### 2. Permission Denied

**Symptoms:**
- Permission dialog appeared but you tapped "Don't Allow"
- Console shows: "Current status: 2"

**Fix:**
Settings → Privacy → Camera → Enable for your app

### 3. Simulator Limitations

**Symptoms:**
- Console shows: "Multi-cam NOT supported"

**Fix:**
- Use a real device (iPhone with iOS 13+)
- Or app will work in single-camera mode

---

## 🆘 WHAT TO SHARE FOR HELP

If still stuck, share:

1. **Console output** (copy all text from Xcode console)
2. **Screenshot of Info.plist** (in source code view)
3. **Device/Simulator info** (iOS version, device model)
4. **What happens** when you:
   - Launch app
   - Tap capture button
   - See any errors

---

## ✅ EXPECTED BEHAVIOR

### When Working Correctly:

1. **Launch app** → Permission dialog appears
2. **Tap "OK"** → Camera preview shows (dual view)
3. **Tap capture** (big circle) → Flash animation
4. **Permission dialog** → "Add Photos" → Tap "Allow"
5. **Alert shows** → "2 photo(s) saved successfully!"
6. **Check Photos app** → See 2 new photos

---

## 🔍 Quick Checklist

- [ ] Info.plist has 3 permission keys
- [ ] Permission dialog appeared on first launch
- [ ] Granted camera permission (tapped OK)
- [ ] Camera preview shows (not black screen)
- [ ] Can see front and back camera feeds
- [ ] Buttons are visible on screen
- [ ] Console shows no errors (❌)
- [ ] Tapping capture button works

**If all checked → App works!** ✅

**If any unchecked → See fixes above** ⚠️

---

Need more help? Share your console output!
