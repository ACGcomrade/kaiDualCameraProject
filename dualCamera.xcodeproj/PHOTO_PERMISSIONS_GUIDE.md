# Photo Library Permissions Guide

## Required Info.plist Entry

To save photos to the user's iPhone Photos library, you **MUST** add the following privacy permission to your `Info.plist` file:

### How to Add the Permission:

1. Open your project in Xcode
2. Select your project in the navigator
3. Go to the "Info" tab
4. Right-click in the list and select "Add Row"
5. Add the following key:

```
Key: Privacy - Photo Library Additions Usage Description
Type: String
Value: We need permission to save photos to your library
```

**Or in the Info.plist source code:**

```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>We need permission to save photos to your library</string>
```

### Alternative Translation (Chinese):
```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>需要访问相册以保存照片</string>
```

---

## How the Photo Saving Works

### 1. **Automatic Permission Request**
When the user taps the "Save to Photos" button for the first time, iOS will automatically show a system alert asking for permission.

### 2. **Permission States**
- **Authorized**: User granted full access - photos will save successfully
- **Limited**: User granted limited access - photos will still save successfully
- **Denied**: User denied access - an error message will be shown
- **Not Determined**: First time, system will prompt automatically

### 3. **User Flow**

**First Time:**
1. User captures a photo
2. Photo preview appears with "Save to Photos" button
3. User taps "Save to Photos"
4. iOS shows system permission alert
5. User grants/denies permission
6. App shows success or error message

**After Permission Granted:**
1. User captures a photo
2. Taps "Save to Photos"
3. Photo saves immediately
4. Success message appears

**If Permission Denied:**
1. User sees error message: "Photo library access denied"
2. User needs to go to Settings → Your App → Photos → Allow access
3. Can use the camera permission alert pattern to guide users to Settings

---

## Testing the Feature

### Test Scenarios:

1. **First Launch - Grant Permission**
   - Open app
   - Take a photo
   - Tap "Save to Photos"
   - Tap "Allow" on the system alert
   - Verify success message appears
   - Check Photos app - photo should be there

2. **First Launch - Deny Permission**
   - Open app
   - Take a photo
   - Tap "Save to Photos"
   - Tap "Don't Allow" on the system alert
   - Verify error message appears
   - Photo should NOT be in Photos app

3. **Re-granting Permission**
   - If denied, go to Settings → Your App
   - Find "Photos" permission
   - Change to "Add Photos Only" or "All Photos"
   - Return to app
   - Take new photo and save
   - Should work now

---

## Code Changes Summary

### 1. Camera Preview Layout (DualCameraPreview.swift)
- **Back camera**: Now displays as the main full-screen preview
- **Front camera**: Now displays in the top-right corner (Picture-in-Picture)

### 2. Photo Saving (CameraManager.swift)
- Added `savePhotoToLibrary()` method
- Automatically requests Photo Library permission
- Handles all permission states
- Returns success/error via completion handler

### 3. User Interface (ContentView.swift)
- Added "Save to Photos" button below captured photo preview
- Added alert to show save status (success or error)
- Clear visual feedback for users

### 4. View Model (CameraViewModel.swift)
- Added `savePhotoToLibrary()` method
- Added `saveStatus` and `showSaveAlert` properties
- Coordinates between UI and CameraManager

---

## Important Notes

⚠️ **Without the Info.plist entry, your app will crash!**

✅ The permission request is automatic - you don't need to manually check before saving

✅ Using `.addOnly` authorization - this is the recommended approach for apps that only need to save photos

✅ The code handles all permission states gracefully with user-friendly error messages

---

## Troubleshooting

### App crashes when tapping "Save to Photos"
**Solution**: Make sure you added the `NSPhotoLibraryAddUsageDescription` key to Info.plist

### Permission dialog doesn't appear
**Solution**: Reset permission by going to Settings → General → Reset → Reset Location & Privacy, then relaunch app

### "Denied" error even though permission was granted
**Solution**: 
1. Delete the app completely
2. Reinstall
3. Grant permission again

### Photos not appearing in Photos app
**Solution**: 
1. Check that success message appeared
2. Open Photos app and pull down to refresh
3. Check "Recents" album

