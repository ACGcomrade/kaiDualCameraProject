# 📋 Required Info.plist Permissions

## 🚨 You Need BOTH of These Permissions

Copy and paste these into your `Info.plist` file:

```xml
<key>NSCameraUsageDescription</key>
<string>We need access to your camera to take photos</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>We need permission to save photos to your library</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>We need permission to show your recently captured photos</string>
```

---

## 📝 Explanation

### 1. Camera Permission (REQUIRED)
```xml
<key>NSCameraUsageDescription</key>
<string>We need access to your camera to take photos</string>
```
**Why:** To access the front and back cameras
**When:** Asked on first app launch

---

### 2. Save Photos Permission (REQUIRED)
```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>We need permission to save photos to your library</string>
```
**Why:** To save captured photos to Photo Library
**When:** Asked when you first capture a photo

---

### 3. View Photos Permission (REQUIRED for Gallery Feature)
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>We need permission to show your recently captured photos</string>
```
**Why:** To show photos in the gallery button
**When:** Asked when you first tap the gallery button

---

## 🎯 How to Add These to Your Project

### Method 1: Using Info.plist Source Code

1. In Xcode, find `Info.plist` in your project navigator
2. **Right-click** on `Info.plist`
3. Select **"Open As" → "Source Code"**
4. Find the line with `<dict>` near the top
5. **Paste all three permissions** after the opening `<dict>` tag

**Your Info.plist should look like this:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSCameraUsageDescription</key>
	<string>We need access to your camera to take photos</string>
	<key>NSPhotoLibraryAddUsageDescription</key>
	<string>We need permission to save photos to your library</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>We need permission to show your recently captured photos</string>
	<!-- Your other keys below... -->
</dict>
</plist>
```

---

### Method 2: Using Xcode's Property List Editor

1. In Xcode, click on `Info.plist`
2. You'll see a table view
3. Hover over any row and click the **+** button

**Add Permission #1:**
- Click **+**
- Key: `Privacy - Camera Usage Description`
- Type: String
- Value: `We need access to your camera to take photos`

**Add Permission #2:**
- Click **+**
- Key: `Privacy - Photo Library Additions Usage Description`
- Type: String  
- Value: `We need permission to save photos to your library`

**Add Permission #3:**
- Click **+**
- Key: `Privacy - Photo Library Usage Description`
- Type: String
- Value: `We need permission to show your recently captured photos`

---

## ✅ Verification

### How to Check if Permissions Are Added:

1. Open `Info.plist`
2. Press **Cmd+F** (Find)
3. Search for: `Camera`
   - Should find: `NSCameraUsageDescription` ✅
4. Search for: `Photo`
   - Should find: `NSPhotoLibraryAddUsageDescription` ✅
   - Should find: `NSPhotoLibraryUsageDescription` ✅

**If you find all 3, you're good!** ✅

---

## 🎨 Visual Guide

### What You'll See in Info.plist Editor:

```
Information Property List
├─ Privacy - Camera Usage Description: "We need access to your camera to take photos"
├─ Privacy - Photo Library Additions Usage Description: "We need permission to save photos to your library"
├─ Privacy - Photo Library Usage Description: "We need permission to show your recently captured photos"
└─ [Other properties...]
```

---

## 🔄 After Adding Permissions

1. **Clean Build Folder**
   - Press: `Cmd + Shift + K`

2. **Rebuild Project**
   - Press: `Cmd + B`

3. **Delete App from Device/Simulator**
   - Long press app icon → Remove App

4. **Run Again**
   - Press: `Cmd + R`

5. **Grant Permissions When Asked**
   - Camera permission → Tap "OK"
   - Photo Library permission → Tap "Allow"

---

## 📱 What Users Will See

### First Launch:
```
┌─────────────────────────────────┐
│  "[Your App]" Would Like to    │
│  Access the Camera              │
│                                 │
│  We need access to your camera  │
│  to take photos                 │
│                                 │
│     [Don't Allow]    [OK]       │
└─────────────────────────────────┘
```

### First Photo Capture:
```
┌─────────────────────────────────┐
│  "[Your App]" Would Like to    │
│  Add Photos                     │
│                                 │
│  We need permission to save     │
│  photos to your library         │
│                                 │
│  [Don't Allow]    [Allow]       │
└─────────────────────────────────┘
```

### First Gallery Access:
```
┌─────────────────────────────────┐
│  "[Your App]" Would Like to    │
│  Access Your Photos             │
│                                 │
│  We need permission to show     │
│  your recently captured photos  │
│                                 │
│  [Select Photos]  [Allow Access]│
│          [Don't Allow]          │
└─────────────────────────────────┘
```

---

## 🌐 Optional: Localized Strings (Chinese)

If you want Chinese translations:

```xml
<!-- Camera -->
<key>NSCameraUsageDescription</key>
<string>需要访问相机以拍摄照片</string>

<!-- Save Photos -->
<key>NSPhotoLibraryAddUsageDescription</key>
<string>需要访问相册以保存照片</string>

<!-- View Photos -->
<key>NSPhotoLibraryUsageDescription</key>
<string>需要访问相册以显示您最近拍摄的照片</string>
```

---

## 🚨 Important Notes

### Without These Permissions:

❌ **No Camera Permission:**
- App will crash or show black screen
- Cannot access camera

❌ **No Photo Library Add Permission:**
- Photos won't save
- Will get error message

❌ **No Photo Library Read Permission:**
- Gallery button won't work
- App will crash when tapping gallery

### With All Permissions: ✅
- Camera works
- Photos save automatically
- Gallery shows your photos
- Everything works perfectly!

---

## 📋 Copy-Paste Ready

**For Quick Copy:**

```xml
<key>NSCameraUsageDescription</key>
<string>We need access to your camera to take photos</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>We need permission to save photos to your library</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>We need permission to show your recently captured photos</string>
```

**Just copy the above and paste into your Info.plist!**

---

## ✅ Checklist

- [ ] Added `NSCameraUsageDescription`
- [ ] Added `NSPhotoLibraryAddUsageDescription`
- [ ] Added `NSPhotoLibraryUsageDescription`
- [ ] Saved Info.plist
- [ ] Cleaned build (Cmd+Shift+K)
- [ ] Rebuilt project (Cmd+B)
- [ ] Deleted old app from device
- [ ] Ran app (Cmd+R)
- [ ] Ready to test!

---

**Once you add these 3 permissions, your app will work perfectly!** 🎉
