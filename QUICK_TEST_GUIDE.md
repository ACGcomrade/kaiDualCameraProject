# Quick Test Guide

## What Changed

✅ Photo outputs are now added/removed dynamically during capture
✅ Gallery button now opens PhotoGalleryView
✅ Sequential capture eliminates multi-cam ambiguity

## Testing Steps

### 1. Clean Build
```
⌘ + Shift + K (Clean Build Folder)
⌘ + R (Build and Run)
```

### 2. Test Preview
- Both cameras should show in preview (back full screen, front PIP top-right)
- If preview doesn't appear, check Console for permission errors

### 3. Test Photo Capture
1. Tap white circular capture button
2. Wait for ~0.3 seconds
3. Check Console logs:
   ```
   ✅ Back photo output added temporarily
   📸 Back camera captured, image: true
   🗑️ Back photo output removed
   ✅ Front photo output added temporarily
   📸 Front camera captured, image: true
   🗑️ Front photo output removed
   ```
4. Thumbnails should appear above buttons
5. Open Photos app → should see 2 new photos

### 4. Test Gallery Button
1. Tap gallery button (bottom-left thumbnail)
2. Gallery should open showing recent media
3. Photos and videos should appear in grid
4. Tap video to play it
5. Tap "Done" to close gallery

### 5. Test Video Recording
1. Tap mode switch → Video mode
2. Tap red button → Start recording
3. Timer should count up
4. Tap red square → Stop recording
5. Videos should save to Photos app

## Expected Success Indicators

✅ No "Cannot Record" errors
✅ No "Cannot add connection" errors
✅ "Back camera captured, image: true"
✅ "Front camera captured, image: true"
✅ Photos save successfully
✅ Gallery opens and shows media

## Common Issues

### Issue: Preview doesn't show
**Fix:** Check Camera permission in Settings → Privacy → Camera

### Issue: Gallery button does nothing
**Fix:** Rebuild project (⌘ + Shift + K, then ⌘ + R)

### Issue: Photos don't save
**Fix:** Grant Photo Library permission in Settings → Privacy → Photos

### Issue: Only one camera captures
**Fix:** Check Console for "output added temporarily" messages for BOTH cameras

## Console Log Comparison

### ❌ Before Fix (BROKEN):
```
❌ Cannot add back camera photo connection
❌ Cannot add front camera video connection
❌ PhotoCaptureDelegate: Capture error: Cannot Record
```

### ✅ After Fix (WORKING):
```
✅ Back photo output added temporarily
📸 Back camera captured, image: true
🗑️ Back photo output removed
✅ Front photo output added temporarily  
📸 Front camera captured, image: true
🗑️ Front photo output removed
```

## If Still Not Working

1. Delete app from device
2. Clean build folder (⌘ + Shift + K)
3. Restart Xcode
4. Rebuild and run (⌘ + R)
5. Grant all permissions when prompted
6. Check Console logs for any remaining errors

The "Added temporarily" and "removed" messages are KEY - they confirm the dynamic output management is working.
